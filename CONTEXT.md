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
A special Canonical Category, separate from the topic taxonomy, holding each source's first successfully-discovered section (always that source's first discovered Source Section) — which is that source's actual front page for some sources, and simply the first allowlisted topical section for others (e.g. Dhaka Tribune, Ittefaq, where a genuine front-page/aggregator page is deliberately excluded from discovery). Not reached via the Section→Category Mapping — assigned unconditionally, one per source.

**Section→Category Mapping**:
The explicit, per-source lookup table (`{source_slug: {section_slug: canonical_category}}`) that decides an article's Canonical Category from the Source Section it was listed under. Takes priority over keyword classification; a Source Section with no entry falls through to keyword matching instead of being classified directly. A Source Section that matches neither is dropped, same as today.

**Discovery Report**:
The output of the reusable `scripts/discover_sections.py` tool: every raw Source Section per source, including ones a source's own `discover_sections()` normally filters out via a curated allowlist (Dhaka Tribune's and Ittefaq's `CORE_SECTION_SLUGS`). Used to design the Canonical Category list and the Section→Category Mapping by hand — bypasses those allowlists rather than trusting them as "complete."

**Visible Category**:
A Canonical Category currently shown as a pill/tab in the app: it exists in the fetched `categories` list, has at least one article surviving the Language and Source filters, and the user hasn't unchecked it in the Category filter. One derived list drives both the pill bar and the swipeable feed — there's no separate concept of a "tab list" versus a "filter list." Always ordered by the fetched `categories` list's own order (`main` first), never re-sorted by the app.
_Avoid_: Tab, active category (both mean this only in passing — use Visible Category for the app-wide derived list itself)

**Filter Dimension**:
One of the app's three independent ways to hide articles: Category, Language, or Source. Each dimension persists its own set of *excluded* keys (never the checked ones) and combines with the others by AND — an article shows only if none of its category, language, and source are excluded. The three dimensions never cross-reference each other's exclusions, even though today every Source maps to exactly one Language (`SOURCE_LANGUAGE` in `generate_data.py`).

**Filter Option**:
One selectable (key, label) entry in the Language or Source filter list, sourced from the `languages`/`sources` manifest arrays `generate_data.py` emits in `articles.json` (alongside `categories`) — alphabetically ordered by label. A Source Filter Option's key is the same display-name string stored in an article's `source` field (e.g. `"Bangla Tribune"`), not the backend's internal source slug.
