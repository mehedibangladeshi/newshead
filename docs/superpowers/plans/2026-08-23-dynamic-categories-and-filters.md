# Dynamic Categories, Filters & Card Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide empty/user-excluded category pills, add a per-article bilingual publish timestamp with an untruncated headline, replace the app bar's date with the NewsHead brand mark, and add a persisted category filter bottom sheet.

**Architecture:** The pill bar and swipeable feed already read from a fetched `categories` list (done in the category-remapping work); this plan adds one more derivation step — a pure `visibleCategories()` function that intersects the fetched list with "has ≥1 article" and "not excluded by the reader" — and threads a new `publishedAt`/`language` field per article all the way from each Python scraper's already-captured raw listing-time string through to a bilingual Dart formatter. The category filter's choice is persisted locally as the set of *excluded* keys via `shared_preferences`, so a brand-new category (new source, new taxonomy entry) defaults to visible with no migration.

**Tech Stack:** Python 3.14 / BeautifulSoup (scraper, unchanged), Flutter/Dart (app). New Flutter deps: `shared_preferences` (local filter persistence), `google_fonts` (the wordmark's Anton typeface). No new Python deps — the timestamp parsers use only `re`, `datetime`, `zoneinfo` (stdlib).

**Spec:** This plan's spec is the conversation record of a `/grill-with-docs` session held earlier the same day (2026-08-23) that resolved every open decision below — there is no separate written spec document. The reviewed-and-approved HTML prototype lives at `https://claude.ai/code/artifact/cec64952-a765-4e1b-8761-111f8afe3bce`.

## Global Constraints

- Commit messages follow `<type>(<scope>): <description>` (~80 chars), one line per logical change, per this repo's `CLAUDE.md`. Never add AI co-author lines.
- **Visible Category** (see `CONTEXT.md`) is one derived list — fetched ∩ has-articles ∩ not-excluded — that drives both the pill bar and the swipeable feed. Never maintain two separate lists.
- Category order always follows the fetched `categories` array's own order (`main` first); never re-sorted client-side.
- The filter store persists only the **excluded** category keys, never the checked ones. "Everything checked" is an empty store. A category the store has never seen (new source, new taxonomy entry) defaults to visible.
- The filter bottom sheet always lists the *full* fetched taxonomy (not just currently-visible categories), and applies every toggle live — no separate Apply/Save button.
- A news card's headline is never truncated with an ellipsis. Only the text block below the photo may scroll; the photo's own sizing is unchanged.
- A card's publish timestamp always shows both the absolute day/date *and* a live relative offset together (e.g. `Sun, Aug 23 · 3h ago`), computed at render time against the current clock — never frozen at fetch time.
- A Bengali-source article's timestamp renders entirely in Bengali (digits, month/weekday names, "ago" phrasing, day-before-month date order); an English-source article renders entirely in English. Never mixed.
- A missing or unparseable `publishedAt` omits the timestamp row entirely — no placeholder text, no guess.
- `dailystar` has no absolute timestamp at listing level (only a relative English phrase like "2 hours ago") and getting one would require an extra per-article HTTP request. By design, its `publishedAt` is approximate — parsed from that phrase, anchored to the scrape run's own start time. Never add a per-article fetch to improve this.
- The app bar's brand mark (badge + "NEWSHEAD" wordmark) is built from native Flutter widgets, not the flattened reference PNG in `docs/branding/` (that PNG has no real transparency and can't be safely re-cut — see the session's asset-analysis notes).

---

## Task 1: Per-source publish-timestamp parsing (Python)

**Files:**
- Create: `scraper/timestamps.py`
- Modify: `scraper/bengali_date.py` (rename `_MONTH_NAMES` → public `MONTH_NAMES`)
- Test: `tests/test_timestamps.py`

**Interfaces:**
- Produces: `timestamps.parse_published_at(source_slug: str, raw, run_started_at: datetime | None) -> str | None` — an ISO-8601 string with UTC offset, or `None` if `raw` is missing/unparseable for that source. Task 3 calls this directly.
- Produces: `bengali_date.MONTH_NAMES: dict[int, str]` (was private `_MONTH_NAMES`) — Task 1's own Bengali-datetime parser reads it; `bengali_date.format_bengali_date` keeps using it under its new public name.

- [ ] **Step 1: Rename `_MONTH_NAMES` to `MONTH_NAMES` in `scraper/bengali_date.py`**

In `scraper/bengali_date.py`, rename the module-level dict and its one usage:

```python
MONTH_NAMES = {
    1: "জানুয়ারি",
    2: "ফেব্রুয়ারি",
    3: "মার্চ",
    4: "এপ্রিল",
    5: "মে",
    6: "জুন",
    7: "জুলাই",
    8: "আগস্ট",
    9: "সেপ্টেম্বর",
    10: "অক্টোবর",
    11: "নভেম্বর",
    12: "ডিসেম্বর",
}


def format_bengali_date(iso_date):
    """Format an ISO date string ("2026-08-12") as a Bengali-language date
    string ("১২ আগস্ট, ২০২৬") for display in the epub."""
    parsed = date.fromisoformat(iso_date)
    day_bn = f"{parsed.day:02d}".translate(_DIGIT_MAP)
    year_bn = str(parsed.year).translate(_DIGIT_MAP)
    return f"{day_bn} {MONTH_NAMES[parsed.month]}, {year_bn}"
```

(Only the dict's name changes, at its definition and at the one call site inside `format_bengali_date`; `_DIGIT_MAP` stays private and unchanged.)

- [ ] **Step 2: Write the failing tests for `scraper/timestamps.py`**

Create `tests/test_timestamps.py`:

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from scraper.timestamps import parse_published_at

DHAKA_TZ = ZoneInfo("Asia/Dhaka")


def test_parse_published_at_dhakatribune_iso_offset():
    result = parse_published_at("dhakatribune", "2026-08-23T12:58:59+06:00", None)
    assert result == "2026-08-23T12:58:59+06:00"


def test_parse_published_at_ittefaq_iso_offset():
    result = parse_published_at("ittefaq", "2026-08-23T14:45:30+06:00", None)
    assert result == "2026-08-23T14:45:30+06:00"


def test_parse_published_at_dhakatribune_returns_none_for_garbage():
    assert parse_published_at("dhakatribune", "not a date", None) is None


def test_parse_published_at_dhakatribune_returns_none_for_missing_value():
    assert parse_published_at("dhakatribune", "", None) is None
    assert parse_published_at("dhakatribune", None, None) is None


def test_parse_published_at_prothomalo_epoch_ms():
    # epoch_ms=0 is 1970-01-01T00:00:00Z, i.e. 06:00 in Asia/Dhaka (UTC+6).
    assert parse_published_at("prothomalo", 0, None) == "1970-01-01T06:00:00+06:00"


def test_parse_published_at_prothomalo_returns_none_for_non_numeric():
    assert parse_published_at("prothomalo", "not-a-number", None) is None
    assert parse_published_at("prothomalo", None, None) is None


def test_parse_published_at_jugantor_bengali_am():
    result = parse_published_at("jugantor", "২৩ আগস্ট ২০২৬, ০৫:২১ এএম", None)
    parsed = datetime.fromisoformat(result)
    assert (parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute) == (
        2026,
        8,
        23,
        5,
        21,
    )


def test_parse_published_at_jugantor_bengali_pm():
    result = parse_published_at("jugantor", "২৩ আগস্ট ২০২৬, ০৫:২১ পিএম", None)
    parsed = datetime.fromisoformat(result)
    assert parsed.hour == 17


def test_parse_published_at_jugantor_bengali_12am_is_midnight():
    result = parse_published_at("jugantor", "০১ জানুয়ারি ২০২৬, ১২:০০ এএম", None)
    parsed = datetime.fromisoformat(result)
    assert parsed.hour == 0


def test_parse_published_at_jugantor_returns_none_for_unrecognized_text():
    assert parse_published_at("jugantor", "unknown format", None) is None
    assert parse_published_at("jugantor", "", None) is None


def test_parse_published_at_dailystar_hours_ago():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "2 hours ago", anchor) == "2026-08-23T12:00:00+06:00"


def test_parse_published_at_dailystar_minutes_ago():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "45 minutes ago", anchor) == "2026-08-23T13:15:00+06:00"


def test_parse_published_at_dailystar_yesterday():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "Yesterday", anchor) == "2026-08-22T14:00:00+06:00"


def test_parse_published_at_dailystar_just_now():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "Just now", anchor) == "2026-08-23T14:00:00+06:00"


