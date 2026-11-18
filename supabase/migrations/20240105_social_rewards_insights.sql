-- ─────────────────────────────────────────────────────────────────────────────
-- Real data for: Profile (followers / following / posts / events), Rewards &
-- Leaderboard, and Event / Indoor Insights.
--
-- Before this migration those screens showed hardcoded numbers (984 followers,
-- "Amara Diallo" on the leaderboard, a fake R284,600 event). Everything below
-- gives them a real source. All cross-user reads go through security-definer
-- functions that return ONLY public fields (never email / phone), because the
-- profiles table is RLS-locked to its owner.
-- ─────────────────────────────────────────────────────────────────────────────

-- ═════════════════════════════ PROFILE / SOCIAL ══════════════════════════════

alter table public.profiles add column if not exists city            text;
alter table public.profiles add column if not exists username        text;
alter table public.profiles add column if not exists bio             text;
alter table public.profiles add column if not exists follower_count  int not null default 0;
alter table public.profiles add column if not exists following_count int not null default 0;
create unique index if not exists profiles_username_key
  on public.profiles (lower(username)) where username is not null;

create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows(followee_id);

alter table public.follows enable row level security;
drop policy if exists "follows_read"   on public.follows;
drop policy if exists "follows_insert" on public.follows;
drop policy if exists "follows_delete" on public.follows;
create policy "follows_read"   on public.follows for select
  using (auth.uid() in (follower_id, followee_id));
create policy "follows_insert" on public.follows for insert
  with check (auth.uid() = follower_id);
create policy "follows_delete" on public.follows for delete
  using (auth.uid() = follower_id);
grant select, insert, delete on public.follows to authenticated;
grant select, insert, update, delete on public.follows to service_role;

-- Keep the denormalised counters on profiles in sync.
create or replace function public.follows_count_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    update public.profiles set follower_count  = follower_count  + 1 where id = new.followee_id;
    update public.profiles set following_count = following_count + 1 where id = new.follower_id;
  elsif TG_OP = 'DELETE' then
    update public.profiles set follower_count  = greatest(follower_count  - 1, 0) where id = old.followee_id;
    update public.profiles set following_count = greatest(following_count - 1, 0) where id = old.follower_id;
  end if;
  return null;
end; $$;
drop trigger if exists follows_count on public.follows;
create trigger follows_count after insert or delete on public.follows
  for each row execute function public.follows_count_trigger();

-- Public profile numbers (computed live, so they can never drift).
create or replace function public.get_profile_stats(p_user uuid)
returns jsonb language sql security definer stable set search_path = public as $$
  select jsonb_build_object(
    'followers', (select count(*) from follows where followee_id = p_user),
    'following', (select count(*) from follows where follower_id = p_user),
    'posts',     (select count(*) from posts   where user_id     = p_user),
    -- "Events" = distinct events the user holds / used a ticket for, plus
    -- events they organise.
    'events',    (select count(*) from (
                    select event_id from tickets
                     where user_id = p_user and event_id is not null
                       and status in ('active','used','listed_for_sale')
                    union
                    select id from events where organizer_id = p_user
                  ) e)
  );
$$;

create or replace function public.get_profile_events(p_user uuid)
returns table (id uuid, name text, event_date timestamptz, venue text,
               city text, image_url text, relation text)
language sql security definer stable set search_path = public as $$
  select e.id, e.name, e.event_date, e.venue, e.city, e.image_url,
         case when e.organizer_id = p_user then 'organiser' else 'attending' end
  from events e
  where e.organizer_id = p_user
     or e.id in (select event_id from tickets
                  where user_id = p_user and event_id is not null
                    and status in ('active','used','listed_for_sale'))
  order by e.event_date desc nulls last
  limit 100;
$$;

create or replace function public.get_followers(p_user uuid)
returns table (id uuid, display_name text, username text, avatar_url text,
               city text, is_following boolean)
language sql security definer stable set search_path = public as $$
  select p.id, p.display_name, p.username, p.avatar_url, p.city,
         exists(select 1 from follows m where m.follower_id = auth.uid()
                                          and m.followee_id = p.id)
  from follows f join profiles p on p.id = f.follower_id
  where f.followee_id = p_user
  order by f.created_at desc limit 200;
