# Bible PAL - Error Type Taxonomy

This document defines the canonical list of `errorType` values used with `logError()`.
All error types must follow this taxonomy to ensure consistent, queryable error logs.

## Naming Convention

- **Format:** `snake_case`
- **Pattern:** `{category}_{specific_error}`
- **Examples:** `audio_load_failed`, `network_timeout`, `storage_write_failed`

## Error Categories

### Audio Errors (`audio_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `audio_load_failed` | Failed to load audio file | Audio file not found, corrupt, or unreadable |
| `audio_play_failed` | Failed to start playback | Player initialization error |
| `audio_decode_error` | Audio decoding failed | Codec issue, corrupt audio data |
| `audio_stream_error` | Streaming audio interrupted | Network issues during streaming |
| `audio_position_error` | Failed to seek to position | Invalid position, player state error |

### Network Errors (`network_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `network_timeout` | Request timed out | Connection or read timeout |
| `network_connection_failed` | Failed to establish connection | No internet, DNS failure |
| `network_ssl_error` | SSL/TLS handshake failed | Certificate issues |
| `network_response_error` | Unexpected response | 4xx/5xx status codes |

### Storage Errors (`storage_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `storage_read_failed` | Failed to read from storage | SharedPreferences, SQLite read error |
| `storage_write_failed` | Failed to write to storage | Disk full, permissions |
| `storage_delete_failed` | Failed to delete data | File locked, permissions |
| `storage_corrupt_data` | Data integrity issue | JSON parse error, invalid schema |

### Story/Content Errors (`story_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `story_load_failed` | Failed to load story | Manifest parse error, missing file |
| `story_not_found` | Requested story doesn't exist | Invalid story_id |
| `story_invalid_metadata` | Story metadata malformed | Missing required fields |
| `story_audio_missing` | Story audio file not found | Audio asset not bundled |

### Verse/Scripture Errors (`verse_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `verse_lookup_failed` | Failed to retrieve verse | Database query error |
| `verse_not_found` | Verse reference invalid | Bad book/chapter/verse |
| `verse_translation_unavailable` | Translation not available | Requested non-allowed translation |

### Text-to-Speech Errors (`tts_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `tts_generation_failed` | TTS API call failed | ElevenLabs API error |
| `tts_voice_unavailable` | Requested voice not available | Invalid voice ID |
| `tts_quota_exceeded` | API quota exhausted | Rate limit hit |
| `tts_invalid_input` | Invalid text for TTS | Empty or too-long text |

### Eligibility/Filtering Errors (`eligibility_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `eligibility_no_stories` | No eligible stories found | All stories filtered out |
| `eligibility_pool_exhausted` | All stories already played | LRP exhausted |
| `eligibility_filter_error` | Filter logic error | Unexpected filter state |

### Permission Errors (`permission_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `permission_microphone_denied` | Microphone access denied | Speech recognition blocked |
| `permission_storage_denied` | Storage access denied | Can't read/write files |
| `permission_notification_denied` | Notification permission denied | Can't show notifications |

### State/Logic Errors (`state_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `state_invalid_transition` | Invalid state transition | State machine violation |
| `state_unexpected_null` | Unexpected null value | Required value missing |
| `state_assertion_failed` | Assertion/invariant violated | Logic error detected |

### Validation Errors (`validation_*`)

| Error Type | Description | When to Use |
|------------|-------------|-------------|
| `validation_kid_safe_failed` | Kid-safe validation failed | Content not safe for kids |
| `validation_translation_blocked` | Banned translation detected | Non-allowed translation ID |
| `validation_input_invalid` | User input validation failed | (Use sparingly - no PII in logs) |

## Usage Guidelines

1. **Always use existing types** when applicable
2. **Create new types** following the `{category}_{specific}` pattern
3. **Never include PII** in error messages or additional data
4. **Include context** via safe fields: `story_id`, `location`, numeric codes
5. **Use appropriate log level**: most errors are `LogLevel.error`

## Example Usage

```dart
// Good - using standard taxonomy
logError(
  'audio_load_failed',
  'ParablePlayerNotifier.loadParable',
  storyId: 'parable_113',
  errorMessage: 'File not found', // Safe - no PII
);

// Good - new specific type following convention
logError(
  'audio_buffer_underrun',
  'AudioService.play',
  additionalData: {'position_ms': 45000},
);

// BAD - don't include user data
logError(
  'validation_failed',
  'MoodService',
  errorMessage: userInput, // NEVER DO THIS
);
```

## Adding New Error Types

When adding a new error type:

1. Check if an existing type covers your case
2. Follow `{category}_{specific_error}` naming
3. Add to this document with description and use case
4. Keep error messages generic (no PII)

## Test Enforcement

The test suite validates that logged error types follow the naming convention.
See `test/core/error_taxonomy_test.dart` for enforcement tests.
