# NewsHead Test Plan

Manual + automated verification covering the scraper pipeline, the published
`articles.json` data contract, and the Flutter app. Re-run this whenever the
category taxonomy, scraper sources, or app data flow changes.

## 1. Automated suites (run first, always)

- `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`
- `.venv/bin/python -m pytest tests/ -v` — scraper unit tests (section→category
  mapping, discovery, generate_data assembly).
- `cd app && flutter analyze` — must report no issues.
- `cd app && flutter test` — model/data/widget/screen tests.

## 2. Scraper / GitHub Action

- [ ] Trigger `.github/workflows/scrape.yml`: `gh workflow run scrape.yml`.
- [ ] `gh run watch <run-id> --exit-status` until it finishes.
- [ ] Read the job log (`gh run view --job=<job-id> --log`) and check each of
      the 8 sources logs `INFO: <source>: collected N article(s)`.
  - **Known limitation, not a regression:** jugantor, dhakatribune, and
    ittefaq return `403 Forbidden` for every section when scraped from
    GitHub-hosted runner IPs (bot protection on those sites' end) — this
    reproduces on every run, old and new. Expect 0 articles from those 3
    sources in CI; only prothomalo, dailystar, tbsnews, banglatribune, and
    samakal reliably succeed there. A local run from a residential IP
    collects from all 8.
  - **2026-08-24 source research:** curled ~20 more Bangladeshi newspaper
    sites with a spoofed desktop UA to check for Cloudflare blocking before
    adding sources. Confirmed Cloudflare-blocked (403 / bot-challenge, same
    failure mode as jugantor/dhakatribune/ittefaq): bdnews24, kalerkantho,
    bd-pratidin, jagonews24, risingbd, daily-sun, banglanews24 — not
    attempted. Confirmed clean but not yet added: see `docs/ideas.md`
    "More scraper sources" backlog. Confirmed clean and added this session:
    tbsnews, banglatribune, samakal.
  - Total article count should be sane (tens, not zero across every source,
    not thousands).

## 3. Data contract (`articles.json`)

Fetch `https://mehedibangladeshi.github.io/newshead/articles.json` (or the
local file from a manual `python scripts/generate.py` run) and verify:

- [ ] Top-level keys are exactly `generated_at`, `categories`, `articles`.
- [ ] `generated_at` matches the date of the most recent successful run.
- [ ] `categories` has exactly 17 entries matching `CATEGORY_DEFINITIONS` in
      `scraper/generate_data.py`, in that order, `main` first.
- [ ] Every article's `category` is one of those 17 keys — no unknown values.
- [ ] Every article has non-empty `id`, `category`, `source`, `headline`,
      `imageUrl`, `articleUrl` (`snippet` may legitimately be empty).
- [ ] No duplicate `id`s.
- [ ] Every article's `language` is `"bn"` or `"en"`, matching its `source`
      (jugantor/prothomalo/ittefaq/banglatribune/samakal → `bn`;
      dhakatribune/dailystar/tbsnews → `en`).
- [ ] `publishedAt` is either a parseable ISO-8601 datetime or `null` — never
      an empty string or a raw source-specific phrase leaking through.
  - Sanity, not a bug, if seen: dailystar's fill rate is only as good as its
    "N MIN(s)"/"N HOUR(s)" listing text; Dhaka Tribune's is well under 100%
    because most of its listing cards carry no time element at all.

Quick check:

```python
import json, urllib.request
from collections import Counter

d = json.load(urllib.request.urlopen('https://mehedibangladeshi.github.io/newshead/articles.json'))
cats = {c['key'] for c in d['categories']}
arts = d['articles']
assert len(d['categories']) == 17
assert all(a['category'] in cats for a in arts)
assert all(all(a.get(k) for k in ('id', 'category', 'source', 'headline', 'imageUrl', 'articleUrl')) for a in arts)
assert len({a['id'] for a in arts}) == len(arts)
assert all(a.get('language') in ('bn', 'en') for a in arts)
print(Counter(a['category'] for a in arts))
print('publishedAt fill rate by source:')
by_source = {}
for a in arts:
    by_source.setdefault(a['source'], [0, 0])
    by_source[a['source']][1] += 1
    if a.get('publishedAt'):
        by_source[a['source']][0] += 1
for source, (has, total) in by_source.items():
    print(f'  {source}: {has}/{total}')
```

## 4. Flutter app — build & install

- [ ] `cd app && flutter pub get`
- [ ] `flutter build apk --debug` (or `flutter run -d <device>` for iteration)
- [ ] `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- [ ] `adb shell am start -n com.newshead.newshead/.MainActivity`

## 5. Flutter app — manual smoke test

- [ ] App launches without crashing; app bar shows the chevron badge +
      "NEWSHEAD" wordmark on the left (no date anywhere) and a filter icon
      on the right.
- [ ] The bottom pill bar renders one pill per **visible** category — a
      category from the fetched JSON with at least one article and not
      hidden by the reader's filter — not the raw fetched list and not a
      hardcoded one. A category with zero articles today must not appear
      as a pill even though it's still in the fetched `categories` array.
- [ ] Tapping a pill animates the tab and switches the feed to that category.
- [ ] Horizontally swiping the main feed also updates the selected pill (the
      `TabController` ↔ `PageView` sync holds both directions), and the pill
      bar auto-scrolls (centered) to keep the newly-selected pill visible
      even when it's off-screen.
- [ ] A category with articles shows: source pill, headline (however long —
      never cut off, never scrollable), a publish-timestamp row under the
      headline in the source's own language when `publishedAt` is present
      (absent entirely when it's null), a correctly-aspect-ratioed sharp
      image, and a blurred backdrop filling the leftover space. The snippet
      shows in full with "Read more" right below when it fits the
      remaining space; only when it doesn't does that snippet+"Read more"
      pair become a small, tightly-bounded scrollable region — swiping
      anywhere else on the card must always page to the next article, never
      get captured by an inner scroll.
- [ ] A category with zero articles shows "No stories yet" instead of
      crashing or looping — exercise this by picking a category only ever
      populated by a currently-blocked source.
- [ ] Vertically swiping within a category advances to the next article;
      swiping past the last article loops back to the first (infinite in
      both directions), never a dead end.
- [ ] Tapping a card opens `ArticleWebViewScreen`, loads the real
      `articleUrl` in a dark reading mode (inverted-CSS-filtered page, site
      logo still legible, photos in natural color), and the back arrow
      returns to the feed.
- [ ] Tapping the refresh button (top bar, right of the filter icon) shows a
      spinner in place of its icon and re-fetches; if the response is
      byte-identical to last time, order visibly reshuffles instead of
      looking like a no-op. There is no pull-to-refresh gesture.
- [ ] Airplane mode / no network: app falls back to the last cached
      `articles.json` rather than showing nothing; tapping refresh shows
      the "Could not refresh — check your connection" snackbar instead of
      crashing.
- [ ] Status bar icons (time/battery/signal) are visible (light icons) on
      every screen, including the home screen's custom top bar, which has
      no `AppBar` for Flutter to auto-derive icon brightness from.
- [ ] Tapping the filter icon opens a bottom sheet listing the **full**
      17-category taxonomy (not just today's visible ones), everything
      checked by default, no visible render-overflow error even scrolled to
      the bottom of the list.
- [ ] Unchecking a category in the sheet hides its pill immediately (no
      Apply button — dismissing the sheet is the only "save" there is), and
      the filter icon gains a small red badge dot.
- [ ] Relaunching the app after unchecking a category keeps it hidden (the
      choice is persisted via `shared_preferences`), and the badge dot is
      still showing.

## 6. This session's run (2026-08-23)

- Triggered `scrape.yml` manually (run `32627509841`) — succeeded in 1m59s.
  Log confirmed the known 403 pattern for jugantor/dhakatribune/ittefaq;
  prothomalo (70) + dailystar (91) = 161 articles published.
- Verified the published `articles.json`: 17 categories present and in
  order, 0 unknown categories, 0 missing required fields, 0 duplicate ids.
- Ran the full smoke test (§5) on a Pixel 9 (API 35) emulator against the
  live data: category pills, tab/swipe sync, empty-category state, vertical
  paging, article webview, and category filtering all matched the fetched
  data correctly.
- **Bug found and fixed:** a transient network blip during the very first
  image request left that image permanently black for the rest of the app
  session — `NetworkImage` has no connect timeout by default, so a
  black-holed connection just hangs forever instead of erroring into the
  widget's own broken-image fallback. Fixed in `app/lib/main.dart` with a
  global `HttpOverrides` setting a 15s `connectionTimeout`, matching the
  existing 15s timeout already used for the `articles.json` fetch in
  `article_repository.dart`. Verified fixed by reproducing the hang, then
  confirming a fresh launch loaded the same image correctly.
- Pre-existing, out of scope: the 403s in §2 are infra-level (GitHub Actions
  IP ranges being blocked by 3 of 5 sources), unrelated to the
  category-remapping change that was reviewed and merged this session.

## 7. Dynamic categories, filters, timestamp & branding feature (2026-08-23)

Implemented via `docs/superpowers/plans/2026-08-23-dynamic-categories-and-filters.md`
(13 tasks + a final-review fix wave), merged to `main` at `bca431a`. Full
suite green at merge: 58 Python tests, `flutter analyze` clean, 61 Flutter
tests.

Two real bugs were found only through on-device verification, not by any
automated test, and both are fixed and re-verified on an emulator:

- **dailystar's `publishedAt` never parsed in production (0/114 articles).**
  The parser expected "2 hours ago"; the site's real listing text is
  "1 MIN(s)" / "5 HOUR(s)" — abbreviated units, no "ago". Caught by the
  final whole-branch review fetching the live page directly, since the
  test fixture had been hand-written from the plan's (wrong) assumption
  rather than pasted from a real response. Fixed by broadening
  `scraper/timestamps.py`'s regex, and the fixture now uses the real text.
- **The filter sheet overflowed on a real device with the full 17-category
  list** ("BOTTOM OVERFLOWED BY 79 PIXELS") — invisible to widget tests,
  which only ever used 2 fake categories. Fixed with
  `isScrollControlled: true` on the `showModalBottomSheet` call.

Lesson for future scraper work on this repo: a source's raw HTML/markup
fixture must be pasted from an actual live response, never hand-written
from a plan's prose description of what the markup "should" look like —
both bugs above trace back to exactly that shortcut.

Also fixed in the same final review: unbounded relative-time formatting
(a genuinely old article was rendering as e.g. "3333d ago" — added
week/month/year tiers), and a `language` field parsed less defensively
than `publishedAt` (a stray non-string value silently dropped the whole
article).

Parked, not fixed — real but non-blocking; see the plan's own ledger for
full rulings: a triplicated derive-and-resize-controllers pattern in
`home_screen.dart`, a filter badge that doesn't clear if an excluded
category later leaves the taxonomy, a brief cold-start pill-bar flicker
before the persisted filter loads, a fire-and-forget preference write,
and the brand wordmark's font being fetched over the network on first use
rather than bundled.

## 8. Dark theme, WebView dark mode, and feed interaction overhaul (2026-08-23)

Two pieces of work, both verified live on a Pixel 9 (API 35) emulator.

**WebView dark mode.** `ArticleWebViewScreen` injects a CSS invert filter
(`invert(1) hue-rotate(180deg)` on `html`, re-inverted on photo/video/embed
elements) into the external article page on `onPageFinished`, so it roughly
matches the app's dark theme instead of opening a jarring light page.
Two real bugs were found only by inspecting a live article's DOM (via
`setOnConsoleMessage` + an injected survey script), not by guessing:

- **Site logo unreadable.** The logo `<img>` was correctly re-inverted back
  to its true (dark-on-light-designed) colors, but its `<header>` container
  only got the page-wide invert once — a correctly-restored dark logo on a
  correctly-inverted dark header is unreadable. Fixed by excluding
  `header img`/`nav img` from the re-invert rule, so logos behave like the
  rest of the page's text (single-inverted, dark→light) instead of being
  restored to their original colors.
- **Main image looked inverted.** The site wraps its real (correctly
  re-inverted) `<img>` in a `<div style="background-image:url(...)">`
  lazy-load placeholder, set via inline `style` — invisible to a plain
  `img`/`video`/... selector, so it showed through in the wrong colors at
  the image's edges/loading window. Fixed by adding
  `[style*="background-image"]` to the re-invert selector.

Both fixes are generic (`<header>`/`<nav>` and inline-style background
placeholders are common patterns, not Prothom Alo-specific), not point
patches for one source.

**Dark theme + feed interactions.** Consolidated every screen's hand-rolled
color/font literals into `lib/theme/app_theme.dart` (`AppColors`, an
`AppTypography` `ThemeExtension` for Anton), fixed the status bar/Android
nav-bar icon brightness (previously invisible against the dark background,
since most screens have no `AppBar` for Flutter to auto-derive it from),
and shipped four feed changes: the category pill bar auto-scrolls the
selected pill into view via `Scrollable.ensureVisible`; pull-to-refresh was
replaced with a refresh button + spinner; the vertical article feed now
loops infinitely (same large-base/modulo `PageView` technique already used
for the horizontal category loop); and the news card's snippet area no
longer wraps the whole text block in one big scrollable — headline/meta
are always static, and only the snippet+"Read more" pair becomes a small
bounded scrollable when it doesn't fit, so a swipe anywhere else on the
card reliably pages to the next article.

**Lesson for future multi-agent dispatch on this repo:** three of five
subagents run in parallel for this work independently invoked
`git stash`/`git stash pop` mid-task (to "diff against a clean baseline"),
which collided across the shared working tree and briefly reverted two
files to their pre-session state. Recovered via the stray stash entry each
collision left behind; no work was ultimately lost, but future prompts to
parallel agents editing the same working tree should explicitly forbid git
operations beyond read-only status checks.

## 9. Three new scraper sources: The Business Standard, Bangla Tribune, Samakal (2026-08-24)

Researched ~20 additional Bangladeshi newspapers, curl-tested each for
Cloudflare blocking (see §2 above and `docs/ideas.md`), then added the 3
that came back clean: `scraper/sources/tbsnews.py` (English),
`scraper/sources/banglatribune.py` (Bangla), `scraper/sources/samakal.py`
(Bangla) — one module per source, built in parallel by independent
subagents that fetched real live pages before writing selectors (per the
lesson in §7, no hand-written fixtures). Wired into
`scraper/config.py::SOURCES`, `scraper/generate_data.py`
(`SOURCE_DISPLAY_NAMES`, `SOURCE_LANGUAGE`, `SECTION_CATEGORY_MAP`), and
`scraper/timestamps.py` (2 new parser cases: tbsnews's abbreviated relative
time `"6m"/"1h"/"1d"`, samakal's 24-hour Bengali absolute datetime with no
AM/PM marker — banglatribune reused the existing ISO-offset parser, same
CMS as dhakatribune).

An Opus-level audit pass over the diff (the one designated Opus step for
this task) caught two real bugs before commit: `samakal.py`'s
`parse_articles()` only selected the lead card + top-4 cards per section,
silently missing a further ~10-story `div.CatSubList-area` list that
carries its own summary/timestamp markup (fixed by extending the card
selector — samakal's per-run count went 50 → 150); and `tbsnews`'s
sections are derived from each article URL's own path segment rather than
a fixed nav, so 5 real slugs (`foreign-policy`, `nbr`, `infograph`,
`top-news`, `rohingya-crisis`) had no `SECTION_CATEGORY_MAP`/
`SECTION_DISPLAY_NAMES` entry and were being silently dropped by
`classify_category` (fixed by mapping all 5). Also added the missing
`tests/test_tbsnews_sections.py`, `tests/test_banglatribune_sections.py`,
`tests/test_samakal_sections.py` and timestamp-parser test cases the audit
flagged as absent, and hardened the 2 new `timestamps.py` parsers (case-
sensitive unit letters, `OverflowError` guard) per its minor-nit list.

Verified with a full local `python scripts/generate.py` run after fixes
(all 8 sources succeeded; 75 pytest suite green, up from 58): `tbsnews` 177
articles, `banglatribune` 251 (211/251 `publishedAt` filled), `samakal` 150
(150/150). Data contract re-validated against the live output — 17
categories, no unknown categories, no missing required fields, no
duplicate ids, every `language` is `bn`/`en` and matches its source.

**Not yet confirmed:** whether these 3 also hit the CI-runner-IP 403
pattern from §2 — that curl-based research was done from a residential IP,
same limitation as the original jugantor/dhakatribune/ittefaq finding.
Confirm on the next `gh workflow run scrape.yml` and update §2's fill list
if any of the 3 turn out to be CI-blocked too.

**Parked as future work**, not attempted this session: the 9 other
confirmed-clean candidates and 7 newly-confirmed-blocked sites listed in
`docs/ideas.md`.
