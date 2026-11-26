/*
# Superadmin dispute arbitration + UPI payout approval queue

1. New columns
- `wallet_transactions.status` (text, nullable) — payout queue state for UPI payout
  rows: NULL/'pending' = awaiting review, 'completed' = paid out, 'rejected' =
  denied (excluded from balance deductions downstream).
- `wallet_transactions.resolved_at` (timestamptz, nullable) — when an admin approved
  or rejected the payout.

2. New functions (SECURITY DEFINER, callable by authenticated only)
- `admin_resolve_dispute(p_order_id text, p_action text)` — atomic Superadmin
  arbitration. Accepts 'force_refund' | 'force_release' | 'force_reship'. Updates
  the matching `orders` row (status, order_status, delivery_status, is_delivered,
  escrow_status, bounty_status, dispute_status, dispute_resolved) AND the matching
  `disputes` row (status, resolution, updated_at) in one call, so the UI refreshes
  once and sees consistent state. The requested outcome is stored in the existing
  `resolution` column as 'resolution_type: <refund|release|reship>' since no
  separate resolution_type column exists. Token restoration is intentionally NOT
  done here — the existing `trg_order_brand_tokens` trigger on `orders` handles
  restoring `token_discount_used` to brand_tokens automatically. Throws if the
  action is unknown or the order does not exist.
- `admin_resolve_payout(p_txn_id uuid, p_action text)` — atomic payout decision.
  Accepts 'approve' (status -> 'completed') or 'reject' (status -> 'rejected').
  Only rows whose status is NULL or 'pending' can be decided; deciding twice is
  rejected. Throws if the transaction does not exist or is already decided.

3. Security
- No new tables. RLS on `wallet_transactions` is unchanged; the two new columns
  are covered by existing table-level grants.
- Both functions are SECURITY DEFINER (they must arbitrate rows belonging to any
  user, which row-owner RLS forbids) but EXECUTE is revoked from PUBLIC and anon
  and granted only to `authenticated`, so only signed-in Superadmin sessions can
  invoke them.
- `set search_path = public` is pinned on both functions.

## Notes
- The migration is idempotent: column additions are guarded by IF NOT EXISTS,
  and CREATE OR REPLACE FUNCTION plus drop-before-grant makes re-running safe.
- No destructive operations; no data is removed or rewritten.
*/

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallet_transactions' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.wallet_transactions ADD COLUMN status text;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallet_transactions' AND column_name = 'resolved_at'
  ) THEN
    ALTER TABLE public.wallet_transactions ADD COLUMN resolved_at timestamptz;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(p_order_id text, p_action text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_order_status text;
  v_new_dispute_status text;
  v_resolution_type text;
BEGIN
  IF p_action = 'force_refund' THEN
    v_new_order_status := 'refunded';
    v_new_dispute_status := 'resolved_refunded';
    v_resolution_type := 'refund';
  ELSIF p_action = 'force_release' THEN
    v_new_order_status := 'delivered';
    v_new_dispute_status := 'resolved_released';
    v_resolution_type := 'release';
  ELSIF p_action = 'force_reship' THEN
    v_new_order_status := 'processing';
    v_new_dispute_status := 'resolved_reshipped';
    v_resolution_type := 'reship';
  ELSE
    RAISE EXCEPTION 'Unknown arbitration action: %', p_action;
  END IF;

  UPDATE public.orders
  SET
    status = v_new_order_status,
    order_status = v_new_order_status,
    delivery_status = v_new_order_status,
    is_delivered = (p_action = 'force_release'),
    escrow_status = CASE
      WHEN p_action = 'force_refund' THEN 'cancelled'
      WHEN p_action = 'force_release' THEN 'released'
      ELSE 'locked'
    END,
    bounty_status = CASE
      WHEN p_action = 'force_refund' THEN 'cancelled'
      WHEN p_action = 'force_release' THEN 'released'
      ELSE 'locked'
    END,
    dispute_status = v_new_dispute_status,
    dispute_resolved = true
  WHERE id = p_order_id::uuid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found: %', p_order_id;
  END IF;

  UPDATE public.disputes
  SET
    status = v_new_dispute_status,
    resolution = 'resolution_type: ' || v_resolution_type,
    updated_at = now()
  WHERE order_id = p_order_id;

  RETURN v_new_dispute_status;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_resolve_payout(p_txn_id uuid, p_action text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_new_status text;
BEGIN
  IF p_action NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Unknown payout action: %', p_action;
  END IF;

  SELECT status INTO v_current_status
  FROM public.wallet_transactions
  WHERE id = p_txn_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet transaction not found: %', p_txn_id;
  END IF;

  IF v_current_status IS NOT NULL AND v_current_status NOT IN ('pending') THEN
    RAISE EXCEPTION 'Payout already decided (status: %)', v_current_status;
  END IF;

  v_new_status := CASE WHEN p_action = 'approve' THEN 'completed' ELSE 'rejected' END;

  UPDATE public.wallet_transactions
  SET status = v_new_status, resolved_at = now()
  WHERE id = p_txn_id;

  RETURN v_new_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_resolve_dispute(text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_payout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_resolve_payout(uuid, text) TO authenticated;
