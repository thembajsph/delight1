-- Delight 0108 — tickets must actually cost money, and resale must be safe.
-- Before this: mint_ticket handed out tickets without charging anyone (it trusted a
-- client-sent price and never touched the wallet), and buy_resale_ticket took the
-- buyer id from the client, so anyone could make anyone else buy a ticket.
-- Safe to run more than once.

-- 1) Primary sale: debit buyer, credit organiser (minus 3% platform fee), issue the
--    ticket and bump the tier's sold count — all in one transaction.
--    Service role only: called by the mint_ticket edge function after it has
--    authenticated the user, so the price can never come from the client.
create or replace function public._buy_ticket(
  p_user uuid, p_event uuid, p_tier text,
  p_metadata_uri text, p_owner_address text, p_nft_tx jsonb
) returns public.tickets
language plpgsql security definer set search_path = public as $$
declare
  v_ev      public.events;
  v_tiers   jsonb;
  v_tier    jsonb;
  v_price   numeric;          -- DC (XRP units), same unit as wallets.balance_dc
  v_fee     numeric;
  v_rate    numeric;
  v_bal     numeric;
  v_total   int;
  v_sold    int;
  v_ticket  public.tickets;
begin
  select * into v_ev from events where id = p_event for update;
  if not found then raise exception 'Event not found'; end if;
  if not coalesce(v_ev.is_published, false) then raise exception 'Event is not on sale'; end if;
  if v_ev.event_date is not null and v_ev.event_date < now() - interval '12 hours' then
    raise exception 'This event has already happened';
  end if;

  v_tiers := coalesce(v_ev.ticket_tiers, '[]'::jsonb);
  select t into v_tier from jsonb_array_elements(v_tiers) t
   where t->>'name' = p_tier limit 1;
  if v_tier is null then raise exception 'Unknown ticket tier'; end if;

  v_price := coalesce((v_tier->>'priceXRP')::numeric, 0);
  v_total := coalesce((v_tier->>'totalTickets')::int, 0);
  v_sold  := coalesce((v_tier->>'soldTickets')::int, 0);
  if v_price < 0 then raise exception 'Invalid price'; end if;
  if v_total > 0 and v_sold >= v_total then raise exception 'Sold out'; end if;

  select balance_dc, coalesce(xrp_price, 9.50) into v_bal, v_rate
    from wallets where user_id = p_user for update;
  if v_bal is null then raise exception 'Wallet not found'; end if;
  if v_bal < v_price then raise exception 'Not enough balance'; end if;

  v_fee := round(v_price * 0.03, 8);

  if v_price > 0 then
    update wallets set balance_dc = balance_dc - v_price where user_id = p_user;
    if v_ev.organizer_id is not null then
      update wallets set balance_dc = balance_dc + (v_price - v_fee)
       where user_id = v_ev.organizer_id;
    end if;
  end if;

  update events set ticket_tiers = (
    select jsonb_agg(case when t->>'name' = p_tier
             then jsonb_set(t, '{soldTickets}', to_jsonb(v_sold + 1)) else t end)
      from jsonb_array_elements(v_tiers) t)
   where id = p_event;

  insert into tickets (user_id, event_id, tier, price_zar, owner_address, metadata_uri,
                       nft_tx, status, minted_at)
    values (p_user, p_event, p_tier, round(v_price * v_rate, 2), p_owner_address,
            p_metadata_uri, p_nft_tx, 'pending_mint', now())
    returning * into v_ticket;

  if v_price > 0 then
    insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status, reference, metadata)
    values
      (p_user, 'ticket_purchase', v_price, round(v_price * v_rate, 2), 0, 'completed',
        v_ticket.id::text, jsonb_build_object('event', p_event, 'tier', p_tier)),
      (v_ev.organizer_id, 'ticket_sale', v_price - v_fee, round((v_price - v_fee) * v_rate, 2),
        v_fee, 'completed', v_ticket.id::text,
        jsonb_build_object('event', p_event, 'tier', p_tier, 'buyer', p_user))
    ;
  end if;
  return v_ticket;
end;
$$;
revoke all on function public._buy_ticket(uuid,uuid,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public._buy_ticket(uuid,uuid,text,text,text,jsonb) to service_role;

-- 2) Resale: the buyer is always the signed-in caller (the parameter must match),
--    amounts use the ledger's DC units, and the seller gets the price minus 3%.
create or replace function public.buy_resale_ticket(
  p_ticket_id uuid,
  p_buyer_id  uuid
) returns public.tickets
language plpgsql security definer set search_path = public as $$
declare
  v_ticket public.tickets;
  v_seller uuid;
  v_zar    numeric;
  v_rate   numeric;
  v_dc     numeric;
  v_fee    numeric;
  v_net    numeric;
  v_bal    numeric;
begin
  if auth.uid() is null or p_buyer_id is distinct from auth.uid() then
    raise exception 'Not allowed';
  end if;

  select * into v_ticket from tickets where id = p_ticket_id for update;
  if v_ticket is null then raise exception 'Ticket not found'; end if;
  if not coalesce(v_ticket.is_for_sale, false) then raise exception 'Ticket is not listed for sale'; end if;
  if v_ticket.user_id = p_buyer_id then raise exception 'You already own this ticket'; end if;

  v_seller := v_ticket.user_id;
  v_zar    := coalesce(v_ticket.resale_price_zar, v_ticket.price_zar);

  select balance_dc, coalesce(xrp_price, 9.50) into v_bal, v_rate
    from wallets where user_id = p_buyer_id for update;
  if v_bal is null then raise exception 'Buyer wallet not found'; end if;

  v_dc  := round(v_zar / v_rate, 8);
  v_fee := round(v_dc * 0.03, 8);
  v_net := v_dc - v_fee;
  if v_bal < v_dc then raise exception 'Insufficient balance'; end if;

  update wallets set balance_dc = balance_dc - v_dc where user_id = p_buyer_id;
  update wallets set balance_dc = balance_dc + v_net where user_id = v_seller;

  update tickets set user_id = p_buyer_id, is_for_sale = false,
         resale_price_zar = null, status = 'transferred'
   where id = p_ticket_id returning * into v_ticket;

  insert into transactions (user_id, type, amount_dc, amount_zar, fee_dc, status, reference, metadata)
  values
    (p_buyer_id, 'ticket_purchase', v_dc, v_zar, 0, 'completed', p_ticket_id::text,
      jsonb_build_object('resale', true, 'seller', v_seller)),
    (v_seller, 'ticket_sale', v_net, round(v_net * v_rate, 2), v_fee, 'completed',
      p_ticket_id::text, jsonb_build_object('resale', true, 'buyer', p_buyer_id));
  return v_ticket;
end;
$$;
revoke all on function public.buy_resale_ticket(uuid,uuid) from public, anon;
grant execute on function public.buy_resale_ticket(uuid,uuid) to authenticated, service_role;
