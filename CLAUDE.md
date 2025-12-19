# Claude Code Instructions for Bible PAL

This document provides essential context and instructions for AI assistants working on the Bible PAL project.

---

## 🎯 Project Overview

**Bible PAL** is a Flutter application for faith-based storytelling and Bible engagement. It generates personalized audio parables based on user mood, faith tradition, and preferences using AI-generated content and text-to-speech narration.

**Key Technology Stack:**
- Flutter 3.24.5+ / Dart 3.6.0+
- State Management: Riverpod
- Audio Playback: just_audio
- Text-to-Speech: ElevenLabs v3 API
- Local Storage: SQLite + SharedPreferences
- Speech Recognition: speech_to_text + flutter_tts

---

## ⚖️ Document Hierarchy & Conflict Resolution

**If CLAUDE.md conflicts with [docs/INVARIANTS.md](docs/INVARIANTS.md) or [docs/SPEC.md](docs/SPEC.md), the official docs win.**

This document (CLAUDE.md) is a convenience guide for AI assistants. The authoritative sources are:
1. **[docs/INVARIANTS.md](docs/INVARIANTS.md)** - Non-negotiable rules (highest authority)
2. **[docs/SPEC.md](docs/SPEC.md)** - Product specification
3. **[docs/BIBLE_TRANSLATION_COMPLIANCE.md](docs/BIBLE_TRANSLATION_COMPLIANCE.md)** - Compliance details
4. **CLAUDE.md** - This file (summary/quick reference only)

**If you're unsure about any requirement or notice a conflict:**
1. Check the official docs ([docs/INVARIANTS.md](docs/INVARIANTS.md) and [docs/SPEC.md](docs/SPEC.md)) first
2. Trust the official docs over this file
3. Ask the project owner for clarification
4. Update this file after resolution to maintain consistency

---

## 🔒 CRITICAL: Bible Translation Compliance (NON-NEGOTIABLE)

**This is the most important rule in the entire project. It must NEVER be violated.**

### The Rule

Bible PAL must **ONLY** use public-domain or open-source Bible translations. Using copyrighted Bible translations violates copyright law and exposes the project to legal liability.

### Allowed Translations (EXHAUSTIVE LIST)

