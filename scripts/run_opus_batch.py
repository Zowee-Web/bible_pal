#!/usr/bin/env python3
"""
Bible PAL — Opus Batch Runner

Thin orchestration wrapper around generate_story_opus.py.
Reads a batch config JSON file, calls the generator for each story.

Usage:
  # Full batch
  python3 scripts/run_opus_batch.py configs/opus_batch_04.json

  # Dry run (no files written)
  python3 scripts/run_opus_batch.py configs/opus_batch_04.json --dry-run

  # Only specific stories
  python3 scripts/run_opus_batch.py configs/opus_batch_04.json --only 1064,1065,2064

  # Start from a specific ID (skip earlier ones)
  python3 scripts/run_opus_batch.py configs/opus_batch_04.json --start-id 1072

  # Retry only stories that failed in previous run
  python3 scripts/run_opus_batch.py configs/opus_batch_04.json --retry-failed

  # Skip long versions for all stories
  python3 scripts/run_opus_batch.py configs/opus_batch_04.json --skip-long
"""

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GENERATOR = PROJECT_ROOT / "scripts" / "generate_story_opus.py"
LOGS_DIR = PROJECT_ROOT / "logs"


def load_config(config_path: str) -> dict:
    with open(config_path) as f:
        return json.load(f)


def load_failures(log_path: Path) -> set:
    """Load story IDs from a failures log."""
    if not log_path.exists():
        return set()
    ids = set()
    for line in log_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            try:
                ids.add(int(line.split()[0]))
            except (ValueError, IndexError):
                pass
    return ids


def run_story(story: dict, batch: str, dry_run: bool, skip_long: bool) -> dict:
    """Run generate_story_opus.py for a single story. Returns result dict."""
    sid = story["id"]
    cmd = [
        sys.executable, str(GENERATOR),
        "--story-id", str(sid),
        "--mode", story["mode"],
        "--mood", story["mood"],
        "--voice", story["voice"],
        "--title", story["title"],
        "--batch", batch,
    ]

    if story.get("anchor"):
        cmd += ["--anchor", story["anchor"]]
    if story.get("bibleKey"):
        cmd += ["--bible-key", story["bibleKey"]]
    if story.get("kid"):
        cmd.append("--kid")
    if story.get("theme"):
        cmd += ["--theme", story["theme"]]
    if story.get("passageSummary"):
        cmd += ["--passage-summary", story["passageSummary"]]
    if dry_run:
        cmd.append("--dry-run")
    if skip_long:
        cmd.append("--skip-long")

    start = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5 min max per story
        )
        elapsed = time.time() - start

        # Parse output for repair/review status
        output = result.stdout
        repaired = "repaired and clean" in output
        manual_review = "MANUAL REVIEW" in output
        lint_clean = "Lint clean" in output
        audit_clean = "Audit clean" in output

        if result.returncode == 0:
            status = "manual_review" if manual_review else ("repaired" if repaired else "passed")
        else:
            status = "failed"

        return {
            "id": sid,
            "status": status,
            "elapsed": round(elapsed, 1),
            "lint_clean": lint_clean,
            "audit_clean": audit_clean,
            "repaired": repaired,
            "manual_review": manual_review,
            "output": output[-500:] if output else "",
            "error": result.stderr[-300:] if result.stderr else "",
        }

    except subprocess.TimeoutExpired:
        return {
            "id": sid,
            "status": "timeout",
            "elapsed": 300,
            "output": "",
            "error": "Timed out after 300 seconds",
        }
    except Exception as e:
        return {
            "id": sid,
            "status": "error",
            "elapsed": 0,
            "output": "",
            "error": str(e),
        }


