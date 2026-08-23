# Category/Topic Remapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current 5-keyword-guessed category system with an explicit, user-designed taxonomy built from every real navigational section across all 5 papers, uncap article volume, and make the app's category tabs data-driven instead of hardcoded.

**Architecture:** Two phases. **Phase A** (fully executable now) adds an `include_all` bypass to each source module's section discovery so a new, reusable `scripts/discover_sections.py` can dump every raw section per source — including the ones today's curated allowlists/denylists quietly drop — into a report for the user to review. **Phase B** (mechanism fully executable now; final task gated on the user's taxonomy) replaces `generate_data.py`'s keyword-only classification with an explicit per-source `SECTION_CATEGORY_MAP` (falling back to keyword matching only when a section has no explicit entry), removes all per-category/per-source article caps, and makes `articles.json` emit an ordered `"categories"` list that the Flutter app reads instead of a hardcoded Dart const.

**Tech Stack:** Python 3 (`scraper/` package, pytest), Flutter/Dart (`app/`, `flutter test`).

**Spec:** No separate spec doc — requirements were resolved via a grill-with-docs interview against the live codebase; canonical terms (Source Section, Canonical Category, Main, Section→Category Mapping, Discovery Report) are recorded in `CONTEXT.md` at the repo root. This plan is the spec of record for the resulting work.

## Global Constraints

- Source set is unchanged: `jugantor, prothomalo, dhakatribune, dailystar, ittefaq` (`scraper/config.py:19`).
- `include_all` bypass functions default to `False` — every existing production code path (`list_articles`, the real `python scripts/generate.py` run, today's 5-category behavior) is untouched until Task 14 supplies the new taxonomy.
- "Main" keeps working exactly as today: each source's first discovered section, unconditionally category `"main"`, orthogonal to the Section→Category Mapping — only touched by Task 9 (cap removal) and Task 10 (label lookup), never by the mapping/keyword logic.
- No per-category or per-source article count caps anywhere after Task 9 (not `ARTICLES_PER_CATEGORY_CAP`, not `MAIN_ARTICLES_PER_SOURCE`) — every mapped section's articles are published, round-robin-interleaved across sources for mix, but never truncated.
- An explicitly-mapped section's category always wins outright over keyword matching; keyword matching (`CATEGORY_KEYWORDS`) only runs for a section with no `SECTION_CATEGORY_MAP` entry.
- Commit messages follow `CLAUDE.md`'s convention: `<task_type>(<location>): <description>`, one line per file/feature area touched, no AI co-author attribution.
- Task 7 (running the live discovery scrape) and Task 14 (applying the real taxonomy + manual app/runtime verification) are the two points in this plan that require the user's input or a live run — everything else is self-contained, testable code.

---

## Phase A — Section Discovery Tooling

### Task 1: `include_all` bypass in `jugantor.py` (structural filter only — no allowlist exists)

**Files:**
- Modify: `scraper/sources/jugantor.py:54-90` (`parse_sections`, `discover_sections`)
- Test: `tests/test_jugantor_sections.py` (new)

**Interfaces:**
- Produces: `parse_sections(html, include_all=False)`, `discover_sections(include_all=False)` — same shared two-function shape every source module now exposes, consumed by `scripts/discover_sections.py` (Task 6).

- [ ] **Step 1: Write the failing test**

```python
# tests/test_jugantor_sections.py
from scraper.sources.jugantor import parse_sections

_HTML = """
<div class="desktopSubCategoryDiv">
  <a href="/tp-sports" aria-label="খেলা">খেলা</a>
  <a href="/tp-city" aria-label="নগর-মহানগর">নগর-মহানগর</a>
</div>
"""


def test_parse_sections_default_matches_include_all():
    # Jugantor has no curated allow/deny list — every "/tp-" link is already
    # "everything" — so include_all is a documented no-op here.
    assert parse_sections(_HTML) == parse_sections(_HTML, include_all=True)
    assert parse_sections(_HTML) == [
        ("tp-sports", "খেলা"),
        ("tp-city", "নগর-মহানগর"),
    ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_jugantor_sections.py -v`
Expected: FAIL with `TypeError: parse_sections() got an unexpected keyword argument 'include_all'`

- [ ] **Step 3: Write minimal implementation**

In `scraper/sources/jugantor.py`, change the two signatures (body unchanged otherwise — no filtering logic exists to bypass):

```python
def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes raw HTML, returns
    a list of (slug, section_name) or [] if none were found.

    include_all is accepted for interface parity with the other source
    modules' discovery bypass (used by scripts/discover_sections.py) but is
    a no-op here — Jugantor has no curated allow/deny list to bypass; every
    "/tp-" link found is already the full set."""
    soup = BeautifulSoup(html, "html.parser")
    container = soup.select_one("div.desktopSubCategoryDiv") or soup

    sections = []
    seen_slugs = set()
    for link in container.select("a[href]"):
        href = link["href"]
        if "/tp-" not in href:
            continue
        slug = _slug_from_href(href)
        if not slug or slug in seen_slugs:
            continue
        name = _normalize(link.get("aria-label") or link.get_text(strip=True))
        if not name:
            continue
        seen_slugs.add(slug)
        sections.append((slug, name))

    return sections


def discover_sections(include_all=False):
    try:
        html = _get(TODAYS_PAPER_URL)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", TODAYS_PAPER_URL)
        return list(FALLBACK_SECTIONS)

    sections = parse_sections(html, include_all=include_all)
    if not sections:
        logger.warning("No sections discovered on %s, using fallback list", TODAYS_PAPER_URL)
        return list(FALLBACK_SECTIONS)

    return sections
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_jugantor_sections.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/sources/jugantor.py tests/test_jugantor_sections.py
git commit -m "feat(jugantor_source): accept include_all on section discovery for parity with other sources"
```

---

### Task 2: `include_all` bypass in `dhakatribune.py` (bypasses `CORE_SECTION_SLUGS` allowlist)

**Files:**
- Modify: `scraper/sources/dhakatribune.py:63-100` (`parse_sections`, `discover_sections`)
- Test: `tests/test_dhakatribune_sections.py` (new)

**Interfaces:**
- Produces: `parse_sections(html, include_all=False)`, `discover_sections(include_all=False)`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_dhakatribune_sections.py
from scraper.sources.dhakatribune import parse_sections

_HTML = """
<div id="main_menu">
  <a href="https://www.dhakatribune.com/world">World</a>
  <a href="https://www.dhakatribune.com/magazine">Magazine</a>
</div>
"""


def test_parse_sections_default_applies_core_allowlist():
    assert parse_sections(_HTML) == [("world", "World")]


def test_parse_sections_include_all_bypasses_allowlist():
    assert parse_sections(_HTML, include_all=True) == [
        ("world", "World"),
        ("magazine", "Magazine"),
    ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_dhakatribune_sections.py -v`
Expected: FAIL with `TypeError: parse_sections() got an unexpected keyword argument 'include_all'`

- [ ] **Step 3: Write minimal implementation**

```python
def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes the homepage's raw
    HTML, returns a list of (slug, section_name) or [] if none were found.

    include_all=True bypasses CORE_SECTION_SLUGS, returning every nav link
    found (mega-menu subcategories, catch-alls like "Magazine"/"More",
    everything) — used only by scripts/discover_sections.py to audit the
    real nav; production discovery (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")
    container = soup.select_one("#main_menu") or soup

    sections = []
    seen_slugs = set()
    for link in container.select("a[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != "www.dhakatribune.com":
            continue
        slug = parsed.path.strip("/")
        if not slug or slug in seen_slugs:
            continue
        if not include_all and slug not in CORE_SECTION_SLUGS:
            continue
        name = _normalize(link.get_text(strip=True))
        if not name:
            continue
        seen_slugs.add(slug)
        sections.append((slug, name))

    return sections


def discover_sections(include_all=False):
    try:
        html = _get(BASE_URL)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    sections = parse_sections(html, include_all=include_all)
    if not sections:
        logger.warning("No sections discovered on %s, using fallback list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    return sections
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_dhakatribune_sections.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/sources/dhakatribune.py tests/test_dhakatribune_sections.py
git commit -m "feat(dhakatribune_source): add include_all bypass of CORE_SECTION_SLUGS for discovery audits"
```

---

### Task 3: `include_all` bypass in `ittefaq.py` (bypasses `CORE_SECTION_SLUGS` allowlist)

**Files:**
- Modify: `scraper/sources/ittefaq.py:90-127` (`parse_sections`, `discover_sections`)
- Test: `tests/test_ittefaq_sections.py` (new)

**Interfaces:**
- Produces: `parse_sections(html, include_all=False)`, `discover_sections(include_all=False)`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_ittefaq_sections.py
from scraper.sources.ittefaq import parse_sections

_HTML = """
<a href="https://www.ittefaq.com.bd/national">জাতীয়</a>
<a href="https://www.ittefaq.com.bd/jobs">চাকরি</a>
"""


def test_parse_sections_default_applies_core_allowlist():
    assert parse_sections(_HTML) == [("national", "জাতীয়")]


def test_parse_sections_include_all_bypasses_allowlist():
    assert parse_sections(_HTML, include_all=True) == [
        ("national", "জাতীয়"),
        ("jobs", "চাকরি"),
    ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_ittefaq_sections.py -v`
Expected: FAIL with `TypeError: parse_sections() got an unexpected keyword argument 'include_all'`

- [ ] **Step 3: Write minimal implementation**

```python
def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes the homepage's raw
    HTML, returns a list of (slug, section_name) or [] if none were found.

    include_all=True bypasses CORE_SECTION_SLUGS (see its comment above) —
    used only by scripts/discover_sections.py to audit the real nav;
    production discovery (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")

    sections = []
    seen_slugs = set()
    for link in soup.select("a[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != "www.ittefaq.com.bd":
            continue
        slug = parsed.path.strip("/")
        if not slug or slug in seen_slugs:
            continue
        if not include_all and slug not in CORE_SECTION_SLUGS:
            continue
        name = _text(link)
        if not name:
            continue
        seen_slugs.add(slug)
        sections.append((slug, name))

    return sections


def discover_sections(include_all=False):
    try:
        html = _get(BASE_URL)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    sections = parse_sections(html, include_all=include_all)
    if not sections:
        logger.warning("No sections discovered on %s, using fallback list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    return sections
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_ittefaq_sections.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/sources/ittefaq.py tests/test_ittefaq_sections.py
git commit -m "feat(ittefaq_source): add include_all bypass of CORE_SECTION_SLUGS for discovery audits"
```

---

### Task 4: `include_all` bypass in `prothomalo.py` (bypasses `EXCLUDED_SECTION_SLUGS` denylist)

**Files:**
- Modify: `scraper/sources/prothomalo.py:79-119` (`parse_sections`, `discover_sections`)
- Test: `tests/test_prothomalo_sections.py` (new)

**Interfaces:**
- Produces: `parse_sections(html, include_all=False)`, `discover_sections(include_all=False)`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_prothomalo_sections.py
from scraper.sources.prothomalo import parse_sections

_HTML = """
<div id="navbar">
  <a href="https://www.prothomalo.com/bangladesh">বাংলাদেশ</a>
  <a href="https://www.prothomalo.com/video">ভিডিও</a>
</div>
"""


def test_parse_sections_default_applies_denylist():
    assert parse_sections(_HTML) == [("bangladesh", "বাংলাদেশ")]


def test_parse_sections_include_all_bypasses_denylist():
    assert parse_sections(_HTML, include_all=True) == [
        ("bangladesh", "বাংলাদেশ"),
        ("video", "ভিডিও"),
    ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_prothomalo_sections.py -v`
Expected: FAIL with `TypeError: parse_sections() got an unexpected keyword argument 'include_all'`

- [ ] **Step 3: Write minimal implementation**

```python
def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes the homepage's raw
    HTML, returns a list of (slug, section_name) or [] if none were found.

    include_all=True bypasses EXCLUDED_SECTION_SLUGS (video, chakri) — used
    only by scripts/discover_sections.py to audit the real nav; production
    discovery (include_all=False) is unchanged. The single-segment-path
    filter stays regardless of include_all — it distinguishes real nav
    categories from permalinks/search/oauth links, not curated content."""
    soup = BeautifulSoup(html, "html.parser")
    container = soup.select_one("#navbar") or soup

    sections = []
    seen_slugs = set()
    for link in container.select("a[href]"):
        href = link["href"]
        if not href.startswith(BASE_URL):
            continue
        path = urlparse(href).path.strip("/")
        if not path or "/" in path:
            continue
        if path in seen_slugs:
            continue
        if not include_all and path in EXCLUDED_SECTION_SLUGS:
            continue
        name = _normalize(link.get("aria-label") or link.get_text(strip=True))
        if not name:
            continue
        seen_slugs.add(path)
        sections.append((path, name))

    return sections


def discover_sections(include_all=False):
    try:
        html = _get(BASE_URL)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    sections = parse_sections(html, include_all=include_all)
    if not sections:
        logger.warning("No sections discovered on %s, using fallback list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    return sections
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_prothomalo_sections.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/sources/prothomalo.py tests/test_prothomalo_sections.py
git commit -m "feat(prothomalo_source): add include_all bypass of EXCLUDED_SECTION_SLUGS for discovery audits"
```

---

### Task 5: `include_all` bypass in `dailystar.py` (bypasses `EXCLUDED_SECTION_SLUGS`, applied inside listing grouping)

**Files:**
- Modify: `scraper/sources/dailystar.py:94-150` (`parse_todays_news`, `_get_grouped_listing`, `discover_sections`)
- Test: `tests/test_dailystar_sections.py` (new)

**Interfaces:**
- Produces: `parse_todays_news(html, include_all=False)`, `_get_grouped_listing(include_all=False)`, `discover_sections(include_all=False)`.
- Note: unlike the other 4 sources, Daily Star's filter lives inside the listing-grouping step (`parse_todays_news`), not a separate section-list filter, because `discover_sections()` here is derived from the same grouped-by-section listing that `list_articles()` reads. The cache key must vary by `include_all` so a discovery run's bypassed grouping never gets reused by (or poisons) a later production `list_articles()` call within the same process.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_dailystar_sections.py
from scraper.sources.dailystar import parse_todays_news

_HTML = """
<div class="views-row">
  <div class="card-title"><a href="https://www.thedailystar.net/news/one">Headline One</a></div>
  <div class="card-intro">Summary one</div>
  <div class="card-info">2 hours ago</div>
</div>
<div class="views-row">
  <div class="card-title"><a href="https://www.thedailystar.net/star-multimedia/two">Video headline</a></div>
  <div class="card-intro">Summary two</div>
  <div class="card-info">3 hours ago</div>
</div>
"""


def test_parse_todays_news_default_excludes_video_hub():
    grouped = parse_todays_news(_HTML)
    assert list(grouped.keys()) == ["news"]


def test_parse_todays_news_include_all_keeps_video_hub():
    grouped = parse_todays_news(_HTML, include_all=True)
    assert set(grouped.keys()) == {"news", "star-multimedia"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_dailystar_sections.py -v`
Expected: FAIL with `TypeError: parse_todays_news() got an unexpected keyword argument 'include_all'`

- [ ] **Step 3: Write minimal implementation**

```python
def parse_todays_news(html, include_all=False):
    """Pure parsing step; takes /todays-news' raw HTML, returns a dict of
    {section_slug: [article dict, ...]}, deduped by URL across the whole
    page (the same story commonly appears in more than one listing widget).

    include_all=True keeps EXCLUDED_SECTION_SLUGS sections (e.g. the
    "star-multimedia" video hub) instead of dropping them — used only by
    scripts/discover_sections.py to audit the real nav; production grouping
    (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")

    grouped = {}
    seen_urls = set()
    for row in soup.select(".views-row"):
        link_tag = row.select_one(".card-title a[href]")
        if link_tag is None:
            continue

        url = urljoin(BASE_URL, link_tag["href"])
        if url in seen_urls:
            continue

        slug = _section_slug(url)
        if not slug or (not include_all and slug in EXCLUDED_SECTION_SLUGS):
            continue
        seen_urls.add(url)

        img_tag = row.select_one("img[src]")

        grouped.setdefault(slug, []).append(
            {
                "url": url,
                "headline": _text(link_tag),
                "summary": _text(row.select_one(".card-intro")),
                "listing_time": _text(row.select_one(".card-info")),
                "thumbnail": urljoin(BASE_URL, img_tag["src"]) if img_tag else None,
            }
        )

    return grouped


def _get_grouped_listing(include_all=False):
    cache_key = "grouped_all" if include_all else "grouped"
    if cache_key not in _listing_cache:
        html = _get(TODAYS_NEWS_URL)
        _listing_cache[cache_key] = parse_todays_news(html, include_all=include_all)
    return _listing_cache[cache_key]


def discover_sections(include_all=False):
    try:
        grouped = _get_grouped_listing(include_all=include_all)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", TODAYS_NEWS_URL)
        return list(FALLBACK_SECTIONS)

    if not grouped:
        logger.warning("No sections discovered on %s, using fallback list", TODAYS_NEWS_URL)
        return list(FALLBACK_SECTIONS)

    return [(slug, SECTION_DISPLAY_NAMES.get(slug, slug.replace("-", " ").title())) for slug in grouped]


def list_articles(slug, edition_date=None):
    grouped = _get_grouped_listing()
    return grouped.get(slug, [])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_dailystar_sections.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/sources/dailystar.py tests/test_dailystar_sections.py
git commit -m "feat(dailystar_source): add include_all bypass of EXCLUDED_SECTION_SLUGS for discovery audits"
```

---

### Task 6: `scripts/discover_sections.py` — reusable full-nav report generator

**Files:**
- Create: `scripts/discover_sections.py`
- Test: `tests/test_discover_sections_report.py` (new)

**Interfaces:**
- Consumes: `module.discover_sections(include_all=True)` from each of the 5 source modules (Tasks 1-5), `scraper.config.SOURCES`, `scraper.config.PROJECT_ROOT`.
- Produces: `render_report(results: dict[str, list[tuple[str, str]]]) -> str` (pure, tested), `discover_all_sections() -> dict[str, list[tuple[str, str]]]` (I/O, not unit-tested — same house convention as `generate_data.py`'s `main()`/`collect_source_articles()`), writes `docs/section-discovery-report.md`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_discover_sections_report.py
from scripts.discover_sections import render_report


def test_render_report_lists_every_section_grouped_by_source():
    results = {
        "jugantor": [("tp-sports", "খেলা"), ("tp-city", "নগর-মহানগর")],
        "prothomalo": [("bangladesh", "বাংলাদেশ")],
    }
    report = render_report(results)
    assert "## jugantor (2 sections)" in report
    assert "- `tp-sports` — খেলা" in report
    assert "- `tp-city` — নগর-মহানগর" in report
    assert "## prothomalo (1 sections)" in report
    assert "- `bangladesh` — বাংলাদেশ" in report


def test_render_report_handles_a_source_with_no_sections():
    report = render_report({"dailystar": []})
    assert "## dailystar (0 sections)" in report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_discover_sections_report.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts.discover_sections'`

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""One-off / re-runnable audit tool: dumps every raw section (slug + name)
each source's own nav exposes, bypassing the curated allowlist/denylist
each source module normally applies in discover_sections(). Used to design
(or re-audit, if a source redesigns its nav later) the app's canonical
category taxonomy and the SECTION_CATEGORY_MAP in scraper/generate_data.py.

Run manually:
    python scripts/discover_sections.py
"""
import importlib
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scraper import config

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

REPORT_PATH = os.path.join(config.PROJECT_ROOT, "docs", "section-discovery-report.md")


def discover_all_sections():
    """Returns {source_slug: [(section_slug, section_name), ...]} using each
    source's full, unfiltered nav. Skips (with a warning) any source whose
    discovery fails outright, mirroring generate_data.py's per-source
    try/except pattern."""
    results = {}
    for source_slug in config.SOURCES:
        module = importlib.import_module(f"scraper.sources.{source_slug}")
        try:
            sections = module.discover_sections(include_all=True)
        except Exception as exc:
            logger.warning("Skipping %s: could not discover sections: %s", source_slug, exc)
            continue
        results[source_slug] = sections
    return results


def render_report(results):
    """Pure formatting step: {source_slug: [(slug, name), ...]} -> markdown."""
    lines = [
        "# Section Discovery Report",
        "",
        "Every raw nav section per source, bypassing each source's curated "
        "allowlist/denylist. Regenerate with `python scripts/discover_sections.py`.",
        "",
    ]
    for source_slug, sections in results.items():
        lines.append(f"## {source_slug} ({len(sections)} sections)")
        lines.append("")
        for slug, name in sections:
            lines.append(f"- `{slug}` — {name}")
        lines.append("")
    return "\n".join(lines)


def main():
    results = discover_all_sections()
    report = render_report(results)

    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write(report)

    total = sum(len(sections) for sections in results.values())
    logger.info("Wrote %d section(s) across %d source(s) to %s", total, len(results), REPORT_PATH)
    print(report)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_discover_sections_report.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/discover_sections.py tests/test_discover_sections_report.py
git commit -m "feat(discover_sections): add reusable full-nav section discovery report tool"
```

---

### Task 7: Run the discovery report for real — CHECKPOINT

This is the plan's first stop-and-wait point. It requires live network access and produces the input the user needs to design the taxonomy (Phase B's Task 14 cannot start without it).

- [ ] **Step 1: Run the tool**

Run: `python scripts/discover_sections.py`

This hits all 5 live sites once each (respecting each source's existing `REQUEST_DELAY_SECONDS`), writes `docs/section-discovery-report.md`, and prints the same report to stdout.

- [ ] **Step 2: Sanity-check the output**

Confirm the report has 5 `##` sections (one per source in `scraper.config.SOURCES`), and that at minimum the previously-curated sources (`dhakatribune`, `ittefaq`, `prothomalo`, `dailystar`) now show more entries than their production `discover_sections()` (`include_all=False`) would — if any of them shows the exact same count as before, `include_all=True` likely isn't reaching that source's filter and Tasks 2-5 need a second look before proceeding.

- [ ] **Step 3: Commit the report**

```bash
git add docs/section-discovery-report.md
git commit -m "docs(section_discovery): add full raw nav report across all 5 sources"
```

- [ ] **Step 4: STOP — hand the report to the user**

Present `docs/section-discovery-report.md` to the user. Do not proceed to Task 14 (and do not invent a taxonomy) until the user has reviewed it and dictated back: (a) the final canonical category list (key + display label, in display order, `main` first), and (b) for each source, which of its raw sections map to which canonical category. Tasks 8-13 below don't need this input and can proceed immediately.

---

## Phase B — Classification Mechanism, Uncapping, Data-Driven Categories

### Task 8: `SECTION_CATEGORY_MAP` — explicit section→category lookup, keyword fallback

**Files:**
- Modify: `scraper/generate_data.py:44-176` (add `SECTION_CATEGORY_MAP`, add `classify_article_category`, update `collect_source_articles`)
- Modify: `tests/test_generate_data.py` (add tests; existing `classify_category` tests are untouched — its signature doesn't change)

**Interfaces:**
- Consumes: existing `classify_category(headline, section_name)` (unchanged, still pure keyword matching, `scraper/generate_data.py:68`).
- Produces: `classify_article_category(source_slug, section_slug, section_name, headline) -> str | None` — the new call site used by `collect_source_articles`. Precedence: `SECTION_CATEGORY_MAP[source_slug][section_slug]` wins outright if present; otherwise falls back to `classify_category(headline, section_name)`; otherwise `None` (article dropped, same as today).

- [ ] **Step 1: Write the failing test**

```python
# append to tests/test_generate_data.py
from scraper.generate_data import classify_article_category, SECTION_CATEGORY_MAP


def test_classify_article_category_uses_explicit_mapping_when_present():
    SECTION_CATEGORY_MAP.setdefault("testsource", {})["tech"] = "technology"
    try:
        # Headline would keyword-match "sports" if the mapping weren't
        # checked first — explicit mapping must win outright.
        result = classify_article_category("testsource", "tech", "Tech", "Cricket team wins")
        assert result == "technology"
    finally:
        del SECTION_CATEGORY_MAP["testsource"]


def test_classify_article_category_falls_back_to_keywords_when_unmapped():
    result = classify_article_category("testsource", "unmapped-section", "Sports", "Local team wins the match")
    assert result == "sports"


def test_classify_article_category_returns_none_when_neither_matches():
    result = classify_article_category("testsource", "unmapped-section", "Opinion", "A completely unrelated headline")
    assert result is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_generate_data.py -v -k classify_article_category`
Expected: FAIL with `ImportError: cannot import name 'classify_article_category'`

- [ ] **Step 3: Write minimal implementation**

In `scraper/generate_data.py`, add below `CATEGORY_KEYWORDS` (after line 65) and above `classify_category` (line 68):

```python
# Explicit per-source, per-section-slug -> canonical-category overrides.
# Checked before classify_category()'s keyword guessing; a section listed
# here always wins outright for every article it contains, regardless of
# headline text. A source's absent-or-empty dict, or a section with no
# entry, falls through to keyword matching instead. Filled in per Task 14
# once the taxonomy from docs/section-discovery-report.md is finalized.
SECTION_CATEGORY_MAP = {
    "jugantor": {},
    "prothomalo": {},
    "dhakatribune": {},
    "dailystar": {},
    "ittefaq": {},
}


def classify_article_category(source_slug, section_slug, section_name, headline):
    """Resolve an article's canonical category: an explicit
    SECTION_CATEGORY_MAP entry for this source+section wins outright;
    otherwise fall back to keyword-matching the headline/section name.
    Returns None (article dropped) if neither matches."""
    mapped = SECTION_CATEGORY_MAP.get(source_slug, {}).get(section_slug)
    if mapped is not None:
        return mapped
    return classify_category(headline, section_name)
```

Then update the per-section classification call in `collect_source_articles` (`scraper/generate_data.py:159-174`):

```python
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
            articles.append(build_article(source_slug, source_name, category, item, fallback_image_url))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_generate_data.py -v`
Expected: PASS (all tests, including the pre-existing `classify_category` ones, since that function's signature is untouched)

- [ ] **Step 5: Commit**

```bash
git add scraper/generate_data.py tests/test_generate_data.py
git commit -m "feat(generate_data): add explicit per-source section-to-category mapping with keyword fallback"
```

---

### Task 9: Remove all per-category and per-source article caps

**Files:**
- Modify: `scraper/generate_data.py:29-30,121-203` (remove `ARTICLES_PER_CATEGORY_CAP`/`MAIN_ARTICLES_PER_SOURCE` constants, un-slice the main-section loop, un-cap `cap_per_category`, rename to `interleave_by_source`)
- Modify: `tests/test_generate_data.py` (replace any cap-specific assumptions — there are none today; add interleaving tests)

**Interfaces:**
- Produces: `interleave_by_source(all_articles: list[dict]) -> list[dict]` (replaces `cap_per_category`, same round-robin-across-sources-within-a-category behavior, no count ceiling). `main()`'s call site updates accordingly.

- [ ] **Step 1: Write the failing test**

```python
# append to tests/test_generate_data.py
from scraper.generate_data import interleave_by_source


def test_interleave_by_source_round_robins_without_a_cap():
    articles = (
        [{"category": "sports", "source": "A", "id": f"a{i}"} for i in range(5)]
        + [{"category": "sports", "source": "B", "id": f"b{i}"} for i in range(2)]
    )
    result = interleave_by_source(articles)
    ids = [a["id"] for a in result]
    # Round-robin across sources: A,B,A,B,A,A,A — every article kept, none
    # capped, but B's 2 articles aren't pushed to the back of the list.
    assert ids == ["a0", "b0", "a1", "b1", "a2", "a3", "a4"]
    assert len(result) == 7


def test_interleave_by_source_keeps_every_article_for_a_single_source():
    articles = [{"category": "main", "source": "A", "id": f"a{i}"} for i in range(20)]
    result = interleave_by_source(articles)
    assert len(result) == 20
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_generate_data.py -v -k interleave_by_source`
Expected: FAIL with `ImportError: cannot import name 'interleave_by_source'`

- [ ] **Step 3: Write minimal implementation**

In `scraper/generate_data.py`, remove the two cap constants (lines 29-30):

```python
CATEGORIES = ["politics", "world", "bangladesh", "sports", "finance"]
```

(delete the `ARTICLES_PER_CATEGORY_CAP = 12` and `MAIN_ARTICLES_PER_SOURCE = 2` lines entirely)

Un-slice the main-section loop (was `for item in main_items[:MAIN_ARTICLES_PER_SOURCE]:`):

```python
    for item in main_items:
        if not item.get("url") or item["url"] in seen_urls:
            continue
        item = enrich_item(source_module, item)
        seen_urls.add(item["url"])
        articles.append(build_article(source_slug, source_name, "main", item, fallback_image_url))
```

Replace `cap_per_category` entirely:

```python
def interleave_by_source(all_articles):
    """Round-robins articles across sources within each category, so the
    feed doesn't front-load one source's articles before ever showing
    another's — but keeps every article (no count ceiling)."""
    by_category_source = defaultdict(lambda: defaultdict(deque))
    source_order = defaultdict(list)
    for article in all_articles:
        category = article["category"]
        source = article["source"]
        if source not in source_order[category]:
            source_order[category].append(source)
        by_category_source[category][source].append(article)

    interleaved = []
    for category in CATEGORIES + ["main"]:
        sources = source_order.get(category, [])
        while any(by_category_source[category][s] for s in sources):
            for source in sources:
                queue = by_category_source[category][source]
                if queue:
                    interleaved.append(queue.popleft())
    return interleaved
```

Update `main()`'s call site (was `capped_articles = cap_per_category(all_articles)`):

```python
    interleaved_articles = interleave_by_source(all_articles)

    if not interleaved_articles:
        logger.error("No articles were scraped from any source; not writing output.")
        raise SystemExit(1)

    output = {
        "generated_at": edition_date,
        "articles": interleaved_articles,
    }
```

(rename the `logger.info("Wrote %d article(s)...` line's variable reference from `capped_articles` to `interleaved_articles` too)

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_generate_data.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/generate_data.py tests/test_generate_data.py
git commit -m "feat(generate_data): remove per-category and per-source article caps, keep round-robin interleaving"
```

---

### Task 10: Data-driven `CATEGORY_DEFINITIONS` + `"categories"` output field

**Files:**
- Modify: `scraper/generate_data.py:28,206-234` (add `CATEGORY_DEFINITIONS`, derive `CATEGORIES` from it, extract a pure `build_output`, emit `"categories"`)
- Modify: `tests/test_generate_data.py` (add `build_output` test)

**Interfaces:**
- Consumes: `interleave_by_source` (Task 9), `CATEGORIES` (now derived, same name/shape other code already reads).
- Produces: `CATEGORY_DEFINITIONS: list[tuple[str, str]]` (key, label — display order, `"main"` first), `build_output(edition_date, articles) -> dict` (pure, tested) with shape `{"generated_at": ..., "categories": [{"key":..., "label":...}, ...], "articles": [...]}`.

- [ ] **Step 1: Write the failing test**

```python
# append to tests/test_generate_data.py
from scraper.generate_data import build_output, CATEGORY_DEFINITIONS


def test_build_output_includes_ordered_category_definitions():
    output = build_output("2026-08-23", [])
    assert output["generated_at"] == "2026-08-23"
    assert output["categories"] == [
        {"key": key, "label": label} for key, label in CATEGORY_DEFINITIONS
    ]
    assert output["categories"][0]["key"] == "main"


def test_build_output_includes_the_given_articles():
    articles = [{"id": "a1", "category": "main"}]
    output = build_output("2026-08-23", articles)
    assert output["articles"] == articles
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_generate_data.py -v -k build_output`
Expected: FAIL with `ImportError: cannot import name 'build_output'`

- [ ] **Step 3: Write minimal implementation**

Replace the old `CATEGORIES = ["politics", "world", "bangladesh", "sports", "finance"]` line (`scraper/generate_data.py:28`) with:

```python
# Single source of truth for the app's canonical category taxonomy: key,
# display label, in display order ("main" always first). Edited as part of
# Task 14 once the taxonomy from docs/section-discovery-report.md is
# finalized — today's 5 keyword-classified categories are the placeholder
# starting point, unchanged in meaning from before this pass.
CATEGORY_DEFINITIONS = [
    ("main", "Main"),
    ("politics", "Politics"),
    ("world", "World"),
    ("bangladesh", "Bangladesh"),
    ("sports", "Sports"),
    ("finance", "Finance"),
]

# Non-"main" category keys, in the order interleave_by_source() should
# process them — derived from CATEGORY_DEFINITIONS so there's one place to
# edit when the taxonomy changes.
CATEGORIES = [key for key, _label in CATEGORY_DEFINITIONS if key != "main"]
```

Add `build_output` (near `main()`, `scraper/generate_data.py:206`):

```python
def build_output(edition_date, articles):
    """Pure assembly of the published JSON shape."""
    return {
        "generated_at": edition_date,
        "categories": [{"key": key, "label": label} for key, label in CATEGORY_DEFINITIONS],
        "articles": articles,
    }
```

Update `main()` to use it (was building the `output` dict inline):

```python
    output = build_output(edition_date, interleaved_articles)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_generate_data.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scraper/generate_data.py tests/test_generate_data.py
git commit -m "feat(generate_data): emit ordered categories list in articles.json, derive CATEGORIES from it"
```

---

### Task 11: Dart `AppCategory` model + `categories` parsing in `article_repository.dart`

**Files:**
- Create: `app/lib/models/app_category.dart`
- Modify: `app/lib/data/article_repository.dart` (add `parseCategories`, `kDefaultCategories`, extend `ArticlesFetchResult`, update `fetchArticles`)
- Test: `app/test/models/app_category_test.dart` (new)
- Modify: `app/test/data/article_repository_test.dart` (add categories fixtures/tests)

**Interfaces:**
- Produces: `AppCategory { final String key; final String label; }` (with `==`/`hashCode` for test equality). `parseCategories(String jsonString) -> List<AppCategory>`. `const kDefaultCategories = [AppCategory(key: 'main', label: 'Main')]` — the single hardcoded fallback used whenever a parsed JSON blob has no `"categories"` field, or when there's no cache and no network at all. `ArticlesFetchResult` gains `final List<AppCategory> categories;`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/app_category_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/app_category.dart';

void main() {
  test('AppCategory instances with the same key and label are equal', () {
    const a = AppCategory(key: 'main', label: 'Main');
    const b = AppCategory(key: 'main', label: 'Main');
    expect(a, equals(b));
  });

  test('AppCategory instances with a different key are not equal', () {
    const a = AppCategory(key: 'main', label: 'Main');
    const b = AppCategory(key: 'politics', label: 'Main');
    expect(a, isNot(equals(b)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/app_category_test.dart`
Expected: FAIL with "Error: Error when reading 'lib/models/app_category.dart': No such file or directory"

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/models/app_category.dart
class AppCategory {
  final String key;
  final String label;

  const AppCategory({required this.key, required this.label});

  @override
  bool operator ==(Object other) =>
      other is AppCategory && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/app_category_test.dart`
Expected: PASS

- [ ] **Step 5: Write the failing test for `parseCategories`/`fetchArticles`**

```dart
// append to app/test/data/article_repository_test.dart
import 'package:newshead/models/app_category.dart';
```

Update `_validJson` (used throughout this file) to include a `"categories"` field:

```dart
const _validJson = '''
{
  "generated_at": "2026-08-20",
  "categories": [
    {"key": "main", "label": "Main"},
    {"key": "politics", "label": "Politics"},
    {"key": "sports", "label": "Sports"}
  ],
  "articles": [
    {"id": "a1", "category": "politics", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"},
    {"id": "a2", "category": "sports", "source": "Ittefaq", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2"}
  ]
}
''';

const _jsonWithoutCategories = '''
{
  "generated_at": "2026-08-20",
  "articles": [
    {"id": "a1", "category": "politics", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"}
  ]
}
''';
```

Add new tests (append inside `main()`, alongside the existing ones):

```dart
  test('parseCategories parses every category in order', () {
    final categories = parseCategories(_validJson);
    expect(categories, [
      const AppCategory(key: 'main', label: 'Main'),
      const AppCategory(key: 'politics', label: 'Politics'),
      const AppCategory(key: 'sports', label: 'Sports'),
    ]);
  });

  test('parseCategories returns the default list when categories is missing', () {
    expect(parseCategories(_jsonWithoutCategories), kDefaultCategories);
  });

  test('fetchArticles returns parsed categories from a successful response', () async {
    final client = MockClient((request) async => http.Response(_validJson, 200));
    final cache = InMemoryArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.categories, [
      const AppCategory(key: 'main', label: 'Main'),
      const AppCategory(key: 'politics', label: 'Politics'),
      const AppCategory(key: 'sports', label: 'Sports'),
    ]);
  });

  test('fetchArticles falls back to kDefaultCategories when there is no cache and no network', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.categories, kDefaultCategories);
  });
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `cd app && flutter test test/data/article_repository_test.dart`
Expected: FAIL — `parseCategories`/`kDefaultCategories` undefined, `ArticlesFetchResult` has no `categories` named parameter.

- [ ] **Step 7: Write minimal implementation**

In `app/lib/data/article_repository.dart`, add the import and the new parsing/default logic:

```dart
import '../models/app_category.dart';

const kDefaultCategories = [AppCategory(key: 'main', label: 'Main')];

List<AppCategory> parseCategories(String jsonString) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final rawCategories = decoded['categories'] as List<dynamic>?;
  if (rawCategories == null || rawCategories.isEmpty) return kDefaultCategories;

  final categories = <AppCategory>[];
  for (final raw in rawCategories) {
    try {
      final map = raw as Map<String, dynamic>;
      categories.add(AppCategory(
        key: map['key'] as String,
        label: map['label'] as String,
      ));
    } catch (_) {
      continue;
    }
  }
  return categories.isEmpty ? kDefaultCategories : categories;
}
```

Extend `ArticlesFetchResult`:

```dart
class ArticlesFetchResult {
  final List<NewsArticle> articles;
  final List<AppCategory> categories;
  final String? rawBody;
  final bool fromNetwork;

  const ArticlesFetchResult({
    required this.articles,
    required this.categories,
    required this.rawBody,
    required this.fromNetwork,
  });
}
```

Update every `ArticlesFetchResult(...)` construction site in `fetchArticles` to also populate `categories`:

```dart
Future<ArticlesFetchResult> fetchArticles({
  required Uri sourceUrl,
  required http.Client client,
  required ArticleCache cache,
}) async {
  try {
    final response = await client.get(sourceUrl);
    if (response.statusCode == 200) {
      final articles = parseArticles(response.body);
      final categories = parseCategories(response.body);
      try {
        await cache.write(response.body);
      } catch (_) {
        // Best-effort cache write; a failure here shouldn't discard a
        // successful fetch that's already been parsed.
      }
      return ArticlesFetchResult(
        articles: articles,
        categories: categories,
        rawBody: response.body,
        fromNetwork: true,
      );
    }
    debugPrint('fetchArticles: unexpected status ${response.statusCode} from $sourceUrl');
  } catch (error) {
    debugPrint('fetchArticles: network fetch of $sourceUrl failed: $error');
  }

  final cached = await cache.read();
  if (cached != null) {
    try {
      return ArticlesFetchResult(
        articles: parseArticles(cached),
        categories: parseCategories(cached),
        rawBody: cached,
        fromNetwork: false,
      );
    } catch (error) {
      debugPrint('fetchArticles: failed to parse cached articles: $error');
      return const ArticlesFetchResult(
        articles: [],
        categories: kDefaultCategories,
        rawBody: null,
        fromNetwork: false,
      );
    }
  }
  return const ArticlesFetchResult(
    articles: [],
    categories: kDefaultCategories,
    rawBody: null,
    fromNetwork: false,
  );
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd app && flutter test test/data/article_repository_test.dart test/models/app_category_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/lib/models/app_category.dart app/lib/data/article_repository.dart app/test/models/app_category_test.dart app/test/data/article_repository_test.dart
git commit -m "feat(article_repository): parse the categories list from articles.json with a hardcoded fallback"
```

---

### Task 12: `home_screen.dart` — drive tabs from data instead of a hardcoded const

**Files:**
- Modify: `app/lib/screens/home_screen.dart` (remove `kCategories`, accept `categories` from the widget, rebuild controllers if the category count changes on refresh)
- Modify: `app/lib/main.dart:19-31` (pass `categories: result.categories` through to `HomeScreen`)

**Interfaces:**
- Consumes: `AppCategory` (Task 11), `ArticlesFetchResult.categories` (Task 11).
- Produces: `HomeScreen({..., required List<AppCategory> categories})` — no more module-level `kCategories` const; `CategoryFeed`'s `category` param now receives `AppCategory.key` as before (unchanged), its pill label now comes from `AppCategory.label`.

- [ ] **Step 1: Update `HomeScreen`'s constructor and state**

In `app/lib/screens/home_screen.dart`, remove the `kCategories` const entirely (lines 9-16) and add the import:

```dart
import '../models/app_category.dart';
```

Add `categories` to the widget:

```dart
class HomeScreen extends StatefulWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;

  const HomeScreen({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
```

- [ ] **Step 2: Replace every `kCategories` reference with instance state, and rebuild controllers if the category count changes**

Replace the `_HomeScreenState` fields/`initState`/`dispose` block with:

```dart
class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const int _kLargePageBase = 100000;

  late TabController _tabController;
  late PageController _categoryPageController;
  bool _isSyncingFromPage = false;

  late List<NewsArticle> _articles;
  late List<AppCategory> _categories;
  String? _lastRawBody;
  int _refreshGeneration = 0;

  // ... (_weekdayNames / _monthNames unchanged) ...

  @override
  void initState() {
    super.initState();
    _articles = widget.initialArticles;
    _categories = widget.initialCategories;
    _lastRawBody = widget.initialRawBody;
    _initControllers(_categories.length);
  }

  void _initControllers(int n) {
    _tabController = TabController(length: n, vsync: this);
    _categoryPageController = PageController(
      initialPage: (_kLargePageBase ~/ n) * n,
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
```

- [ ] **Step 3: Replace every remaining `kCategories` reference with `_categories`**

`_onTabChanged`/`_nearestPageForCategory`/`_onCategoryPageChanged` each read `kCategories.length` — replace with `_categories.length`:

```dart
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

  int _nearestPageForCategory(int currentPage, int categoryIndex) {
    final n = _categories.length;
    final currentCategoryIndex = currentPage % n;
    var diff = categoryIndex - currentCategoryIndex;
    if (diff > n / 2) diff -= n;
    if (diff < -n / 2) diff += n;
    return currentPage + diff;
  }

  void _onCategoryPageChanged(int page) {
    _isSyncingFromPage = true;
    _tabController.index = page % _categories.length;
    _isSyncingFromPage = false;
  }
```

- [ ] **Step 4: Update `_handleRefresh` to also refresh categories, rebuilding controllers if the count changed**

```dart
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
    setState(() {
      _articles = articles;
      _lastRawBody = result.rawBody;
      _refreshGeneration++;
      if (result.categories.length != _categories.length) {
        _disposeControllers();
        _initControllers(result.categories.length);
      }
      _categories = result.categories;
    });
  }
```

- [ ] **Step 5: Update `build()` to read `_categories` instead of `kCategories`**

```dart
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
                child: Text(
                  _todayLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _categoryPageController,
              onPageChanged: _onCategoryPageChanged,
              itemBuilder: (context, page) {
                final category = _categories[page % _categories.length];
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
      bottomNavigationBar: ColoredBox(
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
                      for (var i = 0; i < _categories.length; i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                          child: _CategoryPill(
                            label: _categories[i].label,
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
```

(`_CategoryPill` itself is unchanged.)

- [ ] **Step 6: Update `main.dart` to pass categories through**

```dart
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
  ));
}

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

(add `import 'models/app_category.dart';` to `main.dart`'s imports)

- [ ] **Step 7: Run the full Dart test suite**

Run: `cd app && flutter test`
Expected: PASS (no `home_screen_test.dart` exists today, so this task has no dedicated widget test to update — `article_repository_test.dart` and `app_category_test.dart` from Task 11 are what exercise the new data shape)

- [ ] **Step 8: Manual smoke test**

Run: `cd app && flutter run` (any connected device/simulator). Confirm: the app launches, the bottom pill bar still shows "Main, Politics, World, Bangladesh, Sports, Finance" (today's `CATEGORY_DEFINITIONS` placeholder from Task 10 — unchanged in meaning), swiping/tapping between them still works, and pull-to-refresh still works.

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/home_screen.dart app/lib/main.dart
git commit -m "feat(home_screen): drive category tabs from fetched data instead of a hardcoded constant"
```

---

### Task 13: Update remaining Dart test fixtures that assume the old JSON shape

**Files:**
- Modify: `app/test/data/article_cache_test.dart`, `app/test/screens/category_feed_test.dart`, `app/test/widgets/news_card_test.dart` — check each for any JSON fixture or `ArticlesFetchResult`/`HomeScreen` construction that predates the `categories` field or the `initialCategories` constructor parameter.

**Interfaces:**
- None new — this task only fixes compilation/fixture drift introduced by Tasks 11-12.

- [ ] **Step 1: Search for other call sites that need updating**

Run: `cd app && grep -rn "ArticlesFetchResult(\|HomeScreen(\|kCategories" test/ lib/`

Expected: only the sites already updated in Tasks 11-12 remain, plus `test/data/article_repository_test.dart` (already updated). `article_cache_test.dart`, `category_feed_test.dart`, and `news_card_test.dart` don't construct `ArticlesFetchResult` or `HomeScreen` and don't reference `kCategories` (per the earlier grep during planning), so no changes are expected here — this step is a verification, not a rewrite.

- [ ] **Step 2: Run the full test suite**

Run: `cd app && flutter test`
Expected: PASS. If Step 1's grep turns up an unexpected call site, fix its fixture the same way `article_repository_test.dart` was fixed in Task 11 (add a `"categories"` field to any inline JSON fixture; add `initialCategories`/`categories` to any `HomeScreen`/`ArticlesFetchResult` construction) before re-running.

- [ ] **Step 3: Commit (only if Step 1 required changes)**

```bash
git add app/test
git commit -m "test(app): fix remaining fixtures for the new categories field"
```

---

### Task 14: Apply the real taxonomy — GATED on Task 7's discovery report + user input

**Do not start this task until the user has reviewed `docs/section-discovery-report.md` (Task 7) and dictated back the final category list and per-source section mapping.** Tasks 8-13 built the mechanism this task fills in; nothing here changes app behavior beyond what those tasks already validated with the placeholder 5-category taxonomy.

**Files:**
- Modify: `scraper/generate_data.py` — `CATEGORY_DEFINITIONS` (Task 10), `SECTION_CATEGORY_MAP` (Task 8), `CATEGORY_KEYWORDS` (existing, pre-Task-8)
- Test: `tests/test_generate_data.py` — add mapping/keyword assertions for the real taxonomy

- [ ] **Step 1: Replace `CATEGORY_DEFINITIONS` with the user's final category list**

Edit the list added in Task 10 to the user's dictated `(key, label)` pairs, in their dictated display order, with `"main"` first:

```python
CATEGORY_DEFINITIONS = [
    ("main", "Main"),
    # ... one (key, label) tuple per category the user dictated ...
]
```

`CATEGORIES` (derived from this) updates automatically.

- [ ] **Step 2: Fill in `SECTION_CATEGORY_MAP` per source**

For each source in `scraper.config.SOURCES`, add an entry per raw section from `docs/section-discovery-report.md` that the user assigned to a category:

```python
SECTION_CATEGORY_MAP = {
    "jugantor": {
        # "raw-section-slug": "canonical_category_key",
    },
    "prothomalo": {},
    "dhakatribune": {},
    "dailystar": {},
    "ittefaq": {},
}
```

A source's sections the user did NOT assign are left out of its dict entirely — they'll fall through to `CATEGORY_KEYWORDS` matching (Step 3) or be dropped, exactly as today's unmatched sections are.

- [ ] **Step 3: Expand `CATEGORY_KEYWORDS` for every new category**

For each new category in `CATEGORY_DEFINITIONS` that isn't one of the original 5 (`politics, world, bangladesh, sports, finance`), add a bilingual (English + Bengali) keyword list, matching the existing style at `scraper/generate_data.py:44-65`:

```python
CATEGORY_KEYWORDS = {
    "politics": [...],  # unchanged
    "sports": [...],  # unchanged
    "finance": [...],  # unchanged
    "world": [...],  # unchanged
    "bangladesh": [...],  # unchanged
    # "new_category_key": ["english keyword", ..., "বাংলা কিওয়ার্ড", ...],
}
```

- [ ] **Step 4: Write tests for the new taxonomy**

Add to `tests/test_generate_data.py`, using the user's actual new category keys/keywords in place of the placeholders below:

```python
def test_classify_article_category_maps_new_sections_explicitly():
    # One assertion per (source, section) pair the user assigned in
    # SECTION_CATEGORY_MAP, e.g.:
    # assert classify_article_category("dhakatribune", "arts-and-letters", "Arts & Letters", "A new exhibit opens") == "culture"
    pass  # replace with real assertions before running


def test_classify_category_matches_new_category_keywords():
    # One assertion per new CATEGORY_KEYWORDS entry, e.g.:
    # assert classify_category("New exhibit opens downtown", "Arts") == "culture"
    pass  # replace with real assertions before running
```

- [ ] **Step 5: Run the full Python test suite**

Run: `pytest -v`
Expected: PASS

- [ ] **Step 6: Runtime sanity check — time a real generation run**

Run: `time python scripts/generate.py`

Uncapping article volume (Task 9) means this run now scrapes every mapped section's full article list instead of stopping at 12/category — check the elapsed time and the article count logged ("Wrote N article(s) to..."). If N is unexpectedly large (many hundreds+) or the run takes long enough to threaten the GitHub Actions workflow's timeout, revisit which sections were mapped in Step 2 (a very broad mapping across many high-volume sections is the most likely cause) before proceeding — this plan intentionally left no code-level cap, per the resolved decision to fetch everything.

- [ ] **Step 7: Manual end-to-end app verification**

Run: `cd app && flutter run`. Confirm every category the user dictated appears as a pill in the correct order, swiping/tapping through all of them works, and each category that should have articles actually shows some (i.e. the mapping in Step 2 is producing real classified articles, not silently dropping everything into "no matches").

- [ ] **Step 8: Commit**

```bash
git add scraper/generate_data.py tests/test_generate_data.py
git commit -m "feat(generate_data): apply the finalized category taxonomy and section mapping"
```

---

## Self-Review Notes

- **Spec coverage**: every resolved decision from the grill-with-docs interview maps to a task — bypass allowlists (Tasks 1-5), committed discovery tool (Task 6), checkpoint before taxonomy work (Task 7), Main untouched (all tasks, explicitly called out in Global Constraints and Task 8), explicit mapping wins over keyword fallback (Task 8), expanded keyword fallback (Task 14 Step 3), centralized mapping in `generate_data.py` (Task 8), uncapped fetch with interleaving kept (Task 9), data-driven app categories with a hardcoded missing-field default (Tasks 10-12), user dictates the taxonomy directly with no AI-drafted proposal (Task 7's stop point, Task 14's gate).
- **Placeholder scan**: Task 14 is the one task that can't contain real values yet (the taxonomy doesn't exist until the user supplies it after Task 7) — its steps are fully actionable instructions (exact structures to edit, exact commands to run) rather than vague TODOs, consistent with why Phase B was split the way it was.
- **Type/name consistency checked**: `classify_article_category` (Task 8) is the only new call site `collect_source_articles` uses; `interleave_by_source` (Task 9) is what `main()` calls, replacing `cap_per_category` everywhere including its import in any future test; `CATEGORY_DEFINITIONS`/`CATEGORIES` (Task 10) — `CATEGORIES` is derived, not independently maintained; `AppCategory`/`kDefaultCategories`/`parseCategories` (Task 11) are consumed by `ArticlesFetchResult.categories` and then by `HomeScreen.initialCategories` (Task 12) — same names throughout.