$$;

create or replace function public.get_following(p_user uuid)
returns table (id uuid, display_name text, username text, avatar_url text,
               city text, is_following boolean)
language sql security definer stable set search_path = public as $$
  select p.id, p.display_name, p.username, p.avatar_url, p.city,
         exists(select 1 from follows m where m.follower_id = auth.uid()
                                          and m.followee_id = p.id)
  from follows f join profiles p on p.id = f.followee_id
  where f.follower_id = p_user
  order by f.created_at desc limit 200;
$$;

-- Find people to follow (name / username only — never email or phone).
create or replace function public.search_people(p_query text)
returns table (id uuid, display_name text, username text, avatar_url text,
               city text, is_following boolean)
language sql security definer stable set search_path = public as $$
  select p.id, p.display_name, p.username, p.avatar_url, p.city,
         exists(select 1 from follows m where m.follower_id = auth.uid()
                                          and m.followee_id = p.id)
  from profiles p
  where char_length(trim(p_query)) >= 2
    and p.id <> auth.uid()
    and (p.display_name ilike '%' || trim(p_query) || '%'
      or p.username     ilike '%' || trim(p_query) || '%')
  order by p.follower_count desc, p.display_name
  limit 25;
$$;

-- ═════════════════════════════ REWARDS ═══════════════════════════════════════
-- Tasks are verified SERVER-SIDE from real activity. The client can no longer
-- credit itself (the old screen called walletProvider.addAmount locally).
-- Tasks that cannot be verified (share to Instagram/TikTok) are not offered.
--
-- BUSINESS NOTE: every claimed reward credits wallets.balance_dc, i.e. it is a
-- liability Delight must be able to honour at cash-out. Tune reward_dc, or set
-- active=false, from the dashboard / SQL editor at any time.

create table if not exists public.reward_tasks (
  id          text primary key,
  title       text not null,
  description text,
  emoji       text default '🎁',
  reward_dc   numeric not null check (reward_dc >= 0),
  active      boolean not null default true,
  sort_order  int default 0
);

create table if not exists public.reward_claims (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  task_id    text not null references public.reward_tasks(id),
  claim_date date not null,
  amount_dc  numeric not null,
  created_at timestamptz default now(),
  primary key (user_id, task_id, claim_date)
);

alter table public.reward_tasks  enable row level security;
alter table public.reward_claims enable row level security;
drop policy if exists "reward_tasks_read"   on public.reward_tasks;
drop policy if exists "reward_claims_own"   on public.reward_claims;
create policy "reward_tasks_read" on public.reward_tasks for select using (true);
create policy "reward_claims_own" on public.reward_claims for select using (auth.uid() = user_id);
grant select on public.reward_tasks  to authenticated;
grant select on public.reward_claims to authenticated;
grant select, insert, update, delete on public.reward_tasks  to service_role;
grant select, insert, update, delete on public.reward_claims to service_role;

insert into public.reward_tasks (id, title, description, emoji, reward_dc, sort_order) values
  ('post_today',   'Post today',        'Share anything to your feed',        '📸', 0.10, 1),
  ('like_5',       'Like 5 posts',      'Like 5 posts from other people',     '❤️', 0.05, 2),
  ('send_payment', 'Send a payment',    'Pay someone using Delight',          '💸', 0.05, 3),
  ('view_event',   'View an event',     'Discover events near you',           '🎟', 0.02, 4)
on conflict (id) do nothing;

-- "Today" is South African time so the daily reset matches users' day.
create or replace function public._sa_today() returns date
language sql stable as $$ select (now() at time zone 'Africa/Johannesburg')::date $$;

