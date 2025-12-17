# Bible PAL - Technical Specification

**Version:** 1.1
**Last Updated:** 2025-12-08

This document is the single source of truth for Bible PAL's features and behavior. All code must follow this specification. Changes to app behavior require explicit updates to this document.

---

## Table of Contents

1. [PAL's Parables System](#pals-parables-system)
2. [Onboarding](#onboarding)
3. [Daily Bread](#daily-bread)
4. [Settings](#settings)
5. [Security & Technical Architecture](#security--technical-architecture)

---

## PAL's Parables System

### Core User Flow

**1. PAL's Parables Button**
- Main button on the home screen to start the parable experience

**2. Context-Aware Emotional Check-In Greeting (Feature 2.1)**
- After tapping PAL's Parables, PAL greets the user with a time-appropriate emotional check-in question
- The greeting adjusts based on current time of day
- Randomly selects from 3-5 phrasing variations for naturalness
- Avoids sounding robotic or repetitive
- This greeting leads directly into mood detection

**Time Windows and Greeting Options:**

🌅 **Morning (5 AM – 11:59 AM)**
- "Good morning! How's your day starting out?"
- "Morning! How are you feeling so far today?"
- "Hi there — how's your morning going?"
- "Good morning! What's on your heart today?"

🌤️ **Afternoon (12 PM – 4:59 PM)**
- "How's your afternoon going?"
- "I'm glad you're here — how are you doing today?"
- "How's your day been so far?"
- "Checking in — how are you feeling this afternoon?"

🌇 **Evening (5 PM – 8:59 PM)**
- "How's your evening going?"
- "Good to see you — how are you feeling tonight?"
- "How has your day been winding down?"
- "How are you doing this evening?"

🌙 **Late Night (9 PM – 4:59 AM)**
- "How's your night going?"
- "It's a quiet hour — how are you feeling?"
- "How are you doing tonight?"
- "Is everything going okay this late? How are you feeling?"

**Implementation Notes:**
- App randomly selects one greeting from the appropriate time window
- Displayed on PAL's Parables mood check-in screen
- Choice of greeting does not affect mood classification, only UX
- This is the first step before mood detection

**3. Mood Detection Flow**
- User can type or speak their answer to the greeting question
- Text is analyzed to detect mood (positive / neutral / negative plus finer emotional tags)

**4. Compassionate Reply System**
- After mood detection, app shows a short, caring text reply that matches the mood
- This reply appears before the parable starts

**5. Parable Generation / Selection Engine**
- Chooses or generates a parable based on:
  - User's detected mood
  - Faith tradition
  - Storytelling mode (creative vs traditional)
  - Selected length
- If pre-generated stories exist that match criteria, selects one
- Otherwise generates a new one on demand

### Story Length & Generation

**6. Fixed Length Options**
- Four fixed durations: **5, 10, 15, 20 minutes**
- No slider interface
- Length is stored as metadata with each story

**7. Nightly Batch Generation**
- Automated script runs at 2:00 AM daily
- Generates 20 new parables per night
- Moods and lengths are mixed across generation
- Stories stored as text files plus metadata

### Metadata & Organization

**8. Parable Metadata System**

Each parable includes:
- `storyId` (unique identifier)
- `title` (AI-generated, user-editable)
- `mood` / emotional tags
- `length` (5, 10, 15, or 20 minutes)
- `faithTradition`
- `storytellingMode` (creative or traditional)
- `scriptureSources` (array of verse references)

**9. AI-Generated Story Titles (Editable)**
- Each parable has an AI-generated title by default
- User can rename any title
- Edited title replaces AI title for that user
- Original AI title preserved for other users

### User Library Management

**10. Favorites System**
- Unlimited favorites capacity
- Saved locally on device (SQLite)
- Metadata stored per favorite:
  - `storyId`
  - `title` (edited or AI-generated)
  - `mood`
  - `length`
  - `faithTradition`
  - `scriptureSources`
  - `dateSaved`

**11. History System**
- Automatically records listened parables
- Stores last **100 entries only**
- When 101st entry added, oldest entry is removed (FIFO)
- Metadata stored per entry:
  - `storyId`
  - `title`
  - `mood`
  - `length`
  - `faithTradition`
  - `scriptureSources`
  - `timestamp`

**12. Scripture Sources Panel**
- Displays during parable playback
- Lists all Bible verses used in the story
- Uses user's selected Bible translation
- Source list saved per `storyId`
- Reused in Favorites and History views

### Storytelling Modes

**13. Creative / Traditional Mode Toggle**

Two distinct storytelling approaches:
- **Creative Mode:** Modern, imaginative style with contemporary applications
- **Traditional Mode:** Biblical narrative tone, closer to scripture style

Affects:
- Story generation prompts
- Pre-generated story selection pool

### Sharing & Replay Logic

**14. Share With a PAL**
- Available after parable completion
- Shares specific parable by `storyId`
- Recipient can open shared story in their own app

**15. Non-Repeat Story Serving Rule**
- User should not receive same parable twice until all eligible parables exhausted
- Eligibility based on current filters:
  - Storytelling mode
  - Length preference
  - Faith tradition
  - Other active criteria
- After pool exhausted, stories repeat using "least recently played" ordering

### Storage & Playback

**16. Offline Local + External Storage**
- Parables stored locally on device
- Support for external drive storage (e.g., T9) for bulk libraries
- App fully functional without internet connection

**17. ElevenLabs v3 Multi-Voice Playback**
- Parables converted to audio using ElevenLabs v3
- Multiple voices per story
- SSML tags for enhanced narration
- Pre-generated audio files (not live streaming TTS)
- High-quality playback from stored audio files

---

## Onboarding

**18. Faith Tradition Selector**
- Presented on first launch
- Options include:
  - Catholic
  - Protestant
  - Orthodox
  - Messianic
  - Non-Denominational
  - Other
- Influences story details and scripture interpretation
- User can change later in Settings

**19. Bible Translation Selector**
- Presented on first launch
- User selects preferred Bible translation(s)
- Affects:
  - Scripture references throughout app
  - Scripture Sources panel
  - Daily Bread verse
- User can change later in Settings

---

## Daily Bread

**20. Daily Bread Verse Display**
- Static verse displayed at top of main menu
- Uses user's selected Bible translation
- Fixed position and style (no floating animation)

**21. Thematic Alignment**
- When possible, Daily Bread verse should match or complement the theme of the day's parable

---

## Settings

**22. Creative/Traditional Mode Toggle**
- Global setting for default storytelling mode
- Affects parable selection and generation

**23. Change Faith Tradition**
- Allows user to update faith tradition after onboarding

**24. Change Bible Translation**
- Allows user to update preferred Bible translation(s) after onboarding

**25. Content Filtering / Moderation Controls**
- Filter inappropriate or offensive content in generated parables
- Applied before content reaches user

---

## Security & Technical Architecture

**26. User Data Encryption**
- Secure storage for:
  - Mood input text
  - User preferences
  - Favorites metadata
  - History metadata

**27. Local Parable Library + Optional Cloud Sync**
- Parable metadata can sync from Mac (generation source) to user devices
- Personal user data remains local only (not synced to cloud)
- Only story libraries and story-related metadata sync
- User preferences, favorites, and history stay on-device

---

## Development Principles

1. **SPEC.md is the source of truth** - All code must align with this document
2. **No feature creep** - Do not add features unless explicitly requested
3. **Update SPEC.md first** - Any intentional behavior changes must update this document before code changes
4. **Maintain simplicity** - Follow the specified features without over-engineering