def test_parse_published_at_dailystar_returns_none_without_an_anchor():
    assert parse_published_at("dailystar", "2 hours ago", None) is None


def test_parse_published_at_dailystar_returns_none_for_unrecognized_text():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "sometime", anchor) is None


def test_parse_published_at_returns_none_for_an_unknown_source():
    assert parse_published_at("madeup", "2026-08-23T12:00:00+06:00", None) is None
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `.venv/bin/python -m pytest tests/test_timestamps.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'scraper.timestamps'`

- [ ] **Step 4: Implement `scraper/timestamps.py`**

```python
"""Normalize each source's raw listing-time signal into a publishedAt
instant.

Every source module's list_articles() already captures a raw per-article
time signal into item["listing_time"] (see scraper/sources/*.py) — this
module is the one place that knows how to turn each source's particular
raw shape into a real, timezone-aware datetime, or None if it can't be
parsed confidently. Never guess: an unparseable value returns None rather
than a wrong instant.
"""
import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from . import bengali_date

DHAKA_TZ = ZoneInfo("Asia/Dhaka")

_BN_TO_ASCII_DIGITS = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")
_BN_MONTH_TO_NUM = {name: num for num, name in bengali_date.MONTH_NAMES.items()}

_BENGALI_ABSOLUTE_RE = re.compile(
    r"(?P<day>[০-৯]{1,2})\s+(?P<month>\S+)\s+(?P<year>[০-৯]{4}),\s*"
    r"(?P<hour>[০-৯]{1,2}):(?P<minute>[০-৯]{2})\s*(?P<ampm>\S+)"
)

_RELATIVE_ENGLISH_RE = re.compile(
    r"(?P<n>\d+)\s*(?P<unit>second|minute|hour|day|week|month|year)s?\s+ago",
    re.IGNORECASE,
)

_UNIT_SECONDS = {
    "second": 1,
    "minute": 60,
    "hour": 3600,
    "day": 86400,
    "week": 604800,
    "month": 2592000,
    "year": 31536000,
}


def _parse_iso_offset(raw):
    """dhakatribune / ittefaq: an ISO-8601 string with a UTC offset already
    attached, e.g. "2026-08-23T12:58:59+06:00"."""
    if not raw or not isinstance(raw, str):
        return None
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return None


def _parse_epoch_ms(raw):
    """prothomalo: a Quintype CMS `published-at` epoch-millisecond int."""
    if not isinstance(raw, (int, float)):
        return None
    try:
        return datetime.fromtimestamp(raw / 1000, tz=DHAKA_TZ)
    except (OverflowError, OSError, ValueError):
        return None


def _parse_bengali_absolute(raw):
    """jugantor: a full Bengali-language absolute datetime, e.g.
    "২৩ আগস্ট ২০২৬, ০৫:২১ এএম" ("23 August 2026, 05:21 AM")."""
    if not raw or not isinstance(raw, str):
        return None
    match = _BENGALI_ABSOLUTE_RE.search(raw)
    if not match:
        return None
    month = _BN_MONTH_TO_NUM.get(match.group("month"))
    if month is None:
        return None
    day = int(match.group("day").translate(_BN_TO_ASCII_DIGITS))
    year = int(match.group("year").translate(_BN_TO_ASCII_DIGITS))
    hour = int(match.group("hour").translate(_BN_TO_ASCII_DIGITS))
    minute = int(match.group("minute").translate(_BN_TO_ASCII_DIGITS))
    ampm = match.group("ampm")
    if ampm.startswith("প"):  # পিএম = PM
        if hour != 12:
            hour += 12
    elif hour == 12:  # এএম = AM
        hour = 0
    try:
        return datetime(year, month, day, hour, minute, tzinfo=DHAKA_TZ)
    except ValueError:
        return None


def _parse_relative_english(raw, anchor):
    """dailystar: a relative phrase off the page's own listing card, e.g.
    "2 hours ago". anchor is the scrape run's own start time — the result
    is necessarily approximate, rounded to whatever granularity the site's
    own listing already used."""
    if not raw or not isinstance(raw, str) or anchor is None:
        return None
    text = raw.strip().lower()
    if text in ("just now", "moments ago"):
        return anchor
    if text == "yesterday":
        return anchor - timedelta(days=1)
    match = _RELATIVE_ENGLISH_RE.search(text)
    if not match:
        return None
    n = int(match.group("n"))
    unit = match.group("unit").lower()
    return anchor - timedelta(seconds=n * _UNIT_SECONDS[unit])


_SOURCE_PARSERS = {
    "dhakatribune": lambda raw, anchor: _parse_iso_offset(raw),
    "ittefaq": lambda raw, anchor: _parse_iso_offset(raw),
    "prothomalo": lambda raw, anchor: _parse_epoch_ms(raw),
    "jugantor": lambda raw, anchor: _parse_bengali_absolute(raw),
    "dailystar": lambda raw, anchor: _parse_relative_english(raw, anchor),
}


def parse_published_at(source_slug, raw, run_started_at):
    """Returns an ISO-8601 string (with UTC offset) for the given source's
    raw listing-time signal, or None if it's missing/unparseable. Never
    raises — an unrecognized shape is exactly the case this returns None
    for."""
    parser = _SOURCE_PARSERS.get(source_slug)
    if parser is None:
        return None
    result = parser(raw, run_started_at)
    return result.isoformat() if result is not None else None
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `.venv/bin/python -m pytest tests/test_timestamps.py -v`
Expected: 17 passed

- [ ] **Step 6: Run the full Python suite to check for regressions**

Run: `.venv/bin/python -m pytest tests/ -v`
Expected: all passed (31 previous + 17 new = 48)

- [ ] **Step 7: Commit**

```bash
git add scraper/timestamps.py scraper/bengali_date.py tests/test_timestamps.py
git commit -m "feat(scraper): add per-source publish-timestamp parsing
docs(bengali_date): expose MONTH_NAMES publicly for timestamps.py to reuse"
```

---

## Task 2: Propagate Prothom Alo's raw epoch timestamp

**Files:**
- Modify: `scraper/sources/prothomalo.py:214-221`
- Test: `tests/test_prothomalo_sections.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `parse_articles()`'s returned item dicts now carry the real epoch-ms value in `listing_time` (was hardcoded to `""`) — Task 3's `build_article()` reads this via `item.get("listing_time")`.

**Context:** `prothomalo.py`'s `parse_articles()` already reads each story's `published-at` epoch to *filter* by date (`_story_date`), but then discards it when building the returned item dict — `"listing_time": ""` is a hardcoded placeholder. Every other source already populates `listing_time` with its own raw signal; Prothom Alo is the one gap.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_prothomalo_sections.py`:

```python
import json
from datetime import datetime
from zoneinfo import ZoneInfo

from scraper.sources.prothomalo import parse_articles

DHAKA_TZ = ZoneInfo("Asia/Dhaka")


def _static_page_html(stories):
    payload = {"qt": {"data": {"collection": {"items": [
        {"type": "story", "story": story} for story in stories
    ]}}}}
    return '<script type="application/json" id="static-page">' + json.dumps(payload) + "</script>"


