-- ─────────────────────────────────────────────────────────────────────────────
-- Real analytics for the admin dashboard. Replaces the old hardcoded/random
-- demo numbers (revenue, geography, time-spent, return-visit charts) with a
-- genuine, if initially sparse, data source — this app is pre-launch, so an
-- honest dashboard shows small real numbers (or "not enough data yet"), not
-- a confident simulation of numbers that were never real.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── City on profiles — lets "User Geography" aggregate real signups ──────────
alter table public.profiles add column if not exists city text;

-- ── Lightweight usage telemetry ───────────────────────────────────────────────
-- One row per app-open and per screen view, tagged with a client-generated
-- session id so session length / screens-per-session can be computed for
-- real. No PII beyond user_id — city/device aren't collected.
create table if not exists public.analytics_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  session_id  text not null,
  event_type  text not null check (event_type in ('app_open','screen_view')),
  screen      text,
  created_at  timestamptz default now()
);

create index if not exists analytics_events_created_idx on public.analytics_events(created_at);
create index if not exists analytics_events_user_idx    on public.analytics_events(user_id);
create index if not exists analytics_events_session_idx on public.analytics_events(session_id);

alter table public.analytics_events enable row level security;

-- Any signed-in user can log their own events.
drop policy if exists "analytics_events_insert_own" on public.analytics_events;
create policy "analytics_events_insert_own" on public.analytics_events
  for insert with check (auth.uid() = user_id);

-- Only admins can read the raw log (the dashboard reads via aggregate
-- queries run as the signed-in admin).
drop policy if exists "analytics_events_admin_read" on public.analytics_events;
create policy "analytics_events_admin_read" on public.analytics_events
  for select using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

grant select, insert on public.analytics_events to authenticated;
grant select, insert on public.analytics_events to service_role;

-- ── Admin-entered business inputs ─────────────────────────────────────────────
-- Figures like customer-acquisition cost or an NPS survey result don't live
-- in any product table — they come from the business side. Rather than
-- hardcoding invented numbers, the Scale Readiness tab reads/writes them
-- here, and is honest about "not set yet" until an admin fills them in.
create table if not exists public.admin_settings (
  key         text primary key,
  value       numeric,
  updated_at  timestamptz default now()
);

alter table public.admin_settings enable row level security;

drop policy if exists "admin_settings_admin_all" on public.admin_settings;
create policy "admin_settings_admin_all" on public.admin_settings
  for all using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

grant select, insert, update, delete on public.admin_settings to authenticated;
grant select, insert, update, delete on public.admin_settings to service_role;

-- ── Top users by real transaction volume ──────────────────────────────────────
-- Used by the admin dashboard's "Top Users by Volume" table — replaces a
-- hardcoded list of five fake names/amounts with a real aggregate over
-- completed transactions.
create or replace function public.get_top_users_by_volume(p_limit int default 5)
returns table (user_id uuid, display_name text, role text, total_zar numeric)
language sql security definer as $$
  select t.user_id, p.display_name, p.role, sum(t.amount_zar) as total_zar
  from public.transactions t
  join public.profiles p on p.id = t.user_id
  where t.status = 'completed'
  group by t.user_id, p.display_name, p.role
  order by total_zar desc
  limit p_limit;
$$;

grant execute on function public.get_top_users_by_volume(int) to authenticated;
