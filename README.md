# JustUs 💖

![JustUs](JustUs.png)

**JustUs** is a premium digital ecosystem designed specifically for couples. Built with a modern **Flutter** frontend and a robust **Hybrid Backend** (Supabase + Node.js), it provides a secure and intimate space to share emotions, preserve memories, and engage in meaningful daily interactions.

---

## ✨ Key Features

### 🌈 Mood & Emotions
Express yourself beyond words. Share your emotional state using a rich set of emojis and view your partner's current mood in real-time. 
- **Recent Trends**: Track the couple's emotional history with a list of recently used emojis.
- **Instant Sync**: Changes are updated immediately across devices and cached locally for a zero-latency experience.

### 💓 Miss You & Connection
A simple, powerful way to stay connected throughout the day. 
- **One-Tap Notifies**: Send a quick "I miss you" notification to your partner with a single tap.
- **Shared Counter**: A persistent counter celebrates every time you've thought of each other, creating a visual record of your bond.

### 🎮 AI-Powered Couple Game
Discover new layers of your relationship every day.
- **Daily Challenges**: A fresh "who is more likely to…" question is generated on demand through the **[OpenRouter](https://openrouter.ai/) AI gateway**, which walks a fallback chain of free models (`openrouter/free` → `openai/gpt-oss-120b:free` → `nvidia/nemotron-3-super:free`) under a per-user daily token quota and a circuit breaker.
- **Interactive Voting**: Partners vote between two options (each other) on fun and meaningful scenarios.
- **Shared History**: Build a library of memories by revisiting past questions and seeing how your answers align over time.

### 📂 Shared Drive (R2 Cloud Gallery)
A high-performance, private cloud space for your shared memories.
- **Hybrid Storage**: Combines **Supabase** metadata for fast indexing with **Cloudflare R2** for cost-effective, high-speed media delivery.
- **Interactive Gallery**: React to photos and videos with emojis, or mark your favorite moments to find them easily later; audio and PDF files are uploadable and openable in-app.
- **Mobile Optimized**: Automatically compresses media before upload (15 MB hard cap, thumbnails generated client-side) and uses an incremental sync engine to keep the gallery up-to-date with minimal data usage.

### 📝 Collaborative Bucket List
Plan your future together with a shared roadmap of dreams and tasks.
- **Categorized Goals**: Organize your ambitions by category (e.g., Travel, Food, Experiences).
- **Real-time Collaboration**: Add, edit, or complete items and see changes instantly on both devices.

### 👤 Secure Partner Linking
Your privacy is our priority.
- **Unique Identification**: Link with your partner using a secure, one-time invitation system.
- **Device Fingerprinting**: Advanced security measures ensure that only authorized devices can access your shared space.

### 🎨 Personalization & Accessibility
- **Dark & Light Themes**: A tokenized violet-neon design system (Material 3 + Plus Jakarta Sans) with a persisted theme preference; your choice survives restarts and is preserved on logout.
- **Localization**: Italian (default) and English via ARB-based `flutter_localizations`, with the language preference preserved across sessions.
- **Accessible by construction**: shared components expose `Semantics` (buttons, list rows, navigation) and localized tooltips, and both themes are tokenized so contrast stays consistent; per-component A11y/theme/localization status is tracked in `docs/app/design-system/doc.md`.

---

## 🛠️ Tech Stack

### **Frontend** (Cross-Platform)
- **Framework**: [Flutter](https://flutter.dev/) (Dart 3.x, Material 3)
- **State Management**: [Provider](https://pub.dev/packages/provider) for reactive UI.
- **Localization**: `flutter_localizations` + `intl` with ARB catalogs (`Flutter/lib/core/localization`).
- **Security**: HMAC Request Signing and SHA-256 fingerprinting for API integrity.
- **Media**: Advanced caching with `CachedNetworkImage` and custom `MediaCacheManager`.

### **Backend Infrastructure** (Hybrid)
- **Database & Auth**: [Supabase](https://supabase.com/) (PostgreSQL + GoTrue) for real-time data and secure authentication.
- **Service Layer**: [Node.js](https://nodejs.org/) (Express) acting as a secure gateway for AI and Media services.
- **Cloud Storage**: [Cloudflare R2](https://www.cloudflare.com/developer-platform/r2/) for private media hosting.
- **AI Engine**: [OpenRouter](https://openrouter.ai/) chat-completions gateway (`Backend/config/aiConfig.js`) — no local model runtime required; only `OPENROUTER_API_KEY` is needed.
- **Notifications**: [Firebase Cloud Messaging (FCM)](https://firebase.google.com/docs/cloud-messaging).

---

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x, Dart SDK `>=3.0.0 <4.0.0`)
- [Node.js](https://nodejs.org/) (v20.19+ / v22 LTS)
- A [Supabase](https://supabase.com/) project (PostgreSQL + Auth + Realtime) with the schema from `supabase/schemas/**` applied
- A private [Cloudflare R2](https://www.cloudflare.com/developer-platform/r2/) bucket
- An [OpenRouter](https://openrouter.ai/) API key (AI game questions)
- A Firebase service-account JSON for FCM (push notifications)

### 2. Backend Setup
1. Navigate to the `Backend` directory:
   ```bash
   cd Backend
   npm install
   ```
2. Create a `.env` file in the **repository root** (refer to `.env.example`). The backend resolves its env file from there — `<repo-root>/.env` by default, `<repo-root>/.env.test` when `ENV=test`/`NODE_ENV=test`, or `JUSTUS_ENV_FILE` when exported in the real process environment.

   Variables without a code default are mandatory and the server refuses to boot without them: `SUPABASE_ANON_KEY`, `JUSTUS_DATA_DIR`, `MAX_ACCESS_TOKEN_LIFETIME_SEC` (must be ≥ your Supabase Auth JWT expiry) and `LOG_RETENTION_DAYS`.

3. Start the server:
   ```bash
   npm start
   ```

### 3. Flutter App Setup
1. Navigate to `Flutter`:
   ```bash
   cd Flutter
   ```
2. Create a `.env` file in the `Flutter` directory (refer to `Flutter/.env.example`). Server origins are resolved from the build mode and can be overridden with `--dart-define=JUSTUS_DEV_SERVER_ORIGIN=…` / `--dart-define=JUSTUS_PROD_SERVER_ORIGIN=…`.
3. Run the app:
   ```bash
   flutter pub get
   flutter run
   ```

### 4. Testing
The repository includes an isolated test setup for both backend and Flutter code.

- Backend API suite (lint + Jest, tests live in `test/backend`):
  ```bash
  cd Backend
  npm test
  ```
- Full local runner (backend lint + circular-dependency + syntax + tests, `jscpd` duplication scan, `flutter analyze` + hardcoded-string check + Flutter tests):
  ```bash
  npm run validate          # bash ./scripts/test-all.sh
  ```
- Duplication scan only:
  ```bash
  npm run scan:duplicates
  ```

Test environment highlights:
- `ENV=test` / `NODE_ENV=test` support via the root `.env.test`
- mocked Supabase / R2 boundaries for backend route tests
- local mock AI server in `test/mock-ai/server.js`
- Docker stack in `scripts/docker-compose.test.yml` for environments with Docker available (`JUSTUS_BACKEND_IN_DOCKER=1` to run the backend tests inside it)
- Flutter unit/widget tests under `Flutter/test/`
- reports/logs from a failed run are preserved under `test/logs/`

---

## 📂 Project Structure

```text
.
├── Backend/          # Node.js Service Layer (AI, Media, Security)
│   ├── config/       # Env loading, AI provider, routes map, Supabase/R2 clients
│   ├── features/     # Domain features (ai, auth, media, notifications, user)
│   ├── core/         # Errors, infra clients, logger, cron jobs (log retention)
│   ├── middleware/   # JWT validation, HMAC/nonce checks, rate limits, sanitization
│   ├── services/     # Request signing/fingerprinting, app version metadata
│   └── all_imports.js # Centralized barrel file
├── Flutter/          # Main Mobile/Web Application (Dart)
│   ├── lib/
│   │   ├── core/      # Infrastructure (Network, Storage, Media, Theme, Localization, Versioning)
│   │   ├── shared/    # Design System & Utils
│   │   ├── features/  # Domain-grouped features (Auth, Drive, Games, etc.)
│   │   └── all_imports.dart # Centralized barrel file
│   └── tool/          # Build scripts & tools
├── supabase/schemas/ # Source of truth for the PostgreSQL schema (tables, RLS, RPCs)
├── docs/             # Architecture, backend, feature and audit documentation
└── JustUs.png        # Project Branding
```

---

## 📚 Documentation
Reference documentation lives in [`docs/`](docs/) and is kept in sync with the code:

- `docs/app/` — architecture, navigation, state management, storage & caching, theming, design system, realtime, notifications, localization
- `docs/backend/` — API architecture, security, infrastructure, error handling
- `docs/features/` — one document per feature (auth, mood, miss-you, game, shared drive, bucket list, partnership, profile & settings)
- `docs/supabase/` — schema and RLS documentation
- `docs/audits/` — secrets, email, media-delete, data-retention, distributed-state and dead-code audits
- `docs/fixing-phase-log.md` — closed bug-fixing phase: every defect found, the decisions taken and the tests added

---

## 🛡️ Security & Performance
- **HMAC Signing**: All requests to the backend service are signed with a unique device secret to prevent tampering.
- **RLS (Row Level Security)**: Supabase policies ensure that data is only accessible by the authorized couple.
- **Cloudflare Integration**: Media is served via R2 for global low-latency and cost-effective storage.
- **Turnstile / Bot protection**: Cloudflare Turnstile runs in **Managed** mode in the app and the resulting `captchaToken` is validated by **Supabase Auth**; the Node backend only performs risk assessment (strikes / IP / device locks) and never verifies Turnstile tokens itself.

---

## 🔔 Auto-Update System
The application includes a built-in update mechanism. The latest release metadata is defined in `app_version.json` (on the backend's data directory, `$JUSTUS_DATA_DIR/versions/app_version.json`) and served via `GET /api/v1/app-version`. The APK is distributed exclusively through GitHub Releases; the `apk_url` field points to the release asset URL. When a newer build is available, the app prompts the user to download it from the GitHub Release.

---

### Developed by
**Federico Cisera**