---
name: add-new-source
description: Use when the user wants to add a new news source/newspaper to the NewsHead scraper (Bangladeshi or, in future, global).
---

Add one or more scraper sources to NewsHead. Every source — even a single one — gets delegated to its own Sonnet subagent, each touching only its own new files (never the shared files in step 3), so N of them run in parallel with no conflict between them.

## 1. Confirm each candidate is clean

Before writing any code, curl the site's homepage + a section page with the UA from `scraper/config.py` (`USER_AGENT`). **Clean** = 200, no Cloudflare challenge (`server: cloudflare` alone is fine; a challenge/403 is not). This check always stays inline — never delegated, no matter how many candidates — it's a deterministic HTTP check with no model judgment in it. Trust `docs/ideas.md`'s candidate list if it already marked the site clean or blocked from *this* session — Cloudflare blocking drifts per-IP over time, so re-check anything older.

Blocked candidates: stop, report it, don't implement a broken source.

**Language/timezone gate:** if the source isn't `bn`/`en` or isn't Asia/Dhaka local time, stop here and `AskUserQuestion` before implementing — see "Global sources" below. Never guess a timezone or language formatter.

## 2. Implement each clean source in parallel

Launch one `general-purpose` subagent per clean source (`model: sonnet`), all in one message so they run concurrently. Give each subagent:
- The **interface contract** below.
- Two existing modules to read as the pattern: an English one (`tbsnews.py` or `dhakatribune.py`) or Bangla one (`samakal.py` or `jugantor.py`) matching the new source's language, plus whichever is structurally closest (single rolling "latest" feed vs. per-category pages vs. dynamic vs. fixed nav).
- Instruction to do real research (curl/fetch live pages, no hand-written fixtures) and prefer `ld_json.select_by_type` for article metadata over hand-parsed DOM when a `NewsArticle` block exists.
- Instruction to write `scraper/sources/<slug>.py` + `tests/test_<slug>_sections.py`, run that test file, and do one live sanity call (`discover_sections()` + `list_articles()` + `fetch_article()` against the real site).
- Instruction to report back: display name, language, every discovered section slug (flag any that won't keyword-match a category — see `generate_data.py`'s `CATEGORY_KEYWORDS`), whether `sections[0]` (Main) is a fixed nav slug or dynamic per-run, and 2-3 raw `listing_time` examples (or "no time signal" if the field is always empty).

**If a subagent's test file fails, or its live sanity call comes back empty/zero** (an objective signal — not the subagent merely saying a source seems hard): resume that same subagent via a message with the specific failure, so it keeps its research context instead of re-doing the legwork. If the resumed attempt fails the same way again, escalate once to a fresh subagent on `model: opus`, handing it the accumulated findings from both attempts.

## 3. Wire the shared files yourself

Cheap and mechanical — do this directly, no subagent, once all reports are in:

- `scraper/config.py::SOURCES` — append each slug.
- `scraper/generate_data.py::SOURCE_DISPLAY_NAMES` and `SOURCE_LANGUAGE`.
- `scraper/generate_data.py::SECTION_CATEGORY_MAP` — map every discovered non-Main section explicitly (don't rely on keyword fallback silently dropping unmapped ones). If Main is dynamic, map `sections[0]`'s slug too, since it won't always land there.
- `scraper/timestamps.py` — if `listing_time` has a parseable raw shape, add a parser function + a `_SOURCE_PARSERS` entry. No time signal at all → leave the source unregistered; `parse_published_at` already returns `None` safely.

## 4. Test and validate

- `pytest tests/test_<slug>_sections.py -v` for each new source.
- **No silent drops:** for each new source, run `classify_article_category(source_slug, slug, name, "")` for every slug from `discover_sections()` and confirm none return `None` outside of sections deliberately excluded in the module itself (e.g. video hubs). A repo-real bug once shipped 5 unmapped tbsnews slugs silently dropping articles — this check exists specifically to catch that again.
- One live scrape of only the new source(s), appended onto the last published `articles.json` (`git show origin/gh-pages:articles.json`) — never a full re-scrape of the other sources just to test. Check: every article has `id`/`category`/`source`/`headline`/`imageUrl`/`articleUrl`, no duplicate ids, `category` is a known key, `language` is `bn`/`en`, `publishedAt` fill rate matches what step 2 reported (100% if a parser was added, 0% if not).

## 5. Update docs and commit

Mirror the existing entries in `docs/ideas.md` (remove from the candidate list) and `docs/test-plan.md` (one dated session entry: sources added, article counts, anything unusual found). Update the source count in `README.md` if it states one. Commit message format: repo `CLAUDE.md`.

Optional, only if the user wants full CI confidence: `gh workflow run scrape.yml` and watch it — a residential curl test doesn't guarantee the CI runner's IP isn't separately blocked (see `docs/test-plan.md` §2).

---

## Interface contract

Every `scraper/sources/<slug>.py` module exposes exactly:

- `discover_sections() -> list[(slug, display_name)]` — `sections[0]` is treated as "Main" by `generate_data.py`.
- `list_articles(slug, edition_date=None) -> list[dict]` — each dict has `url`, `headline`, `summary`, `listing_time` (raw, unparsed), `thumbnail`.
- `fetch_article(url) -> dict` — `url`, `headline`, `author`, `date_published`, `image_url`, `paragraphs` (list of strings).
- `get_cover_logo_url() -> str` — a real, HEAD-verified image URL.
- `format_date(edition_date) -> str` — `english_date.format_english_date` or `bengali_date.format_bengali_date` depending on language.

## Global (non-Bangladeshi) sources

The pattern above is language-agnostic, but `SOURCE_LANGUAGE`/`format_date` currently only branch on `bn`/`en`, and every existing source assumes Asia/Dhaka local time in its timestamp parser. A source in another language or timezone needs a new `format_date` path and a timezone-aware `timestamps.py` parser — the step 1 gate stops implementation until the user has weighed in on that design, since guessing here corrupts `publishedAt` the same way an unmapped section silently drops articles.
