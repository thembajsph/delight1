-- Social feed posts — previously the app only ever showed hardcoded fake
-- seed posts and never persisted anything a real user created. This adds
-- the real table + RLS so posts and likes actually save and are visible
-- to everyone, not just the device that created them.

create table if not exists public.posts (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references public.profiles(id) on delete cascade,
  user_display_name   text,
  user_avatar_url     text,
  event_id            uuid references public.events(id),
  event_name          text,
  content             text not null default '',
  image_urls          jsonb default '[]'::jsonb,
  nft_token_id        text,
  is_nft_memory       boolean default false,
  memory_token_id     text,
  attended_event_name text,
  attended_event_venue text,
  attended_tier       text,
  attended_ticket_id  text,
  event_date          timestamptz,
  has_video           boolean default false,
  memory_style        text,
  likes_count         int default 0,
  comments_count      int default 0,
  created_at          timestamptz default now()
);

create table if not exists public.post_likes (
  post_id    uuid references public.posts(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

alter table public.posts      enable row level security;
alter table public.post_likes enable row level security;

drop policy if exists "posts_read"  on public.posts;
drop policy if exists "posts_write" on public.posts;
create policy "posts_read"  on public.posts for select using (true);
drop policy if exists "posts_write" on public.posts;
create policy "posts_write" on public.posts for insert with check (auth.uid() = user_id);
drop policy if exists "posts_own_update" on public.posts;
create policy "posts_own_update" on public.posts for update using (auth.uid() = user_id);

drop policy if exists "likes_read"  on public.post_likes;
drop policy if exists "likes_write" on public.post_likes;
create policy "likes_read"  on public.post_likes for select using (true);
drop policy if exists "likes_write" on public.post_likes;
create policy "likes_write" on public.post_likes for all using (auth.uid() = user_id);

-- Auto-maintain likes_count so the client never has to trust a
-- client-supplied number
create or replace function public.update_post_likes_count()
returns trigger language plpgsql security definer as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  elsif TG_OP = 'DELETE' then
    update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end; $$;

drop trigger if exists on_post_like_change on public.post_likes;
create trigger on_post_like_change
  after insert or delete on public.post_likes
  for each row execute function public.update_post_likes_count();

create index if not exists posts_created_at_idx on public.posts(created_at desc);
create index if not exists posts_user_id_idx    on public.posts(user_id);

-- ── Data API grants ─────────────────────────────────────────────────────────
-- Required from Oct 30 2026 onward — see 20240101_delight_schema.sql for
-- why. Feed posts and likes are public content (select for anon is
-- correct here — browsing the feed logged-out is a reasonable product
-- choice; RLS still blocks anon from writing).

grant select on public.posts to anon;
grant select, insert, update, delete on public.posts to authenticated;
grant select, insert, update, delete on public.posts to service_role;

grant select on public.post_likes to anon;
grant select, insert, update, delete on public.post_likes to authenticated;
grant select, insert, update, delete on public.post_likes to service_role;