**ONLY these 5 translations are permitted:**
- **WEB** (World English Bible) - Default
- **KJV** (King James Version)
- **ASV** (American Standard Version)
- **YLT** (Young's Literal Translation)
- **DRA** (Douay-Rheims American Edition)

### Banned Translations (MUST NEVER APPEAR)

The following translations are **explicitly banned**:
- NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT
- **And ALL others not explicitly in the allowed list**

### Enforcement

This invariant is enforced through:
1. **Code-level allowlist**: [lib/core/bible_translation_registry.dart](lib/core/bible_translation_registry.dart)
2. **Runtime guards**: Automatic validation that resets to WEB if violation detected
3. **Build-failing tests**: Tests will FAIL if banned translations detected anywhere in codebase
4. **CI enforcement**: GitHub Actions blocks PRs with violations

### When Working on Translation-Related Code

- **ALWAYS** validate translation IDs through `BibleTranslationRegistry`
- **NEVER** bypass registry or runtime guards
- **ALWAYS** run compliance tests before committing:
  ```bash
  flutter test test/core/bible_translation_compliance_test.dart test/core/repo_wide_compliance_scan_test.dart
  ```
- **NEVER** weaken or remove compliance tests
- If you see a violation, FIX it immediately—don't ignore it

### Resources

- Full documentation: [docs/BIBLE_TRANSLATION_COMPLIANCE.md](docs/BIBLE_TRANSLATION_COMPLIANCE.md)
- Invariants document: [docs/INVARIANTS.md](docs/INVARIANTS.md)
- Registry code: [lib/core/bible_translation_registry.dart](lib/core/bible_translation_registry.dart)

---

## 📋 Development Guidelines

### Source of Truth Documents

**Always reference these documents before making changes:**

1. **[docs/SPEC.md](docs/SPEC.md)** - Complete product specification
   - All features and behavior must align with SPEC.md
   - Any behavior changes require SPEC.md updates FIRST
   - Do not add features unless explicitly in the spec

2. **[docs/INVARIANTS.md](docs/INVARIANTS.md)** - Non-negotiable project rules
   - Hard constraints that must never be violated
   - Currently contains Bible translation compliance rules
   - Future invariants will be added here

3. **[docs/BIBLE_TRANSLATION_COMPLIANCE.md](docs/BIBLE_TRANSLATION_COMPLIANCE.md)** - Detailed compliance guide
   - Complete reference for translation handling
   - Testing procedures
   - Violation response protocols

### Project Architecture

**Key Directories:**
- `lib/` - Main Flutter application code
  - `core/` - Core utilities and registries (including translation registry)
  - `features/` - Feature modules (onboarding, parables, settings, etc.)
  - `models/` - Data models (Parable, UserPreferences, etc.)
  - `providers/` - Riverpod state management
  - `services/` - Business logic services (audio, mood detection, TTS, etc.)
  - `widgets/` - Reusable UI components
- `test/` - Unit and integration tests
- `assets/` - Static assets (stories, app icons)
- `server/` - Node.js scripts for batch parable generation
- `docs/` - Project documentation

**Key Files:**
- [lib/core/bible_translation_registry.dart](lib/core/bible_translation_registry.dart) - Translation allowlist
- [lib/models/user_preferences.dart](lib/models/user_preferences.dart) - User settings model
- [lib/services/parable_service.dart](lib/services/parable_service.dart) - Parable selection/generation
- [lib/services/audio_service.dart](lib/services/audio_service.dart) - Audio playback
- [lib/services/eleven_labs_tts.dart](lib/services/eleven_labs_tts.dart) - ElevenLabs TTS integration
- [lib/services/mood_service.dart](lib/services/mood_service.dart) - Mood detection

### Testing Requirements

**Before committing any code:**

```bash
# Run all tests (MUST PASS)
flutter test

# Run compliance tests specifically
flutter test test/core/bible_translation_compliance_test.dart test/core/repo_wide_compliance_scan_test.dart

# Static analysis (MUST PASS)
flutter analyze
```

**CI/CD:**
- GitHub Actions runs automatically on all PRs
- All tests must pass before merging
- Workflow file: [.github/workflows/flutter.yml](.github/workflows/flutter.yml)

### Code Style & Philosophy

1. **No Over-Engineering**
   - Only make changes directly requested or clearly necessary
   - Keep solutions simple and focused
   - Don't add features, refactorings, or "improvements" beyond what was asked
   - Don't add comments/docs to code you didn't change

2. **SPEC.md is Law**
   - Don't deviate from specified behavior
   - Don't add features not in the spec
   - Update SPEC.md FIRST if intentional behavior change needed

3. **Security First**
   - Avoid OWASP Top 10 vulnerabilities (XSS, SQL injection, etc.)
   - Encrypt user data properly
   - Never expose API keys in code

4. **Backwards Compatibility**
   - Remove unused code completely—don't leave stubs
   - No renaming unused `_vars` or `// removed` comments
   - Delete cleanly

---

## 🚀 Common Development Tasks

### Running the App

```bash
# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Run tests
flutter test

# Static analysis
flutter analyze
```

### Adding a New Feature

1. Check if feature is in [docs/SPEC.md](docs/SPEC.md)
2. If not, discuss with project owner first
3. Update SPEC.md if adding new behavior
4. Implement the feature
5. Add tests
6. Run `flutter test` and `flutter analyze`
7. Commit with descriptive message

### Modifying Bible Translation Handling

1. **READ** [docs/INVARIANTS.md](docs/INVARIANTS.md) first
2. **NEVER** bypass [lib/core/bible_translation_registry.dart](lib/core/bible_translation_registry.dart)
3. **ALWAYS** validate translation IDs
4. **RUN** compliance tests before committing
5. If adding new public-domain translation:
   - Verify license thoroughly
   - Update registry
   - Update docs
   - Run tests

### Debugging Compliance Violations

If you see a compliance violation error:

1. **DO NOT** ignore it
2. **DO NOT** add banned translation to allowlist
3. Find where banned translation ID appears in code
4. Replace with allowed translation (usually WEB)
5. Run compliance tests to verify fix
6. Check runtime guards are working properly

---

## 📱 Platform-Specific Notes

### iOS
- Requires Xcode for building
- App icons configured in `ios/Runner/Assets.xcassets/`
- Permissions handled in `Info.plist`
- CocoaPods used for dependencies

### Android
- Android Studio recommended
- App icons in `android/app/src/main/res/mipmap-*/`
- Adaptive icons configured via `flutter_launcher_icons`
- Permissions in `AndroidManifest.xml`

---

## 🔐 Environment Setup

**Required environment variables:**
- Create `.env` file in project root
- Add ElevenLabs API key: `ELEVEN_LABS_API_KEY=your_key_here`
- Never commit `.env` file to git

---

## 📝 Git Workflow

### Commit Message Style
- Use clear, descriptive commit messages
- Reference related issues if applicable
- Examples from repo:
  - `chore: stop tracking generated audio (mp3) and temp_segments`
  - `chore: initial Bible PAL project import`
  - `Spec: invariants - improve compliance scan reporting by directory`

### Branch Strategy
- Main branch: `master`
- All tests must pass on `master`
- CI blocks merges with failing tests

---

## 🆘 Getting Help

### Documentation Priority
1. [docs/SPEC.md](docs/SPEC.md) - Feature behavior
2. [docs/INVARIANTS.md](docs/INVARIANTS.md) - Hard rules
3. [docs/BIBLE_TRANSLATION_COMPLIANCE.md](docs/BIBLE_TRANSLATION_COMPLIANCE.md) - Translation details
4. [README.md](README.md) - Setup and basic usage
5. Code comments - When present, for specific implementation details

### When Something is Unclear
1. Check documentation first
2. Search codebase for similar patterns
3. Ask project owner for clarification
4. Update documentation after resolution

---

## ⚠️ Common Pitfalls to Avoid

1. **Using banned Bible translations** - The #1 rule violation
2. **Adding features not in SPEC.md** - Leads to scope creep
3. **Not running tests before committing** - Breaks CI
4. **Over-engineering solutions** - Keep it simple
5. **Modifying SPEC.md without approval** - Spec changes need owner approval
6. **Committing sensitive data** - Never commit API keys or .env files
7. **Weakening compliance tests** - Tests exist to protect project legally

---

## 📊 Project Status

**Current Version:** 1.0.0+1

**Development Stage:** Active development

**Key Features Implemented:**
- ✅ Onboarding (faith tradition + Bible translation selection)
- ✅ PAL's Parables player with mood detection
- ✅ Context-aware emotional check-in greetings
- ✅ ElevenLabs TTS integration
- ✅ Favorites and History systems
- ✅ Settings screen
- ✅ Daily Bread verse display
- ✅ Bible translation compliance enforcement

**Known Active Development Areas:**
- Parable generation pipeline refinement
- Mood detection accuracy improvements
- Audio playback optimizations

---

## 🎯 Quick Reference: Most Important Rules

1. **ONLY use allowed Bible translations** (WEB, KJV, ASV, YLT, DRA)
2. **Follow SPEC.md exactly** - Don't add unspecified features
3. **Run tests before committing** - `flutter test` must pass
4. **Update docs before code** - Behavior changes need SPEC.md updates first
5. **Keep it simple** - No over-engineering

---

**Last Updated:** 2025-12-18
**Maintained By:** Bible PAL Development Team
