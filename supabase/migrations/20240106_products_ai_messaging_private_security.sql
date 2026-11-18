-- ─────────────────────────────────────────────────────────────────────────────
-- 20240106 — Product-level sales data, AI report storage, real messaging,
--            persisted private events, gate check-in RPC, security hardening.
-- Run after 20240105.
-- ─────────────────────────────────────────────────────────────────────────────

-- ═════════════════════════════ SECURITY HARDENING (round 2) ══════════════════

-- Tickets: owners may only list / delist their OWN unused ticket for resale and
-- may only touch three columns. They can no longer rewrite price, tier, owner,
-- used-flag, or insert/delete tickets (minting is server-side via mint_ticket).
drop policy if exists "tickets_own"        on public.tickets;
drop policy if exists "tickets_read_own"   on public.tickets;
drop policy if exists "tickets_owner_list" on public.tickets;
create policy "tickets_read_own" on public.tickets for select
  using (auth.uid() = user_id);
create policy "tickets_owner_list" on public.tickets for update
  using      (auth.uid() = user_id and is_used = false
              and status in ('active','listed_for_sale'))
  with check (auth.uid() = user_id and is_used = false
              and status in ('active','listed_for_sale')
              and (resale_price_zar is null or resale_price_zar >= 0));
revoke insert, update, delete on public.tickets from authenticated;
grant  update (is_for_sale, resale_price_zar, status) on public.tickets to authenticated;

-- Posts: like / comment counters are trigger-maintained, never client-set
-- (they feed the "Influencer" badge), and a post cannot be re-assigned.
create or replace function public.posts_guard()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if TG_OP = 'INSERT' then
      new.likes_count := 0; new.comments_count := 0;
    else
      new.likes_count := old.likes_count; new.comments_count := old.comments_count;
      new.user_id := old.user_id;
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists posts_guard on public.posts;
create trigger posts_guard before insert or update on public.posts
  for each row execute function public.posts_guard();

-- Gate check-in. The organiser's device cannot read other users' tickets under
-- RLS, so scanning must run server-side. Authorised: the event's organiser or
-- an admin. Atomic (row lock) so two gates cannot admit the same ticket.
create or replace function public.gate_check_in(
  p_event uuid, p_token text, p_staff uuid default null, p_gate text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_t tickets; v_result text; v_name text; v_staff uuid;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not exists(select 1 from events where id = p_event and organizer_id = v_uid)
     and not public.is_admin() then
    raise exception 'Not authorised for this event';
  end if;
  select id into v_staff from gate_staff where id = p_staff and event_id = p_event;

  select * into v_t from tickets
   where event_id = p_event and (token_id = p_token or id::text = p_token)
   for update;

  if not found or v_t.status = 'pending_mint' then
    insert into gate_checkins (event_id, staff_id, gate_name, result)
      values (p_event, v_staff, p_gate, 'invalid');
    return jsonb_build_object('result', 'invalid');
  end if;

  if v_t.is_used then
    v_result := 'already_used';
  else
    v_result := 'admitted';
    update tickets set is_used = true, used_at = now(), status = 'used',
                       is_for_sale = false, resale_price_zar = null
     where id = v_t.id;
  end if;

  insert into gate_checkins (event_id, ticket_id, staff_id, gate_name, result)
    values (p_event, v_t.id, v_staff, p_gate, v_result);
  select display_name into v_name from profiles where id = v_t.user_id;

  return jsonb_build_object('result', v_result, 'holderName', coalesce(v_name, 'Guest'),
                            'tier', v_t.tier, 'ticketId', v_t.id);
end; $$;

-- ═════════════════════════════ MESSAGING ═════════════════════════════════════
-- The app called these tables but no migration ever created them, and the chat
-- screen kept messages only in memory. Real, RLS-protected, realtime-ready.

create table if not exists public.conversations (
  id              uuid primary key default gen_random_uuid(),
  name            text,
  is_group        boolean not null default false,
  avatar_emoji    text default '💬',
  created_by      uuid references public.profiles(id) on delete set null,
  event_id        uuid references public.events(id) on delete cascade,
  last_message    text,
  last_message_at timestamptz default now(),
  created_at      timestamptz default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  unread_count    int not null default 0,
  joined_at       timestamptz default now(),
  primary key (conversation_id, user_id)
);
create index if not exists conv_members_user_idx on public.conversation_members(user_id);

create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(id) on delete cascade,
  content         text not null check (char_length(content) between 1 and 4000),
  created_at      timestamptz default now()
);
create index if not exists messages_conv_idx on public.messages(conversation_id, created_at desc);

create table if not exists public.contacts (
  user_id          uuid not null references public.profiles(id) on delete cascade,
  contact_id       uuid not null references public.profiles(id) on delete cascade,
  last_interaction timestamptz default now(),
  primary key (user_id, contact_id)
);

-- If these tables were created earlier by hand (the app used them before any
-- migration existed), "create table if not exists" skips them and columns we
-- rely on may be missing. Bring any older version up to the expected shape.
alter table public.conversations add column if not exists name            text;
alter table public.conversations add column if not exists is_group        boolean not null default false;
alter table public.conversations add column if not exists avatar_emoji    text default '💬';
alter table public.conversations add column if not exists created_by      uuid references public.profiles(id) on delete set null;
alter table public.conversations add column if not exists event_id        uuid references public.events(id) on delete cascade;
alter table public.conversations add column if not exists last_message    text;
alter table public.conversations add column if not exists last_message_at timestamptz default now();
alter table public.conversations add column if not exists created_at      timestamptz default now();
create unique index if not exists conversations_event_uidx
  on public.conversations(event_id) where event_id is not null;

alter table public.conversation_members add column if not exists unread_count int not null default 0;
alter table public.conversation_members add column if not exists joined_at    timestamptz default now();
create unique index if not exists conv_members_pair_uidx
  on public.conversation_members(conversation_id, user_id);