def test_parse_articles_propagates_the_raw_published_at_epoch_into_listing_time():
    published = datetime(2026, 8, 23, 10, 0, tzinfo=DHAKA_TZ)
    epoch_ms = int(published.timestamp() * 1000)
    html = _static_page_html([
        {
            "url": "https://www.prothomalo.com/bangladesh/abc123",
            "headline": "Headline",
            "subheadline": "Summary",
            "published-at": epoch_ms,
            "hero-image-s3-key": None,
        }
    ])

    articles = parse_articles(html, "2026-08-23")

    assert len(articles) == 1
    assert articles[0]["listing_time"] == epoch_ms
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `.venv/bin/python -m pytest tests/test_prothomalo_sections.py::test_parse_articles_propagates_the_raw_published_at_epoch_into_listing_time -v`
Expected: FAIL — `assert '' == 1787544000000` (or similar; the current hardcoded `""` doesn't equal the epoch)

- [ ] **Step 3: Fix `scraper/sources/prothomalo.py`**

In `parse_articles()`, change:

```python
        articles.append(
            {
                "url": story["url"],
                "headline": _normalize(story.get("headline") or ""),
                "summary": _normalize(story.get("subheadline") or ""),
                "listing_time": "",
                "thumbnail": thumbnail,
            }
        )
```

to:

```python
        articles.append(
            {
                "url": story["url"],
                "headline": _normalize(story.get("headline") or ""),
                "summary": _normalize(story.get("subheadline") or ""),
                "listing_time": story.get("published-at"),
                "thumbnail": thumbnail,
            }
        )
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `.venv/bin/python -m pytest tests/test_prothomalo_sections.py -v`
Expected: all passed

- [ ] **Step 5: Run the full Python suite to check for regressions**

Run: `.venv/bin/python -m pytest tests/ -v`
Expected: all passed

- [ ] **Step 6: Commit**

```bash
git add scraper/sources/prothomalo.py tests/test_prothomalo_sections.py
git commit -m "fix(prothomalo_source): propagate the raw published-at epoch into listing_time"
```

---

## Task 3: Wire `language` and `publishedAt` into the published JSON

**Files:**
- Modify: `scraper/generate_data.py` (imports, `SOURCE_LANGUAGE`, `build_article`, `collect_source_articles`, `main`)
- Test: `tests/test_generate_data.py`

**Interfaces:**
- Consumes: `timestamps.parse_published_at` (Task 1), the fixed `prothomalo.parse_articles` (Task 2).
- Produces: every article dict in `articles.json` now has `"language": "bn" | "en"` and `"publishedAt": <iso-string> | None`. The Flutter side (Task 5) reads these two keys by name.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_generate_data.py` (near the existing `build_article`-adjacent tests — check the top of the file for its existing imports before adding these):

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from scraper.generate_data import build_article, SOURCE_LANGUAGE

DHAKA_TZ = ZoneInfo("Asia/Dhaka")


def test_build_article_includes_language_for_a_bengali_source():
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": ""}
    article = build_article("jugantor", "Jugantor", "main", item, "", None)
    assert article["language"] == "bn"


def test_build_article_includes_language_for_an_english_source():
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": ""}
    article = build_article("dailystar", "The Daily Star", "main", item, "", None)
    assert article["language"] == "en"


def test_source_language_covers_every_configured_source():
    from scraper import config

    for source_slug in config.SOURCES:
        assert source_slug in SOURCE_LANGUAGE


def test_build_article_includes_a_parsed_published_at():
    item = {
        "url": "https://example.com/a",
        "headline": "H",
        "summary": "S",
        "listing_time": "2026-08-23T12:58:59+06:00",
    }
    article = build_article("dhakatribune", "Dhaka Tribune", "main", item, "", None)
    assert article["publishedAt"] == "2026-08-23T12:58:59+06:00"


def test_build_article_leaves_published_at_none_when_unparseable():
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": ""}
    article = build_article("dhakatribune", "Dhaka Tribune", "main", item, "", None)
    assert article["publishedAt"] is None


def test_build_article_uses_run_started_at_to_anchor_dailystar_relative_time():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": "2 hours ago"}
    article = build_article("dailystar", "The Daily Star", "main", item, "", anchor)
    assert article["publishedAt"] == "2026-08-23T12:00:00+06:00"
```

Check `scraper.config.SOURCES` exists (it's already imported/used elsewhere in `generate_data.py` as `config.SOURCES`) before relying on it in the third test above.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `.venv/bin/python -m pytest tests/test_generate_data.py -v -k "language or published_at"`
Expected: FAIL — `TypeError: build_article() missing 1 required positional argument: 'run_started_at'` (and `ImportError` for `SOURCE_LANGUAGE` before that, since neither exists yet)

- [ ] **Step 3: Implement the changes in `scraper/generate_data.py`**

Add the import (alongside the existing `from . import config`):

```python
from . import config, timestamps
```

Add `SOURCE_LANGUAGE`, right after the existing `SOURCE_DISPLAY_NAMES` dict:

```python
# Per-source display language for formatting an article's publishedAt on
# the client — mirrors the bengali_date/english_date split each source
# module already uses for its own format_date().
SOURCE_LANGUAGE = {
    "jugantor": "bn",
    "prothomalo": "bn",
    "dhakatribune": "en",
    "dailystar": "en",
    "ittefaq": "bn",
}
```

Change `build_article` (currently at line 310) from:

```python
def build_article(source_slug, source_name, category, item, fallback_image_url):
    return {
        "id": make_article_id(source_slug, item["url"]),
        "category": category,
        "source": source_name,
        "headline": item.get("headline", ""),
        "snippet": truncate_snippet(item.get("summary", "")),
        "imageUrl": item.get("thumbnail") or fallback_image_url,
        "articleUrl": item["url"],
    }
```

to:

```python
def build_article(source_slug, source_name, category, item, fallback_image_url, run_started_at):
    return {
        "id": make_article_id(source_slug, item["url"]),
        "category": category,
        "source": source_name,
        "headline": item.get("headline", ""),
        "snippet": truncate_snippet(item.get("summary", "")),
        "imageUrl": item.get("thumbnail") or fallback_image_url,
        "articleUrl": item["url"],
        "language": SOURCE_LANGUAGE.get(source_slug, "en"),
        "publishedAt": timestamps.parse_published_at(
            source_slug, item.get("listing_time"), run_started_at
        ),
    }
```

In `collect_source_articles` (`scraper/generate_data.py:340-397`), add the `run_started_at` parameter and thread it through both `build_article` call sites:

```python
def collect_source_articles(source_slug, edition_date, run_started_at):
    source_module = importlib.import_module(f"scraper.sources.{source_slug}")
    source_name = SOURCE_DISPLAY_NAMES.get(source_slug, source_slug)

    try:
        sections = source_module.discover_sections()
    except Exception as exc:
        logger.warning("Skipping source %s: could not discover sections: %s", source_slug, exc)
        return []

    if not sections:
        logger.warning("Skipping source %s: no sections discovered", source_slug)
        return []

    try:
        fallback_image_url = source_module.get_cover_logo_url()
    except Exception:
        fallback_image_url = ""

    articles = []
    seen_urls = set()

    # First section is treated as this source's top/front listing -> "main".
    main_slug, _main_name = sections[0]
    try:
        main_items = source_module.list_articles(main_slug, edition_date)
    except Exception as exc:
        logger.warning("Skipping %s section %s: %s", source_slug, main_slug, exc)
        main_items = []

    for item in main_items:
        if not item.get("url") or item["url"] in seen_urls:
            continue
        item = enrich_item(source_module, item)
        seen_urls.add(item["url"])
        articles.append(
            build_article(source_slug, source_name, "main", item, fallback_image_url, run_started_at)
        )

    # Remaining sections are classified into canonical categories via
    # SECTION_CATEGORY_MAP (explicit, wins outright) or, failing that,
    # keyword matching.
    for slug, section_name in sections[1:]:
        try:
            items = source_module.list_articles(slug, edition_date)
        except Exception as exc:
            logger.warning("Skipping %s section %s: %s", source_slug, slug, exc)
            continue

        for item in items:
            if not item.get("url") or item["url"] in seen_urls:
                continue
            category = classify_article_category(source_slug, slug, section_name, item.get("headline", ""))
            if category is None:
                continue
            item = enrich_item(source_module, item)
            seen_urls.add(item["url"])
            articles.append(
                build_article(source_slug, source_name, category, item, fallback_image_url, run_started_at)
            )

    return articles
```

In `main()` (`scraper/generate_data.py:433-457`), capture the full instant once and pass it down:

```python
def main():
    run_started_at = datetime.now(DHAKA_TZ)
    edition_date = run_started_at.date().isoformat()

    all_articles = []
    for source_slug in config.SOURCES:
        try:
            source_articles = collect_source_articles(source_slug, edition_date, run_started_at)
        except Exception as exc:
            logger.warning("Skipping source %s: %s", source_slug, exc)
            continue
        logger.info("%s: collected %d article(s)", source_slug, len(source_articles))
        all_articles.extend(source_articles)

    interleaved_articles = interleave_by_source(all_articles)

    if not interleaved_articles:
        logger.error("No articles were scraped from any source; not writing output.")
        raise SystemExit(1)

    output = build_output(edition_date, interleaved_articles)

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    logger.info("Wrote %d article(s) to %s", len(interleaved_articles), OUTPUT_PATH)
```

(Only `edition_date`'s computation and the two `collect_source_articles` call sites change — everything else in `main()` is unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `.venv/bin/python -m pytest tests/test_generate_data.py -v`
Expected: all passed

- [ ] **Step 5: Run the full Python suite to check for regressions**

Run: `.venv/bin/python -m pytest tests/ -v`
Expected: all passed

- [ ] **Step 6: Manually verify the real pipeline still runs end-to-end**

Run: `.venv/bin/python scripts/generate.py` (from the repo root)
Expected: exits 0, and `articles.json` articles all have non-null `language` and a `publishedAt` that's either an ISO string or `null` (spot check a few with `python3 -c "import json; d=json.load(open('articles.json')); print(d['articles'][0])"`).

- [ ] **Step 7: Commit**

```bash
git add scraper/generate_data.py tests/test_generate_data.py
git commit -m "feat(generate_data): emit language and publishedAt on every article"
```

---

## Task 4: `NewsArticle` model gains `language` and `publishedAt`

**Files:**
- Modify: `app/lib/models/news_article.dart`
- Test: `app/test/models/news_article_test.dart`

**Interfaces:**
- Produces: `NewsArticle.language: String` (defaults `'en'`), `NewsArticle.publishedAt: DateTime?` (defaults `null`). Both optional constructor params, so every existing call site/test fixture that omits them keeps compiling unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/models/news_article_test.dart`:

```dart
  test('language defaults to en and publishedAt defaults to null when omitted', () {
    const article = NewsArticle(
      id: 'a1',
      category: 'politics',
      source: 'Jugantor',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://example.com/i.jpg',
      articleUrl: 'https://example.com/a',
    );

    expect(article.language, 'en');
    expect(article.publishedAt, isNull);
  });

  test('stores language and publishedAt when provided', () {
    final publishedAt = DateTime.utc(2026, 8, 23, 10, 0);
    final article = NewsArticle(
      id: 'a1',
      category: 'politics',
      source: 'Jugantor',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://example.com/i.jpg',
      articleUrl: 'https://example.com/a',
      language: 'bn',
      publishedAt: publishedAt,
    );

    expect(article.language, 'bn');
    expect(article.publishedAt, publishedAt);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/models/news_article_test.dart`
Expected: FAIL — `The named parameter 'language' isn't defined`

- [ ] **Step 3: Implement the model change**

Replace `app/lib/models/news_article.dart` entirely with:

```dart
class NewsArticle {
  final String id;
  final String category;
  final String source;
  final String headline;
  final String snippet;
  final String imageUrl;
  final String articleUrl;
  final String language;
  final DateTime? publishedAt;

  const NewsArticle({
    required this.id,
    required this.category,
    required this.source,
    required this.headline,
    required this.snippet,
    required this.imageUrl,
    required this.articleUrl,
    this.language = 'en',
    this.publishedAt,
  });
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/models/news_article_test.dart`
Expected: 3 passed

- [ ] **Step 5: Run the full Flutter suite to check for regressions**

Run: `cd app && flutter test`
Expected: all passed (no other file constructs `NewsArticle` with positional args, so the new optional params shouldn't break anything)

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/news_article.dart app/test/models/news_article_test.dart
git commit -m "feat(news_article): add language and publishedAt fields"
```

---

## Task 5: Parse `language`/`publishedAt` in `article_repository.dart`

**Files:**
- Modify: `app/lib/data/article_repository.dart:12-30`
- Test: `app/test/data/article_repository_test.dart`

**Interfaces:**
- Consumes: `NewsArticle.language`/`publishedAt` (Task 4).
- Produces: `parseArticles()` now populates both fields from the JSON's `language`/`publishedAt` keys, defaulting/nulling out gracefully on anything missing or malformed — same "skip, don't crash" spirit as every other field in this function.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/data/article_repository_test.dart` (alongside the existing JSON fixture constants near the top):

```dart
const _jsonWithTimestamps = '''
{
  "generated_at": "2026-08-20",
  "categories": [{"key": "main", "label": "Main"}],
  "articles": [
    {"id": "a1", "category": "main", "source": "Prothom Alo", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1", "language": "bn", "publishedAt": "2026-08-23T10:00:00+06:00"},
    {"id": "a2", "category": "main", "source": "The Daily Star", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2", "language": "en", "publishedAt": "not-a-timestamp"},
    {"id": "a3", "category": "main", "source": "The Daily Star", "headline": "H3", "snippet": "S3", "imageUrl": "https://example.com/3.jpg", "articleUrl": "https://example.com/a3"}
  ]
}
''';
```

and these tests inside `main()`:

```dart
  test('parseArticles parses language and publishedAt when present', () {
    final articles = parseArticles(_jsonWithTimestamps);
    expect(articles[0].language, 'bn');
    expect(articles[0].publishedAt, DateTime.parse('2026-08-23T10:00:00+06:00'));
  });

  test('parseArticles leaves publishedAt null for an unparseable timestamp', () {
    final articles = parseArticles(_jsonWithTimestamps);
    expect(articles[1].language, 'en');
    expect(articles[1].publishedAt, isNull);
  });

  test('parseArticles defaults language to en and publishedAt to null when both are absent', () {
    final articles = parseArticles(_jsonWithTimestamps);
    expect(articles[2].language, 'en');
    expect(articles[2].publishedAt, isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/data/article_repository_test.dart`
Expected: FAIL — `articles[0].language` is `'en'` not `'bn'` (the field is parsed but not from JSON yet — it's just the model default)

- [ ] **Step 3: Implement the parsing change**

In `app/lib/data/article_repository.dart`, change `parseArticles` from:

```dart
List<NewsArticle> parseArticles(String jsonString) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final rawArticles = decoded['articles'] as List<dynamic>? ?? [];

  final articles = <NewsArticle>[];
  for (final raw in rawArticles) {
    try {
      final map = raw as Map<String, dynamic>;
      articles.add(NewsArticle(
        id: map['id'] as String,
        category: map['category'] as String,
        source: map['source'] as String,
        headline: map['headline'] as String,
        snippet: (map['snippet'] as String?) ?? '',
        imageUrl: map['imageUrl'] as String,
        articleUrl: map['articleUrl'] as String,
      ));
    } catch (_) {
      continue;
    }
  }
  return articles;
}
```

to:

```dart
DateTime? _tryParsePublishedAt(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

List<NewsArticle> parseArticles(String jsonString) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final rawArticles = decoded['articles'] as List<dynamic>? ?? [];

  final articles = <NewsArticle>[];
  for (final raw in rawArticles) {
    try {
      final map = raw as Map<String, dynamic>;
      articles.add(NewsArticle(
        id: map['id'] as String,
        category: map['category'] as String,
        source: map['source'] as String,
        headline: map['headline'] as String,
        snippet: (map['snippet'] as String?) ?? '',
        imageUrl: map['imageUrl'] as String,
        articleUrl: map['articleUrl'] as String,
        language: (map['language'] as String?) ?? 'en',
        publishedAt: _tryParsePublishedAt(map['publishedAt']),
      ));
    } catch (_) {
      continue;
    }
  }
  return articles;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/data/article_repository_test.dart`
Expected: all passed

- [ ] **Step 5: Run the full Flutter suite to check for regressions**

Run: `cd app && flutter test`
Expected: all passed

- [ ] **Step 6: Commit**

```bash
git add app/lib/data/article_repository.dart app/test/data/article_repository_test.dart
git commit -m "feat(article_repository): parse language and publishedAt per article"
```

---

## Task 6: Bilingual publish-timestamp formatter

**Files:**
- Create: `app/lib/data/timestamp_format.dart`
- Test: `app/test/data/timestamp_format_test.dart`

**Interfaces:**
- Produces: `formatPublishedAt(DateTime publishedAt, String language, {DateTime? now}) -> String`. Task 10 (`news_card.dart`) calls this directly.

- [ ] **Step 1: Write the failing tests**

Create `app/test/data/timestamp_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/timestamp_format.dart';

void main() {
  test('formats an English source with hours-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 23, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Sun, Aug 23 · 3h ago');
  });

  test('formats a Bengali source with hours-ago relative time in Bengali', () {
    final publishedAt = DateTime(2026, 8, 23, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'bn', now: now), 'রবি, ২৩ আগস্ট · ৩ ঘণ্টা আগে');
  });

  test('formats minutes-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 23, 12, 15);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Sun, Aug 23 · 45m ago');
  });

  test('formats days-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 21, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Fri, Aug 21 · 2d ago');
  });

  test('clamps a future timestamp (clock skew) to just now in English', () {
    final publishedAt = DateTime(2026, 8, 23, 13, 5);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Sun, Aug 23 · just now');
  });

  test('clamps a future timestamp (clock skew) to just now in Bengali', () {
    final publishedAt = DateTime(2026, 8, 23, 13, 5);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'bn', now: now), 'রবি, ২৩ আগস্ট · এইমাত্র');
  });

  test('defaults now to the current clock when not provided', () {
    final publishedAt = DateTime.now().subtract(const Duration(minutes: 5));
    expect(formatPublishedAt(publishedAt, 'en'), contains('ago'));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/data/timestamp_format_test.dart`
Expected: FAIL — `Error: Not found: 'package:newshead/data/timestamp_format.dart'`

- [ ] **Step 3: Implement `app/lib/data/timestamp_format.dart`**

```dart
const _enWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _bnWeekdays = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহস্পতি', 'শুক্র', 'শনি', 'রবি'];
const _bnMonths = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
];
const _bnDigits = {
  '0': '০', '1': '১', '2': '২', '3': '৩', '4': '৪',
  '5': '৫', '6': '৬', '7': '৭', '8': '৮', '9': '৯',
};

String _toBengaliDigits(String input) =>
    input.split('').map((c) => _bnDigits[c] ?? c).join();

String _formatRelative(Duration diff, bool isBengali) {
  final seconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
  if (seconds < 60) {
    return isBengali ? 'এইমাত্র' : 'just now';
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return isBengali ? '${_toBengaliDigits('$minutes')} মিনিট আগে' : '${minutes}m ago';
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return isBengali ? '${_toBengaliDigits('$hours')} ঘণ্টা আগে' : '${hours}h ago';
  }
  final days = hours ~/ 24;
  return isBengali ? '${_toBengaliDigits('$days')} দিন আগে' : '${days}d ago';
}

/// The absolute day/date and a live relative offset together, e.g.
/// "Sun, Aug 23 · 3h ago" or, for a Bengali-language source, entirely in
/// Bengali with the day-before-month date order that language uses:
/// "রবি, ২৩ আগস্ট · ৩ ঘণ্টা আগে". [now] defaults to the current clock;
/// pass it explicitly in tests for a deterministic result.
String formatPublishedAt(DateTime publishedAt, String language, {DateTime? now}) {
  final effectiveNow = now ?? DateTime.now();
  final local = publishedAt.toLocal();
  final isBengali = language == 'bn';
  final weekday = (isBengali ? _bnWeekdays : _enWeekdays)[local.weekday - 1];
  final month = (isBengali ? _bnMonths : _enMonths)[local.month - 1];
  final day = isBengali ? _toBengaliDigits('${local.day}') : '${local.day}';
  final datePart = isBengali ? '$day $month' : '$month $day';
  final relative = _formatRelative(effectiveNow.difference(publishedAt), isBengali);
  return '$weekday, $datePart · $relative';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/data/timestamp_format_test.dart`
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/timestamp_format.dart app/test/data/timestamp_format_test.dart
git commit -m "feat(timestamp_format): add the bilingual publishedAt formatter"
```

---

## Task 7: Persisted category filter store

**Files:**
- Modify: `app/pubspec.yaml` (add `shared_preferences`)
- Create: `app/lib/data/category_filter_store.dart`
- Test: `app/test/data/category_filter_store_test.dart`

**Interfaces:**
- Produces: `abstract class CategoryFilterStore { Future<Set<String>> readExcludedKeys(); Future<void> writeExcludedKeys(Set<String> keys); }` and `class SharedPreferencesCategoryFilterStore implements CategoryFilterStore`. Task 12 (`home_screen.dart`) depends on the interface; `main.dart` (Task 13) instantiates the concrete class; tests elsewhere use their own in-memory fake implementing the same interface (same pattern as `ArticleCache`/`InMemoryArticleCache`).

- [ ] **Step 1: Add the dependency**

Run: `cd app && flutter pub add shared_preferences`
Expected: `pubspec.yaml` gains `shared_preferences: ^2.5.5` (or whatever the resolver picks — don't hand-edit the version, let `pub add` write it)

- [ ] **Step 2: Write the failing tests**

Create `app/test/data/category_filter_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newshead/data/category_filter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('readExcludedKeys returns an empty set when nothing is stored', () async {
    final store = SharedPreferencesCategoryFilterStore();
    expect(await store.readExcludedKeys(), isEmpty);
  });

  test('writeExcludedKeys then readExcludedKeys round-trips the same set', () async {
    final store = SharedPreferencesCategoryFilterStore();
    await store.writeExcludedKeys({'sports', 'entertainment'});
    expect(await store.readExcludedKeys(), {'sports', 'entertainment'});
  });

  test('writeExcludedKeys with an empty set clears previously stored keys', () async {
    final store = SharedPreferencesCategoryFilterStore();
    await store.writeExcludedKeys({'sports'});
    await store.writeExcludedKeys({});
    expect(await store.readExcludedKeys(), isEmpty);
  });
}
```


- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd app && flutter test test/data/category_filter_store_test.dart`
Expected: FAIL — `Error: Not found: 'package:newshead/data/category_filter_store.dart'`

- [ ] **Step 4: Implement `app/lib/data/category_filter_store.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// The reader's category filter choice, stored as the set of *excluded*
/// category keys — never the checked ones. See CONTEXT.md's "Visible
/// Category" entry for why: an empty store means everything is checked,
/// and a category the store has never seen defaults to visible.
abstract class CategoryFilterStore {
  Future<Set<String>> readExcludedKeys();
  Future<void> writeExcludedKeys(Set<String> keys);
}

const _kExcludedCategoryKeysPref = 'excluded_category_keys';

class SharedPreferencesCategoryFilterStore implements CategoryFilterStore {
  @override
  Future<Set<String>> readExcludedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kExcludedCategoryKeysPref) ?? const []).toSet();
  }

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kExcludedCategoryKeysPref, keys.toList());
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd app && flutter test test/data/category_filter_store_test.dart`
Expected: 3 passed

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/data/category_filter_store.dart app/test/data/category_filter_store_test.dart
git commit -m "feat(category_filter_store): persist the excluded-category set via shared_preferences"
```

---

## Task 8: `visibleCategories()` — the one derived list

**Files:**
- Create: `app/lib/data/category_visibility.dart`
- Test: `app/test/data/category_visibility_test.dart`

**Interfaces:**
- Consumes: `AppCategory` (existing), `NewsArticle.category` (existing).
- Produces: `visibleCategories({required List<AppCategory> fetchedCategories, required List<NewsArticle> articles, required Set<String> excludedKeys}) -> List<AppCategory>`. Task 12 (`home_screen.dart`) calls this on every rebuild that could change visibility (initial load, refresh, filter toggle).

- [ ] **Step 1: Write the failing tests**

Create `app/test/data/category_visibility_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/category_visibility.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/news_article.dart';

const _categories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'politics', label: 'Politics'),
  AppCategory(key: 'sports', label: 'Sports'),
];

