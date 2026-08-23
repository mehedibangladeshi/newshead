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
      the 5 sources logs `INFO: <source>: collected N article(s)`.
  - **Known limitation, not a regression:** jugantor, dhakatribune, and
    ittefaq return `403 Forbidden` for every section when scraped from
    GitHub-hosted runner IPs (bot protection on those sites' end) — this
    reproduces on every run, old and new. Expect 0 articles from those 3
    sources in CI; only prothomalo and dailystar reliably succeed there.
    A local run from a residential IP collects from all 5.
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
      (jugantor/prothomalo/ittefaq → `bn`; dhakatribune/dailystar → `en`).
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
      `TabController` ↔ `PageView` sync holds both directions).
- [ ] A category with articles shows: source pill, headline (however long —
      never cut off with "…"; only the text block below the photo scrolls
      if it doesn't fit), a publish-timestamp row under the headline in the
      source's own language when `publishedAt` is present (absent entirely
      when it's null), snippet, "Read more", a correctly-aspect-ratioed
      sharp image, and a blurred backdrop filling the leftover space.
- [ ] A category with zero articles shows "No stories yet" instead of
      crashing or looping — exercise this by picking a category only ever
      populated by a currently-blocked source.
- [ ] Vertically swiping within a category advances to the next article;
      swiping past the last article doesn't crash (bounded, not infinite).
- [ ] Tapping a card opens `ArticleWebViewScreen`, loads the real
      `articleUrl`, and the back arrow returns to the feed.
- [ ] Pull-to-refresh shows a spinner and re-fetches; if the response is
      byte-identical to last time, order visibly reshuffles instead of
      looking like a no-op.
- [ ] Airplane mode / no network: app falls back to the last cached
      `articles.json` rather than showing nothing; pulling to refresh shows
      the "Could not refresh — check your connection" snackbar instead of
      crashing.
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