alter table public.messages add column if not exists created_at timestamptz default now();
create index if not exists messages_conv_idx on public.messages(conversation_id, created_at desc);

alter table public.contacts add column if not exists last_interaction timestamptz default now();
create unique index if not exists contacts_pair_uidx on public.contacts(user_id, contact_id);

create or replace function public.is_conversation_member(p_conv uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from conversation_members
                 where conversation_id = p_conv and user_id = auth.uid())
$$;

alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;
alter table public.contacts             enable row level security;

drop policy if exists "conv_read"      on public.conversations;
drop policy if exists "members_read"   on public.conversation_members;
drop policy if exists "members_update" on public.conversation_members;
drop policy if exists "messages_read"  on public.messages;
drop policy if exists "messages_send"  on public.messages;
drop policy if exists "contacts_read"  on public.contacts;
create policy "conv_read"      on public.conversations        for select using (public.is_conversation_member(id));
create policy "members_read"   on public.conversation_members for select using (user_id = auth.uid());
create policy "members_update" on public.conversation_members for update using (user_id = auth.uid());
create policy "messages_read"  on public.messages for select using (public.is_conversation_member(conversation_id));
create policy "messages_send"  on public.messages for insert
  with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id));
create policy "contacts_read"  on public.contacts for select using (user_id = auth.uid());

grant select on public.conversations, public.contacts to authenticated;
grant select on public.conversation_members to authenticated;
grant update (unread_count) on public.conversation_members to authenticated;
grant select, insert on public.messages to authenticated;
grant select, insert, update, delete on public.conversations, public.conversation_members,
  public.messages, public.contacts to service_role;

create or replace function public.messages_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_group boolean;
begin
  update conversations set last_message = left(new.content, 120),
         last_message_at = new.created_at where id = new.conversation_id
    returning is_group into v_group;
  update conversation_members set unread_count = unread_count + 1
   where conversation_id = new.conversation_id and user_id <> new.sender_id;
  if not coalesce(v_group, true) then
    insert into contacts (user_id, contact_id, last_interaction)
      select new.sender_id, m.user_id, now() from conversation_members m
       where m.conversation_id = new.conversation_id and m.user_id <> new.sender_id
    on conflict (user_id, contact_id) do update set last_interaction = now();
    insert into contacts (user_id, contact_id, last_interaction)
      select m.user_id, new.sender_id, now() from conversation_members m
       where m.conversation_id = new.conversation_id and m.user_id <> new.sender_id
    on conflict (user_id, contact_id) do update set last_interaction = now();
  end if;
  return null;
end; $$;
drop trigger if exists messages_after_insert on public.messages;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.messages_after_insert();

