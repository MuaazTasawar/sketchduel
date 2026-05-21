# SketchDuel 🎨⚔️

> Real-time AI-judged drawing battle game. Draw fast, bluff the AI, beat your opponent.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter)
![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?style=flat&logo=fastapi)
![Supabase](https://img.shields.io/badge/Supabase-Free_Tier-3ECF8E?style=flat&logo=supabase)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat&logo=python)
![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen?style=flat)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat)

---

## Table of Contents

- [What is SketchDuel](#what-is-sketchduel)
- [Game Loop](#game-loop)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [Supabase Setup](#supabase-setup)
- [Running Locally](#running-locally)
- [Scoring System](#scoring-system)
- [API Reference](#api-reference)
- [Deployment](#deployment)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## What is SketchDuel?

SketchDuel is a **real-time multiplayer drawing battle game** where two players race to draw the same prompt. A machine learning model watches your drawing **as you draw** and scores you based on how well — or how cleverly badly — you draw it.

### The Bluff Mechanic

Most drawing games use human guessing. SketchDuel uses **ML confidence scores as a live game mechanic**. The AI is a third player you can manipulate:

- **Draw accurately** → high AI confidence → high base score
- **Draw fast** → speed bonus up to 25 points
- **Bluff the AI** → draw something the AI misidentifies with >60% confidence → 15 point bluff bonus

This creates a meta-game: sometimes drawing *wrong* on purpose is the winning strategy.

---

## Game Loop

```
Both players get the same prompt
        ↓
60 seconds to draw on canvas
        ↓
AI watches drawing live (confidence bar updates every 5 seconds)
        ↓
Submit drawing → ML model scores it
        ↓
Score = AI confidence + speed bonus + bluff bonus
        ↓
Both scores revealed → winner announced → leaderboard updated
```

---

## Tech Stack

| Layer | Technology | Cost |
|---|---|---|
| Frontend | Flutter 3.x (Web + Mobile) | Free |
| Backend | FastAPI + Python 3.11 | Free |
| Database | Supabase PostgreSQL | Free tier: 500MB |
| Realtime | Supabase Realtime WebSockets | Free tier: 200 concurrent |
| Auth | Supabase Auth | Free tier: 50,000 MAU |
| ML Inference | QuickDraw CNN (TFLite) | Free open source model |
| Deployment | Render.com | Free tier: 750hrs/month |

**Total monthly cost: $0**

---

## Project Structure

```
sketchduel/
│
├── README.md
├── .gitignore
│
├── backend/                          # FastAPI Python backend
│   ├── .env                          # Environment variables (never commit)
│   ├── render.yaml                   # Render.com deployment config
│   ├── requirements.txt              # Python dependencies
│   └── app/
│       ├── main.py                   # Entry point, CORS, router registration
│       ├── api/
│       │   ├── __init__.py           # Registers all routers
│       │   └── routes/
│       │       ├── auth.py           # Register, login, get profile
│       │       ├── game.py           # Room create/join, score submission
│       │       └── leaderboard.py    # Global rankings
│       ├── core/
│       │   ├── config.py             # Pydantic settings from .env
│       │   └── supabase.py           # Supabase client instances
│       ├── models/
│       │   ├── game.py               # GameRoom, DrawingSubmission, ScoreResult
│       │   └── user.py               # UserRegister, UserLogin, UserResponse
│       └── services/
│           ├── game_service.py       # Room logic, score saving, user stats
│           └── ml_service.py         # Image preprocessing, inference, scoring
│
└── frontend/                         # Flutter mobile/web app
    ├── pubspec.yaml                  # Flutter dependencies
    ├── assets/
    │   └── models/                   # TFLite model file goes here
    └── lib/
        ├── main.dart                 # App entry point, GoRouter, Supabase init
        ├── core/
        │   ├── constants/
        │   │   └── app_constants.dart     # API URLs, timeouts, config
        │   ├── theme/
        │   │   └── app_theme.dart         # Dark theme, colors, typography
        │   └── utils/
        │       └── supabase_client.dart   # Supabase init + realtime helpers
        ├── data/
        │   ├── datasources/
        │   │   └── api_datasource.dart    # HTTP GET/POST wrapper
        │   ├── models/
        │   │   ├── game_model.dart        # GameRoom, ScoreResult data classes
        │   │   └── user_model.dart        # UserModel data class
        │   └── repositories/
        │       └── game_repository.dart   # All game-related API calls
        └── features/
            ├── auth/
            │   └── screens/
            │       ├── login_screen.dart       # Email/password login
            │       └── register_screen.dart    # New account creation
            ├── home/
            │   └── screens/
            │       └── home_screen.dart        # Create/Join/Leaderboard menu
            ├── game/
            │   ├── screens/
            │   │   ├── lobby_screen.dart       # Create room or join with code
            │   │   ├── game_screen.dart        # Drawing canvas + timer + AI bar
            │   │   └── result_screen.dart      # Win/lose + score breakdown
            │   └── widgets/
            │       ├── drawing_canvas.dart     # Custom paint canvas with export
            │       ├── ai_score_bar.dart       # Live AI confidence indicator
            │       └── prompt_card.dart        # Prompt display + countdown timer
            └── leaderboard/
                └── screens/
                    └── leaderboard_screen.dart # Global rankings table
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Python | 3.11+ | [python.org](https://python.org) |
| Flutter | 3.0+ | [flutter.dev](https://flutter.dev) |
| Git | 2.x+ | [git-scm.com](https://git-scm.com) |

Verify installations:

```powershell
python --version
flutter --version
flutter doctor
git --version
```

`flutter doctor` must show no critical errors before proceeding.

---

## Getting Started

### 1. Clone the repository

```powershell
git clone https://github.com/MuaazTasawar/sketchduel.git
cd sketchduel
```

### 2. Backend setup

```powershell
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Flutter setup

```powershell
cd frontend
flutter pub get
```

---

## Environment Variables

Create `backend/.env` — never commit this file:

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_KEY=your-anon-public-key
SUPABASE_SERVICE_KEY=your-service-role-key
SECRET_KEY=anylongrandomstring123456
ENVIRONMENT=development
```

Update `frontend/lib/core/constants/app_constants.dart`:

```dart
class AppConstants {
  static const String appName = 'SketchDuel';

  // For Chrome / Web
  static const String baseUrl = 'http://localhost:8000/api/v1';
  // For Android emulator use:
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  // For production use:
  // static const String baseUrl = 'https://sketchduel-api.onrender.com/api/v1';

  static const String supabaseUrl = 'https://your-project-id.supabase.co';
  static const String supabaseAnonKey = 'your-anon-public-key';

  static const int drawingTimeSeconds = 60;
  static const int maxRoomCodeLength = 6;
}
```

---

## Supabase Setup

### 1. Create a free project

Go to [supabase.com](https://supabase.com) → New Project → choose a region.

### 2. Run this SQL in the SQL Editor

```sql
create table profiles (
  id uuid references auth.users on delete cascade primary key,
  username text unique not null,
  email text unique not null,
  total_wins integer default 0,
  total_games integer default 0,
  best_score float default 0.0,
  created_at timestamp with time zone default timezone('utc', now())
);

create table game_rooms (
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

create policy "Profiles are publicly readable"
  on profiles for select using (true);

create policy "Users can update their own profile"
  on profiles for update using (auth.uid() = id);

create policy "Game rooms are publicly readable"
  on game_rooms for select using (true);

create policy "Authenticated users can create rooms"
  on game_rooms for insert with check (auth.role() = 'authenticated');

create policy "Players can update their own room"
  on game_rooms for update using (
    auth.uid() = player1_id or auth.uid() = player2_id
  );

alter publication supabase_realtime add table game_rooms;
```

### 3. Get your credentials

```
Supabase Dashboard → Settings → API
- Project URL        → SUPABASE_URL
- anon public key    → SUPABASE_KEY and supabaseAnonKey
- service_role key   → SUPABASE_SERVICE_KEY
```

### 4. Disable email confirmation for local dev

```
Authentication → Providers → Email → Toggle OFF "Confirm email" → Save
```

---

## Running Locally

### Terminal 1 — Start Backend

```powershell
cd backend
venv\Scripts\activate
uvicorn app.main:app --reload --port 8000
```

Visit `http://localhost:8000/docs` to verify all endpoints are live.

### Terminal 2 — Start Flutter

```powershell
cd frontend
flutter run -d chrome
```

### Test the full game flow

```
1. Register two accounts (use incognito window for second player)
2. Player 1 → Create Room → copy the 6-character code
3. Player 2 → Join Room → enter the code
4. Both land on Game Screen with the same prompt
5. Draw within 60 seconds → Submit
6. Result screen shows scores and winner
7. Leaderboard updates automatically
```

---

## Scoring System

```
┌─────────────────────────────────────────────────────┐
│                  SCORING BREAKDOWN                   │
├──────────────────┬──────────────────────────────────┤
│ Base Score       │ AI confidence × 60   (max 60 pts)│
│ Speed Bonus      │ time_left/60 × 25    (max 25 pts)│
│ Bluff Bonus      │ +15 pts if AI wrong  (>60% conf) │
├──────────────────┼──────────────────────────────────┤
│ Maximum Score    │ 100 pts                           │
└──────────────────┴──────────────────────────────────┘
```

**Bluff Bonus conditions:**
- AI must be >60% confident in its prediction
- That prediction must not match the actual prompt
- Rewards abstract drawing that cleverly tricks the model

---

## API Reference

Base URL: `http://localhost:8000/api/v1`

### Auth

| Method | Endpoint | Description |
|---|---|---|
| POST | `/auth/register` | Create new account |
| POST | `/auth/login` | Login, returns token |
| GET | `/auth/profile/{user_id}` | Get user profile |

### Game

| Method | Endpoint | Description |
|---|---|---|
| POST | `/game/room/create` | Create a game room |
| POST | `/game/room/join` | Join existing room |
| GET | `/game/room/{room_code}` | Get room details |
| POST | `/game/score` | Submit drawing for AI scoring |
| GET | `/game/history/{user_id}` | Get past games |

### Leaderboard

| Method | Endpoint | Description |
|---|---|---|
| GET | `/leaderboard/top` | Get top 20 players |

### Example Score Response

```json
{
  "score": 78.5,
  "base_score": 51.0,
  "speed_bonus": 22.5,
  "bluff_bonus": 0.0,
  "bluff_detected": false,
  "recognized_as": "cat",
  "confidence": 0.85,
  "status": "waiting_for_opponent"
}
```

---

## Deployment

### Backend → Render.com (Free)

```
1. Push repo to GitHub
2. Go to render.com → New → Web Service
3. Connect your GitHub repo
4. Set Root Directory: backend
5. Build Command: pip install -r requirements.txt
6. Start Command: uvicorn app.main:app --host 0.0.0.0 --port $PORT
7. Add all environment variables in the Render dashboard
8. Deploy — live at https://sketchduel-api.onrender.com
```

### Frontend → Vercel (Free)

```powershell
cd frontend
flutter build web --release
npm i -g vercel
cd build\web
vercel --prod
```

After deploying backend, update `app_constants.dart`:

```dart
static const String baseUrl = 'https://sketchduel-api.onrender.com/api/v1';
```

> **Note:** Render free tier sleeps after 15 min of inactivity. First request after sleep takes ~30 seconds. Normal for a portfolio project.

---

## Common Issues

| Problem | Fix |
|---|---|
| `Connection refused` in Flutter | Backend not running — start it first |
| `10.0.2.2` not working | You are on Chrome — use `localhost` instead |
| `email rate limit exceeded` | Disable email confirmation in Supabase Auth settings |
| `email not confirmed` | Manually confirm user in Supabase → Authentication → Users |
| `relation does not exist` | SQL schema not run yet in Supabase |
| Port 8000 already in use | Run `netstat -ano \| findstr :8000` then `taskkill /PID <id> /F` |
| Flutter web CORS error | Check CORS origins in `backend/app/main.py` includes your Flutter port |

---

## Roadmap

- [ ] Replace mock ML with real TFLite QuickDraw model
- [ ] Live stroke-by-stroke AI inference
- [ ] Spectator mode
- [ ] Tournament brackets (4/8 player elimination)
- [ ] Custom prompt packs (Animals, Food, Architecture)
- [ ] Drawing replay system
- [ ] Daily global challenge mode
- [ ] PWA installable web version
- [ ] Chat and emoji reactions during game

---

## Contributing

```powershell
git checkout -b feature/your-feature-name
# make your changes
git commit -m "feat: your feature description"
git push origin feature/your-feature-name
# Open a Pull Request on GitHub
```

Please follow the existing code style:
- Dart files: `snake_case` for filenames, `PascalCase` for classes
- Python files: PEP8 standard

---

## License

MIT License — free to use, modify, and distribute.

---

Built with FastAPI, Flutter, Supabase, and a love for tricking neural networks. ✏️