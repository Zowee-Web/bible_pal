#!/usr/bin/env python3
"""
backfill_kid_keyverse.py — set the single "key verse" shown in the ungated
kid-simple Scripture view (SPEC Feature 12.1). One central verse per story,
hand-curated to capture the heart of the passage. Writes scriptureKeyVerse =
{ "ref": <display ref>, "text": <WEB verse text> } onto each kid meta + manifest.
Validates every ref against bible_web.json; fails loudly on any miss.

Usage: python3 scripts/backfill_kid_keyverse.py [--dry-run]
"""
import argparse, glob, json, os, sys
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)
from lib.bible_ref_parser import parse_bible_ref, extract_verses
KIDS = os.path.join(ROOT, "assets", "stories", "kids")
WEB = os.path.join(ROOT, "server", "data", "bible_web.json")

KEYVERSE = {
 1801:"1 Samuel 17:47", 1802:"Jonah 2:9", 1803:"Psalm 23:1", 1804:"Matthew 14:27",
 1805:"Genesis 1:31", 1806:"Mark 5:36", 1807:"Mark 10:14", 1808:"Genesis 9:13",
 1809:"Matthew 2:10", 1810:"Exodus 2:10", 1811:"Exodus 3:14", 1812:"Matthew 28:6",
 1813:"Exodus 14:14", 1814:"Daniel 6:22", 1815:"Luke 10:33", 1816:"Mark 4:39",
 1817:"Luke 15:20", 1818:"Joshua 6:20", 1819:"Genesis 45:5", 1820:"1 Samuel 3:10",
 1821:"Luke 23:46", 1822:"Daniel 3:25", 1823:"Genesis 12:2", 1824:"Luke 1:38",
 1825:"John 6:9", 1826:"Luke 15:6", 1827:"Matthew 7:24", 1828:"Matthew 13:32",
 1829:"Luke 2:7", 1830:"John 2:11", 1831:"Luke 19:5", 1832:"Matthew 21:9",
 1833:"Luke 2:11", 1834:"Genesis 2:8", 1835:"Psalm 139:14", 1836:"1 Samuel 16:13",
 1837:"Ruth 1:16", 1838:"Esther 4:14", 1839:"1 Kings 19:12", 1840:"Revelation 21:4",
 1841:"Genesis 7:16", 1842:"1 Kings 18:39", 1843:"Matthew 6:9", 1844:"Genesis 37:3",
 1845:"Acts 2:4", 1846:"1 Samuel 18:3", 1847:"1 Kings 17:6", 1848:"Mark 10:52",
 1849:"Exodus 20:2", 1850:"Luke 22:19", 1851:"Acts 9:4", 1852:"Genesis 18:14",
 1853:"Luke 17:16", 1854:"2 Samuel 9:7", 1855:"Daniel 1:8", 1856:"Acts 12:7",
 1857:"1 Samuel 16:23", 1858:"Genesis 15:5", 1859:"Matthew 5:9", 1860:"Genesis 41:16",
 1861:"Mark 2:11", 1862:"2 Kings 5:14", 1863:"Luke 10:42", 1864:"Acts 1:11",
 1865:"Luke 24:31", 1866:"Matthew 11:28", 1867:"Matthew 6:26", 1868:"John 13:14",
 1869:"Galatians 5:22", 1870:"John 11:35", 1871:"John 20:27", 1872:"Mark 12:43",
 1873:"Luke 15:9", 1874:"Esther 2:17", 1875:"1 Samuel 1:27", 1876:"Matthew 17:5",
 1877:"Matthew 17:27", 1878:"Numbers 22:28", 1879:"Judges 14:6", 1880:"2 Kings 2:11",
 1881:"Judges 7:7", 1882:"1 Kings 3:9", 1883:"Luke 5:5", 1884:"Genesis 11:9",
 1885:"2 Kings 4:6", 1886:"Exodus 16:15", 1887:"Matthew 13:44", 1888:"Joshua 3:17",
 1889:"John 4:14", 1890:"Acts 16:25", 1891:"Matthew 3:17", 1892:"Exodus 17:6",
 1893:"Judges 4:14", 1894:"Luke 2:49", 1895:"Acts 8:39", 1896:"1 Kings 8:11",
 1897:"Acts 9:40", 1898:"Matthew 8:8", 1899:"Joshua 10:13", 1900:"Genesis 28:15",
 1901:"Luke 22:42", 1902:"Genesis 33:4", 1903:"John 21:12", 1904:"1 Kings 17:16",
 1905:"Luke 18:1",
}


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    web = json.load(open(WEB, encoding="utf-8"))
    metas = {int(json.load(open(p))["storyNumber"]): p
             for p in glob.glob(os.path.join(KIDS, "*", "meta_*.json"))}
    missing = [sid for sid in metas if sid not in KEYVERSE]
    fails, results = [], {}
    for sid, ref in KEYVERSE.items():
        try:
            r = parse_bible_ref(ref)
            verses = extract_verses(web, r)
            if not verses:
                raise ValueError("no verse text")
            text = " ".join(t for _, _, t in verses).strip()
            results[sid] = {"ref": ref, "text": text}
        except Exception as e:
            fails.append((sid, ref, f"{type(e).__name__}: {e}"))
    if missing:
        print("STORIES WITHOUT A KEY VERSE:", sorted(missing))
    for sid, ref, err in fails:
        print(f"  FAIL {sid} ({ref}): {err}")
    if fails or missing:
        sys.exit(1)
    if args.dry_run:
        for sid in sorted(results):
            print(f"  {sid} {results[sid]['ref']:<20} {results[sid]['text'][:64]}")
        print(f"\nDRY-RUN: {len(results)} key verses resolved, 0 fail")
        return
    # write to metas
    for sid, kv in results.items():
        mp = metas[sid]; m = json.load(open(mp))
        m["scriptureKeyVerse"] = kv
        json.dump(m, open(mp, "w", encoding="utf-8"), indent=2, ensure_ascii=False); open(mp, "a").write("\n")
    # write to kids_manifest (every cut)
    KM = os.path.join(ROOT, "assets", "stories", "kids_manifest.json"); km = json.load(open(KM))
    for s in km["stories"]:
        if s.get("storyNumber") in results:
            s["scriptureKeyVerse"] = results[s["storyNumber"]]
    json.dump(km, open(KM, "w", encoding="utf-8"), indent=2, ensure_ascii=False); open(KM, "a").write("\n")
    print(f"set scriptureKeyVerse on {len(results)} stories (metas + manifest), 0 fail")


if __name__ == "__main__":
    main()
