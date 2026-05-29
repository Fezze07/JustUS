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
- **Daily Challenges**: Every 24 hours, a new question is generated using the integrated **Llama 3.2 AI engine**.
- **Interactive Voting**: Partners vote between two options (each other) on fun and meaningful scenarios.
- **Shared History**: Build a library of memories by revisiting past questions and seeing how your answers align over time.

### 📂 Shared Drive (R2 Cloud Gallery)
A high-performance, private cloud space for your shared memories.
- **Hybrid Storage**: Combines **Supabase** metadata for fast indexing with **Cloudflare R2** for cost-effective, high-speed media delivery.
- **Interactive Gallery**: React to photos and videos with emojis, or mark your favorite moments to find them easily later.
- **Mobile Optimized**: Automatically compresses media before upload and uses an incremental sync engine to keep the gallery up-to-date with minimal data usage.

### 📝 Collaborative Bucket List
Plan your future together with a shared roadmap of dreams and tasks.
- **Categorized Goals**: Organize your ambitions by category (e.g., Travel, Food, Experiences).
- **Real-time Collaboration**: Add, edit, or complete items and see changes instantly on both devices.

### 👤 Secure Partner Linking
Your privacy is our priority.
- **Unique Identification**: Link with your partner using a secure, one-time invitation system.
- **Device Fingerprinting**: Advanced security measures ensure that only authorized devices can access your shared space.

---

## 🛠️ Tech Stack

### **Frontend** (Cross-Platform)
- **Framework**: [Flutter](https://flutter.dev/) (Dart 3.x)
- **State Management**: [Provider](https://pub.dev/packages/provider) for reactive UI.
- **Security**: HMAC Request Signing and SHA-256 fingerprinting for API integrity.
- **Media**: Advanced caching with `CachedNetworkImage` and custom `MediaCacheManager`.

### **Backend Infrastructure** (Hybrid)
- **Database & Auth**: [Supabase](https://supabase.com/) (PostgreSQL + GoTrue) for real-time data and secure authentication.
- **Service Layer**: [Node.js](https://nodejs.org/) (Express) acting as a secure gateway for AI and Media services.
- **Cloud Storage**: [Cloudflare R2](https://www.cloudflare.com/developer-platform/r2/) for private media hosting.
- **AI Engine**: [Ollama](https://ollama.com/) (Running Llama 3.2:3b locally or on-server).
- **Notifications**: [Firebase Cloud Messaging (FCM)](https://firebase.google.com/docs/cloud-messaging).

---

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.0.0+)
- [Node.js](https://nodejs.org/) (v18+)
- [Ollama](https://ollama.com/) (for AI features)

### 2. Backend Setup
1. Navigate to the `Backend` directory:
   ```bash
   cd Backend
   npm install
   ```
2. Create a `.env` file in the root directory (refer to `.env.example`):

3. Start the server:
   ```bash
   npm start
   ```

### 3. Flutter App Setup
1. Navigate to `Flutter`:
   ```bash
   cd Flutter
   ```
2. Create a `.env` file in the root directory (refer to `.env.example`).
3. Run the app:
   ```bash
   flutter pub get
   flutter run
   ```

### 4. Testing
The repository includes an isolated test setup for both backend and Flutter code.

- Backend API suite:
  ```bash
  cd Backend
  npm test
  ```
- Full local runner:
  ```bash
  ./test-all.sh
  ```

Test environment highlights:
- `ENV=test` support via root `.env.test`
- mocked Supabase / R2 boundaries for backend route tests
- local mock AI server in `testing/mock-ai/server.js`
- Docker stack in `docker-compose.test.yml` for environments with Docker available
- Flutter unit/widget tests under `Flutter/test/`

---

## 📂 Project Structure

```text
.
├── Backend/          # Node.js Service Layer (AI, Media, Security)
├── Flutter/          # Main Mobile/Web Application (Dart)
│   ├── lib/
│   │   ├── core/      # Infrastructure (Network, Storage, Versioning)
│   │   ├── shared/    # Design System & Utils
│   │   ├── features/  # Domain-grouped features (Auth, Drive, Games, etc.)
│   │   └── all_imports.dart # Centralized barrel file
│   └── tool/          # Build scripts & tools
└── JustUs.png        # Project Branding
```

---

## 🛡️ Security & Performance
- **HMAC Signing**: All requests to the backend service are signed with a unique device secret to prevent tampering.
- **RLS (Row Level Security)**: Supabase policies ensure that data is only accessible by the authorized couple.
- **Cloudflare Integration**: Media is served via R2 for global low-latency and cost-effective storage.
- **Turnstile**: Protected authentication flows using Cloudflare Turnstile to prevent bot abuse.

---

## 🔔 Auto-Update System
The application includes a built-in update mechanism. New APKs placed in `Backend/versions/apk/` with an updated `app_version.json` will trigger a notification in the app, allowing users to download the latest version directly.

---

### Developed by
**Federico Cisera**