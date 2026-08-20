# NewsHead v1 — Design

## Overview

NewsHead is a standalone news app: a Python scraper pipeline that runs on a schedule, publishes a JSON snapshot of real news articles to GitHub Pages, and a Flutter app that fetches that JSON and presents it as a reels-style (TikTok/Instagram-like) vertical card feed, swipeable between 6 fixed categories.

This is the first "real project" iteration, evolved out of a throwaway prototype (`mobile_prototype/` in `mehedibangladeshi/DailyNewspaperPublish`) that used a hand-scraped, one-time, bundled-asset data snapshot. NewsHead replaces that with a live, self-refreshing pipeline and its own repo, identity, and independent evolution — no shared code or CI with the Kindle-epub project it was extracted from.

## Repo & Directory Structure

New repo: `mehedibangladeshi/newshead` (public, so GitHub Pages can serve the JSON without auth and the app can fetch it unauthenticated).

```
newshead/
  scraper/
    sources/              # jugantor.py, prothomalo.py, dhakatribune.py, dailystar.py,
                           #   ittefaq.py, text_utils.py, ld_json.py — copied from the
                           #   prototype's jugantor_epub/sources/*.py, then evolve
                           #   independently (no shared code with the origin repo going
                           #   forward)
    config.py              # SOURCES list, request settings (copied/trimmed from
                            #   jugantor_epub/config.py)
    bengali_date.py         # only if still needed
    generate_data.py        # copied/adapted from jugantor_epub/prototype_data.py —
                             #   classify_category, truncate_snippet, make_article_id,
                             #   enrich_item, collect_source_articles, cap_per_category,
                             #   main() — including this session's fixes (sports-before-
                             #   world keyword ordering, round-robin source capping,
                             #   fetch_article() enrichment)
    requirements.txt
  scripts/
    generate.py              # thin CLI wrapper (same shape as
                              #   scripts/generate_prototype_data.py)
  app/
    (the renamed Flutter project — was mobile_prototype/)
    lib/
      data/
        article_repository.dart   # now fetches from a URL + caches locally, no bundled
                                   #   assets/articles.json
      ...
  .github/workflows/
    scrape.yml                # cron 4x/day, runs scripts/generate.py, publishes to
                               #   gh-pages
  docs/
    superpowers/specs/, plans/   # same convention as the origin repo
  README.md
```

## Scraper Pipeline & Publishing

- `scraper/generate_data.py` is a direct port of `jugantor_epub/prototype_data.py`'s logic: `discover_sections()` → `list_articles()` per section → keyword classification (or "main" for a source's first section) → `enrich_item()` (calls `fetch_article()` only for listing items missing a thumbnail/summary) → round-robin `cap_per_category()` at 12 per category.
- `.github/workflows/scrape.yml`: triggers on `cron: '0 1,5,10,14 * * *'` (UTC, = 7 AM / 11 AM / 4 PM / 8 PM Asia/Dhaka) plus `workflow_dispatch` for manual runs. Steps: checkout, set up Python, install `scraper/requirements.txt`, run `scripts/generate.py` to produce `articles.json`, then publish that single file to the `gh-pages` branch with a force-orphan replace (same mechanism as the origin repo's existing `opds_publish.py` — full branch history isn't needed, each run's snapshot fully replaces the last).
- Published URL: `https://mehedibangladeshi.github.io/newshead/articles.json`.
- **Failure handling**: if the scrape/generate step fails (network error, all 5 sources down), the workflow does not reach the publish step, so GitHub Pages keeps serving the last successful snapshot rather than an empty or corrupt one. A single source failing (as already handled by the copied pipeline's per-source try/except) still produces a valid partial snapshot and publishes normally.

## Flutter App Changes

- **Rename**: pubspec `name: newshead`; Android `applicationId` and iOS bundle identifier both `com.newshead.app`; app display title "NewsHead". Done once, cleanly, as part of the repo move (not left as `mobile_prototype`-era debt).
- **Data source**: `assets/articles.json` and its `pubspec.yaml` asset declaration are removed. `lib/data/article_repository.dart` gains:
  ```dart
  Future<List<NewsArticle>> fetchArticles({required Uri sourceUrl})
  ```
  which does an HTTP GET (via the `http` package) against the published GitHub Pages URL, parses the response with the existing `parseArticles()`, and on success writes the raw response body to a local cache file (via `path_provider`, e.g. `<app documents dir>/articles_cache.json`).
- **Fallback behavior**: if the HTTP GET fails (no network, GitHub Pages unreachable) or returns a non-200 status, read the local cache file if it exists and parse that instead. If there's no cache either (first-ever launch with no network), fall back to an empty list — same "No stories yet" empty-category UI the app already has, no new UI needed.
- `main()` stays async, now awaiting `fetchArticles(...)` instead of `rootBundle.loadString(...)`.
- Both `http` and `path_provider` are standard, first-party Flutter/Dart packages (not new architectural surface).
- No pull-to-refresh in this pass — one fetch per app launch.

## Migration From the Prototype

- Copy (not history-preserving move) into the new repo: the Flutter app with renames applied, the 5 scraper source modules, and `prototype_data.py`'s logic adapted into `generate_data.py`.
- Seed the new repo with one already-generated `articles.json` (reuse the one already produced in the prototype) so the app has something to render before the first scheduled cron run.
- The origin repo's `mobile_prototype/` directory is deleted only after the new repo is confirmed working end-to-end, and only with explicit go-ahead at that point — not automatically as part of this migration.

## Error Handling & Edge Cases

- Cron run fails entirely → last successful `articles.json` keeps serving (see Failure handling above).
- Malformed/corrupted local cache file → treated the same as "no cache" (parse failure falls through to empty list), not a crash.
- `parseArticles()` continues to skip individual malformed JSON entries rather than failing the whole parse (unchanged from the prototype).

## Testing

- Python: same approach as the prototype — pure functions (`classify_category`, `truncate_snippet`, `make_article_id`, `enrich_item`'s pure parts) unit-tested; I/O-driving orchestration verified by actually running the generator, not unit-tested.
- Flutter: `fetchArticles()` takes an injectable HTTP client (same testability-shim pattern as `NewsCard`'s `imageProviderBuilder`), so success, HTTP-failure-with-cache, and no-cache-no-network paths are all unit-testable without real network calls or a real filesystem (inject a fake cache reader/writer too, or test against a temp directory — implementation detail for the plan).

## Out of Scope (this pass)

- Pull-to-refresh or any in-app manual refresh control.
- Push notifications.
- Any change to the origin `DailyNewspaperPublish` repo (it is not touched by this work).
- Preserving git history/commit authorship across the prototype → NewsHead copy.
