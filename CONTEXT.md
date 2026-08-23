# NewsHead

A Python scraper pipeline that publishes a JSON snapshot of news articles from 5 Bengali/English newspapers, and a Flutter app that renders it as a swipeable, reels-style feed split by category.

## Language

**Source Section**:
A navigational section on one newspaper's own website (e.g. Dhaka Tribune's "Sport", Ittefaq's "রাজনীতি"), identified by a `(slug, name)` pair returned by that source's `discover_sections()`. Sections are source-specific — the same real-world topic has a different slug and name on every source.
_Avoid_: Category, topic (both mean the app-facing concept below, not a source's own section)

**Canonical Category**:
One of the app's own fixed set of topic buckets (e.g. `politics`, `sports`) that every source's articles get classified into, regardless of what that source calls its own section. Defined once, shared across all 5 sources. An article's `category` field in `articles.json` is always a Canonical Category key, never a raw Source Section slug.
_Avoid_: Topic, section (when meaning the app-facing bucket)

**Main**:
A special Canonical Category, separate from the topic taxonomy, holding each source's front-page/latest listing (always that source's first discovered Source Section). Not reached via the Section→Category Mapping — assigned unconditionally, one per source.

**Section→Category Mapping**:
The explicit, per-source lookup table (`{source_slug: {section_slug: canonical_category}}`) that decides an article's Canonical Category from the Source Section it was listed under. Takes priority over keyword classification; a Source Section with no entry falls through to keyword matching instead of being classified directly. A Source Section that matches neither is dropped, same as today.

**Discovery Report**:
The output of the reusable `scripts/discover_sections.py` tool: every raw Source Section per source, including ones a source's own `discover_sections()` normally filters out via a curated allowlist (Dhaka Tribune's and Ittefaq's `CORE_SECTION_SLUGS`). Used to design the Canonical Category list and the Section→Category Mapping by hand — bypasses those allowlists rather than trusting them as "complete."
