"""Generate a real-data JSON snapshot for the NewsHead app.

Scrapes 11 Bengali/English newspaper sources, classifies articles into the
app's fixed category taxonomy, and writes articles.json at the repo root.
Published to GitHub Pages by .github/workflows/scrape.yml, which runs this
4x/day.

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

from . import config, timestamps

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

DHAKA_TZ = ZoneInfo("Asia/Dhaka")

OUTPUT_PATH = os.path.join(config.PROJECT_ROOT, "articles.json")

# Single source of truth for the app's canonical category taxonomy: key,
# display label, in display order ("main" always first).
CATEGORY_DEFINITIONS = [
    ("main", "Main"),
    ("politics", "Politics"),
    ("world", "World"),
    ("city", "City"),
    ("country", "Country"),
    ("business", "Business"),
    ("sports", "Sports"),
    ("entertainment", "Entertainment"),
    ("lifestyle", "Lifestyle"),
    ("opinion", "Opinion"),
    ("tech", "Tech"),
    ("health", "Health"),
    ("education", "Education"),
    ("religion", "Religion"),
    ("arts_literature", "Arts & Literature"),
    ("expat", "Expat/Probash"),
    ("miscellaneous", "Miscellaneous"),
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
    "tbsnews": "The Business Standard",
    "banglatribune": "Bangla Tribune",
    "samakal": "Samakal",
    "bdnews24": "bdnews24.com",
    "bdnews24bangla": "বিডিনিউজ টোয়েন্টিফোর বাংলা",
    "dhakapost": "The Dhaka Post",
}

# Per-source display language for formatting an article's publishedAt on
# the client — mirrors the bengali_date/english_date split each source
# module already uses for its own format_date().
SOURCE_LANGUAGE = {
    "jugantor": "bn",
    "prothomalo": "bn",
    "dhakatribune": "en",
    "dailystar": "en",
    "ittefaq": "bn",
    "tbsnews": "en",
    "banglatribune": "bn",
    "samakal": "bn",
    "bdnews24": "en",
    "bdnews24bangla": "bn",
    "dhakapost": "en",
}

# Bilingual (English + Bengali) keyword lists used to classify an article's
# headline + section name into one of the app's fixed categories. Checked
# in this order; first match wins. Covers all 15 non-"main", non-
# "miscellaneous" categories; "miscellaneous" intentionally has no keyword
# entry — it has no reliable keyword signal and is only reachable via an
# explicit SECTION_CATEGORY_MAP entry. An article matching none of these is
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
    "business": [
        "business", "economy", "market", "stock", "trade", "finance",
        "বাণিজ্য", "অর্থনীতি", "শেয়ারবাজার", "ব্যবসা",
    ],
    "world": [
        "world", "international", "global", "আন্তর্জাতিক", "বিশ্বজুড়ে",
    ],
    "city": [
        "dhaka", "ঢাকা", "রাজধানী",
    ],
    "country": [
        "bangladesh", "national", "nationwide", "country",
        "জাতীয়", "বাংলাদেশ", "সারাদেশ",
    ],
    "entertainment": [
        "entertainment", "movie", "film", "actor", "actress", "celebrity",
        "বিনোদন", "চলচ্চিত্র", "নায়ক", "নায়িকা",
    ],
    "lifestyle": [
        "lifestyle", "fashion", "recipe",
        "জীবনযাপন", "লাইফস্টাইল", "ফ্যাশন",
    ],
    "opinion": [
        "opinion", "editorial", "column", "op-ed",
        "মতামত", "সম্পাদকীয়", "উপসম্পাদকীয়",
    ],
    "tech": [
        "technology", "gadget", "software", "internet",
        "প্রযুক্তি", "টেক", "ইন্টারনেট",
    ],
    "health": [
        "health", "medical", "hospital", "doctor", "disease",
        "স্বাস্থ্য", "চিকিৎসা", "রোগ",
    ],
    "education": [
        "education", "school", "university", "student", "exam",
        "শিক্ষা", "বিশ্ববিদ্যালয়", "শিক্ষার্থী", "পরীক্ষা",
    ],
    "religion": [
        "religion", "islam", "hindu", "prayer",
        "ধর্ম", "ইসলাম", "নামাজ",
    ],
    "arts_literature": [
        "literature", "poetry", "novel",
        "সাহিত্য", "কবিতা", "উপন্যাস",
    ],
    "expat": [
        "expatriate", "probash", "remittance",
        "প্রবাস", "প্রবাসী", "রেমিট্যান্স",
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
# entry, falls through to keyword matching instead. Transcribed from the
# user-dictated taxonomy interview against docs/section-discovery-report.md.
SECTION_CATEGORY_MAP = {
    "jugantor": {
        # sections[0] "tp-firstpage" is Main, excluded.
        "tp-lastpage": "country",
        "tp-city": "city",
        "tp-sports": "sports",
        "tp-anando-nagar": "entertainment",
        "tp-news": "country",
        "tp-second-edition": "country",
        "tp-ten-horizon": "opinion",
        "tp-bangla-face": "country",
        "tp-editorial": "opinion",
        "tp-ub-editorial": "opinion",
        "tp-window": "lifestyle",
        "tp-imp": "miscellaneous",
        "tp-it-world": "tech",
        "tp-everyday": "lifestyle",
        "tp-letter": "miscellaneous",
        "tp-obituary": "miscellaneous",
    },
    "prothomalo": {
        # sections[0] "bangladesh" is Main, excluded. "chakri" and "video"
        # are pre-filtered (jobs/classifieds, video hub) and stay unmapped.
        "politics": "politics",
        "world": "world",
        "business": "business",
        "opinion": "opinion",
        "sports": "sports",
        "entertainment": "entertainment",
        "lifestyle": "lifestyle",
    },
    "dhakatribune": {
        # sections[0] is "bangladesh" (Main) - the first allowlisted
        # topical section in nav order, not the genuine front page;
        # "latest-news", the real front-page/aggregator, is deliberately
        # excluded from discovery (see CORE_SECTION_SLUGS in
        # scraper/sources/dhakatribune.py), along with "others",
        # "around-the-web", "photo-gallery", "magazine-archive", and
        # "archive", which stay unmapped.
        "bangladesh": "country",
        "bangladesh/dhaka": "city",
        "bangladesh/education": "education",
        "bangladesh/election": "politics",
        "bangladesh/foreign-affairs": "world",
        "bangladesh/nation": "country",
        "bangladesh/politics": "politics",
        "bangladesh/weather": "country",
        "bangladesh/campus1": "education",
        "bangladesh/accidents": "country",
        "business": "business",
        "business/economy": "business",
        "business/banks": "business",
        "business/commerce": "business",
        "business/stock": "business",
        "business/real-estate": "business",
        "world": "world",
        "world/asia": "world",
        "world/south-asia": "world",
        "world/africa": "world",
        "world/middle-east": "world",
        "world/europe": "world",
        "world/north-america": "world",
        "sport": "sports",
        "sport/cricket": "sports",
        "sport/football": "sports",
        "sport/tennis": "sports",
        "sport/athletics": "sports",
        "sport/formula-one": "sports",
        "sport/other-sports": "sports",
        "opinion": "opinion",
        "opinion/op-ed": "opinion",
        "opinion/editorial": "opinion",
        "opinion/longform": "opinion",
        "showtime": "entertainment",
        "feature": "lifestyle",
        "magazine-1": "lifestyle",
        "arts-and-letters": "arts_literature",
        "arts-and-letters/poetry": "arts_literature",
        "arts-and-letters/book-review": "arts_literature",
        "arts-and-letters/fiction": "arts_literature",
        "arts-and-letters/tribute": "arts_literature",
        "arts-and-letters/non-fiction": "arts_literature",
        "arts-and-letters/essay": "arts_literature",
        "tribune-z": "miscellaneous",
        "science-technology-environment": "tech",
        "interviews-and-dialogue": "opinion",
        "brief": "country",
    },
    "dailystar": {
        # dailystar's discover_sections()[0] (Main) is whichever section
        # happens to have the first article on a given day's /todays-news
        # page, not a fixed section name like the other 4 sources - so ALL
        # 6 discovered sections are mapped here, including "sports" (today's
        # Main; on a day it isn't first, its articles flow through here).
        "sports": "sports",
        "slow-reads": "lifestyle",
        "news": "country",
        "business": "business",
        "ds": "miscellaneous",
        "health": "health",
    },
    "ittefaq": {
        # sections[0] is "editorial" (Main) - the first allowlisted topical
        # section in nav order, not the genuine front page; "home", the
        # real front page, is deliberately excluded from discovery (see
        # CORE_SECTION_SLUGS in scraper/sources/ittefaq.py). "latest-news",
        # utility pages, "archive", the unicode converter, "jobs", media
        # hubs, transient topic tag pages, and numeric-ID article
        # permalinks are pre-filtered and stay unmapped.
        "editorial": "opinion",
        "national": "country",
        "capital": "city",
        "country": "country",
        "politics": "politics",
        "world-news": "world",
        "sports": "sports",
        "entertainment": "entertainment",
        "business": "business",
        "tech": "tech",
        "education": "education",
        "health": "health",
        "social-media": "tech",
        "projonmo": "lifestyle",
        "probash": "expat",
        "campus": "education",
        "literature": "arts_literature",
        "religion": "religion",
        "lifestyle": "lifestyle",
        "law-and-court": "country",
        "opinion": "opinion",
        "news": "country",
        "environment": "tech",
    },
    "tbsnews": {
        # tbsnews's discover_sections()[0] (Main) is whichever section
        # happens to have the newest card on /latest on a given run, not a
        # fixed section - same "Main is dynamic, map every discovered slug"
        # approach as dailystar above.
        "bangladesh": "country",
        "economy": "business",
        "world": "world",
        "worldbiz": "world",
        "sports": "sports",
        "features": "lifestyle",
        "tech": "tech",
        "splash": "miscellaneous",
        "offbeat": "miscellaneous",
        "magazine": "lifestyle",
        "supplement": "miscellaneous",
        "environment": "tech",
        "long-read": "lifestyle",
        "interviews": "opinion",
        "thoughts": "opinion",
        # Confirmed live on /latest (2026-08-24) - since sections are
        # derived from URL path segments rather than a fixed nav, this list
        # isn't closed; audit again with scripts/discover_sections.py if
        # unmapped-slug articles start getting silently dropped.
        "foreign-policy": "world",
        "nbr": "business",
        "infograph": "miscellaneous",
        "top-news": "country",
        "rohingya-crisis": "world",
    },
    "banglatribune": {
        # sections[0] "national" is Main, excluded (see CORE_SECTION_SLUGS
        # in scraper/sources/banglatribune.py for what's pre-filtered).
        "politics": "politics",
        "law-and-crime": "country",
        "country": "country",
        "foreign": "world",
        "exclusive": "miscellaneous",
        "business": "business",
        "entertainment": "entertainment",
        "sport": "sports",
        "tech-and-gadget": "tech",
        "educations": "education",
        "health": "health",
        "lifestyle": "lifestyle",
        "literature": "arts_literature",
    },
    "samakal": {
        # sections[0] "bangladesh" is Main, excluded (see CORE_SECTION_SLUGS
        # in scraper/sources/samakal.py for what's pre-filtered).
        "politics": "politics",
        "economics": "business",
        "international": "world",
        "sports": "sports",
        "entertainment": "entertainment",
        "crime": "country",
        "opinion": "opinion",
        "capital": "city",
        "lifestyle": "lifestyle",
    },
    "bdnews24": {
        # bdnews24's discover_sections()[0] (Main) is whichever section
        # happens to have the newest card on its shared /archive feed on a
        # given run, not a fixed section - same "Main is dynamic, map every
        # discovered slug" approach as dailystar/tbsnews above.
        "bangladesh": "country",
        "politics": "politics",
        "campus": "education",
        "education": "education",
        "environment": "tech",
        "health": "health",
        "fashion": "lifestyle",
        "people": "lifestyle",
        "automobile": "miscellaneous",
        "aviation": "miscellaneous",
        "world": "world",
        "science": "tech",
        "sport": "sports",
        "cricket": "sports",
        "neighbours": "world",
        "business": "business",
        "economy": "business",
        "opinion": "opinion",
        "technology": "tech",
        "lifestyle": "lifestyle",
        "entertainment": "entertainment",
    },
    "bdnews24bangla": {
        # sections[0] "samagrabangladesh" is Main, excluded (a fixed
        # nav-derived slug, not dynamic like bdnews24/tbsnews above - see
        # scraper/sources/bdnews24bangla.py's EXCLUDED_SECTION_SLUGS for
        # what's pre-filtered).
        "ctg": "city",
        "world": "world",
        "politics": "politics",
        "arts": "arts_literature",
        "glitz": "entertainment",
        "lifestyle": "lifestyle",
        "tech": "tech",
        "kidz": "lifestyle",
        "probash": "expat",
        "bangladesh": "country",
        "science": "tech",
        "environment": "tech",
        "health": "health",
        "campus": "education",
        "special": "miscellaneous",
        "nareespandan": "lifestyle",
        "cricket": "sports",
        "sport": "sports",
        "opinion": "opinion",
        "finance-and-trade": "business",
        "business": "business",
        "economy": "business",
        "stocks": "business",
        "corporate": "business",
        "neighbour": "world",
    },
    "dhakapost": {
        # sections[0] "national" is Main, excluded (a fixed nav-derived
        # slug - see scraper/sources/dhakapost.py's EXCLUDED_SECTION_SLUGS,
        # currently empty since every discovered section is real prose).
        "politics": "politics",
        "foreign-news": "world",
        "world": "world",
        "business": "business",
        "sports": "sports",
        "health": "health",
        "education": "education",
        "tech": "tech",
        "entertainment": "entertainment",
        "lifesyle": "lifestyle",  # site's own slug typo, not "lifestyle"
        "weird": "miscellaneous",
        "interview": "opinion",
    },
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


if __name__ == "__main__":
    main()
