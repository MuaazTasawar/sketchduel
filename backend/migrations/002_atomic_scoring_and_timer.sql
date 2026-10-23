-- 002_atomic_scoring_and_timer.sql
-- Idempotent: safe to run more than once.
--
-- Fixes:
--   * Race conditions: joining a room and finishing a match are now single atomic
--     database operations (row lock + one transaction).
--   * Server-side match clock (started_at) and automatic forfeit of players who never submit.
--   * Atomic stat updates (no read-then-write).
--   * Draws: equal scores no longer silently favour player 1.
--   * Cheating / data leaks: browsers can no longer write to profiles or game_rooms with the
--     public anon key, and profiles.email is no longer publicly readable.
--
-- All writes now go through the FastAPI backend (service_role key).

-- 1) Columns, constraints, indexes ------------------------------------------------------------
alter table game_rooms add column if not exists started_at  timestamptz;
alter table game_rooms add column if not exists finished_at timestamptz;

-- Games that were already running before this migration: start their clock at creation time.
update game_rooms
   set started_at = coalesce(started_at, created_at)
 where status <> 'waiting' and started_at is null;

alter table game_rooms drop constraint if exists game_rooms_status_check;
alter table game_rooms add constraint game_rooms_status_check
  check (status in ('waiting', 'active', 'finished'));

alter table game_rooms drop constraint if exists game_rooms_distinct_players_check;
alter table game_rooms add constraint game_rooms_distinct_players_check
  check (player2_id is null or player1_id is distinct from player2_id);

create index if not exists game_rooms_player1_idx on game_rooms (player1_id);
create index if not exists game_rooms_player2_idx on game_rooms (player2_id);
create index if not exists game_rooms_status_created_idx on game_rooms (status, created_at desc);
create index if not exists profiles_leaderboard_idx on profiles (total_wins desc, best_score desc);

-- 2) Row Level Security: browsers may only READ their own rooms ---------------------------------
drop policy if exists "Profiles are publicly readable" on profiles;
drop policy if exists "Users can update their own profile" on profiles;
drop policy if exists "Game rooms are publicly readable" on game_rooms;
drop policy if exists "Authenticated users can create rooms" on game_rooms;
drop policy if exists "Players can update their own room" on game_rooms;
drop policy if exists "Profiles are readable" on profiles;
drop policy if exists "Players can read their own rooms" on game_rooms;

create policy "Profiles are readable"
  on profiles for select using (true);

create policy "Players can read their own rooms"
  on game_rooms for select to authenticated
  using (auth.uid() = player1_id or auth.uid() = player2_id);

-- No insert/update/delete policies exist any more, and the privileges are revoked as well.
revoke insert, update, delete on profiles   from anon, authenticated;
revoke insert, update, delete on game_rooms from anon, authenticated;
revoke select on game_rooms from anon;

-- Do not expose e-mail addresses through the public anon key.
revoke select on profiles from anon, authenticated;
grant select (id, username, total_wins, total_games, best_score, created_at)
  on profiles to anon, authenticated;

-- 3) Atomic game functions (callable by the backend only) --------------------------------------

-- Join a waiting room. Exactly one caller can win the race; returns 0 rows if the room is
-- missing, already full, or the caller is the creator.
create or replace function join_room(p_room_code text, p_player_id uuid)
returns setof game_rooms
language sql
security definer
set search_path = public
as $$
  update game_rooms
     set player2_id = p_player_id,
         status     = 'active',
         started_at = now()
   where room_code  = upper(p_room_code)
     and status     = 'waiting'
     and player2_id is null
     and player1_id <> p_player_id
  returning *;
$$;

-- Finish a room if both scores are in, or if the deadline passed (missing score counts as 0).
-- Safe to call repeatedly: it is a no-op unless the room is active and finishable.
create or replace function finalize_room(p_game_id uuid, p_limit_seconds integer default 65)
returns game_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  r game_rooms;
  s1 double precision;
  s2 double precision;
  w  uuid;
begin
  select * into r from game_rooms where id = p_game_id for update;
  if not found then
    raise exception 'room_not_found';
  end if;

  if r.status <> 'active' then
    return r;
  end if;

  if not (
       (r.player1_score is not null and r.player2_score is not null)
    or (r.started_at is not null and now() >= r.started_at + make_interval(secs => p_limit_seconds))
  ) then
    return r;
  end if;

  s1 := coalesce(r.player1_score, 0);
  s2 := coalesce(r.player2_score, 0);

  if s1 > s2 then
    w := r.player1_id;
  elsif s2 > s1 then
    w := r.player2_id;
  else
    w := null;  -- draw
  end if;

  update game_rooms
     set player1_score = s1,
         player2_score = s2,
         winner_id     = w,
         status        = 'finished',
         finished_at   = now()
   where id = r.id
  returning * into r;

  update profiles
     set total_games = coalesce(total_games, 0) + 1,
         total_wins  = coalesce(total_wins, 0) + (case when w = id then 1 else 0 end),
         best_score  = greatest(coalesce(best_score, 0), s1)
   where id = r.player1_id;

  update profiles
     set total_games = coalesce(total_games, 0) + 1,
         total_wins  = coalesce(total_wins, 0) + (case when w = id then 1 else 0 end),
         best_score  = greatest(coalesce(best_score, 0), s2)
   where id = r.player2_id;

  return r;
end;
$$;

-- Record one player's score (first submission wins; resubmitting is ignored) and finish the
-- match if possible. Always returns the up-to-date room row.
create or replace function submit_score(
  p_game_id uuid,
  p_player_id uuid,
  p_score double precision,
  p_limit_seconds integer default 65
)
returns game_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  r game_rooms;
begin
  select * into r from game_rooms where id = p_game_id for update;
  if not found then
    raise exception 'room_not_found';
  end if;

  if r.player1_id is distinct from p_player_id and r.player2_id is distinct from p_player_id then
    raise exception 'not_a_player';
  end if;

  if r.status = 'waiting' then
    raise exception 'room_not_active';
  end if;

  if r.status = 'finished' then
    return r;
  end if;

  if r.player1_id = p_player_id then
    if r.player1_score is null then
      update game_rooms set player1_score = p_score where id = r.id;
    end if;
  else
    if r.player2_score is null then
      update game_rooms set player2_score = p_score where id = r.id;
    end if;
  end if;

  return finalize_room(p_game_id, p_limit_seconds);
end;
$$;

-- 4) Only the backend (service_role) may call these ---------------------------------------------
revoke all on function join_room(text, uuid)                          from public, anon, authenticated;
revoke all on function finalize_room(uuid, integer)                   from public, anon, authenticated;
revoke all on function submit_score(uuid, uuid, double precision, integer) from public, anon, authenticated;

grant execute on function join_room(text, uuid)                          to service_role;
grant execute on function finalize_room(uuid, integer)                   to service_role;
grant execute on function submit_score(uuid, uuid, double precision, integer) to service_role;

-- 5) Make sure Realtime still publishes room changes -------------------------------------------
do $$
begin
  alter publication supabase_realtime add table game_rooms;
exception
  when duplicate_object then null;
end $$;

-- Optional checks (run separately):
--   select proname, prosecdef from pg_proc where proname in ('join_room','finalize_room','submit_score');
--   select policyname, tablename from pg_policies where tablename in ('profiles','game_rooms');