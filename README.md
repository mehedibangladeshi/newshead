# NewsHead

A self-scraping news app: a Python pipeline scrapes 5 Bengali/English newspapers
4x/day, classifies articles into a 17-category taxonomy (16 topics plus a
per-source Main), tags each with a publish timestamp and language, and
publishes the result to GitHub Pages. The Flutter app fetches that JSON at
launch and presents it as a reels-style (TikTok/Instagram-like) vertical,
swipeable card feed that loops seamlessly in both directions — never a dead
end scrolling down or between categories. Only categories that actually have
a story today are shown, and the reader can hide any category permanently via
a filter sheet.

## Scraper

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python scripts/generate.py   # writes articles.json at the repo root
.venv/bin/python -m pytest tests/ -v
```

`.github/workflows/scrape.yml` runs this automatically 4x/day (7 AM / 11 AM / 4 PM /
8 PM Asia/Dhaka) and publishes `articles.json` to the `gh-pages` branch, served at
`https://mehedibangladeshi.github.io/newshead/articles.json`.

Use `scripts/discover_sections.py` to audit each source's full raw navigation
(bypassing the per-source discovery allowlists) when auditing or redesigning
the category taxonomy later.

### Data contract

`articles.json` has three top-level keys:

- `generated_at` — the run's edition date (`YYYY-MM-DD`).
- `categories` — the full 17-entry taxonomy in display order, each
  `{"key": ..., "label": ...}`, `main` first.
- `articles` — one object per article:
  - `id`, `category`, `source`, `headline`, `snippet`, `imageUrl`, `articleUrl`
    — always present.
  - `language` — `"bn"` or `"en"`, set per-source (jugantor/prothomalo/ittefaq
    are Bengali; dhakatribune/dailystar are English).
  - `publishedAt` — an ISO-8601 datetime with a UTC offset, or `null` when the
    source's own listing gave no parseable signal. dailystar's is
    approximate (parsed from a relative phrase like "5 HOUR(s)", anchored to
    the scrape run's own start time) since getting an exact one would need an
    extra per-article fetch; Dhaka Tribune's listing only carries a timestamp
    on some cards, so a null rate there reflects the source, not a bug.

## App

```bash
cd app
flutter pub get
flutter run -d <device>
flutter test
```

The app fetches the published JSON at launch and caches it locally, falling back
to that cache if the fetch fails (no network, GitHub Pages unreachable). The
app bar's filter icon opens a bottom sheet listing the full taxonomy; unchecking
a category hides it immediately and the choice persists locally
(`shared_preferences`) across launches. A refresh button next to it re-fetches
on demand (there's no pull-to-refresh — it was replaced so the vertical feed
could loop infinitely instead of stopping dead at the last article).

The app has a single dark theme (`lib/theme/app_theme.dart`'s `AppColors`/
`AppTypography`, no light mode) built around the brand red from the app icon;
the wordmark and category pills use the Anton display font, but fetched
article headlines/snippets never do, since Anton has no Bengali glyphs and
half the sources publish in Bengali. Tapping a card opens the article in an
in-app WebView that's pushed into a dark reading mode via an injected CSS
invert filter — `<header>`/`<nav>` images (site logos) are excluded from the
re-invert so they stay legible against the now-dark header, and elements
with an inline `background-image` style (lazy-load placeholders) are
included so they don't flash the wrong colors while loading.

See `docs/superpowers/specs/2026-08-20-newshead-v1-design.md` for the full design,
and `docs/superpowers/plans/2026-08-23-dynamic-categories-and-filters.md` for the
category-filtering/timestamp/branding feature's implementation plan.

### Release build

Always build release APKs with `app/scripts/build_release_apk.sh` (splits the
build into one APK per CPU architecture instead of one ~49MB universal APK).
See `docs/release.md` for the full breakdown and why this is a script instead
of a Gradle config flag.