create or replace function public.get_or_create_dm(user_a uuid, user_b uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if user_a is distinct from auth.uid() then raise exception 'Not allowed'; end if;
  if user_b = user_a or not exists(select 1 from profiles where id = user_b) then
    raise exception 'Invalid recipient';
  end if;
  select c.id into v_id from conversations c
   where not c.is_group
     and exists(select 1 from conversation_members m where m.conversation_id = c.id and m.user_id = user_a)
     and exists(select 1 from conversation_members m where m.conversation_id = c.id and m.user_id = user_b)
   limit 1;
  if v_id is null then
    insert into conversations (is_group, created_by) values (false, user_a) returning id into v_id;
    insert into conversation_members (conversation_id, user_id) values (v_id, user_a), (v_id, user_b);
  end if;
  return v_id;
end; $$;

create or replace function public.get_my_conversations()
returns table (conversation_id uuid, name text, is_group boolean, avatar_emoji text,
               avatar_url text, event_id uuid, last_message text,
               last_message_at timestamptz, unread_count int)
language sql security definer stable set search_path = public as $$
  select c.id,
         case when c.is_group then coalesce(c.name, 'Group')
              else coalesce((select p.display_name from conversation_members o
                               join profiles p on p.id = o.user_id
                              where o.conversation_id = c.id and o.user_id <> auth.uid()
                              limit 1), 'Direct Message') end,
         c.is_group, c.avatar_emoji,
         (select p.avatar_url from conversation_members o join profiles p on p.id = o.user_id
           where o.conversation_id = c.id and o.user_id <> auth.uid() and not c.is_group limit 1),
         c.event_id, c.last_message, c.last_message_at, m.unread_count
    from conversation_members m join conversations c on c.id = m.conversation_id
   where m.user_id = auth.uid()
   order by c.last_message_at desc nulls last;
$$;

create or replace function public.get_conversation_messages(p_conv uuid, p_limit int default 50)
returns table (id uuid, content text, created_at timestamptz, sender_id uuid,
               sender_name text, sender_avatar text)
language plpgsql security definer stable set search_path = public as $$
begin
  if not public.is_conversation_member(p_conv) then raise exception 'Not a member'; end if;
  return query
    select m.id, m.content, m.created_at, m.sender_id, p.display_name, p.avatar_url
      from messages m join profiles p on p.id = m.sender_id
     where m.conversation_id = p_conv
     order by m.created_at desc limit least(greatest(p_limit, 1), 200);
end; $$;

create or replace function public.get_recent_contacts()
returns table (id uuid, display_name text, avatar_url text, last_interaction timestamptz)
language sql security definer stable set search_path = public as $$
  select p.id, p.display_name, p.avatar_url, c.last_interaction
    from contacts c join profiles p on p.id = c.contact_id
   where c.user_id = auth.uid() order by c.last_interaction desc limit 20;
$$;

-- Event group chats: buying a ticket joins you to the event's chat.
create or replace function public.join_event_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_conv uuid; v_ev events;
begin
  if new.event_id is null or new.user_id is null or new.status = 'pending_mint' then
    return null;
  end if;
  select * into v_ev from events where id = new.event_id;
  if not found then return null; end if;
  select id into v_conv from conversations where event_id = new.event_id;
  if v_conv is null then
    insert into conversations (name, is_group, avatar_emoji, created_by, event_id)
      values (v_ev.name, true, '🎪', v_ev.organizer_id, new.event_id)
      on conflict do nothing returning id into v_conv;
    if v_conv is null then select id into v_conv from conversations where event_id = new.event_id; end if;
    if v_ev.organizer_id is not null then
      insert into conversation_members (conversation_id, user_id)
        values (v_conv, v_ev.organizer_id) on conflict do nothing;
    end if;
  end if;
  insert into conversation_members (conversation_id, user_id)
    values (v_conv, new.user_id) on conflict do nothing;
  return null;
end; $$;
drop trigger if exists tickets_join_chat on public.tickets;
create trigger tickets_join_chat after insert or update of status, user_id on public.tickets
  for each row execute function public.join_event_chat();

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.messages;
    exception when duplicate_object then null; end;
  end if;
end $$;

-- ═════════════════════════════ PRODUCTS & ITEMISED SALES ═════════════════════
-- Each business keeps a catalogue. Payments made with items record exactly
-- what was sold (price is read from the catalogue server-side — a client can
-- never set its own price). This line-item data powers the owner's product
-- insights, the organiser's cross-stall product view, and the AI reports.

create table if not exists public.business_products (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  vendor_id  uuid references public.event_vendors(id) on delete set null,
  name       text not null check (char_length(trim(name)) between 1 and 80),
  category   text not null default 'Other',
  price_zar  numeric not null check (price_zar >= 0 and price_zar <= 100000),
  active     boolean not null default true,
  created_at timestamptz default now()
);
create index if not exists business_products_owner_idx on public.business_products(owner_id);

create table if not exists public.sale_items (
  id             uuid primary key default gen_random_uuid(),
  transaction_id uuid references public.transactions(id) on delete cascade,
  owner_id       uuid not null references public.profiles(id) on delete cascade,
  buyer_id       uuid references public.profiles(id) on delete set null,
  vendor_id      uuid references public.event_vendors(id) on delete set null,
  event_id       uuid references public.events(id) on delete set null,
  product_id     uuid references public.business_products(id) on delete set null,
  product_name   text not null,
  category       text,
  quantity       int not null check (quantity between 1 and 99),
  unit_price     numeric not null,
  line_total     numeric not null,
  created_at     timestamptz default now()
);
create index if not exists sale_items_owner_idx on public.sale_items(owner_id, created_at);
create index if not exists sale_items_event_idx on public.sale_items(event_id) where event_id is not null;

alter table public.business_products enable row level security;
alter table public.sale_items        enable row level security;
drop policy if exists "products_owner"      on public.business_products;
drop policy if exists "products_menu_read"  on public.business_products;
drop policy if exists "products_admin_read" on public.business_products;
drop policy if exists "sale_items_admin_read" on public.sale_items;
create policy "products_owner"     on public.business_products for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "products_menu_read" on public.business_products for select using (active);
create policy "products_admin_read" on public.business_products for select using (public.is_admin());
-- sale_items: NO owner policy on purpose. Owners read aggregates through the
-- insight functions only, so individual buyers are never exposed to vendors.
create policy "sale_items_admin_read" on public.sale_items for select using (public.is_admin());
grant select, insert, update, delete on public.business_products to authenticated;
grant select on public.sale_items to authenticated;
grant select, insert, update, delete on public.business_products, public.sale_items to service_role;

-- A vendor product must belong to a vendor the owner actually runs.
create or replace function public.products_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.vendor_id is not null and not exists(
      select 1 from event_vendors where id = new.vendor_id and owner_id = new.owner_id) then
    raise exception 'That stall is not yours';
  end if;
  return new;
end; $$;
drop trigger if exists products_guard on public.business_products;
create trigger products_guard before insert or update on public.business_products
  for each row execute function public.products_guard();

-- Shared payment engine. Prices always come from the catalogue.
create or replace function public._pay_items(
  p_payer uuid, p_owner uuid, p_vendor uuid, p_event uuid,
  p_items jsonb, p_zar numeric, p_staff uuid, p_label text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_total numeric := p_zar; v_n int; v_price numeric; v_dc numeric; v_fee numeric;
  v_bal numeric; v_tx uuid; v_has_items boolean :=
    p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0;
begin
  if p_owner is null then raise exception 'This vendor cannot receive payments yet'; end if;
  if p_owner = p_payer then raise exception 'You cannot pay yourself'; end if;

  if v_has_items then
    if jsonb_array_length(p_items) > 50 then raise exception 'Too many items'; end if;
    select coalesce(sum(bp.price_zar * q.qty), 0), count(*) into v_total, v_n
      from (select (e->>'product_id')::uuid as pid, (e->>'qty')::int as qty
              from jsonb_array_elements(p_items) e) q
      join business_products bp
        on bp.id = q.pid and bp.owner_id = p_owner and bp.active
       and (p_vendor is null or bp.vendor_id is null or bp.vendor_id = p_vendor)
     where q.qty between 1 and 99;
    if v_n <> jsonb_array_length(p_items) then raise exception 'Invalid items'; end if;
  end if;
  if v_total is null or v_total < 1 then raise exception 'Minimum payment is R1'; end if;

  select coalesce(xrp_price, 9.50) into v_price from wallets where user_id = p_payer;
  v_dc := v_total / v_price; v_fee := v_dc * 0.005;

  if p_payer < p_owner then
    select balance_dc into v_bal from wallets where user_id = p_payer for update;
    perform 1 from wallets where user_id = p_owner for update;
  else
    perform 1 from wallets where user_id = p_owner for update;
    select balance_dc into v_bal from wallets where user_id = p_payer for update;
  end if;
  if v_bal is null then raise exception 'Wallet not found'; end if;
  if not exists(select 1 from wallets where user_id = p_owner) then
    raise exception 'The recipient has no wallet';
  end if;
  if v_bal < v_dc + v_fee then raise exception 'Not enough balance'; end if;

  update wallets set balance_dc = balance_dc - v_dc - v_fee where user_id = p_payer;
  update wallets set balance_dc = balance_dc + v_dc         where user_id = p_owner;

  insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status,
                            reference, event_id, vendor_id, staff_id, metadata)
    values (p_payer, 'send', v_dc, v_total, v_fee, 'completed', 'pay:' || p_owner,
            p_event, p_vendor, p_staff, jsonb_build_object('to', p_label))
    returning id into v_tx;
  insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status,
                            reference, event_id, vendor_id, staff_id, metadata)
    values (p_owner, 'receive', v_dc, v_total, 0, 'completed', 'from:' || p_payer,
            p_event, p_vendor, p_staff, jsonb_build_object('from_customer', true));

  if v_has_items then
    insert into sale_items (transaction_id, owner_id, buyer_id, vendor_id, event_id,
                            product_id, product_name, category, quantity, unit_price, line_total)
      select v_tx, p_owner, p_payer, p_vendor, p_event, bp.id, bp.name, bp.category,
             q.qty, bp.price_zar, bp.price_zar * q.qty
        from (select (e->>'product_id')::uuid as pid, (e->>'qty')::int as qty
                from jsonb_array_elements(p_items) e) q
        join business_products bp on bp.id = q.pid;
  end if;
  return jsonb_build_object('zar', v_total, 'to', p_label);
