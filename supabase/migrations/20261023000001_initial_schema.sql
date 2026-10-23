-- DeviceTrust initial schema
-- Target: Supabase PostgreSQL (also runs on plain PostgreSQL 14+ for local dev/tests).
-- Access model: ONLY the backend API connects to these tables (via DATABASE_URL).
-- The mobile app and admin dashboard never query the database directly.

create extension if not exists pgcrypto;
create extension if not exists citext;

-- ---------- Enums ----------
create type user_role          as enum ('user', 'admin');
create type user_status        as enum ('active', 'suspended');
create type registry_status    as enum ('registered', 'reported_stolen');
create type acquisition_method as enum ('registration', 'transfer', 'admin_adjustment');
create type listing_status     as enum ('active', 'reserved', 'sold', 'withdrawn', 'removed');
create type device_condition   as enum ('new', 'like_new', 'good', 'fair', 'poor');
create type purchase_status    as enum ('pending', 'accepted', 'rejected', 'cancelled', 'completed');
create type transfer_status    as enum ('pending', 'completed', 'cancelled', 'disputed');
create type report_status      as enum ('pending', 'approved', 'rejected');
create type document_kind      as enum ('purchase_receipt', 'box_photo', 'police_report', 'cnic', 'other');
create type review_status      as enum ('pending', 'approved', 'rejected');
create type dispute_status     as enum ('open', 'resolved', 'rejected');

