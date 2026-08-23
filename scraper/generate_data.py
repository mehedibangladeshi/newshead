"""Generate a real-data JSON snapshot for the NewsHead app.

Scrapes 5 Bengali/English newspaper sources, classifies articles into 6
fixed categories, and writes articles.json at the repo root. Published to
GitHub Pages by .github/workflows/scrape.yml, which runs this 4x/day.

Run manually:
    python scripts/generate.py
"""
import hashlib
import importlib
import json
import logging
import os
from collections import defaultdict, deque
from datetime import datetime
from zoneinfo import ZoneInfo

from . import config

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

DHAKA_TZ = ZoneInfo("Asia/Dhaka")

OUTPUT_PATH = os.path.join(config.PROJECT_ROOT, "articles.json")

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

SOURCE_DISPLAY_NAMES = {
    "jugantor": "Jugantor",
    "prothomalo": "Prothom Alo",
    "dhakatribune": "Dhaka Tribune",
    "dailystar": "The Daily Star",
    "ittefaq": "Ittefaq",
}

# Bilingual (English + Bengali) keyword lists used to classify an article's
# headline + section name into one of the app's fixed categories. Checked
# in this order; first match wins. An article matching none of these is
# dropped rather than forced into a category.
CATEGORY_KEYWORDS = {
    "politics": [
        "politics", "election", "parliament", "minister", "cabinet",
        "government", "বিএনপি", "আওয়ামী লীগ", "রাজনীতি", "রাজনৈতিক",
        "নির্বাচন", "সংসদ", "মন্ত্রী",
    ],
    "sports": [
        "sport", "cricket", "football", "match", "tournament",
        "খেলা", "ক্রিকেট", "ফুটবল", "বিশ্বকাপ",
    ],
    "finance": [
        "business", "economy", "market", "stock", "trade", "finance",
        "বাণিজ্য", "অর্থনীতি", "শেয়ারবাজার", "ব্যবসা",
    ],
    "world": [
        "world", "international", "global", "আন্তর্জাতিক", "বিশ্বজুড়ে",
    ],
    "bangladesh": [
        "bangladesh", "dhaka", "national", "country", "capital",
        "জাতীয়", "বাংলাদেশ", "রাজধানী", "সারাদেশ",
    ],
}


def classify_category(headline, section_name):
    """Pure classification: returns a category slug or None if no keyword
    in CATEGORY_KEYWORDS matches the section name or headline text."""
    haystack = f"{section_name} {headline}".lower()
    for category, keywords in CATEGORY_KEYWORDS.items():
        for keyword in keywords:
            if keyword.lower() in haystack:
                return category
    return None


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


def make_article_id(source_slug, url):
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:10]
    return f"{source_slug}-{digest}"


def truncate_snippet(text, max_length=160):
    text = " ".join((text or "").split())
    if len(text) <= max_length:
        return text
    return text[:max_length].rsplit(" ", 1)[0] + "…"


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


def enrich_item(source_module, item):
    """Fill in a listing item's missing thumbnail/summary from the full
    article page, since some sources' listings never include them."""
    if item.get("thumbnail") and item.get("summary"):
        return item
    try:
        detail = source_module.fetch_article(item["url"])
    except Exception:
        return item

    enriched = dict(item)
    if not enriched.get("thumbnail") and detail.get("image_url"):
        enriched["thumbnail"] = detail["image_url"]
    if not enriched.get("summary") and detail.get("paragraphs"):
        enriched["summary"] = detail["paragraphs"][0]
    return enriched


def collect_source_articles(source_slug, edition_date):
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
        articles.append(build_article(source_slug, source_name, "main", item, fallback_image_url))

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

    return articles


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


def build_output(edition_date, articles):
    """Pure assembly of the published JSON shape."""
    return {
        "generated_at": edition_date,
        "categories": [{"key": key, "label": label} for key, label in CATEGORY_DEFINITIONS],
        "articles": articles,
    }


def main():
    edition_date = datetime.now(DHAKA_TZ).date().isoformat()

    all_articles = []
    for source_slug in config.SOURCES:
        try:
            source_articles = collect_source_articles(source_slug, edition_date)
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


if __name__ == "__main__":
    main()