end; $$;

drop function if exists public.pay_event_vendor(uuid, numeric, uuid);
create or replace function public.pay_event_vendor(
  p_vendor_id uuid, p_zar numeric default null, p_staff uuid default null,
  p_items jsonb default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v event_vendors;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into v from event_vendors where id = p_vendor_id;
  if not found then raise exception 'Vendor not found'; end if;
  return public._pay_items(auth.uid(), v.owner_id, v.id, v.event_id, p_items, p_zar, p_staff, v.name);
end; $$;

-- Everyday business (shop / QR till) outside an event.
create or replace function public.pay_business_items(
  p_owner uuid, p_items jsonb, p_staff uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select display_name into v_name from profiles where id = p_owner;
  if not found then raise exception 'Business not found'; end if;
  return public._pay_items(auth.uid(), p_owner, null, null, p_items, null, p_staff, coalesce(v_name, 'Business'));
end; $$;

-- Menu a customer can build a cart from.
create or replace function public.get_business_menu(p_owner uuid, p_vendor uuid default null)
returns table (id uuid, name text, category text, price_zar numeric)
language sql security definer stable set search_path = public as $$
  select id, name, category, price_zar from business_products
   where owner_id = p_owner and active and (p_vendor is null or vendor_id is null or vendor_id = p_vendor)
   order by category, name;
$$;

-- Owner's own product insights (period vs previous period).
create or replace function public.get_business_product_insights(p_days int default 30)
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_days int := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz; v_prev timestamptz; v_tz text := 'Africa/Johannesburg';
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  v_from := now() - make_interval(days => v_days); v_prev := v_from - make_interval(days => v_days);
  return jsonb_build_object(
    'days', v_days,
    'revenue', (select coalesce(sum(line_total),0) from sale_items where owner_id=v_uid and created_at>=v_from),
    'prev_revenue', (select coalesce(sum(line_total),0) from sale_items where owner_id=v_uid and created_at>=v_prev and created_at<v_from),
    'units', (select coalesce(sum(quantity),0) from sale_items where owner_id=v_uid and created_at>=v_from),
    'orders', (select count(distinct transaction_id) from sale_items where owner_id=v_uid and created_at>=v_from),
    'customers', (select count(distinct buyer_id) from sale_items where owner_id=v_uid and created_at>=v_from),
    'repeat_customers', (select count(*) from (
        select buyer_id from sale_items where owner_id=v_uid and created_at>=v_from and buyer_id is not null
         group by buyer_id having count(distinct transaction_id) >= 2) r),
    'products', coalesce((select jsonb_agg(to_jsonb(p) order by p.revenue desc) from (
        select coalesce(product_id::text, product_name) as key, product_name as name, max(category) as category,
               sum(quantity) filter (where created_at>=v_from) as units,
               coalesce(sum(line_total) filter (where created_at>=v_from),0) as revenue,
               coalesce(sum(quantity) filter (where created_at>=v_prev and created_at<v_from),0) as prev_units,
               max(created_at) as last_sold
          from sale_items where owner_id=v_uid and created_at>=v_prev
         group by coalesce(product_id::text, product_name), product_name
        having sum(quantity) filter (where created_at>=v_from) > 0) p), '[]'::jsonb),
    'unsold', coalesce((select jsonb_agg(jsonb_build_object('name', bp.name, 'category', bp.category, 'price_zar', bp.price_zar))
        from business_products bp where bp.owner_id=v_uid and bp.active
         and not exists(select 1 from sale_items s where s.product_id=bp.id and s.created_at>=v_from)), '[]'::jsonb),
    'by_hour', coalesce((select jsonb_agg(to_jsonb(h) order by h.hour) from (
        select extract(hour from created_at at time zone v_tz)::int as hour, sum(quantity) as units, sum(line_total) as revenue
          from sale_items where owner_id=v_uid and created_at>=v_from group by 1) h), '[]'::jsonb),
    'by_weekday', coalesce((select jsonb_agg(to_jsonb(w) order by w.dow) from (
        select extract(isodow from created_at at time zone v_tz)::int as dow, sum(quantity) as units, sum(line_total) as revenue
          from sale_items where owner_id=v_uid and created_at>=v_from group by 1) w), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.revenue desc) from (
        select coalesce(category,'Other') as category, sum(quantity) as units, sum(line_total) as revenue
          from sale_items where owner_id=v_uid and created_at>=v_from group by 1) c), '[]'::jsonb),
    -- Platform benchmark: only shown when at least 5 OTHER businesses sell in
    -- the category, so no single competitor can be inferred.
    'benchmark', coalesce((select jsonb_agg(to_jsonb(b)) from (
        select s.category, round(avg(s.unit_price),2) as platform_avg_price,
               count(distinct s.owner_id) as businesses
          from sale_items s
         where s.created_at>=v_from and s.owner_id <> v_uid
           and s.category in (select distinct category from sale_items where owner_id=v_uid and created_at>=v_from)
         group by s.category having count(distinct s.owner_id) >= 5) b), '[]'::jsonb)
  );
