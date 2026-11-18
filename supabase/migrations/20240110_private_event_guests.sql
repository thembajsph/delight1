-- Delight 0110 — private events: invite people already on Delight first.
-- * private_event_guests.user_id links a guest to their Delight profile.
-- * add_private_guest_from_user: host picks a Delight user; their phone is read
--   server-side (never sent to the host's app) and an in-app message with the
--   RSVP link is sent to them.
-- * match_delight_contacts: given phone numbers from the host's address book, says
--   which belong to Delight users (id + display name only, never the number back
--   as a searchable list). Capped at 500 numbers per call.
-- Safe to run more than once.

alter table public.private_event_guests
  add column if not exists user_id uuid references public.profiles(id) on delete set null;

create or replace function public._phone_key(p text) returns text
language sql immutable as $$
  select right(regexp_replace(coalesce(p,''), '[^0-9]', '', 'g'), 9)
$$;

create or replace function public.match_delight_contacts(p_phones text[])
returns table (phone_in text, id uuid, display_name text, avatar_url text)
language sql security definer stable set search_path = public as $$
  select x.ph, p.id, p.display_name, p.avatar_url
    from unnest((select coalesce(p_phones[1:500], '{}'))) as x(ph)
    join profiles p on public._phone_key(p.phone) = public._phone_key(x.ph)
   where auth.uid() is not null
     and char_length(public._phone_key(x.ph)) = 9
     and p.id <> auth.uid();
$$;

create or replace function public.add_private_guest_from_user(
  p_event uuid, p_user uuid, p_link text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_ev private_events; v_p profiles; v_g private_event_guests; v_conv uuid; v_phone text;
begin
  select * into v_ev from private_events where id = p_event and host_id = v_me;
  if not found then raise exception 'Not your event'; end if;
  if p_user = v_me then raise exception 'You are the host'; end if;
  select * into v_p from profiles where id = p_user;
  if not found then raise exception 'User not found'; end if;

  v_phone := nullif(trim(coalesce(v_p.phone,'')), '');
  if v_phone is null then v_phone := 'dl:' || left(replace(p_user::text,'-',''), 14); end if;

  insert into private_event_guests (event_id, name, phone, user_id)
    values (p_event, coalesce(nullif(v_p.display_name,''), 'Guest'), v_phone, p_user)
    on conflict (event_id, phone) do nothing
    returning * into v_g;
  if v_g.id is null then raise exception 'duplicate: already on the guest list'; end if;

  -- In-app invitation from the host (appears in their Messages).
  begin
    v_conv := public.get_or_create_dm(v_me, p_user);
    insert into messages (conversation_id, sender_id, content)
      values (v_conv, v_me,
        'You''re invited to ' || v_ev.name || ' 🎉' ||
        case when p_link is not null then E'\nRSVP: ' || p_link else '' end);
  exception when others then
    null;  -- the guest is added even if the message cannot be sent
  end;
  return to_jsonb(v_g);
end; $$;

revoke all on function public.match_delight_contacts(text[]) from public, anon;
revoke all on function public.add_private_guest_from_user(uuid,uuid,text) from public, anon;
grant execute on function public.match_delight_contacts(text[]) to authenticated;
grant execute on function public.add_private_guest_from_user(uuid,uuid,text) to authenticated;