create or replace function public._task_completed(p_user uuid, p_task text)
returns boolean language plpgsql security definer stable set search_path = public as $$
declare v_today date := public._sa_today();
begin
  if p_task = 'post_today' then
    return exists(select 1 from posts where user_id = p_user
      and (created_at at time zone 'Africa/Johannesburg')::date = v_today);
  elsif p_task = 'like_5' then
    return (select count(*) from post_likes l join posts po on po.id = l.post_id
             where l.user_id = p_user and po.user_id <> p_user
               and (l.created_at at time zone 'Africa/Johannesburg')::date = v_today) >= 5;
  elsif p_task = 'send_payment' then
    return exists(select 1 from transactions where user_id = p_user
      and type = 'send' and status = 'completed'
      and (created_at at time zone 'Africa/Johannesburg')::date = v_today);
  elsif p_task = 'view_event' then
    return exists(select 1 from analytics_events where user_id = p_user
      and event_type = 'screen_view' and screen in ('Events','Event Detail')
      and (created_at at time zone 'Africa/Johannesburg')::date = v_today);
  end if;
  return false;
end; $$;

create or replace function public._app_open_streak(p_user uuid)
returns int language plpgsql security definer stable set search_path = public as $$
declare v_day date := public._sa_today(); v_n int := 0;
begin
  if not exists(select 1 from analytics_events where user_id = p_user
      and event_type = 'app_open'
      and (created_at at time zone 'Africa/Johannesburg')::date = v_day) then
    v_day := v_day - 1;
  end if;
  while v_n < 400 and exists(select 1 from analytics_events where user_id = p_user
      and event_type = 'app_open'
      and (created_at at time zone 'Africa/Johannesburg')::date = v_day) loop
    v_n := v_n + 1; v_day := v_day - 1;
  end loop;
  return v_n;
end; $$;

create or replace function public.get_rewards_today()
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_today date := public._sa_today();
  v_monday date; v_week jsonb := '[]'::jsonb; v_i int; v_tasks jsonb;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  v_monday := v_today - (extract(isodow from v_today)::int - 1);
  for v_i in 0..6 loop
    v_week := v_week || to_jsonb(exists(select 1 from analytics_events
      where user_id = v_uid and event_type = 'app_open'
        and (created_at at time zone 'Africa/Johannesburg')::date = v_monday + v_i));
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'title', t.title, 'description', t.description,
      'emoji', t.emoji, 'reward', t.reward_dc,
      'claimed',  exists(select 1 from reward_claims c where c.user_id = v_uid
                          and c.task_id = t.id and c.claim_date = v_today),
      'eligible', public._task_completed(v_uid, t.id)
    ) order by t.sort_order), '[]'::jsonb)
  into v_tasks from reward_tasks t where t.active;

  return jsonb_build_object(
    'tasks', v_tasks,
    'streak', public._app_open_streak(v_uid),
    'week', v_week,
    'today_index', extract(isodow from v_today)::int - 1,
    'earned_today', coalesce((select sum(amount_dc) from reward_claims
                               where user_id = v_uid and claim_date = v_today), 0));
end; $$;

create or replace function public.claim_reward_task(p_task_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_today date := public._sa_today();
  v_task reward_tasks; v_price numeric; v_bal numeric;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  select * into v_task from reward_tasks where id = p_task_id and active;
  if not found then raise exception 'This reward is not available'; end if;
  if not public._task_completed(v_uid, p_task_id) then
    raise exception 'Complete the task first';
  end if;

  -- Row lock on the wallet serialises concurrent claims.
  select balance_dc, coalesce(xrp_price, 9.50) into v_bal, v_price
    from wallets where user_id = v_uid for update;
  if not found then raise exception 'Wallet not found'; end if;

  insert into reward_claims (user_id, task_id, claim_date, amount_dc)
    values (v_uid, p_task_id, v_today, v_task.reward_dc)
    on conflict do nothing;
  if not found then raise exception 'Already claimed today'; end if;

  update wallets set balance_dc = balance_dc + v_task.reward_dc where user_id = v_uid;
  insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status,
                            reference, metadata)
    values (v_uid, 'reward', v_task.reward_dc, v_task.reward_dc * v_price, 0,
            'completed', 'reward:' || p_task_id || ':' || v_today,
            jsonb_build_object('task', p_task_id));

  return jsonb_build_object('reward', v_task.reward_dc,
                            'balance_dc', v_bal + v_task.reward_dc);
