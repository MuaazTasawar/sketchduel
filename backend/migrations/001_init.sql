-- 001_init.sql
-- Baseline schema for SketchDuel (what the project originally shipped with).
-- Idempotent: safe to run on a fresh project. Existing projects already have this;
-- they only need 002_atomic_scoring_and_timer.sql.

create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  username text unique not null,
  email text unique not null,
  total_wins integer default 0,
  total_games integer default 0,
  best_score float default 0.0,
  created_at timestamp with time zone default timezone('utc', now())
);

create table if not exists game_rooms (
  id uuid default gen_random_uuid() primary key,
  room_code text unique not null,
  prompt text not null,
  status text default 'waiting',
  player1_id uuid references profiles(id),
  player2_id uuid references profiles(id),
  player1_score float,
  player2_score float,
  winner_id uuid references profiles(id),
  created_at timestamp with time zone default timezone('utc', now())
);

alter table profiles enable row level security;
alter table game_rooms enable row level security;

drop policy if exists "Profiles are publicly readable" on profiles;
create policy "Profiles are publicly readable"
  on profiles for select using (true);

drop policy if exists "Users can update their own profile" on profiles;
create policy "Users can update their own profile"
  on profiles for update using (auth.uid() = id);

drop policy if exists "Game rooms are publicly readable" on game_rooms;
create policy "Game rooms are publicly readable"
  on game_rooms for select using (true);

drop policy if exists "Authenticated users can create rooms" on game_rooms;
create policy "Authenticated users can create rooms"
  on game_rooms for insert with check (auth.role() = 'authenticated');

drop policy if exists "Players can update their own room" on game_rooms;
create policy "Players can update their own room"
  on game_rooms for update using (
    auth.uid() = player1_id or auth.uid() = player2_id
  );

-- Realtime: the lobby and game screens subscribe to game_rooms changes.
do $$
begin
  alter publication supabase_realtime add table game_rooms;
exception
  when duplicate_object then null;
end $$;