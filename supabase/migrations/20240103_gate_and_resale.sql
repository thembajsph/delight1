-- ─────────────────────────────────────────────────────────────────────────────
-- Gate scanning (real staff roster + check-in audit log) and ticket resale.
-- Replaces the in-app hardcoded demo staff/ticket lists with real, organizer-
-- scoped data. No separate Supabase Auth account needed per gate staffer —
-- the device stays signed in as the organizer, and the 4-digit PIN just
-- picks which staff member is operating that device (consistent with the
-- "no email/password at the gate" design already in the app).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Gate staff roster ───────────────────────────────────────────────────────
create table if not exists public.gate_staff (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  name       text not null,
  gate_name  text not null,
  pin        text not null check (pin ~ '^[0-9]{4}$'),
  created_at timestamptz default now(),
  unique (event_id, pin)
);

-- ── Gate check-in audit log ─────────────────────────────────────────────────
-- One row per scan attempt (admitted, rejected as already-used, or invalid).
-- This is the real source of truth for the gate dashboard — no more
-- hardcoded per-gate numbers.
create table if not exists public.gate_checkins (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid references public.tickets(id) on delete set null,
  event_id   uuid not null references public.events(id) on delete cascade,
  staff_id   uuid references public.gate_staff(id) on delete set null,
  gate_name  text,
  result     text not null check (result in ('admitted','already_used','invalid')),
  scanned_at timestamptz default now()
);

create index if not exists gate_checkins_event_idx on public.gate_checkins(event_id);
create index if not exists gate_checkins_scanned_at_idx on public.gate_checkins(scanned_at);

alter table public.gate_staff    enable row level security;
alter table public.gate_checkins enable row level security;

-- Only the event's organizer can manage staff or read the check-in log.
drop policy if exists "gate_staff_organizer" on public.gate_staff;
create policy "gate_staff_organizer" on public.gate_staff
  for all using (
    auth.uid() = (select organizer_id from public.events where id = event_id)
  );

drop policy if exists "gate_checkins_organizer" on public.gate_checkins;
create policy "gate_checkins_organizer" on public.gate_checkins
  for all using (
    auth.uid() = (select organizer_id from public.events where id = event_id)
  );

grant select, insert, update, delete on public.gate_staff    to authenticated;
grant select, insert, update, delete on public.gate_staff    to service_role;
grant select, insert, update, delete on public.gate_checkins to authenticated;
grant select, insert, update, delete on public.gate_checkins to service_role;

-- ── Ticket resale support ───────────────────────────────────────────────────
-- Lets a buyer purchase a listed resale ticket via a Supabase RPC that runs
-- as the ticket owner (security definer), since a buyer's own session can't
-- update someone else's ticket row or wallet under RLS. The function does
-- the whole transfer atomically: moves ZAR between the two ledger balances,
-- flips ticket ownership, and logs both sides of the transaction.
create or replace function public.buy_resale_ticket(
  p_ticket_id uuid,
  p_buyer_id  uuid
) returns public.tickets
language plpgsql security definer as $$
declare
  v_ticket   public.tickets;
  v_seller   uuid;
  v_price    numeric;
  v_buyer_balance numeric;
  v_fee      numeric;
  v_net      numeric;
begin
  select * into v_ticket from public.tickets where id = p_ticket_id for update;
  if v_ticket is null then
    raise exception 'Ticket not found';
  end if;
  if not v_ticket.is_for_sale then
    raise exception 'Ticket is not listed for sale';
  end if;
  if v_ticket.user_id = p_buyer_id then
    raise exception 'You already own this ticket';
  end if;

  v_seller := v_ticket.user_id;
  v_price  := coalesce(v_ticket.resale_price_zar, v_ticket.price_zar);
  v_fee    := v_price * 0.03;         -- 3% resale fee, matches FeeCalculator
  v_net    := v_price - v_fee;

  select balance_dc into v_buyer_balance from public.wallets
    where user_id = p_buyer_id for update;
  if v_buyer_balance is null then
    raise exception 'Buyer wallet not found';
  end if;
  if v_buyer_balance < v_price then
    raise exception 'Insufficient balance';
  end if;

  -- Move ZAR (as DC, 1:1 internal ledger units already used elsewhere)
  update public.wallets set balance_dc = balance_dc - v_price where user_id = p_buyer_id;
  update public.wallets set balance_dc = balance_dc + v_net   where user_id = v_seller;

  -- Transfer ownership
  update public.tickets set
    user_id          = p_buyer_id,
    is_for_sale       = false,
    resale_price_zar  = null,
    status            = 'transferred'
  where id = p_ticket_id
  returning * into v_ticket;

  insert into public.transactions (user_id, type, amount_dc, amount_zar, fee_dc, status, reference, metadata)
  values
    (p_buyer_id, 'ticket_purchase', v_price, v_price, 0, 'completed', p_ticket_id::text,
      jsonb_build_object('resale', true, 'seller', v_seller)),
    (v_seller,   'ticket_sale',     v_net,   v_net,   v_fee, 'completed', p_ticket_id::text,
      jsonb_build_object('resale', true, 'buyer', p_buyer_id));

  return v_ticket;
end;
$$;

grant execute on function public.buy_resale_ticket(uuid, uuid) to authenticated;