end; $$;

-- Real counters behind the NFT-badge progress bars.
create or replace function public.get_my_stats()
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare v_uid uuid := auth.uid(); v_created timestamptz;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  select created_at into v_created from profiles where id = v_uid;
  return jsonb_build_object(
    'tickets_bought', (select count(*) from transactions
                        where user_id = v_uid and type = 'ticket_purchase'
                          and status = 'completed'),
    'payments_sent',  (select count(*) from transactions
                        where user_id = v_uid and type = 'send' and status = 'completed'),
    'events_attended',(select count(distinct event_id) from tickets
                        where user_id = v_uid and is_used = true),
    'vip_events',     (select count(distinct event_id) from tickets
                        where user_id = v_uid and tier ilike '%vip%'
                          and status in ('active','used','listed_for_sale')),
    'best_post_likes',(select coalesce(max(likes_count), 0) from posts where user_id = v_uid),
    'streak',         public._app_open_streak(v_uid),
    'early_adopter',  (select count(*) from profiles where created_at <= v_created) <= 1000
  );
end; $$;

-- Leaderboard = most DC EARNED from rewards in the period (engagement score).
-- Deliberately NOT spending volume: ranking people by how much money they hold
-- or spend would publish private financial behaviour.
create or replace function public.get_leaderboard(p_city text, p_period text)
returns table (rank bigint, user_id uuid, display_name text, avatar_url text,
               city text, score numeric)
language sql security definer stable set search_path = public as $$
  select row_number() over (order by sum(t.amount_dc) desc, min(p.created_at)) as rank,
         p.id, p.display_name, p.avatar_url, p.city, sum(t.amount_dc) as score
  from transactions t join profiles p on p.id = t.user_id
  where t.type = 'reward' and t.status = 'completed'
    and t.created_at >= case when p_period = 'month'
          then date_trunc('month', now()) else date_trunc('week', now()) end
    and (p_city is null or p_city = '' or p_city = 'All Africa' or p.city = p_city)
  group by p.id, p.display_name, p.avatar_url, p.city
  order by 1
  limit 50;
$$;

create or replace function public.get_leaderboard_cities()
returns text[] language sql security definer stable set search_path = public as $$
  select coalesce(array_agg(city order by n desc), '{}') from (
    select city, count(*) n from profiles
     where city is not null and city <> '' group by city order by n desc limit 8) c;
$$;

-- ═════════════════════════════ EVENT INSIGHTS ════════════════════════════════
-- Vendor / stall sales need a tagged payment trail. Payments made through
-- pay_event_vendor() carry event_id + vendor_id (+ optional staff_id), which is
-- what Sales Insights and Indoor Insights aggregate. Untagged P2P payments are
-- (correctly) not counted as event sales.

alter table public.events add column if not exists venue_type text;

create table if not exists public.event_vendors (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,
  owner_id     uuid references public.profiles(id) on delete set null,
  name         text not null,
  category     text not null default 'Other',   -- Food|Drinks|Merchandise|VIP Services|Entertainment|Other
  emoji        text default '🏪',
  section_type text,                            -- bar|vip_booth|concession|merch|offering_point|floor_service…
  created_at   timestamptz default now()
);
create index if not exists event_vendors_event_idx on public.event_vendors(event_id);

alter table public.event_vendors enable row level security;
drop policy if exists "event_vendors_read"   on public.event_vendors;
drop policy if exists "event_vendors_manage" on public.event_vendors;
create policy "event_vendors_read" on public.event_vendors for select using (
  exists (select 1 from public.events e where e.id = event_id
          and (e.is_published or e.organizer_id = auth.uid())));
create policy "event_vendors_manage" on public.event_vendors for all using (
  exists (select 1 from public.events e where e.id = event_id
          and e.organizer_id = auth.uid()));
grant select, insert, update, delete on public.event_vendors to authenticated;
grant select, insert, update, delete on public.event_vendors to service_role;

