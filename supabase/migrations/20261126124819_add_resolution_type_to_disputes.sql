/*
# Add resolution_type to disputes

1. Modified Tables
- `disputes`: new nullable text column `resolution_type` recording how a dispute
  ended ('refund' | 'release' | 'reship'). Existing rows leave it NULL, which is
  valid for still-open disputes.

2. Security
- Explicitly grant UPDATE on the new column to `authenticated` so the browser
  app (anon-key client with a signed-in session) can write it. RLS is already
  enabled on `disputes` and remains unchanged.
*/

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS resolution_type text;

GRANT UPDATE (resolution_type) ON public.disputes TO authenticated;