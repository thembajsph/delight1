-- ═══════════════════════════════════════════════════════════════════════════════
-- Delight — Full Database Schema (safe re-run version)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Drop existing tables cleanly (in reverse dependency order) ───────────────
drop table if exists public.unmatched_payments cascade;
drop table if exists public.tickets           cascade;
drop table if exists public.transactions      cascade;
drop table if exists public.wallets           cascade;
drop table if exists public.events            cascade;
drop table if exists public.profiles          cascade;

-- ── Profiles ──────────────────────────────────────────────────────────────────
create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  email          text unique,
  display_name   text,
  phone          text,
  avatar_url     text,
  role           text default 'consumer'
                   check (role in ('consumer','business','organizer','admin')),
  is_verified    boolean default false,
  created_at     timestamptz default now()
);

-- ── Events (before tickets — tickets FK references events) ───────────────────
create table public.events (
  id             uuid primary key default gen_random_uuid(),
  organizer_id   uuid references public.profiles(id),
  name           text not null,
  description    text,
  venue          text,
  city           text,
  event_date     timestamptz,
  image_url      text,
  category       text,
  ticket_tiers   jsonb,
  is_published   boolean default false,
  created_at     timestamptz default now()
);

-- ── Wallets ───────────────────────────────────────────────────────────────────
create table public.wallets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid unique references public.profiles(id) on delete cascade,
  xrp_address    text,
  balance_dc     numeric default 0,
  xrp_price      numeric default 9.50,
  last_synced    timestamptz,
  created_at     timestamptz default now()
);

-- ── Transactions ──────────────────────────────────────────────────────────────
create table public.transactions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references public.profiles(id),
  type           text not null
                   check (type in ('send','receive','topup','cashout',
                                   'ticket_purchase','ticket_sale','reward')),
  amount_dc      numeric not null,
  amount_zar     numeric not null,
  fee_dc         numeric default 0,
  status         text default 'pending'
                   check (status in ('pending','completed','failed')),
  reference      text,
  metadata       jsonb,
  created_at     timestamptz default now()
);

-- ── Tickets ───────────────────────────────────────────────────────────────────
create table public.tickets (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references public.profiles(id),
  event_id         uuid references public.events(id),
  tier             text not null,
  price_zar        numeric not null,
  owner_address    text,
  token_id         text,
  metadata_uri     text,
  nft_tx           jsonb,
  status           text default 'pending_mint'
                     check (status in ('pending_mint','active','used',
                                       'listed_for_sale','transferred')),
  is_for_sale      boolean default false,
  resale_price_zar numeric,
  is_used          boolean default false,
  minted_at        timestamptz,
  used_at          timestamptz,
  created_at       timestamptz default now()
);

-- ── Unmatched EFT payments (wrong reference) ──────────────────────────────────
create table public.unmatched_payments (
  id          uuid primary key default gen_random_uuid(),
  reference   text,
  amount_zar  numeric,
  payload     jsonb,
  received_at timestamptz default now()
);

-- ── Atomic DC transfer function ───────────────────────────────────────────────
create or replace function transfer_dc(
  p_sender_id    uuid,
  p_recipient_id uuid,
  p_amount_dc    numeric,
  p_fee_dc       numeric
) returns void
language plpgsql security definer as $$
declare
  v_sender_balance numeric;
begin
  if p_sender_id < p_recipient_id then
    select balance_dc into v_sender_balance
      from wallets where user_id = p_sender_id for update;
    perform 1 from wallets where user_id = p_recipient_id for update;
  else
    perform 1 from wallets where user_id = p_recipient_id for update;
    select balance_dc into v_sender_balance
      from wallets where user_id = p_sender_id for update;
  end if;

  if v_sender_balance < (p_amount_dc + p_fee_dc) then
    raise exception 'Insufficient balance: % DC available, % DC needed',
      v_sender_balance, (p_amount_dc + p_fee_dc);
  end if;

  update wallets
    set balance_dc = balance_dc - p_amount_dc - p_fee_dc
    where user_id = p_sender_id;

  update wallets
    set balance_dc = balance_dc + p_amount_dc
    where user_id = p_recipient_id;
end;
$$;

-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table public.profiles           enable row level security;
alter table public.wallets            enable row level security;
alter table public.transactions       enable row level security;
alter table public.tickets            enable row level security;
alter table public.events             enable row level security;
alter table public.unmatched_payments enable row level security;

create policy "profiles_own"     on public.profiles
  for all using (auth.uid() = id);

create policy "wallets_own"      on public.wallets
  for all using (auth.uid() = user_id);

create policy "transactions_own" on public.transactions
  for all using (auth.uid() = user_id);

create policy "tickets_own"      on public.tickets
  for all using (auth.uid() = user_id);

create policy "tickets_for_sale" on public.tickets
  for select using (is_for_sale = true);

create policy "events_published" on public.events
  for select using (is_published = true);

create policy "events_own"       on public.events
  for all using (auth.uid() = organizer_id);

-- ── Trigger: auto-create profile + wallet on signup ───────────────────────────
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email, display_name, avatar_url)
    values (
      new.id,
      new.email,
      coalesce(new.raw_user_meta_data->>'full_name',
               split_part(new.email, '@', 1)),
      coalesce(new.raw_user_meta_data->>'avatar_url', null)
    )
    on conflict (id) do nothing;

  insert into public.wallets (user_id, balance_dc)
    values (new.id, 0)
    on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ── Data API grants ─────────────────────────────────────────────────────────
-- Required from Oct 30 2026 onward: Supabase no longer auto-grants Data API
-- access to new tables. Without these, PostgREST/supabase-js calls return
-- "permission denied" even though RLS policies above are correct — RLS
-- governs which ROWS are visible, these grants govern whether the role can
-- reach the table via the API at all. Both layers are required together.

grant select on public.profiles to anon;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.profiles to service_role;

grant select on public.events to anon;
grant select, insert, update, delete on public.events to authenticated;
grant select, insert, update, delete on public.events to service_role;

-- No anon grant: wallet balances have no logged-out use case. RLS would
-- block anon anyway, but there's no reason to let the request reach the
-- table at all.
grant select, insert, update, delete on public.wallets to authenticated;
grant select, insert, update, delete on public.wallets to service_role;

-- Same reasoning — transaction history is never public.
grant select, insert, update, delete on public.transactions to authenticated;
grant select, insert, update, delete on public.transactions to service_role;

grant select on public.tickets to anon;
grant select, insert, update, delete on public.tickets to authenticated;
grant select, insert, update, delete on public.tickets to service_role;

-- Internal reconciliation table — service_role (backend/edge functions)
-- only. No end user, logged in or not, should query this directly.
grant select, insert, update, delete on public.unmatched_payments to service_role;
