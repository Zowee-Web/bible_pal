# Bible PAL

A Flutter application for faith-based storytelling and Bible engagement.

## Getting Started

### Prerequisites

- Flutter 3.24.5 or later
- Dart SDK
- Node.js (for server scripts)

### Installation

```bash
# Get Flutter dependencies
flutter pub get

# Run the app
flutter run

# Run tests
flutter test

# Run static analysis
flutter analyze
```

## Development

### Running Tests

```bash
# Run CRITICAL invariant tests first (fast-fail)
./scripts/run_critical_tests.sh

# Run all tests
flutter test

# Run compliance tests only
flutter test test/core/bible_translation_compliance_test.dart test/core/repo_wide_compliance_scan_test.dart
```

**Important**: Always run `./scripts/run_critical_tests.sh` before the full test suite. It enforces CRITICAL invariants (kid safety, canonical story mapping, translation compliance) and fails fast on violations.

### CI/CD

This project uses GitHub Actions for continuous integration. All tests must pass before code can be merged.

See [`.github/workflows/README.md`](.github/workflows/README.md) for CI configuration details.

## 🔒 Important: Bible Translation Compliance

**Bible PAL has a non-negotiable requirement**: It must never use non-open-source or non-public-domain Bible translations.

This is enforced through:
- Code-level allowlists ([`lib/core/bible_translation_registry.dart`](lib/core/bible_translation_registry.dart))
- Runtime validation guards
- Build-failing compliance tests
- GitHub Actions CI enforcement

**Allowed translations**: WEB, KJV, ASV, YLT, DRA

**Banned translations**: NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT (and all others not explicitly allowed)

For complete details, see:
- [`docs/INVARIANTS.md`](docs/INVARIANTS.md) - Core project invariants
- [`docs/BIBLE_TRANSLATION_COMPLIANCE.md`](docs/BIBLE_TRANSLATION_COMPLIANCE.md) - Full compliance documentation

## Documentation

- [`docs/SPEC.md`](docs/SPEC.md) - Product specification
- [`docs/INVARIANTS.md`](docs/INVARIANTS.md) - Non-negotiable project requirements
- [`docs/BIBLE_TRANSLATION_COMPLIANCE.md`](docs/BIBLE_TRANSLATION_COMPLIANCE.md) - Translation compliance guide

## Contributing

When contributing to this project:

1. **Read the invariants**: Review [`docs/INVARIANTS.md`](docs/INVARIANTS.md) before making changes
2. **Run tests locally**: Ensure `flutter test` passes before committing
3. **Check static analysis**: Run `flutter analyze` to catch issues
4. **Never use copyrighted Bible translations**: Only WEB, KJV, ASV, YLT, DRA are allowed
5. **CI must pass**: All GitHub Actions checks must succeed before PRs can be merged

## License

[To be determined]
