-- Delight 0107 — repair users who have no profile/wallet row.
-- Symptom: creating an event fails with
--   insert or update on table "events" violates foreign key constraint
--   Key (organizer_id)=(...) is not present in table "profiles"
-- Cause: the signed-in auth user has no row in public.profiles (they signed up
-- before the signup trigger existed, or the profiles table was recreated).
-- Safe to run any number of times.

insert into public.profiles (id, email, display_name, avatar_url)
select u.id, u.email,
       coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email,'@',1)),
       u.raw_user_meta_data->>'avatar_url'
  from auth.users u
 where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict do nothing;

insert into public.wallets (user_id, balance_dc)
select p.id, 0 from public.profiles p
 where not exists (select 1 from public.wallets w where w.user_id = p.id)
on conflict do nothing;
