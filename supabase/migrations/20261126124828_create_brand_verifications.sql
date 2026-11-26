/*
# Create brand_verifications table

1. New Tables
- `brand_verifications`: one row per brand (keyed by normalized brand name)
  storing the admin's marketplace compliance status.
  - `brand_name` (text, primary key) — UPPER(TRIM(brand_name)) as used by the app.
  - `status` (text) — 'verified' | 'pending' | 'suspended'.
  - `updated_at` (timestamptz).

2. Security
- Enable RLS.
- SELECT: any authenticated user (brands and consumers read brand status).
- INSERT/UPDATE: only the superadmin, identified by the `role: superadmin`
  app_metadata claim in the signed JWT (user-immutable, so safe for authz).
- Grants limited to authenticated for the verbs above.
*/

CREATE TABLE IF NOT EXISTS public.brand_verifications (
  brand_name text PRIMARY KEY,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('verified', 'pending', 'suspended')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.brand_verifications ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.brand_verifications TO authenticated;

DROP POLICY IF EXISTS "Anyone authenticated can read brand status" ON public.brand_verifications;
CREATE POLICY "Anyone authenticated can read brand status"
ON public.brand_verifications FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Superadmin can insert brand status" ON public.brand_verifications;
CREATE POLICY "Superadmin can insert brand status"
ON public.brand_verifications FOR INSERT
TO authenticated
WITH CHECK (auth.jwt() -> 'app_metadata' ->> 'role' = 'superadmin');

DROP POLICY IF EXISTS "Superadmin can update brand status" ON public.brand_verifications;
CREATE POLICY "Superadmin can update brand status"
ON public.brand_verifications FOR UPDATE
TO authenticated
USING (auth.jwt() -> 'app_metadata' ->> 'role' = 'superadmin')
WITH CHECK (auth.jwt() -> 'app_metadata' ->> 'role' = 'superadmin');