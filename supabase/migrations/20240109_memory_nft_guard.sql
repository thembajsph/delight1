-- Delight 0109 — a Memory NFT post must come from a ticket the poster owns,
-- for an event that has happened or where they were scanned in at the gate.
-- Before this the app could claim any ticket id and get the "verified" badge.
-- Safe to run more than once.
create or replace function public.posts_memory_guard()
-- Deliberately NOT security definer: current_user must stay 'authenticated' for the check.
returns trigger language plpgsql set search_path = public as $$
declare v_t tickets; v_date timestamptz;
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if coalesce(new.is_nft_memory, false) then
    select * into v_t from tickets
     where id::text = new.attended_ticket_id and user_id = new.user_id;
    if not found then
      raise exception 'Memory NFTs need a ticket you own';
    end if;
    select event_date into v_date from events where id = v_t.event_id;
    if not (coalesce(v_t.is_used, false) or (v_date is not null and v_date < now())) then
      raise exception 'This ticket unlocks after the event';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists posts_memory_guard on public.posts;
create trigger posts_memory_guard before insert or update of is_nft_memory, attended_ticket_id
  on public.posts for each row execute function public.posts_memory_guard();
