/*
# Admin payout queue listing function

1. New functions (SECURITY DEFINER, callable by authenticated only)
- `admin_list_payouts()` — returns every `wallet_transactions` row where
  tx_type = 'upi_payout', newest first, with id, consumer_email, upi_id,
  cash_amount, created_at, and status (NULL = pending). This is the read side of
  the Superadmin UPI payout approval queue: `wallet_transactions` RLS is
  owner-scoped (each user can only see their own rows), so an admin client
  cannot list other users' payouts directly. This function reads them with
  elevated rights while write access still goes through `admin_resolve_payout`.

2. Security
- SECURITY DEFINER with pinned `set search_path = public`.
- EXECUTE revoked from PUBLIC and anon, granted only to `authenticated`.
- Read-only: performs a SELECT, no writes.

## Notes
- Idempotent via CREATE OR REPLACE FUNCTION plus drop-before-grant.
- No destructive operations.
*/

CREATE OR REPLACE FUNCTION public.admin_list_payouts()
RETURNS TABLE (id uuid, consumer_email text, upi_id text, cash_amount numeric, created_at timestamptz, status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT wt.id, wt.consumer_email, wt.upi_id, wt.cash_amount, wt.created_at, wt.status
  FROM public.wallet_transactions wt
  WHERE wt.tx_type = 'upi_payout'
  ORDER BY wt.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_payouts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_payouts() TO authenticated;