NewsArticle _articleIn(String category) => NewsArticle(
      id: 'id-$category',
      category: category,
      source: 'Test',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://example.com/i.jpg',
      articleUrl: 'https://example.com/a',
    );

void main() {
  test('keeps only categories that have at least one article', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('main'), _articleIn('politics')],
      excludedKeys: const {},
    );
    expect(result, [
      const AppCategory(key: 'main', label: 'Main'),
      const AppCategory(key: 'politics', label: 'Politics'),
    ]);
  });

  test('drops a category the reader has excluded even if it has articles', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('main'), _articleIn('politics')],
      excludedKeys: const {'politics'},
    );
    expect(result, [const AppCategory(key: 'main', label: 'Main')]);
  });

  test('preserves the fetched categories order, not article order', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('sports'), _articleIn('main'), _articleIn('politics')],
      excludedKeys: const {},
    );
    expect(result.map((c) => c.key), ['main', 'politics', 'sports']);
  });

  test('returns an empty list when every category is empty or excluded', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: const [],
      excludedKeys: const {},
    );
    expect(result, isEmpty);
  });

  test('a category unknown to the excluded set defaults to visible', () {
    // Simulates a brand-new category the reader has never seen/excluded.
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('main')],
      excludedKeys: const {'some-other-category-the-reader-excluded-earlier'},
    );
    expect(result, [const AppCategory(key: 'main', label: 'Main')]);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/data/category_visibility_test.dart`
Expected: FAIL — `Error: Not found: 'package:newshead/data/category_visibility.dart'`

- [ ] **Step 3: Implement `app/lib/data/category_visibility.dart`**

```dart
import '../models/app_category.dart';
import '../models/news_article.dart';

