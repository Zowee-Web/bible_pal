"""
Bible reference parser for bibleSourceRef strings.

Parses formats observed in Bible PAL traditional stories:
  "Mark 4:35-41"       → single chapter, verse range
  "Psalm 23"           → whole chapter
  "Daniel 6"           → whole chapter
  "Esther 4-7"         → multi-chapter range (whole chapters)
  "1 Samuel 17:1-54"   → numbered book, verse range
  "Romans 8:28"        → single verse
  "Isaiah 40:28–31"    → en-dash variant (legacy stories)

STRICT: fails loudly on ambiguous or unparseable references.
"""

import re
from dataclasses import dataclass
from typing import Optional


@dataclass
class BibleRef:
    book: str
    start_chapter: int
    end_chapter: int
    start_verse: Optional[int]  # None = whole chapter
    end_verse: Optional[int]    # None = single verse (if start_verse set) or whole chapter

    @property
    def is_whole_chapter(self) -> bool:
        return self.start_verse is None

    @property
    def is_multi_chapter(self) -> bool:
        return self.start_chapter != self.end_chapter

    def display(self, translation: str = "WEB") -> str:
        """Format as display string, e.g. 'Mark 4:35-41 (WEB)'"""
        if self.is_whole_chapter:
            if self.is_multi_chapter:
                s = f"{self.book} {self.start_chapter}-{self.end_chapter}"
            else:
                s = f"{self.book} {self.start_chapter}"
        elif self.end_verse is not None and self.end_verse != self.start_verse:
            s = f"{self.book} {self.start_chapter}:{self.start_verse}-{self.end_verse}"
        else:
            s = f"{self.book} {self.start_chapter}:{self.start_verse}"
        return f"{s} ({translation})"


# Normalize dashes: en-dash (–), em-dash (—) → hyphen (-)
def _normalize_dashes(s: str) -> str:
    return s.replace('\u2013', '-').replace('\u2014', '-')


def parse_bible_ref(ref: str) -> BibleRef:
    """
    Parse a bibleSourceRef string into a BibleRef.

    Raises ValueError with a descriptive message on parse failure.
    Does NOT silently guess or skip.
    """
    if not ref or not ref.strip():
        raise ValueError("Empty reference string")

    ref = _normalize_dashes(ref.strip())

    # Pattern breakdown:
    #   ^(book name)  (start_chapter) [: (start_verse)] [- [(end_chapter):] (end_verse_or_chapter)]$
    #
    # Book name: optional leading digit + space, then words
    #   e.g. "1 Samuel", "Genesis", "Song of Solomon"
    pattern = r'^(\d?\s*[A-Za-z]+(?:\s+[A-Za-z]+)*)\s+(\d+)(?::(\d+))?(?:\s*-\s*(?:(\d+):)?(\d+))?$'

    m = re.match(pattern, ref)
    if not m:
        raise ValueError(f"Cannot parse reference: '{ref}'")

    book = m.group(1).strip()
    num1 = int(m.group(2))       # Always present: start chapter (or only chapter)
    num2 = m.group(3)            # Optional: start verse (after colon)
    num3 = m.group(4)            # Optional: end chapter (before colon in range)
    num4 = m.group(5)            # Optional: end verse or end chapter

    if num2 is not None:
        # Has a colon → num1 is chapter, num2 is start verse
        start_chapter = num1
        start_verse = int(num2)

        if num4 is not None:
            if num3 is not None:
                # Cross-chapter verse range like "Genesis 1:1-2:3"
                # Not observed in our data but handle it
                end_chapter = int(num3)
                end_verse = int(num4)
            else:
                # Same chapter verse range: "Mark 4:35-41"
                end_chapter = start_chapter
                end_verse = int(num4)
        else:
            # Single verse: "Romans 8:28"
            end_chapter = start_chapter
            end_verse = start_verse

        return BibleRef(
            book=book,
            start_chapter=start_chapter,
            end_chapter=end_chapter,
            start_verse=start_verse,
            end_verse=end_verse,
        )
    else:
        # No colon → whole chapter(s)
        start_chapter = num1

        if num4 is not None:
            # Chapter range: "Esther 4-7"
            end_chapter = int(num4)
            if end_chapter < start_chapter:
                raise ValueError(
                    f"End chapter ({end_chapter}) < start chapter ({start_chapter}) in '{ref}'"
                )
        else:
            # Single whole chapter: "Psalm 23"
            end_chapter = start_chapter

        return BibleRef(
            book=book,
            start_chapter=start_chapter,
            end_chapter=end_chapter,
            start_verse=None,
            end_verse=None,
        )


def extract_verses(bible_data: dict, ref: BibleRef) -> list[tuple[int, int, str]]:
    """
    Extract verses from a Bible JSON structure given a parsed BibleRef.

    Returns list of (chapter, verse_num, text) tuples in order.
    Raises ValueError if the book or chapter is not found.
    """
    books = bible_data.get("books", {})

    if ref.book not in books:
        raise ValueError(f"Book '{ref.book}' not found in Bible data")

    result = []

    for ch in range(ref.start_chapter, ref.end_chapter + 1):
        ch_str = str(ch)
        if ch_str not in books[ref.book]:
            raise ValueError(
                f"Chapter {ch} of '{ref.book}' not found in Bible data"
            )

        chapter_data = books[ref.book][ch_str]

        if ref.is_whole_chapter:
            # All verses in chapter
            for v_str in sorted(chapter_data.keys(), key=int):
                result.append((ch, int(v_str), chapter_data[v_str]))
        else:
            # Verse range within chapter(s)
            if ch == ref.start_chapter:
                v_start = ref.start_verse
            else:
                v_start = 1

            if ch == ref.end_chapter:
                v_end = ref.end_verse
            else:
                v_end = max(int(k) for k in chapter_data.keys())

            for v in range(v_start, v_end + 1):
                v_str = str(v)
                if v_str not in chapter_data:
                    raise ValueError(
                        f"Verse {ref.book} {ch}:{v} not found in Bible data"
                    )
                result.append((ch, v, chapter_data[v_str]))

    if not result:
        raise ValueError(f"No verses extracted for {ref.book} reference")

    return result


def format_scripture_text(ref: BibleRef, verses: list[tuple[int, int, str]], translation: str) -> str:
    """
    Format extracted verses as plain text with reference header.

    Output format:
        Mark 4:35-41 (WEB)

        35 "Who then is this, that even the wind and the sea obey him?"
        36 ...
    """
    header = ref.display(translation)
    lines = [header, ""]

    for _ch, verse_num, text in verses:
        lines.append(f"{verse_num} {text}")

    return "\n".join(lines) + "\n"
