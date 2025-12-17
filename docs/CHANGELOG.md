# Bible PAL - Changelog

This document tracks all intentional changes to the Bible PAL specification and codebase.

---

## [1.1] - 2025-12-08

### Added

**Feature 2.1: Context-Aware Emotional Check-In Greeting**

- Added dynamic, time-appropriate greeting system for emotional check-in
- PAL now greets users with varied, natural-sounding questions based on time of day
- Four time windows implemented:
  - 🌅 Morning (5 AM - 11:59 AM): 4 greeting variations
  - 🌤️ Afternoon (12 PM - 4:59 PM): 4 greeting variations
  - 🌇 Evening (5 PM - 8:59 PM): 4 greeting variations
  - 🌙 Late Night (9 PM - 4:59 AM): 4 greeting variations
- System randomly selects one greeting per session to avoid repetition
- Greeting appears before mood detection on PAL's Parables screen

**Implementation:**
- Created `lib/services/greeting_service.dart`
  - `getGreeting()` - Returns time-appropriate greeting
  - `getTimeWindowName()` - Returns current time window name
  - `getTimeWindowEmoji()` - Returns emoji for current time window
  - Deterministic time window logic
  - Random selection from greeting pool

### Changed

- **SPEC.md**
  - Version updated to 1.1
  - Added Feature 2.1 with complete greeting specifications
  - Renumbered subsequent features (2→3, 3→4, etc.)
  - Updated all feature cross-references

- **ARCHITECTURE.md**
  - Added GreetingService to service layer documentation
  - Updated project structure to include greeting_service.dart
  - Updated service numbering and SPEC.md references

### Technical Notes

- Greeting selection does not affect mood classification (UX only)
- Service is stateless and can be easily tested
- Time windows are clear and non-overlapping
- All greeting text is defined as constants for easy modification

---

## [1.0] - 2025-12-04

### Initial Release

- Created complete SPEC.md with 26 features
- Scaffolded Flutter project architecture
- Implemented core models, services, and providers
- Created comprehensive documentation (SPEC.md, ARCHITECTURE.md, SCAFFOLDING_SUMMARY.md)
- Set up dependency structure in pubspec.yaml

**Core Features Documented:**
1. PAL's Parables System (Features 1-17)
2. Onboarding (Features 18-19)
3. Daily Bread (Features 20-21)
4. Settings (Features 22-25)
5. Security & Technical Architecture (Features 26-27)

**Scaffolded Components:**
- 5 data models
- 6 service classes
- 2 state management providers
- Project structure and documentation