alter table public.transactions add column if not exists event_id  uuid references public.events(id)        on delete set null;
alter table public.transactions add column if not exists vendor_id uuid references public.event_vendors(id) on delete set null;
alter table public.transactions add column if not exists staff_id  uuid references public.profiles(id)      on delete set null;
create index if not exists transactions_event_idx  on public.transactions(event_id)  where event_id  is not null;
create index if not exists transactions_vendor_idx on public.transactions(vendor_id) where vendor_id is not null;

-- Pay a vendor at an event. Atomic, ledger-only (same 0.5% fee as P2P sends).
create or replace function public.pay_event_vendor(
  p_vendor_id uuid, p_zar numeric, p_staff uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_vendor event_vendors; v_price numeric;
  v_dc numeric; v_fee numeric; v_bal numeric;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if p_zar is null or p_zar < 1 then raise exception 'Minimum payment is R1'; end if;
  select * into v_vendor from event_vendors where id = p_vendor_id;
  if not found then raise exception 'Vendor not found'; end if;
  if v_vendor.owner_id is null then raise exception 'This vendor cannot receive payments yet'; end if;
  if v_vendor.owner_id = v_uid then raise exception 'You cannot pay yourself'; end if;

  select coalesce(xrp_price, 9.50) into v_price from wallets where user_id = v_uid;
  v_dc  := p_zar / v_price;
  v_fee := v_dc * 0.005;

  -- Lock both wallets in a stable order to avoid deadlocks.
  if v_uid < v_vendor.owner_id then
    select balance_dc into v_bal from wallets where user_id = v_uid for update;
    perform 1 from wallets where user_id = v_vendor.owner_id for update;
  else
    perform 1 from wallets where user_id = v_vendor.owner_id for update;
    select balance_dc into v_bal from wallets where user_id = v_uid for update;
  end if;
  if v_bal is null then raise exception 'Wallet not found'; end if;
  if v_bal < v_dc + v_fee then raise exception 'Not enough balance'; end if;

  update wallets set balance_dc = balance_dc - v_dc - v_fee where user_id = v_uid;
  update wallets set balance_dc = balance_dc + v_dc         where user_id = v_vendor.owner_id;

  insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status,
                            reference, event_id, vendor_id, staff_id, metadata)
    values (v_uid, 'send', v_dc, p_zar, v_fee, 'completed', 'vendor:' || p_vendor_id,
            v_vendor.event_id, p_vendor_id, p_staff,
            jsonb_build_object('vendor', v_vendor.name));
  insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status,
                            reference, event_id, vendor_id, staff_id, metadata)
    values (v_vendor.owner_id, 'receive', v_dc, p_zar, 0, 'completed', 'from:' || v_uid,
            v_vendor.event_id, p_vendor_id, p_staff,
            jsonb_build_object('vendor', v_vendor.name));

  return jsonb_build_object('zar', p_zar, 'vendor', v_vendor.name);
end; $$;

-- One call powers every tab of Sales Insights AND Indoor Insights.
-- Only the event's organiser (or an admin) may call it.
create or replace function public.get_event_insights(p_event_id uuid)
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_ev events; v_tz text := 'Africa/Johannesburg';
  v_ok boolean; v_total numeric; v_prev uuid; v_prev_total numeric;
  v_vs numeric := null;
