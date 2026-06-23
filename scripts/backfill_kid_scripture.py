#!/usr/bin/env python3
"""
backfill_kid_scripture.py — generate WEB scripture-text files for kid-lane stories.

Mirrors the Traditional Feature-12 backfill (scripts/backfill_scripture_text.py) but
for assets/stories/kids/. Kids are WEB-only (kid compliance). For each kid story it:
  1. reads bibleSourceRef from meta_<id>.json (or a curated override below)
  2. resolves the reference (handles ';' compounds + book-carry-forward, e.g.
     "Genesis 18:1-15; 21:1-7" -> the 21:1-7 inherits "Genesis")
  3. extracts the verses from server/data/bible_web.json
  4. writes scripture_<id>_web.txt (header = display ref; chapter labels when the
     passage spans >1 chapter; otherwise plain numbered verses like the adult files)
  5. sets meta.scriptureTextFilePath

Curated overrides: a few stories cite a broad span where most of it is not what the
story draws from (e.g. 1 Kings 6-8 is mostly building measurements). For those, the
bundled TEXT is the key passages; bibleSourceRef (the citation) is unchanged.

Usage:
  python3 scripts/backfill_kid_scripture.py --dry-run   # preview, no writes
  python3 scripts/backfill_kid_scripture.py             # write files + update metas
"""
import argparse, glob, json, os, re, sys
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)
from lib.bible_ref_parser import parse_bible_ref, extract_verses

KIDS_DIR = os.path.join(ROOT, "assets", "stories", "kids")
WEB_PATH = os.path.join(ROOT, "server", "data", "bible_web.json")

# Stories where the bundled scripture TEXT should be curated key passages rather than
# the full broad citation (per Adam: match the text to what the story actually draws from).
TEXT_OVERRIDES = {
    1896: {  # Solomon's Temple: 1 Kings 6-8 is mostly cubit measurements
        "display": "1 Kings 6–8 (key passages)",
        "refs": ["1 Kings 6:1", "1 Kings 6:7", "1 Kings 8:6-13", "1 Kings 8:22-30"],
    },
}


def resolve_refs(ref_str):
    """Split on ';' and carry the book name forward to book-less continuations."""
    out, last_book = [], None
    for part in [p.strip() for p in ref_str.split(";") if p.strip()]:
        if not re.search(r"[A-Za-z]", part) and last_book:  # e.g. "21:1-7" / "8:22-30"
            part = f"{last_book} {part}"
        r = parse_bible_ref(part)
        last_book = r.book
        out.append(r)
    return out


def build_text(display_ref, verses):
    """verses: list of (chapter, verse, text). Header + numbered verses; chapter
    labels only when the passage spans more than one chapter."""
    chapters = sorted({c for c, _, _ in verses})
    multi = len(chapters) > 1
    lines = [f"{display_ref} (WEB)", ""]
    last_ch = None
    for ch, vs, text in verses:
        if multi and ch != last_ch:
            if last_ch is not None:
                lines.append("")
            lines.append(f"Chapter {ch}")
            last_ch = ch
        lines.append(f"{vs} {text}")
    return "\n".join(lines).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    web = json.load(open(WEB_PATH, encoding="utf-8"))
    metas = sorted(glob.glob(os.path.join(KIDS_DIR, "*", "meta_*.json")))
    ok, fails, total_words = 0, [], 0
    for mp in metas:
        meta = json.load(open(mp, encoding="utf-8"))
        sid = meta.get("storyNumber")
        src = meta.get("bibleSourceRef")
        if not src:
            continue
        ov = TEXT_OVERRIDES.get(sid)
        display = ov["display"] if ov else src
        ref_list = ov["refs"] if ov else [src]
        try:
            verses = []
            for rs in ref_list:
                for r in resolve_refs(rs):
                    verses.extend(extract_verses(web, r))
            if not verses:
                raise ValueError("no verses extracted")
            text = build_text(display, verses)
            words = sum(len(t.split()) for _, _, t in verses)
            total_words += words
            ok += 1
            out_name = f"scripture_{sid}_web.txt"
            if args.dry_run:
                print(f"  OK {sid:>4} {src:<28} -> {len(verses):>3} verses, {words:>4} words")
            else:
                open(os.path.join(KIDS_DIR, str(sid), out_name), "w", encoding="utf-8").write(text)
                meta["scriptureTextFilePath"] = f"kids/{sid}/{out_name}"
                json.dump(meta, open(mp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
                open(mp, "a").write("\n")
        except Exception as e:
            fails.append((sid, src, f"{type(e).__name__}: {e}"))
    print(f"\n{'DRY-RUN ' if args.dry_run else ''}done: {ok} ok, {len(fails)} failed, ~{total_words} total words")
    for sid, src, err in fails:
        print(f"  FAIL {sid} ({src}): {err}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
