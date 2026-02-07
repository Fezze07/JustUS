# JustUs Flutter App

A cross-platform Flutter app for couples, rebuilt from the Android native app.

## Features

- 💖 **Miss You** - Send and track "miss you" messages
- 🌈 **Mood** - Share your current mood with emojis
- 📝 **Bucket List** - Shared goals and dreams
- 🎮 **Couple Game** - Daily quiz questions
- 📂 **Drive** - Shared photo/video storage
- 👤 **Profile** - User and partner profile management

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Dart SDK 3.0+

### Installation

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Run on specific platform:
   ```bash
   # Android
   flutter run -d android

   # Windows
   flutter run -d windows

   # Linux
   flutter run -d linux

   # Web
   flutter run -d chrome
   ```

### Build

```bash
# Android APK
flutter build apk

# Windows
flutter build windows

# Linux
flutter build linux

# Web
flutter build web
```

## Project Structure

```
lib/
├── main.dart              # App entry point
├── models/
│   └── models.dart        # Data models
├── services/
│   ├── api_service.dart   # HTTP client
│   ├── result_wrapper.dart # Error handling
│   └── storage_service.dart # Local storage
├── repositories/
│   └── api_repository.dart # API abstraction
├── state/
│   ├── auth_state.dart
│   ├── login_state.dart
│   ├── register_state.dart
│   ├── homepage_state.dart
│   ├── mood_state.dart
│   ├── bucket_state.dart
│   ├── game_state.dart
│   ├── drive_state.dart
│   ├── partner_state.dart
│   └── profile_state.dart
├── screens/
│   ├── splash_screen.dart
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── homepage_screen.dart
│   ├── partner_screen.dart
│   ├── mood_screen.dart
│   ├── bucket_list_screen.dart
│   ├── game_screen.dart
│   ├── drive_screen.dart
│   ├── drive_item_screen.dart
│   ├── profile_screen.dart
│   ├── change_password_screen.dart
│   └── favorites_screen.dart
└── widgets/
    └── (reusable widgets)
```

## Configuration

Edit `lib/services/api_service.dart` to change the backend URL:

```dart
static const String debugBaseUrl = 'http://192.168.1.100:5001';
static const String releaseBaseUrl = 'https://justus.serverfede.eu';
static const bool isDebug = true; // Set to false for production
```

## Architecture

- **State Management**: Provider with ChangeNotifier
- **Networking**: http package with custom API service
- **Local Storage**: SharedPreferences
- **UI**: Material Design 3

## Platforms

- ✅ Android
- ✅ Windows
- ✅ Linux
- ✅ Web
- ❌ iOS (not targeted)
- ❌ macOS (not targeted)
