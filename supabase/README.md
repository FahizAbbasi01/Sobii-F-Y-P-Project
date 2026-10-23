# Database

`migrations/` holds plain PostgreSQL files applied in filename order. Apply them **one** way:

- `cd backend && npm run migrate` (recommended; tracks applied files in `schema_migrations`), or
- paste them into the Supabase **SQL Editor** in order, or
- `supabase db push` with the Supabase CLI.

## What the schema enforces (even if API code had a bug)

- An IMEI can exist only once across all devices and SIM slots (`device_imeis` primary key).
- One open ownership record per device; one live listing per device; one pending transfer per device.
- A transfer can only be `completed` when both confirmation timestamps are set.
- One pending stolen report per device; one open purchase request per buyer per listing.
- Prices, text lengths, phone formats and upload sizes/types are checked by constraints.
- `audit_logs` rejects UPDATE and DELETE (trigger).
- Row Level Security is **on** for every table with **no policies**, and the Supabase `anon` / `authenticated`
  roles have all privileges revoked, so the public Supabase REST/GraphQL APIs can read nothing.

## Optional: least-privilege API role

By default the backend connects as `postgres` (simplest for an FYP). For least privilege, run this in the
SQL Editor with your own strong password, then use `devicetrust_api` in `DATABASE_URL` for `npm run dev`
(keep the `postgres` connection for `npm run migrate`):

```sql
create role devicetrust_api login password 'CHANGE-ME-long-random';
grant usage on schema public to devicetrust_api;
grant select, insert, update, delete on all tables in schema public to devicetrust_api;
grant usage, select on all sequences in schema public to devicetrust_api;
revoke update, delete on audit_logs from devicetrust_api;
-- RLS is on, so the role needs policies that admit it:
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('create policy api_all on %I for all to devicetrust_api using (true) with check (true)', t);
  end loop;
end $$;
```
This role cannot create/drop tables, cannot touch other schemas, and cannot alter the audit log.