-- ---------- Users ----------
create table users (
  id             uuid primary key default gen_random_uuid(),
  email          citext not null unique,
  full_name      text   not null check (char_length(full_name) between 2 and 100),
  phone          text   check (phone ~ '^\+?[0-9]{10,15}$'),
  city           text,
  password_hash  text   not null,
  role           user_role   not null default 'user',
  status         user_status not null default 'active',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table refresh_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  token_hash  text not null unique,
  expires_at  timestamptz not null,
  revoked_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index refresh_tokens_user_idx on refresh_tokens(user_id);

-- ---------- Devices & IMEIs ----------
create table devices (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references users(id),
  brand            text not null check (char_length(brand) between 1 and 50),
  model            text not null check (char_length(model) between 1 and 80),
  storage_gb       int  check (storage_gb is null or storage_gb between 1 and 4096),
  color            text,
  registry_status  registry_status not null default 'registered',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index devices_owner_idx on devices(owner_id);

-- One row per IMEI; the primary key makes an IMEI globally unique,
-- covering dual-SIM phones (slot 1 and slot 2 can never collide with another device).
create table device_imeis (
  imei       char(15) primary key check (imei ~ '^[0-9]{15}$'),
  device_id  uuid not null references devices(id) on delete cascade,
  slot       smallint not null check (slot in (1, 2)),
  unique (device_id, slot)
);
create index device_imeis_device_idx on device_imeis(device_id);

create table ownership_history (
  id            uuid primary key default gen_random_uuid(),
  device_id     uuid not null references devices(id) on delete cascade,
  owner_id      uuid not null references users(id),
  acquired_via  acquisition_method not null,
  transfer_id   uuid,
  acquired_at   timestamptz not null default now(),
  released_at   timestamptz
);
create index ownership_history_device_idx on ownership_history(device_id);
-- Exactly one open ownership record per device.
create unique index ownership_history_one_open on ownership_history(device_id) where released_at is null;

-- ---------- Marketplace ----------
create table listings (
  id           uuid primary key default gen_random_uuid(),
  device_id    uuid not null references devices(id),
  seller_id    uuid not null references users(id),
  title        text not null check (char_length(title) between 3 and 120),
  description  text check (description is null or char_length(description) <= 2000),
  price        numeric(12,2) not null check (price > 0 and price < 100000000),
  condition    device_condition not null,
  city         text not null check (char_length(city) between 2 and 60),
  status       listing_status not null default 'active',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
-- A device can only have one live (active/reserved) listing at a time.
create unique index listings_one_live_per_device on listings(device_id) where status in ('active', 'reserved');
create index listings_status_created_idx on listings(status, created_at desc);
create index listings_seller_idx on listings(seller_id);

create table listing_images (
  id            uuid primary key default gen_random_uuid(),
  listing_id    uuid not null references listings(id) on delete cascade,
  storage_path  text not null,
  position      smallint not null default 0,
  created_at    timestamptz not null default now()
);
create index listing_images_listing_idx on listing_images(listing_id);

create table purchase_requests (
  id           uuid primary key default gen_random_uuid(),
  listing_id   uuid not null references listings(id),
  buyer_id     uuid not null references users(id),
  offer_price  numeric(12,2) not null check (offer_price > 0),
  message      text check (message is null or char_length(message) <= 500),
  status       purchase_status not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
-- A buyer can only have one open request per listing.
create unique index purchase_requests_one_open on purchase_requests(listing_id, buyer_id) where status in ('pending', 'accepted');
-- Only one accepted request per listing.
create unique index purchase_requests_one_accepted on purchase_requests(listing_id) where status = 'accepted';
create index purchase_requests_buyer_idx on purchase_requests(buyer_id);

-- ---------- Ownership transfers ----------
create table ownership_transfers (
  id                   uuid primary key default gen_random_uuid(),
  device_id            uuid not null references devices(id),
  from_user_id         uuid not null references users(id),
  to_user_id           uuid not null references users(id),
  purchase_request_id  uuid references purchase_requests(id),
  status               transfer_status not null default 'pending',
  seller_confirmed_at  timestamptz,
  buyer_confirmed_at   timestamptz,
  cancelled_by         uuid references users(id),
  created_at           timestamptz not null default now(),
  completed_at         timestamptz,
  check (from_user_id <> to_user_id),
  check (status <> 'completed' or (seller_confirmed_at is not null and buyer_confirmed_at is not null))
);
-- Never more than one in-flight transfer per device.
create unique index ownership_transfers_one_pending on ownership_transfers(device_id) where status = 'pending';
create index ownership_transfers_from_idx on ownership_transfers(from_user_id);
create index ownership_transfers_to_idx on ownership_transfers(to_user_id);

alter table ownership_history
  add constraint ownership_history_transfer_fk foreign key (transfer_id) references ownership_transfers(id);

-- ---------- Stolen reports ----------
create table stolen_reports (
  id             uuid primary key default gen_random_uuid(),
  device_id      uuid not null references devices(id),
  reporter_id    uuid not null references users(id),
  incident_date  date not null,
  location       text not null check (char_length(location) between 2 and 200),
  description    text not null check (char_length(description) between 10 and 2000),
  police_report_number text,
  status         report_status not null default 'pending',
  reviewed_by    uuid references users(id),
  review_note    text,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now()
);
create unique index stolen_reports_one_pending on stolen_reports(device_id) where status = 'pending';
create index stolen_reports_status_idx on stolen_reports(status, created_at desc);

-- ---------- Documents ----------
create table documents (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references users(id),
  device_id      uuid references devices(id),
  stolen_report_id uuid references stolen_reports(id),
  kind           document_kind not null,
  storage_path   text not null,
  mime_type      text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes     int  not null check (size_bytes > 0 and size_bytes <= 5242880),
  status         review_status not null default 'pending',
  reviewed_by    uuid references users(id),
  review_note    text,
  created_at     timestamptz not null default now()
);
create index documents_status_idx on documents(status, created_at desc);

-- ---------- Disputes ----------
create table disputes (
  id           uuid primary key default gen_random_uuid(),
  transfer_id  uuid references ownership_transfers(id),
  device_id    uuid not null references devices(id),
  raised_by    uuid not null references users(id),
  reason       text not null check (char_length(reason) between 10 and 2000),
  status       dispute_status not null default 'open',
  resolution   text,
  resolved_by  uuid references users(id),
  resolved_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index disputes_status_idx on disputes(status, created_at desc);

-- ---------- Notifications ----------
create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  type        text not null,
  title       text not null,
  body        text not null,
  data        jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_user_idx on notifications(user_id, created_at desc);

-- ---------- Registry lookups & audit ----------
create table imei_lookups (
  id          bigserial primary key,
  imei        char(15) not null,
  user_id     uuid references users(id),
  result      text not null,
  ip          inet,
  created_at  timestamptz not null default now()
);
create index imei_lookups_imei_idx on imei_lookups(imei, created_at desc);

create table audit_logs (
  id           bigserial primary key,
  actor_id     uuid references users(id),
  action       text not null,
  entity_type  text not null,
  entity_id    text,
  metadata     jsonb not null default '{}'::jsonb,
  ip           inet,
  created_at   timestamptz not null default now()
);
create index audit_logs_entity_idx on audit_logs(entity_type, entity_id);
create index audit_logs_created_idx on audit_logs(created_at desc);

-- Audit log is append-only: block UPDATE/DELETE at the database level.
create or replace function audit_logs_immutable() returns trigger language plpgsql as $$
begin
  raise exception 'audit_logs is append-only';
end $$;
create trigger audit_logs_no_update before update or delete on audit_logs
  for each row execute function audit_logs_immutable();

-- ---------- updated_at triggers ----------
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger users_updated_at before update on users for each row execute function set_updated_at();
create trigger devices_updated_at before update on devices for each row execute function set_updated_at();
create trigger listings_updated_at before update on listings for each row execute function set_updated_at();
create trigger purchase_requests_updated_at before update on purchase_requests for each row execute function set_updated_at();

-- ---------- Lock down Supabase's public API roles ----------
-- RLS on + no policies = anon/authenticated (PostgREST) cannot read or write anything.
-- The backend connects with its own role (see 20261023000002) or the postgres role, which bypasses RLS.
do $$
declare t text;
begin
  foreach t in array array['users','refresh_tokens','devices','device_imeis','ownership_history','listings',
    'listing_images','purchase_requests','ownership_transfers','stolen_reports','documents','disputes',
    'notifications','imei_lookups','audit_logs']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema public from anon, authenticated';
    execute 'revoke all on all sequences in schema public from anon, authenticated';
    execute 'revoke all on all functions in schema public from anon, authenticated';
  end if;
end $$;
