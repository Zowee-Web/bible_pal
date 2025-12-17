# Bible PAL - Architecture Documentation

**Version:** 1.0
**Last Updated:** 2025-12-04

This document describes the technical architecture and code organization of Bible PAL.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Data Models](#data-models)
4. [Services Layer](#services-layer)
5. [State Management](#state-management)
6. [Screens & Features](#screens--features)
7. [Data Flow](#data-flow)
8. [File Organization](#file-organization)

---

## Project Structure

```
lib/
├── models/              # Data models
│   ├── parable.dart
│   ├── user_preferences.dart
│   ├── favorite.dart
│   ├── history_entry.dart
│   └── daily_bread.dart
│
├── services/            # Business logic and data operations
│   ├── storage_service.dart
│   ├── parable_service.dart
│   ├── audio_service.dart
│   ├── greeting_service.dart
│   ├── mood_service.dart
│   ├── daily_bread_service.dart
│   └── eleven_labs_tts.dart
│
├── providers/           # State management (Provider pattern)
│   ├── app_state_provider.dart
│   └── parable_player_provider.dart
│
├── features/            # Feature-based screen organization
│   ├── onboarding/
│   │   └── tradition_setup_screen.dart
│   ├── main_menu/
│   │   └── main_menu_screen.dart
│   ├── settings/
│   │   └── settings_screen.dart
│   └── whisper/
│       └── whisper_screen.dart
│
├── widgets/             # Reusable UI components
│
├── utils/               # Utility functions and helpers
│
├── app_router.dart      # App routing configuration
└── main.dart            # App entry point
```

---

## Architecture Overview

Bible PAL follows a **layered architecture** pattern:

1. **Presentation Layer** (Screens & Widgets)
   - User interface components
   - Consumes state from providers
   - Triggers actions via providers

2. **State Management Layer** (Providers)
   - Manages application state
   - Coordinates between services
   - Notifies UI of state changes

3. **Business Logic Layer** (Services)
   - Core business logic
   - Data operations
   - External integrations (audio, storage, APIs)

4. **Data Layer** (Models)
   - Data structures
   - JSON serialization/deserialization
   - Immutable data classes

### Key Architectural Principles

- **Separation of Concerns**: Each layer has a distinct responsibility
- **Dependency Injection**: Services are injected into providers
- **Unidirectional Data Flow**: State flows down, events flow up
- **Single Source of Truth**: SPEC.md defines all features and behavior
- **Immutability**: Models use copyWith() for updates

---

## Data Models

All models are located in `lib/models/` and implement:
- `fromJson()` factory constructor for deserialization
- `toJson()` method for serialization
- `copyWith()` method for immutable updates

### Core Models

1. **Parable** (`parable.dart`)
   - Represents a single parable/story
   - Contains metadata: storyId, title, mood, length, faith tradition, etc.
   - Based on SPEC.md Feature #7

2. **UserPreferences** (`user_preferences.dart`)
   - User settings and onboarding state
   - Faith tradition, Bible translation, storytelling mode
   - Based on SPEC.md Features #17, #18, #21-23

3. **Favorite** (`favorite.dart`)
   - User's favorited parables (unlimited)
   - Stores metadata only, not full parable content
   - Based on SPEC.md Feature #9

4. **HistoryEntry** (`history_entry.dart`)
   - Parable listening history (last 100, FIFO)
   - Based on SPEC.md Feature #10

5. **DailyBread** (`daily_bread.dart`)
   - Daily verse display
   - Based on SPEC.md Features #19-20

---

## Services Layer

Services encapsulate business logic and data operations. They are stateless and can be reused across the app.

### Service Descriptions

1. **StorageService** (`storage_service.dart`)
   - Manages local data persistence using SharedPreferences
   - Handles: user preferences, favorites, history, edited titles
   - Based on SPEC.md Feature #25 (encryption/secure storage)

2. **ParableService** (`parable_service.dart`)
   - Manages parable library and selection
   - Implements non-repeat serving rule (SPEC.md Feature #14)
   - Supports local and external storage (SPEC.md Feature #15)
   - Loads parables from manifest.json

3. **AudioService** (`audio_service.dart`)
   - Handles audio playback using just_audio package
   - Manages play/pause/seek/stop operations
   - Based on SPEC.md Feature #16 (ElevenLabs audio playback)

4. **GreetingService** (`greeting_service.dart`)
   - Provides context-aware emotional check-in greetings
   - Time-appropriate greetings with 3-5 variations per time window
   - Based on SPEC.md Feature 2.1 (Context-Aware Emotional Check-In Greeting)

5. **MoodService** (`mood_service.dart`)
   - Detects user mood from text input
   - Generates compassionate replies
   - Based on SPEC.md Features #3-4

6. **DailyBreadService** (`daily_bread_service.dart`)
   - Manages daily verse selection and display
   - Supports thematic alignment with parables
   - Based on SPEC.md Features #20-21

7. **ElevenLabsTts** (`eleven_labs_tts.dart`)
   - Integrates with ElevenLabs API for voice synthesis
   - Used for generating parable audio (server-side)
   - Based on SPEC.md Feature #17

---

## State Management

Bible PAL uses the **Provider** pattern for state management.

### Provider Classes

1. **AppStateProvider** (`app_state_provider.dart`)
   - Main app state container
   - Manages: user preferences, favorites, history, daily bread
   - Coordinates between multiple services
   - Used by: most screens for global state access

2. **ParablePlayerProvider** (`parable_player_provider.dart`)
   - Manages parable playback state
   - Controls: current parable, audio playback, position, duration
   - Used by: parable player screen

### Provider Setup

Providers are initialized in `main.dart` using `MultiProvider`:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AppStateProvider(...)),
    ChangeNotifierProvider(create: (_) => ParablePlayerProvider(...)),
  ],
  child: MyApp(),
)
```

---

## Screens & Features

Screens are organized by feature in `lib/features/`.

### Current Screens

1. **TraditionSetupScreen** (`features/onboarding/`)
   - Onboarding: faith tradition selection
   - Based on SPEC.md Feature #17

2. **MainMenuScreen** (`features/main_menu/`)
   - Home screen with Daily Bread verse
   - Entry point to PAL's Parables
   - Based on SPEC.md Features #1, #19

3. **SettingsScreen** (`features/settings/`)
   - User preferences management
   - Based on SPEC.md Features #21-24

4. **WhisperScreen** (`features/whisper/`)
   - Existing prototype for mood detection + story playback
   - Will be refactored to align with SPEC.md

### Screens to Build

Based on SPEC.md, the following screens need to be implemented:

1. **Bible Translation Setup Screen** (Onboarding Feature #18)
2. **PAL's Parables Flow Screen** (Features #2-4: mood detection, compassionate reply, parable selection)
3. **Parable Player Screen** (Features #11, #16: playback with scripture panel)
4. **Favorites Screen** (Feature #9)
5. **History Screen** (Feature #10)
6. **Length Selection Screen** (Feature #5: 5, 10, 15, 20 minute options)

---

## Data Flow

### Typical User Flow Example: Listening to a Parable

1. **User Input**
   - User taps "PAL's Parables" button on main screen
   - Navigates to mood detection screen

2. **Mood Detection**
   - User types/speaks how their day is going
   - `MoodService.detectMood()` analyzes input
   - Returns MoodResult (mood, emotional tags, confidence)

3. **Compassionate Reply**
   - `MoodService.generateCompassionateReply()` creates caring response
   - UI displays reply to user

4. **Parable Selection**
   - User selects desired length (5, 10, 15, or 20 minutes)
   - `AppStateProvider.selectParable()` calls `ParableService`
   - `ParableService` filters by mood, length, tradition, mode
   - Implements non-repeat rule using history
   - Returns selected Parable

5. **Audio Playback**
   - `ParablePlayerProvider.loadParable()` loads audio file
   - User presses play
   - `AudioService` handles playback
   - Scripture panel displays verse references

6. **Post-Playback**
   - `AppStateProvider.addToHistory()` records in history
   - User can favorite the parable
   - User can share with a friend (Feature #13)

---

## File Organization

### Naming Conventions

- **Models**: Singular noun (e.g., `parable.dart`, `favorite.dart`)
- **Services**: `<noun>_service.dart` (e.g., `storage_service.dart`)
- **Providers**: `<noun>_provider.dart` (e.g., `app_state_provider.dart`)
- **Screens**: `<feature>_screen.dart` (e.g., `main_menu_screen.dart`)
- **Widgets**: `<description>_widget.dart` (e.g., `scripture_panel_widget.dart`)

### Import Organization

Imports should be organized in this order:
1. Dart/Flutter SDK imports
2. Package imports (alphabetical)
3. Local imports (relative paths, alphabetical)

Example:
```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/parable.dart';
import '../services/storage_service.dart';
```

---

## Next Steps

### Immediate Tasks

1. **Refactor Existing Screens**
   - Update screens to use new providers and services
   - Align with SPEC.md requirements

2. **Build Missing Screens**
   - Parable flow screens (mood detection, selection, playback)
   - Favorites and History screens
   - Length selection screen

3. **Implement Parable Library System**
   - Create manifest.json structure
   - Implement server-side batch generation script (Feature #6)
   - Set up T9 external storage integration

4. **Audio Integration**
   - Integrate ElevenLabs API for audio generation
   - Test multi-voice playback with SSML

5. **Testing**
   - Unit tests for services
   - Widget tests for screens
   - Integration tests for user flows

---

## Development Guidelines

1. **Always refer to SPEC.md** before implementing features
2. **Update SPEC.md** if requirements intentionally change
3. **Keep services stateless** - state belongs in providers
4. **Use dependency injection** - pass services to providers
5. **Write tests** for business logic in services
6. **Document complex logic** with comments
7. **Follow Flutter/Dart best practices** (linting enabled)

---

## Dependencies

Key packages used in this project:

- **provider**: State management
- **just_audio**: Audio playback
- **speech_to_text**: Voice input for mood detection
- **flutter_tts**: Text-to-speech (for prototype)
- **shared_preferences**: Local data persistence
- **path_provider**: File system access
- **http**: API calls (ElevenLabs, future features)
- **sqflite**: SQLite database (for future enhancements)

See `pubspec.yaml` for complete dependency list.