end; $$;

-- Organiser view: what sold across all stalls at one event.
create or replace function public.get_event_product_insights(p_event_id uuid)
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare v_ev events;
begin
  select * into v_ev from events where id = p_event_id;
  if not found then raise exception 'Event not found'; end if;
  if not (v_ev.organizer_id = auth.uid() or public.is_admin()) then raise exception 'Not authorised'; end if;
  return jsonb_build_object(
    'products', coalesce((select jsonb_agg(to_jsonb(p) order by p.revenue desc) from (
        select s.product_name as name, max(s.category) as category, max(v.name) as stall,
               sum(s.quantity) as units, sum(s.line_total) as revenue, round(avg(s.unit_price),2) as avg_price
          from sale_items s left join event_vendors v on v.id = s.vendor_id
         where s.event_id = p_event_id group by s.product_name, s.vendor_id limit 100) p), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.revenue desc) from (
        select coalesce(category,'Other') as category, sum(quantity) as units, sum(line_total) as revenue
          from sale_items where event_id = p_event_id group by 1) c), '[]'::jsonb),
    'itemised_revenue', (select coalesce(sum(line_total),0) from sale_items where event_id = p_event_id)
  );
end; $$;

-- Admin-only market intelligence (the "data business"). Groups of fewer than 3
-- distinct businesses are suppressed so no single business can be identified.
create or replace function public.get_platform_product_trends(p_days int default 30)
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare v_days int := least(greatest(coalesce(p_days,30),1),365); v_from timestamptz; v_prev timestamptz;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  v_from := now() - make_interval(days => v_days); v_prev := v_from - make_interval(days => v_days);
  return jsonb_build_object('days', v_days,
    'products', coalesce((select jsonb_agg(to_jsonb(t) order by t.revenue desc) from (
        select lower(trim(product_name)) as name, max(category) as category,
               sum(quantity) filter (where created_at>=v_from) as units,
               coalesce(sum(line_total) filter (where created_at>=v_from),0) as revenue,
               coalesce(sum(quantity) filter (where created_at>=v_prev and created_at<v_from),0) as prev_units,
               count(distinct owner_id) filter (where created_at>=v_from) as businesses,
               round(avg(unit_price) filter (where created_at>=v_from),2) as avg_price
          from sale_items where created_at>=v_prev
         group by lower(trim(product_name))
        having count(distinct owner_id) filter (where created_at>=v_from) >= 3 limit 100) t), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.revenue desc) from (
        select coalesce(category,'Other') as category, sum(quantity) as units,
               sum(line_total) as revenue, count(distinct owner_id) as businesses
          from sale_items where created_at>=v_from group by 1
        having count(distinct owner_id) >= 3) c), '[]'::jsonb));
end; $$;

-- ═════════════════════════════ AI REPORTS ════════════════════════════════════
-- Written only by the ai_insights edge function (service role). Owners read
-- their own. Inputs are aggregates — never buyer identities.
create table if not exists public.ai_insight_reports (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  scope       text not null check (scope in ('business','event','platform')),
  event_id    uuid references public.events(id) on delete set null,
  period_days int,
  summary     text not null,
  recommendations jsonb not null default '[]'::jsonb,
  model       text,
  created_at  timestamptz default now()
);
create index if not exists ai_reports_owner_idx on public.ai_insight_reports(owner_id, created_at desc);
alter table public.ai_insight_reports enable row level security;
drop policy if exists "ai_reports_own" on public.ai_insight_reports;
create policy "ai_reports_own" on public.ai_insight_reports for select using (owner_id = auth.uid());
grant select on public.ai_insight_reports to authenticated;
grant select, insert, update, delete on public.ai_insight_reports to service_role;

-- ═════════════════════════════ ADMIN → ORGANISER RECOMMENDATIONS ═════════════
create table if not exists public.organiser_messages (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid references public.events(id) on delete cascade,
  organiser_id uuid not null references public.profiles(id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 1000),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz default now(),
  read_at      timestamptz
);
alter table public.organiser_messages enable row level security;
drop policy if exists "org_msgs_read"   on public.organiser_messages;
drop policy if exists "org_msgs_update" on public.organiser_messages;
create policy "org_msgs_read"   on public.organiser_messages for select
  using (organiser_id = auth.uid() or public.is_admin());
create policy "org_msgs_update" on public.organiser_messages for update using (organiser_id = auth.uid());
grant select on public.organiser_messages to authenticated;
grant update (read_at) on public.organiser_messages to authenticated;
grant select, insert, update, delete on public.organiser_messages to service_role;

