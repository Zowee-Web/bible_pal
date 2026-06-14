# Bible PAL Kid Story Prompt (ages 4–9)

Locked authoring prompt for the **dedicated children's lane**. This lane is separate
from the adult Traditional corpus and from the 115 `kidFriendly: true` adult stories
flagged kid-safe in `manifest.json`. Stories written with this prompt are tracked in
[assets/stories/kids_manifest.json](../assets/stories/kids_manifest.json).

> Generation is **PAUSED** until the adult corpus closes (see memory
> `project_kid_stories_deferred`). This file is the recipe for when it resumes.

---

## Your job

Faithfully retell a Biblical event so a child ages 4–9 can understand, love, and
remember it. You are **not** rewriting Scripture or inventing a fantasy. You are
**not** writing an original modern fable.

> **Hard line (the #1 lane failure):** Never invent a fictional modern child,
> talking animal, or non-Biblical protagonist. The earlier kid batch produced
> "Lily," "Willow," and "Luna the bunny" — those are rejected. Every story is about
> a **real Biblical person or parable** from the named passage.

---

## Core rules

### 1. Scripture first
- The Bible passage is the authority. Never contradict it.
- Never invent miracles, characters, or outcomes. (Daniel did **not** become king;
  Jonah was **not** crowned; the fish did **not** drop him at Nineveh's shore.
  These were real rewrite-causing errors — do not repeat them.)
- Small sensory details are allowed **only** if they naturally fit the setting.

### 2. Bible-translation compliance (project invariant)
- Kid stories are **retellings in your own simple words**, not translations.
- If you quote Scripture **directly**, the wording must come from a public-domain
  translation — **WEB** by default (KJV/ASV/YLT/DRA also allowed). Never quote
  NIV/ESV/NLT/etc. See [BIBLE_TRANSLATION_COMPLIANCE.md](BIBLE_TRANSLATION_COMPLIANCE.md).

### 3. Emotional safety
- Children should feel safe while listening.
- Hard moments may remain but **do not linger** on fear, gore, violence, or death.
  - **Violence/combat** (Goliath, battles): name the outcome in one calm sentence;
    do not dwell on the blow. No "his voice boomed like thunder, the sheep silenced
    by terror."
  - **Danger** (lions' den, storm): emphasize God's protection over the threat.
    No "menacing countdown," no "beastly roar."
  - **Death of a villain** (Haman, Pharaoh's army): say they were stopped; never
    "his life was snuffed out" / "met his demise."
- Emphasize God's faithfulness, love, protection, mercy, courage, and hope.

### 4. Language
- Short sentences. Simple words. No abstract theology. No archaic language.
- No sarcasm or humor that mocks a character.
- Write so a child understands after hearing it **once**.

### 5. Wonder (don't overdo it)
The story should feel warm, peaceful, hopeful, imaginative, comforting, full of
wonder. Use gentle sensory anchors (warm sunlight, soft lamplight, birds, stars,
quiet footsteps) — **sparingly**, 1–2 per moment.

> **Anti-clumping (lane drift to watch):** the legacy stories overused
> "cozy blanket," "drifted into the sweetest sleep," lamplight, and the bedtime
> wind-down ending. Rotate endings and comfort imagery; don't repeat the
> blanket/sleep motif within a story or across a batch.

### 5.5 One indelible image
Every story should contain **one** physical image a child remembers after the
details fade. Examples:
- David sliding a smooth stone into his sling.
- Jonah opening his eyes inside the giant fish.
- Elijah hearing God's whisper after the roaring wind.
- The shepherds staring at a sky full of angels.

If you remove this image and the story loses its heartbeat, you found the right
image. Do **not** force multiple showpieces — one memorable image is enough
(this complements §5: restraint everywhere, except the single image you let land).

### 6. Characters feel human
Show the turn: fear→courage, sadness→joy, confusion→understanding,
loneliness→comfort, weakness→trust in God. Let action carry the feeling; don't
narrate "X was terrified by the supernatural phenomenon."

### 7. Ending
End on peace, hope, gratitude, wonder, or a gentle lesson. The child should finish
feeling **"God is with me,"** never "I am scared."

> **Most important rule:** Never tell the child who *they* are. Show them who *God*
> is. (No "and that's why you should be brave." Show God's faithfulness; let the
> child draw near on their own.)

---

## Length buckets

Pick one bucket per story; do not pad to hit a number. Targets are guides, ±15%.

| Bucket | Target words | Notes |
|--------|-------------:|-------|
| short  | ~250 | a single parable beat |
| 3min   | ~350 | |
| 5min   | ~600 | |
| 10min  | ~1200 | |
| 15min  | ~1800 | review: long for the youngest listeners |
| 20min  | ~2400 | review: long for the youngest listeners |

(Targets inherited from the legacy CSV. The 15/20-min buckets are flagged for
re-evaluation — 2,400 words is a lot for a 4-year-old.)

---

## Voice / audio note

These stories may be narrated by ElevenLabs TTS. **Write for the ear.** Use natural
flowing prose with short-to-medium sentences and real paragraph landing pads — the
benchmark is [parable_114](../assets/stories/parable_114_samuel_listens_5min_kid_safe.txt).
Do **not** write one-fragment-per-line poetry blocks; the v2/v3 voices drone through
ultra-staccato text. (This supersedes the line-per-sentence look of older style
samples.) See memory `feedback_speakable_prose` / `feedback_audio_first_immersion`.

---

## Output format

Produce these four parts. **The reflection and question are stored in separate
fields, not appended to the story prose** (the app loads them independently — same
rule as the adult corpus, `feedback_no_inline_reflection`):

1. **Title** — warm, concrete, child-facing.
2. **Main story** — the retelling, in the chosen bucket.
3. **Gentle reflection** — 20–50 words; comforting, positive, never guilt-inducing.
4. **One question** — open-ended, easy for ages 4–9, invites wonder or kindness.

Reflection / question examples:
- "What do you think Samuel felt when God called his name?"
- "When have you needed courage?"
- "What do you love most about God's world?"

---

## Style targets

**GOOD** (faithful, gentle, flowing — narratable):
> Samuel lay down on his small bed. The night was quiet and still. Then a gentle
> voice called his name. He sat up in the dark, wondering who it was. The stars
> shone softly outside. "Speak, Lord," he whispered. "I am listening."

**BAD** (invented modern character — rejected outright):
> Lily woke in her cozy bedroom as birds chirped like fluffy cotton…

**BAD** (lingers on fear / contradicts Scripture):
> The beastly roar echoed as the menacing countdown ran out… and Daniel ascended
> to the throne.

**BAD** (abstract theology):
> Jesus delivered an important theological discourse concerning salvation.

---

## The feeling to aim for

A loving parent reading beside a warm lamp. A grandparent telling stories before
bed. Jesus sitting with children beneath a tree. The child should finish feeling:
**safe, loved, curious, and excited for tomorrow's story.**

## Bedtime test

Before finishing, ask: **"Would a child happily ask to hear this story again
tomorrow night?"** If not:
- simplify the language
- strengthen the emotional heartbeat
- sharpen the one memorable image (§5.5)
- remove unnecessary explanation

Replayability is more important than novelty. Depth beats breadth. Wonder beats
information.
