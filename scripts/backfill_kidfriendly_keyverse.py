#!/usr/bin/env python3
"""
backfill_kidfriendly_keyverse.py — set scriptureKeyVerse on the LEGACY
kidFriendly *traditional* stories (the original adult Traditional stories that
also surface in the kid experience). The dedicated kid lane uses
backfill_kid_keyverse.py; this is its counterpart for traditional/<id> stories.

Without a scriptureKeyVerse, a kidFriendly story's Read-Scripture page falls
through to the full (ungated) passage instead of the parent-gated kid-simple
view (SPEC Feature 12.1). This backfill closes that gap.

Reads chosen refs from a picks JSON: [{"sid": int, "ref": "Book C:V"}, ...]
(curated/verified upstream). For each:
  - resolves exact WEB verse text via bible_ref_parser (never trusts a quote)
  - validates the ref is a SINGLE verse STRICTLY INSIDE the story's passage
  - writes scriptureKeyVerse = {ref, text} onto traditional/<sid>/meta_<sid>.json
  - updates every kidFriendly manifest entry for that sid in place
Fails loudly on any miss; writes nothing unless every pick validates.

Usage: python3 scripts/backfill_kidfriendly_keyverse.py PICKS.json [--write]
"""
import argparse, json, os, sys
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)
from lib.bible_ref_parser import parse_bible_ref, extract_verses

TRAD = os.path.join(ROOT, "assets", "stories", "traditional")
WEB = os.path.join(ROOT, "server", "data", "bible_web.json")
MANIFEST = os.path.join(ROOT, "assets", "stories", "manifest.json")


def is_single_in_range(pick, passage):
    """True if `pick` ref is one verse strictly inside the `passage` ref."""
    if pick.book != passage.book:
        return False, f"book mismatch ({pick.book} vs {passage.book})"
    pv = pick.start_verse
    if pv is None:
        return False, "pick has no verse"
    if pick.end_verse is not None and pick.end_verse != pv:
        return False, "pick is a range, not a single verse"
    pc = pick.start_chapter
    c0, c1 = passage.start_chapter, passage.end_chapter or passage.start_chapter
    if not (c0 <= pc <= c1):
        return False, f"chapter {pc} outside passage {c0}-{c1}"
    # verse-bound check only when passage stays within a single chapter and
    # actually specifies verse bounds (whole-chapter psalms have none).
    if c0 == c1 and passage.start_verse is not None:
        v0 = passage.start_verse
        v1 = passage.end_verse or passage.start_verse
        if not (v0 <= pv <= v1):
            return False, f"verse {pv} outside passage v{v0}-{v1}"
    return True, "ok"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("picks")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    picks = {int(p["sid"]): p["ref"].strip() for p in json.load(open(args.picks))}
    web = json.load(open(WEB, encoding="utf-8"))
    manifest = json.load(open(MANIFEST, encoding="utf-8"))

    # passage ref per sid, from the manifest (bibleSourceRef)
    passage_by_sid = {}
    for p in manifest["parables"]:
        sid = p.get("storyId", "")
        for n in picks:
            if str(sid).startswith(f"story_{n}_") and p.get("bibleSourceRef"):
                passage_by_sid.setdefault(n, p["bibleSourceRef"])

    fails, results = [], {}
    for sid, ref in sorted(picks.items()):
        try:
            passage_raw = passage_by_sid.get(sid)
            if not passage_raw:
                raise ValueError("no passage ref found in manifest")
            pick_r = parse_bible_ref(ref)
            passage_r = parse_bible_ref(passage_raw)
            ok, why = is_single_in_range(pick_r, passage_r)
            if not ok:
                raise ValueError(f"range check: {why} (passage {passage_raw})")
            verses = extract_verses(web, pick_r)
            if not verses:
                raise ValueError("no WEB verse text")
            text = " ".join(t for _, _, t in verses).strip()
            results[sid] = {"ref": ref, "text": text}
        except Exception as e:
            fails.append((sid, ref, f"{type(e).__name__}: {e}"))

    for sid, ref, err in fails:
        print(f"  FAIL {sid} ({ref}): {err}", file=sys.stderr)
    if fails:
        print(f"\n{len(fails)} failure(s); nothing written.", file=sys.stderr)
        sys.exit(1)

    if not args.write:
        for sid in sorted(results):
            print(f"  {sid}  {results[sid]['ref']:<22} {results[sid]['text'][:70]}")
        print(f"\nDRY-RUN: {len(results)} key verses resolved + in-range, 0 fail. Re-run with --write.")
        return

    # 1) write to traditional metas
    for sid, kv in results.items():
        mp = os.path.join(TRAD, str(sid), f"meta_{sid}.json")
        m = json.load(open(mp, encoding="utf-8"))
        m["scriptureKeyVerse"] = kv
        json.dump(m, open(mp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
        open(mp, "a").write("\n")
    # 2) update every kidFriendly manifest entry for these sids in place.
    # Only kidFriendly entries gate on the key verse; leave the adult/KJV
    # variants of the same story untouched.
    touched = 0
    for p in manifest["parables"]:
        if p.get("kidFriendly") is not True:
            continue
        sid = p.get("storyId", "")
        for n, kv in results.items():
            if str(sid).startswith(f"story_{n}_"):
                p["scriptureKeyVerse"] = kv
                touched += 1
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    open(MANIFEST, "a").write("\n")
    print(f"set scriptureKeyVerse on {len(results)} stories "
          f"({touched} manifest entries + metas), 0 fail")


if __name__ == "__main__":
    main()
