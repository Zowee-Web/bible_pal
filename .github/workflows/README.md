# GitHub Actions CI Workflows

This directory contains GitHub Actions workflows that run automatically on every push and pull request.

## flutter.yml

**Purpose**: Enforces code quality and compliance requirements for Bible PAL.

**When it runs**:
- On every push to `master`, `main`, or `develop` branches
- On every pull request targeting these branches

**What it does**:
1. **Setup**: Installs Flutter 3.41.4 and dependencies
2. **Static Analysis**: Runs `flutter analyze` to catch code issues
3. **All Tests**: Runs `flutter test` to verify functionality
4. **🔒 CRITICAL - Bible Translation Compliance**: Runs dedicated compliance tests that enforce the Bible Translation Licensing Invariant

**The compliance step is mandatory** and will fail the build if:
- Any banned translation ID is detected anywhere in the codebase (NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT)
- Any unknown translation ID is used (not in the allowlist: WEB, KJV, ASV, YLT, DRA)

**Why this exists**: See [`docs/INVARIANTS.md`](../../docs/INVARIANTS.md) for the full explanation of the Bible Translation Licensing Invariant.

## Adding New Workflows

When adding new workflows:
1. Use descriptive names (e.g., `deploy.yml`, `lint.yml`)
2. Document the purpose in a comment at the top of the file
3. Ensure workflows fail fast on errors
4. Update this README with a description of the new workflow

## Modifying Existing Workflows

**⚠️  WARNING: DO NOT weaken or remove the Bible Translation Compliance step ⚠️**

The compliance enforcement in `flutter.yml` is a **non-negotiable requirement**. Removing or weakening it violates a core Bible PAL invariant.

If you need to modify other aspects of the workflow:
1. Test changes locally first
2. Ensure all existing checks still run
3. Verify the compliance step remains unchanged
4. Document changes in commit messages

## Troubleshooting

**Build failing on compliance check?**
- Review the test output - it will show which file contains the banned translation
- Remove all references to copyrighted Bible translations (NIV, ESV, etc.)
- Use only allowed translations: WEB, KJV, ASV, YLT, DRA
- See [`docs/BIBLE_TRANSLATION_COMPLIANCE.md`](../../docs/BIBLE_TRANSLATION_COMPLIANCE.md) for details

**Build failing on other tests?**
- Run `flutter test` locally to reproduce the failure
- Fix the failing tests
- Ensure `flutter analyze` passes locally

**Need to skip CI temporarily?**
- You can't. All CI checks must pass for PRs to be merged.
- This is intentional to maintain code quality and compliance.