begin
  select * into v_ev from events where id = p_event_id;
  if not found then raise exception 'Event not found'; end if;
  v_ok := v_ev.organizer_id = v_uid
          or exists(select 1 from profiles where id = v_uid and role = 'admin');
  if not coalesce(v_ok, false) then raise exception 'Not authorised'; end if;

  select coalesce(sum(amount_zar), 0) into v_total from transactions
   where event_id = p_event_id and type = 'send' and status = 'completed'
     and vendor_id is not null;

  -- Compare with this organiser's previous event (only if it has sales).
  select id into v_prev from events
   where organizer_id = v_ev.organizer_id and id <> p_event_id
     and event_date < v_ev.event_date
   order by event_date desc limit 1;
  if v_prev is not null then
    select coalesce(sum(amount_zar), 0) into v_prev_total from transactions
     where event_id = v_prev and type = 'send' and status = 'completed'
       and vendor_id is not null;
    if v_prev_total > 0 then
      v_vs := round(((v_total - v_prev_total) / v_prev_total) * 100, 1);
    end if;
  end if;

  return jsonb_build_object(
    'event', jsonb_build_object('id', v_ev.id, 'name', v_ev.name,
              'event_date', v_ev.event_date, 'venue', v_ev.venue,
              'city', v_ev.city, 'venue_type', v_ev.venue_type),
    'tickets_sold',   (select count(*) from tickets where event_id = p_event_id),
    'ticket_revenue', (select coalesce(sum(price_zar), 0) from tickets where event_id = p_event_id),
    'attended',       (select count(distinct ticket_id) from gate_checkins
                        where event_id = p_event_id and result = 'admitted'),
    'vendor_revenue', v_total,
    'vendor_txns',    (select count(*) from transactions
                        where event_id = p_event_id and type = 'send'
                          and status = 'completed' and vendor_id is not null),
    'vs_last_event_pct', v_vs,

    'stalls', coalesce((select jsonb_agg(to_jsonb(s) order by s.revenue desc) from (
        select v.id, v.name, v.category, v.emoji, v.section_type,
               coalesce(sum(t.amount_zar), 0) as revenue,
               count(t.id) as txns,
               coalesce(avg(t.amount_zar), 0) as avg_txn,
               (select extract(hour from t2.created_at at time zone v_tz)::int
                  from transactions t2
                 where t2.vendor_id = v.id and t2.event_id = p_event_id
                   and t2.type = 'send' and t2.status = 'completed'
                 group by 1 order by sum(t2.amount_zar) desc limit 1) as peak_hour
          from event_vendors v
          left join transactions t on t.vendor_id = v.id and t.event_id = p_event_id
               and t.type = 'send' and t.status = 'completed'
         where v.event_id = p_event_id
         group by v.id) s), '[]'::jsonb),

    -- ordered from 06:00 so a night that crosses midnight stays in sequence
    'by_hour', coalesce((select jsonb_agg(to_jsonb(h) order by (h.hour + 18) % 24) from (
        select extract(hour from t.created_at at time zone v_tz)::int as hour,
               coalesce(sum(t.amount_zar) filter (where v.category in ('Food','Drinks')), 0) as food_drink,
               coalesce(sum(t.amount_zar) filter (where v.category = 'Merchandise'), 0)      as merchandise,
               coalesce(sum(t.amount_zar) filter (where v.category not in ('Food','Drinks','Merchandise')), 0) as other,
               count(*) as txns
          from transactions t join event_vendors v on v.id = t.vendor_id
         where t.event_id = p_event_id and t.type = 'send' and t.status = 'completed'
         group by 1) h), '[]'::jsonb),

    'arrivals', coalesce((select jsonb_agg(to_jsonb(a) order by (a.hour + 18) % 24) from (
        select extract(hour from scanned_at at time zone v_tz)::int as hour,
               count(*) as arrivals
          from gate_checkins
         where event_id = p_event_id and result = 'admitted'
         group by 1) a), '[]'::jsonb),

    'tiers', coalesce((select jsonb_agg(to_jsonb(x) order by x.ticket_revenue desc) from (
        select t.tier,
               count(*) as tickets,
               count(distinct t.user_id) as holders,
               coalesce(sum(t.price_zar), 0) as ticket_revenue,
               coalesce((select sum(s.amount_zar) from transactions s
                          where s.event_id = p_event_id and s.type = 'send'
                            and s.status = 'completed' and s.vendor_id is not null
                            and s.user_id in (select tt.user_id from tickets tt
                                               where tt.event_id = p_event_id
                                                 and tt.tier = t.tier)), 0) as vendor_spend
          from tickets t where t.event_id = p_event_id group by t.tier) x), '[]'::jsonb),

    'staff', coalesce((select jsonb_agg(to_jsonb(st) order by st.revenue desc) from (
        select coalesce(p.display_name, 'Staff') as name,
               v.name as section,
               sum(t.amount_zar) as revenue,
               count(*) as txns,
               avg(t.amount_zar) as avg_txn
          from transactions t
          join event_vendors v on v.id = t.vendor_id
          join profiles p on p.id = t.staff_id
         where t.event_id = p_event_id and t.type = 'send' and t.status = 'completed'
           and t.staff_id is not null
         group by p.id, p.display_name, v.name) st), '[]'::jsonb)
  );
