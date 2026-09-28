# scraper/

Dev-loop commands (venv, `generate.py`, `pytest`): see `README.md`'s
"Scraper" section at the repo root.

## Source module contract

Every file under `sources/` implements the same interface, consumed by
`generate_data.py`:

- `discover_sections()` -> `list[(slug, section_name)]`
- `list_articles(slug, edition_date=None)` -> `list[dict]`
- `fetch_article(url)` -> `dict`
- `get_cover_logo_url()` -> `str`

Each module owns a single `_session = config.make_session()` at import time
and a private `_get(url)` helper (sleep `REQUEST_DELAY_SECONDS`, then
`_session.get(...).raise_for_status()`) — follow this shape for a new source
rather than inventing a different one.

## Cloudflare JS-challenge fallback

If a new source starts getting blocked the way jugantor was (a bot-challenge
page, not a real 403 close), don't re-investigate from scratch — reuse the
pattern already in `scraper/sources/jugantor.py`: `_get()` tries the plain
`requests` session first, and falls back to
`browser_client.get_html(url)` (headless Chromium via Playwright) only on
failure. See `docs/test-plan.md` for the jugantor investigation history.

## Domain language

Read `CONTEXT.md` (repo root) before touching `generate_data.py`'s
classification logic — it defines Source Section, Canonical Category, Main,
and Section→Category Mapping precisely, and they're easy to conflate.