create or replace function public.push_recommendation(p_event uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select organizer_id into v_org from events where id = p_event;
  if v_org is null then raise exception 'Event has no organiser'; end if;
  insert into organiser_messages (event_id, organiser_id, body, created_by)
    values (p_event, v_org, trim(p_body), auth.uid());
end; $$;

-- ═════════════════════════════ PRIVATE EVENTS ════════════════════════════════
create table if not exists public.private_events (
  id              uuid primary key default gen_random_uuid(),
  host_id         uuid not null references public.profiles(id) on delete cascade,
  name            text not null,
  event_type      text not null default 'other',
  venue           text, city text, message text, host_name text,
  event_date      timestamptz not null,
  is_paid         boolean not null default false,
  meal_options    text[] not null default '{}',
  max_plus_ones   int not null default 2 check (max_plus_ones between 0 and 10),
  cover_image_url text,
  has_video       boolean not null default false,
  created_at      timestamptz default now()
);
create table if not exists public.private_event_guests (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.private_events(id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 100),
  phone          text not null check (char_length(phone) between 5 and 20),
  avatar_emoji   text,
  rsvp           text not null default 'pending' check (rsvp in ('pending','yes','no','maybe')),
  ticket_minted  boolean not null default false,
  invite_opened  boolean not null default false,
  meal_choice    text,
  plus_one_count int not null default 0 check (plus_one_count between 0 and 10),
  plus_one_names text[] not null default '{}',
  created_at     timestamptz default now(),
  unique (event_id, phone)
);
alter table public.private_events       enable row level security;
alter table public.private_event_guests enable row level security;
drop policy if exists "pe_host"        on public.private_events;
drop policy if exists "pe_guests_host" on public.private_event_guests;
create policy "pe_host" on public.private_events for all
  using (auth.uid() = host_id) with check (auth.uid() = host_id);
create policy "pe_guests_host" on public.private_event_guests for all
  using (exists(select 1 from private_events e where e.id = event_id and e.host_id = auth.uid()))
  with check (exists(select 1 from private_events e where e.id = event_id and e.host_id = auth.uid()));
grant select, insert, update, delete on public.private_events, public.private_event_guests to authenticated;
grant select, insert, update, delete on public.private_events, public.private_event_guests to service_role;

-- Public invite page (opened from a WhatsApp/SMS link by someone who may not
-- have the app or an account). Returns the invite only — never the guest list.
create or replace function public.get_private_event_invite(p_id uuid)
returns jsonb language sql security definer stable set search_path = public as $$
  select to_jsonb(e) - 'host_id' - 'created_at' from private_events e where e.id = p_id;
$$;

create or replace function public.submit_private_rsvp(
  p_event uuid, p_phone text, p_name text, p_rsvp text,
  p_meal text default null, p_plus_names text[] default '{}'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ev private_events; v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
        v_plus text[] := coalesce(p_plus_names, '{}'); v_count int; v_g private_event_guests;
begin
  select * into v_ev from private_events where id = p_event;
  if not found then raise exception 'Invitation not found'; end if;
  if p_rsvp not in ('yes','no','maybe') then raise exception 'Invalid response'; end if;
  if char_length(v_phone) < 5 then raise exception 'Enter a valid phone number'; end if;
  if char_length(trim(coalesce(p_name,''))) < 1 then raise exception 'Enter your name'; end if;
  if cardinality(v_plus) > v_ev.max_plus_ones then raise exception 'Too many plus-ones'; end if;
  select count(*) into v_count from private_event_guests where event_id = p_event;
  select * into v_g from private_event_guests where event_id = p_event and phone = v_phone;
  if not found then
    if v_count >= 500 then raise exception 'This event is full'; end if;
    insert into private_event_guests (event_id, name, phone, rsvp, invite_opened, meal_choice,
                                      plus_one_count, plus_one_names)
      values (p_event, left(trim(p_name),100), v_phone, p_rsvp, true, left(p_meal,60),
              cardinality(v_plus), v_plus);
  else
    update private_event_guests set rsvp = p_rsvp, invite_opened = true,
           meal_choice = left(p_meal,60), plus_one_count = cardinality(v_plus), plus_one_names = v_plus
     where id = v_g.id;
  end if;
  return jsonb_build_object('ok', true);
end; $$;

-- ═════════════════════════════ GRANTS ════════════════════════════════════════
do $$
declare f text;
begin
  foreach f in array array[
    'gate_check_in(uuid,text,uuid,text)', 'get_or_create_dm(uuid,uuid)',
    'get_my_conversations()', 'get_conversation_messages(uuid,int)', 'get_recent_contacts()',
    'pay_event_vendor(uuid,numeric,uuid,jsonb)', 'pay_business_items(uuid,jsonb,uuid)',
    'get_business_menu(uuid,uuid)', 'get_business_product_insights(int)',
    'get_event_product_insights(uuid)', 'get_platform_product_trends(int)',
    'push_recommendation(uuid,text)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  -- Public invite links must work before sign-in.
  revoke all on function public.get_private_event_invite(uuid) from public;
  revoke all on function public.submit_private_rsvp(uuid,text,text,text,text,text[]) from public;
  grant execute on function public.get_private_event_invite(uuid) to anon, authenticated, service_role;
  grant execute on function public.submit_private_rsvp(uuid,text,text,text,text,text[]) to anon, authenticated, service_role;
  -- Internal helpers: never callable from the API.
  revoke all on function public._pay_items(uuid,uuid,uuid,uuid,jsonb,numeric,uuid,text) from public, anon, authenticated;
  revoke all on function public.is_conversation_member(uuid) from public, anon;
  grant execute on function public.is_conversation_member(uuid) to authenticated;
end $$;


-- ═════════════════════════════ ATOMIC WALLET OPS (edge functions) ════════════
-- The edge functions used read-then-write (balance = old + x), which loses
-- money under concurrency (two top-ups landing together overwrite each other).
-- These do the arithmetic inside one statement. Service role only.
create or replace function public.credit_wallet(p_user uuid, p_dc numeric)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_bal numeric;
begin
  if p_dc is null or p_dc <= 0 then raise exception 'Invalid amount'; end if;
  update wallets set balance_dc = balance_dc + p_dc where user_id = p_user
    returning balance_dc into v_bal;
  if not found then raise exception 'Wallet not found'; end if;
  return v_bal;
end; $$;

create or replace function public.debit_wallet(p_user uuid, p_dc numeric)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_bal numeric;
begin
  if p_dc is null or p_dc <= 0 then raise exception 'Invalid amount'; end if;
  update wallets set balance_dc = balance_dc - p_dc
   where user_id = p_user and balance_dc >= p_dc returning balance_dc into v_bal;
  if not found then raise exception 'Insufficient balance'; end if;
  return v_bal;
end; $$;
revoke all on function public.credit_wallet(uuid, numeric) from public, anon, authenticated;
revoke all on function public.debit_wallet(uuid, numeric)  from public, anon, authenticated;
grant execute on function public.credit_wallet(uuid, numeric) to service_role;
grant execute on function public.debit_wallet(uuid, numeric)  to service_role;


-- ═════════════════════════════ TOP-UP SAFETY ═════════════════════════════════
-- Each user gets a random bank-transfer reference (the old design matched the
-- first 8 characters of the user id with ILIKE, which errors on a uuid column
-- and could collide). A unique index makes a replayed webhook impossible to
-- credit twice, even under concurrency.
alter table public.profiles add column if not exists topup_ref text;
update public.profiles
   set topup_ref = upper(substr(md5(random()::text || id::text || clock_timestamp()::text), 1, 8))
 where topup_ref is null;
alter table public.profiles alter column topup_ref
  set default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
create unique index if not exists profiles_topup_ref_key on public.profiles(topup_ref);
create unique index if not exists transactions_topup_ref_key
  on public.transactions(reference) where type = 'topup' and reference is not null;

-- topup_ref is server-assigned; a client must not rewrite it.
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
    new.topup_ref       := old.topup_ref;
  end if;
  return new;
end; $$;

-- ═════════════════════════════ POST COMMENTS ═════════════════════════════════
create table if not exists public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  content    text not null check (char_length(content) between 1 and 1000),
  created_at timestamptz default now()
);
create index if not exists post_comments_post_idx on public.post_comments(post_id, created_at);
alter table public.post_comments enable row level security;
drop policy if exists "comments_read"   on public.post_comments;
drop policy if exists "comments_insert" on public.post_comments;
drop policy if exists "comments_delete" on public.post_comments;
create policy "comments_read"   on public.post_comments for select using (true);
create policy "comments_insert" on public.post_comments for insert with check (auth.uid() = user_id);
create policy "comments_delete" on public.post_comments for delete using (auth.uid() = user_id or public.is_admin());
revoke all on public.post_comments from anon, authenticated;
grant select on public.post_comments to anon, authenticated;
grant insert, delete on public.post_comments to authenticated;

create or replace function public.bump_comments_count() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update posts set comments_count = comments_count + 1 where id = new.post_id;
  else
    update posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end; $$;
drop trigger if exists post_comments_count on public.post_comments;
create trigger post_comments_count after insert or delete on public.post_comments
  for each row execute function public.bump_comments_count();

create or replace function public.get_post_comments(p_post uuid, p_limit int default 100)
returns table (id uuid, content text, created_at timestamptz, user_id uuid,
               display_name text, avatar_url text)
language sql security definer stable set search_path = public as $$
  select c.id, c.content, c.created_at, c.user_id, p.display_name, p.avatar_url
    from post_comments c join profiles p on p.id = c.user_id
   where c.post_id = p_post order by c.created_at asc limit least(greatest(p_limit,1),300);
$$;
revoke all on function public.get_post_comments(uuid,int) from public, anon;
grant execute on function public.get_post_comments(uuid,int) to authenticated;

-- ═════════════════════════════ EXCLUSIVE POSTS ═══════════════════════════════
-- Organiser content for ticket holders. Locked posts are returned as teasers
-- (no content / images) so the lock is enforced by the database, not the app.
create table if not exists public.exclusive_posts (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events(id) on delete cascade,
  organiser_id  uuid not null references public.profiles(id) on delete cascade,
  content       text not null check (char_length(content) between 1 and 2000),
  image_urls    text[] not null default '{}',
  required_tier text,                 -- null = any ticket holder
  created_at    timestamptz default now()
);
alter table public.exclusive_posts enable row level security;
drop policy if exists "excl_organiser" on public.exclusive_posts;
create policy "excl_organiser" on public.exclusive_posts for all
  using (organiser_id = auth.uid())
  with check (organiser_id = auth.uid()
    and exists (select 1 from events e where e.id = event_id and e.organizer_id = auth.uid()));
revoke all on public.exclusive_posts from anon, authenticated;
grant select, insert, delete on public.exclusive_posts to authenticated;

create or replace function public.get_exclusive_posts()
returns table (id uuid, event_id uuid, event_name text, organiser_name text,
               required_tier text, created_at timestamptz, unlocked boolean,
               content text, image_urls text[])
language sql security definer stable set search_path = public as $$
  select x.id, x.event_id, e.name, coalesce(p.display_name, 'Organiser'),
         x.required_tier, x.created_at, u.ok,
         case when u.ok then x.content end,
         case when u.ok then x.image_urls else '{}'::text[] end
    from exclusive_posts x
    join events e on e.id = x.event_id
    left join profiles p on p.id = x.organiser_id
    cross join lateral (
      select (x.organiser_id = auth.uid()
              or exists (select 1 from tickets t
                          where t.event_id = x.event_id and t.user_id = auth.uid()
                            and t.status in ('active','used','listed_for_sale')
                            and (x.required_tier is null or t.tier = x.required_tier))) as ok) u
   where x.organiser_id = auth.uid()
      or exists (select 1 from tickets t
                  where t.event_id = x.event_id and t.user_id = auth.uid()
                    and t.status in ('active','used','listed_for_sale'))
   order by x.created_at desc limit 50;
$$;
revoke all on function public.get_exclusive_posts() from public, anon;
grant execute on function public.get_exclusive_posts() to authenticated;

-- ═════════════════════════════ GATE STAFF PINS (hashed, server-checked) ══════
-- PINs used to be stored in plain text and compared on the phone, readable by
-- anyone with the organiser session, with no way to see/reset them. Now:
--  • stored as bcrypt hashes, never sent to a client
--  • checked by gate_pin_login with a lock-out after 5 wrong tries
--  • created / reset / removed only through organiser-checked functions
create extension if not exists pgcrypto;
alter table public.gate_staff add column if not exists pin_hash text;
do $$ begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='gate_staff' and column_name='pin') then
    update public.gate_staff set pin_hash = crypt(pin, gen_salt('bf')) where pin_hash is null and pin is not null;
    update public.gate_staff set pin = null;
    alter table public.gate_staff alter column pin drop not null;
    alter table public.gate_staff drop constraint if exists gate_staff_pin_check;
    alter table public.gate_staff drop constraint if exists gate_staff_event_id_pin_key;
  end if;
end $$;

revoke all on public.gate_staff from anon, authenticated;
grant select (id, event_id, name, gate_name, created_at) on public.gate_staff to authenticated;
grant select, insert, update, delete on public.gate_staff to service_role;

create table if not exists public.gate_login_throttle (
  user_id uuid not null, event_id uuid not null,
  fails int not null default 0, locked_until timestamptz,
  primary key (user_id, event_id)
);
alter table public.gate_login_throttle enable row level security;
revoke all on public.gate_login_throttle from anon, authenticated;

create or replace function public._gate_event_ok(p_event uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from events where id = p_event and organizer_id = auth.uid()) or public.is_admin();
$$;

create or replace function public._gate_pin_taken(p_event uuid, p_pin text, p_except uuid default null)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists(select 1 from gate_staff where event_id = p_event
                  and (p_except is null or id <> p_except)
                  and pin_hash = crypt(p_pin, pin_hash));
$$;

create or replace function public.add_gate_staff(p_event uuid, p_name text, p_gate text, p_pin text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not public._gate_event_ok(p_event) then raise exception 'Not authorised for this event'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN must be exactly 4 digits'; end if;
  if char_length(trim(coalesce(p_name,''))) < 1 or char_length(trim(coalesce(p_gate,''))) < 1 then
    raise exception 'Enter a name and a gate name'; end if;
  if public._gate_pin_taken(p_event, p_pin) then
    raise exception 'That PIN is already used by another staff member at this event'; end if;
  insert into gate_staff (event_id, name, gate_name, pin_hash)
    values (p_event, trim(p_name), trim(p_gate), crypt(p_pin, gen_salt('bf'))) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.set_gate_staff_pin(p_staff uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_event uuid;
begin
  select event_id into v_event from gate_staff where id = p_staff;
  if v_event is null then raise exception 'Staff member not found'; end if;
  if not public._gate_event_ok(v_event) then raise exception 'Not authorised for this event'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN must be exactly 4 digits'; end if;
  if public._gate_pin_taken(v_event, p_pin, p_staff) then
    raise exception 'That PIN is already used by another staff member at this event'; end if;
  update gate_staff set pin_hash = crypt(p_pin, gen_salt('bf')) where id = p_staff;
  delete from gate_login_throttle where event_id = v_event;
end; $$;

create or replace function public.remove_gate_staff(p_staff uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from gate_staff where id = p_staff;
  if v_event is null then return; end if;
  if not public._gate_event_ok(v_event) then raise exception 'Not authorised for this event'; end if;
  delete from gate_staff where id = p_staff;
end; $$;

create or replace function public.gate_pin_login(p_event uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); v_t gate_login_throttle; v_s gate_staff; v_count int;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if not public._gate_event_ok(p_event) then raise exception 'Not authorised for this event'; end if;
  select count(*) into v_count from gate_staff where event_id = p_event;
  if v_count = 0 then raise exception 'NO_STAFF'; end if;
  select * into v_t from gate_login_throttle where user_id = v_uid and event_id = p_event;
  if found and v_t.locked_until is not null and v_t.locked_until > now() then
    return jsonb_build_object('error', 'Too many wrong PINs. Try again in a few minutes.'); end if;

  select * into v_s from gate_staff
   where event_id = p_event and pin_hash = crypt(coalesce(p_pin,''), pin_hash) limit 1;
  if not found then
    insert into gate_login_throttle (user_id, event_id, fails) values (v_uid, p_event, 1)
      on conflict (user_id, event_id) do update
        set fails = case when gate_login_throttle.locked_until is not null and gate_login_throttle.locked_until <= now()
                         then 1 else gate_login_throttle.fails + 1 end,
            locked_until = case when gate_login_throttle.fails + 1 >= 5 then now() + interval '5 minutes' else null end;
    -- Returned, not raised: a raise would roll the failure counter back.
    return jsonb_build_object('error', 'Incorrect PIN');
  end if;
  delete from gate_login_throttle where user_id = v_uid and event_id = p_event;
  return jsonb_build_object('id', v_s.id, 'name', v_s.name, 'gate_name', v_s.gate_name, 'event_id', v_s.event_id);
end; $$;

do $$ declare f text; begin
  foreach f in array array['add_gate_staff(uuid,text,text,text)','set_gate_staff_pin(uuid,text)',
    'remove_gate_staff(uuid)','gate_pin_login(uuid,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  revoke all on function public._gate_event_ok(uuid) from public, anon, authenticated;
  revoke all on function public._gate_pin_taken(uuid,text,uuid) from public, anon, authenticated;
end $$;

-- ═════════════════════════════ PAY A BUSINESS ANY AMOUNT ═════════════════════
-- For customers who just want to pay a figure (no items). Not itemised, so it
-- does not appear in product insights, but it is still a real ledger payment.
create or replace function public.pay_business_amount(p_owner uuid, p_zar numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_zar is null or p_zar < 1 or p_zar > 50000 then
    raise exception 'Enter an amount between R1 and R50,000'; end if;
  select display_name into v_name from profiles where id = p_owner;
  if not found then raise exception 'Business not found'; end if;
  return public._pay_items(auth.uid(), p_owner, null, null, null, round(p_zar, 2), null, coalesce(v_name, 'Business'));
end; $$;
revoke all on function public.pay_business_amount(uuid,numeric) from public, anon;
grant execute on function public.pay_business_amount(uuid,numeric) to authenticated, service_role;
