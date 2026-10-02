# NewsHead

A Python scraper pipeline that publishes a JSON snapshot of news articles from 17 Bengali/English news sources, and a Flutter app that renders it as a swipeable, reels-style feed split by category.

## Language

**Source Section**:
A navigational section on one newspaper's own website (e.g. Dhaka Tribune's "Sport", Ittefaq's "রাজনীতি"), identified by a `(slug, name)` pair returned by that source's `discover_sections()`. Sections are source-specific — the same real-world topic has a different slug and name on every source.
_Avoid_: Category, topic (both mean the app-facing concept below, not a source's own section)

**Canonical Category**:
One of the app's own fixed set of topic buckets (e.g. `politics`, `sports`) that every source's articles get classified into, regardless of what that source calls its own section. Defined once, shared across all 5 sources. An article's `category` field in `articles.json` is always a Canonical Category key, never a raw Source Section slug.
_Avoid_: Topic, section (when meaning the app-facing bucket)

**Main**:
A special Canonical Category, separate from the topic taxonomy, holding each source's first successfully-discovered section (always that source's first discovered Source Section) — which is that source's actual front page for some sources, and simply the first allowlisted topical section for others (e.g. Dhaka Tribune, Ittefaq, where a genuine front-page/aggregator page is deliberately excluded from discovery). Assigned unconditionally, one per source — *unless* that first Source Section already has an explicit Section→Category Mapping entry for the source, in which case it's classified through the mapping like any other section instead of becoming Main. This carve-out (tracked via `SOURCES_WITH_MAPPED_MAIN_SECTION` in `scraper/generate_data.py`) exists because Ittefaq's first section is "editorial" (its real front page, "home", is excluded from discovery the same way) — forcing it to Main silently misfiled editorial pieces outside the topic taxonomy instead of letting the mapping route them to `opinion`. It's opt-in per source, not a general rule: other sources with a similarly-excluded, mapped first section (e.g. Dhaka Tribune's "bangladesh" → `country`) are deliberately left forced-to-Main, since there's no clear evidence that's actually wrong for them.

**Section→Category Mapping**:
The explicit, per-source lookup table (`{source_slug: {section_slug: canonical_category}}`) that decides an article's Canonical Category from the Source Section it was listed under. Takes priority over keyword classification; a Source Section with no entry falls through to keyword matching instead of being classified directly. A Source Section that matches neither is dropped, same as today.

**Discovery Report**:
The output of the reusable `scripts/discover_sections.py` tool: every raw Source Section per source, including ones a source's own `discover_sections()` normally filters out via a curated allowlist (Dhaka Tribune's and Ittefaq's `CORE_SECTION_SLUGS`). Used to design the Canonical Category list and the Section→Category Mapping by hand — bypasses those allowlists rather than trusting them as "complete."

**Visible Category**:
A Canonical Category currently shown as a pill/tab in the app: it exists in the fetched `categories` list, has at least one fetched article, and the user hasn't unchecked it in the category filter. One derived list drives both the pill bar and the swipeable feed — there's no separate concept of a "tab list" versus a "filter list." Always ordered by the fetched `categories` list's own order (`main` first), never re-sorted by the app.
_Avoid_: Tab, active category (both mean this only in passing — use Visible Category for the app-wide derived list itself)

**Saved Article**:
An article the reader chose to keep; it is kept as a snapshot so it stays readable after it drops out of the feed. Removing it is the reader's choice; refreshes never remove it. Saved Articles ignore category/language/source filters.

**Auto-scroll**:
Hands-free advancing through the current Visible Category's feed, off by default and switchable by the reader.

**Dwell**:
How long a card stays on screen before Auto-scroll advances to the next one; it grows with the card's word count, Bengali reads slower than English, and it is bounded (min 6s, max 20s).