end; $$;

-- ═════════════════════════════ GRANTS ════════════════════════════════════════
-- Functions default to PUBLIC execute; lock them to signed-in users only.
do $$
declare f text;
begin
  foreach f in array array[
    'get_profile_stats(uuid)', 'get_profile_events(uuid)', 'get_followers(uuid)',
    'get_following(uuid)', 'search_people(text)', 'get_rewards_today()',
    'claim_reward_task(text)', 'get_my_stats()', 'get_leaderboard(text,text)',
    'get_leaderboard_cities()', 'pay_event_vendor(uuid,numeric,uuid)',
    'get_event_insights(uuid)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

-- ═════════════════════════════ SECURITY HARDENING ════════════════════════════
-- The original schema gave every user "for all" access to their OWN wallet,
-- transaction and profile rows. Through the public API that meant any signed-in
-- user could set their own balance, forge 'reward' transactions (poisoning the
-- leaderboard), promote themselves to role='admin', or inflate follower_count.
-- Money and counters may now only change through the security-definer
-- functions / edge functions (service role). The app never wrote these
-- directly (updateWalletBalance / saveTransaction are unused).

drop policy if exists "wallets_own"      on public.wallets;
drop policy if exists "transactions_own" on public.transactions;
drop policy if exists "wallets_read_own"      on public.wallets;
drop policy if exists "wallets_create_empty"  on public.wallets;
drop policy if exists "transactions_read_own" on public.transactions;
create policy "wallets_read_own"      on public.wallets      for select using (auth.uid() = user_id);
-- ensureWallet() fallback: a client may only create its own ZERO-balance wallet.
create policy "wallets_create_empty"  on public.wallets      for insert
  with check (auth.uid() = user_id and balance_dc = 0);
create policy "transactions_read_own" on public.transactions for select using (auth.uid() = user_id);
revoke update, delete on public.wallets      from authenticated;
revoke insert, update, delete on public.transactions from authenticated;

-- Admin helper (security definer so it can read profiles without RLS recursion).
create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and role = 'admin')
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated, service_role;

-- The admin dashboard aggregates across ALL users from the admin's own session.
-- Without these it silently saw only the admin's own rows.
drop policy if exists "profiles_admin_read"     on public.profiles;
drop policy if exists "wallets_admin_read"      on public.wallets;
drop policy if exists "transactions_admin_read" on public.transactions;
drop policy if exists "tickets_admin_read"      on public.tickets;
drop policy if exists "events_admin_read"       on public.events;
create policy "profiles_admin_read"     on public.profiles     for select using (public.is_admin());
create policy "wallets_admin_read"      on public.wallets      for select using (public.is_admin());
create policy "transactions_admin_read" on public.transactions for select using (public.is_admin());
create policy "tickets_admin_read"      on public.tickets      for select using (public.is_admin());
create policy "events_admin_read"       on public.events       for select using (public.is_admin());

-- Block self-promotion to admin and tampering with counters from the client.
-- Inside security-definer functions current_user is the function owner, so the
-- follows trigger and edge functions (service role) are unaffected.
create or replace function public.profiles_guard()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.role = 'admin' and old.role is distinct from 'admin' then
      raise exception 'Admin role can only be granted from the Supabase SQL editor';
    end if;
    new.follower_count  := old.follower_count;
    new.following_count := old.following_count;
    new.is_verified     := old.is_verified;
  end if;
  return new;
end; $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard();

-- Keep internal helpers off the public API (they accept an arbitrary user id).
revoke all on function public._task_completed(uuid, text) from public, anon, authenticated;
revoke all on function public._app_open_streak(uuid)      from public, anon, authenticated;
