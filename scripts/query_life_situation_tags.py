#!/usr/bin/env python3
"""
query_life_situation_tags.py — two-mode CLI for the Life Situation Tags v1
vocabulary smoke test.

This is NOT a natural-language retrieval engine. It is a smoke test for
whether the controlled vocabulary + the seed map surface the right stories
for plausible inputs — and, equally important, do NOT surface the wrong
ones. If retrieval feels wrong, the fix is in the vocabulary descriptions
or the seed map, not in this tool.

Modes
-----
Mode A — exact tag (AND/OR across primary + secondary, pooled):

    python3 scripts/query_life_situation_tags.py --tags A,B,C
    python3 scripts/query_life_situation_tags.py --any  A,B,C

    Membership is pooled (a story matches a tag iff the tag appears in
    primary OR secondary). Ranking is the only place the distinction
    matters: stories with more primary hits sort above stories that
    matched only on secondary.

Mode B — crude keyword overlap against tag descriptions ("probe", smoke
test only — no stemming, no synonyms, no embeddings, no LLM):

    python3 scripts/query_life_situation_tags.py --probe "I let my friend down"

    Tokenizes the input (lower, strip punctuation, drop stopwords),
    finds tags whose tagId / displayName / description share ≥2 tokens
    with the input, then surfaces stories carrying those tags.

Output
------
Plain table by default. `--json` for machine-readable output.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTRY = REPO_ROOT / "assets" / "stories" / "life_situation_tags_registry.json"
STORIES_DIR = REPO_ROOT / "assets" / "stories" / "traditional"

PROBE_MIN_OVERLAP = 2

STOPWORDS = {
    "i", "im", "my", "me", "mine", "a", "an", "the", "and", "or", "but",
    "of", "to", "in", "on", "at", "for", "with", "from", "by", "about",
    "is", "am", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "did", "does", "doing",
    "this", "that", "these", "those",
    "it", "its", "itll", "youre", "youll", "youve",
    "we", "us", "our", "you", "your", "they", "them", "their",
    "he", "him", "his", "she", "her", "hers",
    "feel", "feels", "feeling", "felt",
    "go", "goes", "going", "gone",
    "just", "very", "really", "so", "now", "then",
    "if", "as", "than", "into", "out",
    "what", "which", "when", "where", "why", "how",
    "not", "no", "yes",
    "can", "cant", "will", "wont", "would", "could", "should",
    "some", "any", "all", "most", "more",
}

# "up" / "down" / "in" / "out" are NOT stopwords here — they're often
# load-bearing in situational tag IDs (let_someone_down, sinking_in_fear).
# The ≥2-token-overlap threshold (PROBE_MIN_OVERLAP) is what guards against
# trivial single-particle matches.


def load_registry() -> Tuple[Dict[str, dict], List[str]]:
    with REGISTRY.open() as f:
        data = json.load(f)
    by_id = {t["tagId"]: t for t in data["tags"]}
    banned = data.get("rules", {}).get("bannedGenerics", [])
    return by_id, banned


def load_stories() -> List[dict]:
    stories: List[dict] = []
    for entry in sorted(STORIES_DIR.iterdir()):
        if not entry.is_dir():
            continue
        sid = entry.name
        if not sid.isdigit():
            continue
        meta_path = entry / f"meta_{sid}.json"
        if not meta_path.exists():
            continue
        with meta_path.open() as f:
            meta = json.load(f)
        primary = meta.get("primaryLifeSituationTags") or []
        secondary = meta.get("secondaryLifeSituationTags") or []
        if not primary and not secondary:
            continue
        stories.append({
            "storyId": sid,
            "title": meta.get("title", ""),
            "bibleStoryKey": meta.get("bibleStoryKey", ""),
            "scriptureAnchor": meta.get("scriptureAnchor", ""),
            "primary": primary,
            "secondary": secondary,
        })
    return stories


def tokenize(text: str) -> Set[str]:
    """Lowercase, strip non-letters, split, drop stopwords. No stemming."""
    cleaned = re.sub(r"[^a-zA-Z\s]", " ", text.lower())
    return {w for w in cleaned.split() if w and w not in STOPWORDS}


def tag_token_pool(tag: dict) -> Set[str]:
    """Tokens drawn from tagId (split on _), displayName, and description."""
    tokens = set(tag["tagId"].split("_"))
    tokens |= tokenize(tag.get("displayName", ""))
    tokens |= tokenize(tag.get("description", ""))
    tokens -= STOPWORDS
    return tokens


def run_mode_a(
    args, stories: List[dict], registry: Dict[str, dict]
) -> List[dict]:
    raw_tags = args.tags or args.any_
    requested = [t.strip() for t in raw_tags.split(",") if t.strip()]

    unknown = [t for t in requested if t not in registry]
    if unknown:
        print(
            f"WARN: unknown tag(s) (not in registry): {unknown}",
            file=sys.stderr,
        )

    results = []
    for s in stories:
        pool = set(s["primary"]) | set(s["secondary"])
        if args.tags:
            # AND
            if not all(t in pool for t in requested):
                continue
        else:
            # OR
            if not any(t in pool for t in requested):
                continue
        primary_hits = [t for t in requested if t in s["primary"]]
        secondary_hits = [t for t in requested if t in s["secondary"]]
        results.append({
            **s,
            "primaryMatches": primary_hits,
            "secondaryMatches": secondary_hits,
            "score": len(primary_hits) * 10 + len(secondary_hits),
        })

    results.sort(
        key=lambda r: (-r["score"], -len(r["primaryMatches"]), int(r["storyId"]))
    )
    return results


def run_mode_b(
    args, stories: List[dict], registry: Dict[str, dict]
) -> List[dict]:
    query_tokens = tokenize(args.probe)
    if not query_tokens:
        print("WARN: probe reduced to no meaningful tokens after stopword removal.",
              file=sys.stderr)
        return []

    # Find tags with sufficient token overlap.
    matched_tags = []
    for tag_id, tag in registry.items():
        overlap = query_tokens & tag_token_pool(tag)
        if len(overlap) >= PROBE_MIN_OVERLAP:
            matched_tags.append((tag_id, overlap))

    matched_tag_ids = {tid for tid, _ in matched_tags}

    if args.verbose:
        print(f"DEBUG: query tokens = {sorted(query_tokens)}", file=sys.stderr)
        if matched_tags:
            print("DEBUG: matched tags (≥2 token overlap):", file=sys.stderr)
            for tid, overlap in sorted(matched_tags, key=lambda x: -len(x[1])):
                print(f"  {tid}  overlap={sorted(overlap)}", file=sys.stderr)
        else:
            print("DEBUG: no tags hit ≥2-token overlap threshold.",
                  file=sys.stderr)

    results = []
    for s in stories:
        pool = set(s["primary"]) | set(s["secondary"])
        hits = pool & matched_tag_ids
        if not hits:
            continue
        primary_hits = [t for t in s["primary"] if t in hits]
        secondary_hits = [t for t in s["secondary"] if t in hits]
        results.append({
            **s,
            "primaryMatches": primary_hits,
            "secondaryMatches": secondary_hits,
            "score": len(primary_hits) * 10 + len(secondary_hits),
        })

    results.sort(
        key=lambda r: (-r["score"], -len(r["primaryMatches"]), int(r["storyId"]))
    )
    return results


def format_table(results: List[dict]) -> str:
    if not results:
        return "(no matches)"
    lines = []
    header = f"{'storyId':<8} {'score':<6} {'bibleStoryKey':<36} {'title':<46} matches"
    lines.append(header)
    lines.append("-" * len(header))
    for r in results:
        pm = ",".join(f"{t}(P)" for t in r["primaryMatches"])
        sm = ",".join(f"{t}(S)" for t in r["secondaryMatches"])
        matches = " ".join(x for x in [pm, sm] if x)
        title = (r["title"] or "")[:44]
        key = (r["bibleStoryKey"] or "")[:34]
        lines.append(
            f"{r['storyId']:<8} {r['score']:<6} {key:<36} {title:<46} {matches}"
        )
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    grp = parser.add_mutually_exclusive_group(required=True)
    grp.add_argument(
        "--tags",
        help="Mode A: comma-separated tag IDs (AND across primary+secondary pool)",
    )
    grp.add_argument(
        "--any",
        dest="any_",
        help="Mode A: comma-separated tag IDs (OR across primary+secondary pool)",
    )
    grp.add_argument(
        "--probe",
        help="Mode B: free-text input. Crude keyword overlap against tag "
             "descriptions. Smoke test only — NOT a retrieval engine.",
    )
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--limit", type=int, default=20, help="Max results to show")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print debug info to stderr (probe tokens, matched tags)")
    args = parser.parse_args()

    registry, _banned = load_registry()
    stories = load_stories()

    if args.tags or args.any_:
        results = run_mode_a(args, stories, registry)
    else:
        results = run_mode_b(args, stories, registry)

    results = results[: args.limit]

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(format_table(results))


if __name__ == "__main__":
    main()
