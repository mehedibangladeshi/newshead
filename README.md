# NewsHead

A self-scraping news app: a Python pipeline scrapes 5 Bengali/English newspapers
4x/day, classifies articles into 6 categories, and publishes the result to GitHub
Pages. The Flutter app fetches that JSON at launch and presents it as a
reels-style (TikTok/Instagram-like) vertical, swipeable card feed that loops
seamlessly in both directions — never a dead end scrolling down or between
categories.

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

## App

```bash
cd app
flutter pub get
flutter run -d <device>
flutter test
```

The app fetches the published JSON at launch and caches it locally, falling back
to that cache if the fetch fails (no network, GitHub Pages unreachable).

See `docs/superpowers/specs/2026-08-20-newshead-v1-design.md` for the full design.