/// The one list that drives both the pill bar and the swipeable feed: a
/// fetched category is visible only if it has at least one article *and*
/// the reader hasn't excluded it. Always in the fetched list's own order.
List<AppCategory> visibleCategories({
  required List<AppCategory> fetchedCategories,
  required List<NewsArticle> articles,
  required Set<String> excludedKeys,
}) {
  final categoriesWithArticles = articles.map((a) => a.category).toSet();
  return fetchedCategories
      .where((c) => categoriesWithArticles.contains(c.key))
      .where((c) => !excludedKeys.contains(c.key))
      .toList();
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/data/category_visibility_test.dart`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/category_visibility.dart app/test/data/category_visibility_test.dart
git commit -m "feat(category_visibility): add the fetched+has-articles+not-excluded derivation"
```

---

## Task 9: `BrandMark` widget (app bar branding)

**Files:**
- Modify: `app/pubspec.yaml` (add `google_fonts`)
- Create: `app/lib/widgets/brand_mark.dart`
- Test: `app/test/widgets/brand_mark_test.dart`

**Interfaces:**
- Produces: `class BrandMark extends StatelessWidget` (no constructor params beyond `key`). Task 12 (`home_screen.dart`) places it in the app bar row.

- [ ] **Step 1: Add the dependency**

Run: `cd app && flutter pub add google_fonts`
Expected: `pubspec.yaml` gains `google_fonts: ^8.2.1` (or whatever the resolver picks)

- [ ] **Step 2: Write the failing test**

Create `app/test/widgets/brand_mark_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/widgets/brand_mark.dart';

void main() {
  testWidgets('renders the NEWSHEAD wordmark and the chevron badge', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandMark()));
    await tester.pump();

    expect(find.text('NEWSHEAD'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd app && flutter test test/widgets/brand_mark_test.dart`
Expected: FAIL — `Error: Not found: 'package:newshead/widgets/brand_mark.dart'`

- [ ] **Step 4: Implement `app/lib/widgets/brand_mark.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app bar's brand mark: the same red badge + black chevron as the
/// OS app icon (app/assets/icon/icon.png), reproduced as native widgets
/// rather than that flattened PNG — see this feature's plan for why (no
/// real transparency in the export, and the chevron/canvas colors are too
/// close to safely auto-key). "NEWS" in white, "HEAD" in the brand red,
/// both in Anton to match the approved lockup concept.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  static const _accent = Color(0xFFE1483A);
  static const _chevronColor = Color(0xFF121212);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.chevron_right, color: _chevronColor, size: 18),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'NEWS',
                style: GoogleFonts.anton(color: Colors.white, fontSize: 18),
              ),
              TextSpan(
                text: 'HEAD',
                style: GoogleFonts.anton(color: _accent, fontSize: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd app && flutter test test/widgets/brand_mark_test.dart`
Expected: 1 passed

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/widgets/brand_mark.dart app/test/widgets/brand_mark_test.dart
git commit -m "feat(brand_mark): add the app-bar badge + Anton wordmark widget"
```

---

## Task 10: News card — untruncated headline, scrollable overflow, timestamp row

**Files:**
- Modify: `app/lib/widgets/news_card.dart`
- Test: `app/test/widgets/news_card_test.dart`

**Interfaces:**
- Consumes: `NewsArticle.language`/`publishedAt` (Task 4), `formatPublishedAt` (Task 6).

- [ ] **Step 1: Write the failing tests**

Add to `app/test/widgets/news_card_test.dart` (inside `main()`, alongside the two existing tests):

```dart
  testWidgets('never truncates a long headline', (tester) async {
    final longHeadline = List.filled(300, 'A').join();
    final longArticle = NewsArticle(
      id: 'a2',
      category: 'politics',
      source: 'Jugantor',
      headline: longHeadline,
      snippet: 'snippet',
      imageUrl: 'https://example.com/image.jpg',
      articleUrl: 'https://example.com/article',
    );
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(article: longArticle, imageProviderBuilder: (_) => FailingImageProvider()),
    ));
    await tester.pump();

    final headlineWidget = tester.widget<Text>(find.text(longHeadline));
    expect(headlineWidget.maxLines, isNull);
    expect(headlineWidget.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('shows the formatted publish timestamp when present', (tester) async {
    final withTimestamp = NewsArticle(
      id: 'a3',
      category: 'politics',
      source: 'Jugantor',
      headline: 'Headline',
      snippet: 'snippet',
      imageUrl: 'https://example.com/image.jpg',
      articleUrl: 'https://example.com/article',
      language: 'en',
      publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(article: withTimestamp, imageProviderBuilder: (_) => FailingImageProvider()),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.access_time), findsOneWidget);
  });

  testWidgets('hides the timestamp row when publishedAt is null', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(article: article, imageProviderBuilder: (_) => FailingImageProvider()),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.access_time), findsNothing);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/widgets/news_card_test.dart`
Expected: FAIL — the long-headline test fails because `maxLines` is currently `2`, not `null`; the timestamp tests fail because `Icons.access_time` never appears

- [ ] **Step 3: Implement the `news_card.dart` changes**

Add the import at the top of `app/lib/widgets/news_card.dart`:

```dart
import '../data/timestamp_format.dart';
```

Replace the `Expanded(...)` block that currently reads:

```dart
                Expanded(
                  // A tightly-constrained Align (not one wrapped around a
                  // scroll view, which always reports itself as filling
                  // all available space regardless of its content)
                  // genuinely centers short content vertically in the
                  // leftover space, while keeping it flush left
                  // horizontally. The headline/snippet line caps below
                  // keep total content height comfortably inside the
                  // minimum this box gets.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              article.source,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            article.headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            article.snippet,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Read more →',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
```

with:

```dart
                Expanded(
                  // A LayoutBuilder-fed minHeight keeps short content
                  // vertically centered (the old Align's job), while
                  // SingleChildScrollView lets a headline long enough to
                  // overflow the available space scroll instead of being
                  // clipped or truncated.
                  child: LayoutBuilder(
                    builder: (context, textConstraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: textConstraints.maxHeight,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    article.source,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  article.headline,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (article.publishedAt != null) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: Colors.white54,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        formatPublishedAt(
                                          article.publishedAt!,
                                          article.language,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  article.snippet,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Read more →',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
```

(Everything else in the file — the `Stack`, the blurred backdrop, `_AutoAspectImage` — is unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/widgets/news_card_test.dart`
Expected: 5 passed

- [ ] **Step 5: Run the full Flutter suite to check for regressions**

Run: `cd app && flutter test`
Expected: all passed

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/news_card.dart app/test/widgets/news_card_test.dart
git commit -m "feat(news_card): never truncate the headline, scroll overflow, show publishedAt"
```

---

## Task 11: Category filter bottom sheet

**Files:**
- Create: `app/lib/screens/category_filter_sheet.dart`
- Test: `app/test/screens/category_filter_sheet_test.dart`

**Interfaces:**
- Consumes: `AppCategory` (existing).
- Produces: `showCategoryFilterSheet({required BuildContext context, required List<AppCategory> allCategories, required Set<String> excludedKeys, required void Function(String categoryKey, bool isChecked) onToggle}) -> Future<void>` and the underlying `CategoryFilterSheet` widget. Task 12 (`home_screen.dart`) calls `showCategoryFilterSheet` from the app bar's filter icon.

- [ ] **Step 1: Write the failing tests**

Create `app/test/screens/category_filter_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/screens/category_filter_sheet.dart';

const _categories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'sports', label: 'Sports'),
];

void main() {
  testWidgets('renders one row per category, checked unless excluded', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CategoryFilterSheet(
        allCategories: _categories,
        excludedKeys: const {'sports'},
        onToggle: (_, __) {},
      ),
    ));

    final mainTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Main'),
    );
    final sportsTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Sports'),
    );
    expect(mainTile.value, isTrue);
    expect(sportsTile.value, isFalse);
  });

  testWidgets('tapping a checked row calls onToggle with isChecked false', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(MaterialApp(
      home: CategoryFilterSheet(
        allCategories: _categories,
        excludedKeys: const {},
        onToggle: (key, isChecked) {
          toggledKey = key;
          toggledValue = isChecked;
        },
      ),
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sports'));
    await tester.pump();

    expect(toggledKey, 'sports');
    expect(toggledValue, isFalse);
  });

  testWidgets('tapping an unchecked row calls onToggle with isChecked true', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(MaterialApp(
      home: CategoryFilterSheet(
        allCategories: _categories,
        excludedKeys: const {'sports'},
        onToggle: (key, isChecked) {
          toggledKey = key;
          toggledValue = isChecked;
        },
      ),
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sports'));
    await tester.pump();

    expect(toggledKey, 'sports');
    expect(toggledValue, isTrue);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/screens/category_filter_sheet_test.dart`
Expected: FAIL — `Error: Not found: 'package:newshead/screens/category_filter_sheet.dart'`

- [ ] **Step 3: Implement `app/lib/screens/category_filter_sheet.dart`**

```dart
import 'package:flutter/material.dart';

import '../models/app_category.dart';

/// Opens the category filter as a modal bottom sheet. Always lists every
/// fetched category (not just the currently-visible ones) — see this
/// feature's plan for why: it's a stable settings surface, not a live
/// view, and a category with zero stories today can still be pre-picked
/// for whenever it next has one.
Future<void> showCategoryFilterSheet({
  required BuildContext context,
  required List<AppCategory> allCategories,
  required Set<String> excludedKeys,
  required void Function(String categoryKey, bool isChecked) onToggle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF171310),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => CategoryFilterSheet(
      allCategories: allCategories,
      excludedKeys: excludedKeys,
      onToggle: onToggle,
    ),
  );
}

class CategoryFilterSheet extends StatefulWidget {
  final List<AppCategory> allCategories;
  final Set<String> excludedKeys;
  final void Function(String categoryKey, bool isChecked) onToggle;

  const CategoryFilterSheet({
    super.key,
    required this.allCategories,
    required this.excludedKeys,
    required this.onToggle,
  });

  @override
  State<CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<CategoryFilterSheet> {
  late Set<String> _excludedKeys;

  @override
  void initState() {
    super.initState();
    _excludedKeys = {...widget.excludedKeys};
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const Text(
              'Filter your feed',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "Unchecked categories are hidden right away. Your picks stay put next time you open the app.",
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in widget.allCategories)
                    CheckboxListTile(
                      value: !_excludedKeys.contains(category.key),
                      title: Text(category.label, style: const TextStyle(color: Colors.white)),
                      activeColor: const Color(0xFFE1483A),
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (checked) {
                        final isChecked = checked ?? true;
                        setState(() {
                          if (isChecked) {
                            _excludedKeys.remove(category.key);
                          } else {
                            _excludedKeys.add(category.key);
                          }
                        });
                        widget.onToggle(category.key, isChecked);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/screens/category_filter_sheet_test.dart`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/category_filter_sheet.dart app/test/screens/category_filter_sheet_test.dart
git commit -m "feat(category_filter_sheet): add the live-apply full-taxonomy filter sheet"
```

---

## Task 12: Wire it all into `home_screen.dart`

**Files:**
- Modify: `app/lib/screens/home_screen.dart` (full-file replacement — the app-bar row, pill bar, and category-count logic all change together)
- Test: `app/test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `BrandMark` (Task 9), `visibleCategories` (Task 8), `CategoryFilterStore` (Task 7), `showCategoryFilterSheet` (Task 11).
- Produces: `HomeScreen` gains a new required constructor param `filterStore: CategoryFilterStore`. `main.dart` (Task 13) must be updated to pass one.

- [ ] **Step 1: Write the failing tests**

Replace `app/test/screens/home_screen_test.dart` entirely with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:newshead/data/category_filter_store.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/news_article.dart';
import 'package:newshead/screens/home_screen.dart';

class InMemoryArticleCache implements ArticleCache {
  String? stored;
  InMemoryArticleCache([this.stored]);

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String contents) async => stored = contents;
}

class InMemoryCategoryFilterStore implements CategoryFilterStore {
  Set<String> stored;
  InMemoryCategoryFilterStore([Set<String>? initial]) : stored = initial ?? {};

  @override
  Future<Set<String>> readExcludedKeys() async => stored;

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async => stored = keys;
}

const _twoCategories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'politics', label: 'Politics'),
];

const _oneArticleInMain = [
  NewsArticle(
    id: 'a1',
    category: 'main',
    source: 'Jugantor',
    headline: 'H1',
    snippet: 'S1',
    imageUrl: 'https://example.com/1.jpg',
    articleUrl: 'https://example.com/a1',
  ),
];

const _articlesInMainAndPolitics = [
  NewsArticle(
    id: 'a1',
    category: 'main',
    source: 'Jugantor',
    headline: 'H1',
    snippet: 'S1',
    imageUrl: 'https://example.com/1.jpg',
    articleUrl: 'https://example.com/a1',
  ),
  NewsArticle(
    id: 'a2',
    category: 'politics',
    source: 'Jugantor',
    headline: 'H2',
    snippet: 'S2',
    imageUrl: 'https://example.com/2.jpg',
    articleUrl: 'https://example.com/a2',
  ),
];

const _threeCategoriesJson = '''
{
  "generated_at": "2026-08-23",
  "categories": [
    {"key": "main", "label": "Main"},
    {"key": "politics", "label": "Politics"},
    {"key": "sports", "label": "Sports"}
  ],
  "articles": [
    {"id": "a1", "category": "main", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"},
    {"id": "a2", "category": "politics", "source": "Jugantor", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2"},
    {"id": "a3", "category": "sports", "source": "Jugantor", "headline": "H3", "snippet": "S3", "imageUrl": "https://example.com/3.jpg", "articleUrl": "https://example.com/a3"}
  ]
}
''';

void main() {
  testWidgets('renders one pill per category that actually has an article', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('pull-to-refresh with a different category list re-renders the pill bar', (tester) async {
    final client = MockClient((request) async => http.Response(_threeCategoriesJson, 200));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: client,
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Sports'), findsNothing);

    await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
  });

  testWidgets('unchecking a category in the filter sheet immediately hides its pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _articlesInMainAndPolitics,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Politics'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Politics'));
    await tester.pumpAndSettle();

    // Dismiss the sheet by tapping the scrim, to inspect the feed beneath it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('the filter icon shows a badge dot once a category is excluded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: const [],
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore({'politics'}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(); // let readExcludedKeys()'s Future resolve

    expect(find.byKey(const Key('filterActiveBadge')), findsOneWidget);
  });

  testWidgets('the filter icon shows no badge dot when nothing is excluded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: const [],
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('filterActiveBadge')), findsNothing);
  });

  testWidgets('shows the brand mark instead of a date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('NEWSHEAD'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/screens/home_screen_test.dart`
Expected: FAIL — `The named parameter 'filterStore' isn't defined` (constructor doesn't accept it yet)

- [ ] **Step 3: Replace `app/lib/screens/home_screen.dart` entirely**

```dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/article_cache.dart';
import '../data/article_repository.dart';
import '../data/category_filter_store.dart';
import '../data/category_visibility.dart';
import '../models/app_category.dart';
import '../models/news_article.dart';
import '../widgets/brand_mark.dart';
import 'category_feed.dart';
import 'category_filter_sheet.dart';

class HomeScreen extends StatefulWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;
  final CategoryFilterStore filterStore;

  const HomeScreen({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
    required this.filterStore,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // TickerProviderStateMixin (not SingleTickerProviderStateMixin): a
  // refresh or filter change that changes the visible-category count
  // disposes and recreates the TabController (see _initControllers below),
  // vending a second ticker over this State's lifetime.
  // Large enough that a user could not plausibly swipe past either edge in
  // a session, so category switching loops seamlessly in both directions
  // without true unbounded paging. Rounded down to a multiple of the
  // category count so it starts on the first visible category.
  static const int _kLargePageBase = 100000;

  late TabController _tabController;
  late PageController _categoryPageController;
  bool _isSyncingFromPage = false;

  late List<NewsArticle> _articles;
  late List<AppCategory> _categories;
  Set<String> _excludedCategoryKeys = {};
  late List<AppCategory> _visibleCategories;
  String? _lastRawBody;
  // Bumped on every successful refresh so each CategoryFeed remounts fresh
  // (fresh PageController at the first article) instead of keeping its old
  // scroll position over reordered/changed content.
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _articles = widget.initialArticles;
    _categories = widget.initialCategories;
    _lastRawBody = widget.initialRawBody;
    _visibleCategories = visibleCategories(
      fetchedCategories: _categories,
      articles: _articles,
      excludedKeys: _excludedCategoryKeys,
    );
    _initControllers(_visibleCategories.length);
    _loadExcludedCategoryKeys();
  }

  Future<void> _loadExcludedCategoryKeys() async {
    final stored = await widget.filterStore.readExcludedKeys();
    if (!mounted) return;
    _applyExcludedKeys(stored);
  }

  void _applyExcludedKeys(Set<String> excludedKeys) {
    final nextVisible = visibleCategories(
      fetchedCategories: _categories,
      articles: _articles,
      excludedKeys: excludedKeys,
    );
    setState(() {
      _excludedCategoryKeys = excludedKeys;
      if (nextVisible.length != _visibleCategories.length) {
        _disposeControllers();
        _initControllers(nextVisible.length);
      }
      _visibleCategories = nextVisible;
    });
  }

  void _handleFilterToggle(String categoryKey, bool isChecked) {
    final next = {..._excludedCategoryKeys};
    if (isChecked) {
      next.remove(categoryKey);
    } else {
      next.add(categoryKey);
    }
    _applyExcludedKeys(next);
    widget.filterStore.writeExcludedKeys(next);
  }

  void _openFilterSheet() {
    showCategoryFilterSheet(
      context: context,
      allCategories: _categories,
      excludedKeys: _excludedCategoryKeys,
      onToggle: _handleFilterToggle,
    );
  }

  void _initControllers(int n) {
    _tabController = TabController(length: n, vsync: this);
    _categoryPageController = PageController(
      initialPage: n == 0 ? 0 : (_kLargePageBase ~/ n) * n,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _disposeControllers() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _categoryPageController.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  // Tapping a tab animates the TabController on its own first; once that
  // settles (indexIsChanging is false), animate the page view to the
  // nearest equivalent page for the tapped category. Ignored while we're
  // the ones driving the tab index from a page change (see
  // _onCategoryPageChanged), to avoid feeding back into a loop.
  void _onTabChanged() {
    if (_isSyncingFromPage || _tabController.indexIsChanging) return;
    final currentPage =
        _categoryPageController.page?.round() ??
        _categoryPageController.initialPage;
    final targetPage = _nearestPageForCategory(
      currentPage,
      _tabController.index,
    );
    if (targetPage == currentPage) return;
    _categoryPageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  // The nearest page (forward or backward) that lands on categoryIndex,
  // so the tab-tap animation takes the shortest path around the loop.
  int _nearestPageForCategory(int currentPage, int categoryIndex) {
    final n = _visibleCategories.length;
    final currentCategoryIndex = currentPage % n;
    var diff = categoryIndex - currentCategoryIndex;
    if (diff > n / 2) diff -= n;
    if (diff < -n / 2) diff += n;
    return currentPage + diff;
  }

  void _onCategoryPageChanged(int page) {
    _isSyncingFromPage = true;
    _tabController.index = page % _visibleCategories.length;
    _isSyncingFromPage = false;
  }

  // Pulled from any category feed. Re-fetches from the shared source; if the
  // server returned byte-identical content to last time (nothing new to
  // show), the order is shuffled per category so the pull still visibly
  // "does something" instead of looking like a no-op.
  Future<void> _handleRefresh() async {
    final result = await fetchArticles(
      sourceUrl: widget.sourceUrl,
      client: widget.client,
      cache: widget.cache,
    );

    if (!result.fromNetwork) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh — check your connection'),
          ),
        );
      }
      return;
    }

    var articles = result.articles;
    if (result.rawBody == _lastRawBody) {
      articles = articles.toList()..shuffle();
    }

    if (!mounted) return;
    final nextVisible = visibleCategories(
      fetchedCategories: result.categories,
      articles: articles,
      excludedKeys: _excludedCategoryKeys,
    );
    setState(() {
      _articles = articles;
      _lastRawBody = result.rawBody;
      _refreshGeneration++;
      _categories = result.categories;
      if (nextVisible.length != _visibleCategories.length) {
        _disposeControllers();
        _initControllers(nextVisible.length);
      }
      _visibleCategories = nextVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: const Color(0xFF121212),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const BrandMark(),
                    IconButton(
                      onPressed: _openFilterSheet,
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.tune, color: Colors.white70),
                          if (_excludedCategoryKeys.isNotEmpty)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                key: const Key('filterActiveBadge'),
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE1483A),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _visibleCategories.isEmpty
                ? const Center(
                    child: Text(
                      'No stories yet',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : PageView.builder(
                    // Keyed on the controller's identity so a controller swap
                    // (see _applyExcludedKeys/_handleRefresh, which create a
                    // brand-new PageController when the visible-category
                    // count changes) forces a full remount of this widget.
                    key: ObjectKey(_categoryPageController),
                    controller: _categoryPageController,
                    onPageChanged: _onCategoryPageChanged,
                    itemBuilder: (context, page) {
                      final category = _visibleCategories[page % _visibleCategories.length];
                      return CategoryFeed(
                        key: PageStorageKey('${category.key}#$_refreshGeneration'),
                        category: category.key,
                        articles: articlesForCategory(_articles, category.key),
                        onRefresh: _handleRefresh,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _visibleCategories.isEmpty
          ? null
          : ColoredBox(
              color: const Color(0xFF121212),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ListenableBuilder(
                      listenable: _tabController,
                      builder: (context, _) {
                        return Row(
                          children: [
                            for (var i = 0; i < _visibleCategories.length; i++)
                              Padding(
                                padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                                child: _CategoryPill(
                                  label: _visibleCategories[i].label,
                                  selected: _tabController.index == i,
                                  onTap: () => _tabController.animateTo(i),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : Colors.white70,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/screens/home_screen_test.dart`
Expected: 6 passed

- [ ] **Step 5: Run the full Flutter suite to check for regressions**

Run: `cd app && flutter test`
Expected: all passed

- [ ] **Step 6: Run the analyzer**

Run: `cd app && flutter analyze`
Expected: No issues found! (the old `_todayLabel`/weekday/month constants are fully removed, not just unused, so nothing should be flagged)

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/home_screen.dart app/test/screens/home_screen_test.dart
git commit -m "feat(home_screen): show only visible categories, wire filter sheet and brand mark"
```

---

## Task 13: Wire `CategoryFilterStore` into `main.dart` and do a full-suite verification pass

**Files:**
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes: `SharedPreferencesCategoryFilterStore` (Task 7), `HomeScreen`'s new `filterStore` param (Task 12).

- [ ] **Step 1: Add the import and instantiate the store**

In `app/lib/main.dart`, add the import alongside the existing `data/` imports:

```dart
import 'data/category_filter_store.dart';
```

In `main()`, add the store instantiation next to the existing `cache`/`client` setup:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TimeoutHttpOverrides();

  final documentsDir = await getApplicationDocumentsDirectory();
  final cache = FileArticleCache('${documentsDir.path}/articles_cache.json');
  final client = http.Client();
  final filterStore = SharedPreferencesCategoryFilterStore();

  final result = await fetchArticles(
    sourceUrl: kArticlesUrl,
    client: client,
    cache: cache,
  );

  runApp(NewsHeadApp(
    initialArticles: result.articles,
    initialCategories: result.categories,
    initialRawBody: result.rawBody,
    sourceUrl: kArticlesUrl,
    client: client,
    cache: cache,
    filterStore: filterStore,
  ));
}
```

- [ ] **Step 2: Thread `filterStore` through `NewsHeadApp`**

Change the `NewsHeadApp` class from:

```dart
class NewsHeadApp extends StatelessWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;

  const NewsHeadApp({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHead',
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      home: HomeScreen(
        initialArticles: initialArticles,
        initialCategories: initialCategories,
        initialRawBody: initialRawBody,
        sourceUrl: sourceUrl,
        client: client,
        cache: cache,
      ),
    );
  }
}
```

to:

```dart
class NewsHeadApp extends StatelessWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;
  final CategoryFilterStore filterStore;

  const NewsHeadApp({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
    required this.filterStore,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHead',
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      home: HomeScreen(
        initialArticles: initialArticles,
        initialCategories: initialCategories,
        initialRawBody: initialRawBody,
        sourceUrl: sourceUrl,
        client: client,
        cache: cache,
        filterStore: filterStore,
      ),
    );
  }
}
```

- [ ] **Step 3: Run the full Flutter suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze`: No issues found!; `flutter test`: all passed

- [ ] **Step 4: Run the full Python suite**

Run: `.venv/bin/python -m pytest tests/ -v` (from the repo root)
Expected: all passed

- [ ] **Step 5: Build a debug APK and smoke-test on a device/emulator**

Run: `cd app && flutter build apk --debug`
Then install and launch it (`adb install -r build/app/outputs/flutter-apk/app-debug.apk && adb shell am start -n com.newshead.newshead/.MainActivity`) against the live `articles.json`. Verify by eye against the approved prototype (`https://claude.ai/code/artifact/cec64952-a765-4e1b-8761-111f8afe3bce`):
- App bar shows the chevron badge + "NEWSHEAD" wordmark on the left, a filter icon on the right, no date.
- Bottom pill bar shows only categories with real articles today.
- Tapping the filter icon opens the sheet with all 17 categories checked; unchecking one immediately drops its pill.
- A card's timestamp row appears under the headline, in the source's own language.
- A long headline is fully visible (scroll if needed), never cut off with "…".

- [ ] **Step 6: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(main): wire the persisted category filter store into the app"
```