def main():
    parser = argparse.ArgumentParser(description="Bible PAL Opus Batch Runner")
    parser.add_argument("config", help="Path to batch config JSON")
    parser.add_argument("--dry-run", action="store_true", help="Generate but don't write files")
    parser.add_argument("--only", help="Comma-separated story IDs to run")
    parser.add_argument("--start-id", type=int, help="Skip stories before this ID")
    parser.add_argument("--retry-failed", action="store_true", help="Only retry previously failed stories")
    parser.add_argument("--skip-long", action="store_true", help="Skip long versions")

    args = parser.parse_args()

    config = load_config(args.config)
    batch = config["batch"]
    stories = config["stories"]

    # Filter: --only
    if args.only:
        only_ids = set(int(x) for x in args.only.split(","))
        stories = [s for s in stories if s["id"] in only_ids]

    # Filter: --start-id
    if args.start_id:
        stories = [s for s in stories if s["id"] >= args.start_id]

    # Filter: --retry-failed
    if args.retry_failed:
        LOGS_DIR.mkdir(exist_ok=True)
        failures_log = LOGS_DIR / f"{batch.lower()}_failures.log"
        failed_ids = load_failures(failures_log)
        if not failed_ids:
            print("No failures to retry.")
            return
        stories = [s for s in stories if s["id"] in failed_ids]
        print(f"Retrying {len(stories)} failed stories: {sorted(s['id'] for s in stories)}")

    # Validate: skip stories with TBD or missing required fields
    ready = []
    skipped_tbd = []
    for s in stories:
        title_ok = s.get("title") and s["title"] != "TBD"
        if s["mode"] == "traditional":
            # Traditional requires: title, anchor, bibleKey
            anchor_ok = s.get("anchor") and s["anchor"] != "TBD"
            key_ok = s.get("bibleKey") and s["bibleKey"] != "TBD"
            if title_ok and anchor_ok and key_ok:
                ready.append(s)
            else:
                skipped_tbd.append(s["id"])
        else:
            # Creative requires: title, theme
            theme_ok = s.get("theme") and s["theme"] != "TBD"
            if title_ok and theme_ok:
                ready.append(s)
            else:
                skipped_tbd.append(s["id"])

    if skipped_tbd:
        print(f"Skipping {len(skipped_tbd)} stories with TBD fields: {skipped_tbd}")

    if not ready:
        print("No stories ready to generate. Fill in the config file first.")
        return

    # Run
    LOGS_DIR.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_log = LOGS_DIR / f"{batch.lower()}_run_{timestamp}.log"
    failures_log = LOGS_DIR / f"{batch.lower()}_failures.log"

    print(f"\n{'='*60}")
    print(f"  {batch} — {len(ready)} stories")
    print(f"  {'DRY RUN' if args.dry_run else 'LIVE'}")
    print(f"  Log: {run_log.relative_to(PROJECT_ROOT)}")
    print(f"{'='*60}\n")

    results = []
    for i, story in enumerate(ready, 1):
        print(f"\n[{i}/{len(ready)}] Story {story['id']}...")
        result = run_story(story, batch, args.dry_run, args.skip_long)
        results.append(result)

        icon = {"passed": "✓", "repaired": "🔧", "failed": "✗", "manual_review": "⚠",
                "timeout": "⏰", "error": "💥"}.get(result["status"], "?")
        print(f"  {icon} {result['status']} ({result['elapsed']}s)")

        if result["status"] in ("failed", "error", "timeout"):
            print(f"  Error: {result.get('error', 'unknown')[:200]}")

    # Summary
    passed = sum(1 for r in results if r["status"] == "passed")
    repaired = sum(1 for r in results if r["status"] == "repaired")
    failed = sum(1 for r in results if r["status"] in ("failed", "error", "timeout"))
    manual = sum(1 for r in results if r["status"] == "manual_review")
    total_time = sum(r["elapsed"] for r in results)

    print(f"\n{'='*60}")
    print(f"  {batch} SUMMARY")
    print(f"{'='*60}")
    print(f"  Passed:         {passed}")
    print(f"  Repaired:       {repaired}")
    print(f"  Failed:         {failed}")
    print(f"  Manual review:  {manual}")
    print(f"  Total time:     {total_time:.0f}s ({total_time/60:.1f}m)")
    print(f"{'='*60}")

    # Write run log
    log_data = {
        "batch": batch,
        "timestamp": timestamp,
        "dry_run": args.dry_run,
        "total": len(results),
        "passed": passed,
        "repaired": repaired,
        "failed": failed,
        "manual_review": manual,
        "total_seconds": round(total_time),
        "results": results,
    }
    run_log.write_text(json.dumps(log_data, indent=2) + "\n")
    print(f"\n  Run log: {run_log.relative_to(PROJECT_ROOT)}")

    # Write failures log (overwrite — latest state)
    failed_ids = [r["id"] for r in results if r["status"] in ("failed", "error", "timeout", "manual_review")]
    if failed_ids:
        failures_log.write_text(
            f"# {batch} failures — {timestamp}\n" +
            "\n".join(str(fid) for fid in failed_ids) + "\n"
        )
        print(f"  Failures log: {failures_log.relative_to(PROJECT_ROOT)}")
    elif failures_log.exists():
        failures_log.unlink()
        print(f"  Failures log cleared (all passed)")

    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
