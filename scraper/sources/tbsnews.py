import logging
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

from .. import config, english_date
from .ld_json import select_by_type
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://www.tbsnews.net"
LATEST_URL = f"{BASE_URL}/latest"

# Confirmed live: og:image is a generic 1200x630 site banner (not a
# wordmark), but the Drupal "sloth" theme's actual masthead logo asset
# resolves directly as a fetchable raster PNG (verified via HEAD request:
# HTTP 200, image/png) - unlike Daily Star's SVG-only masthead, this one
# needs no local-asset workaround.
COVER_LOGO_URL = "https://www.tbsnews.net/sites/all/themes/sloth/logo.png"
COVER_ACCENT_COLOR = (196, 30, 30)  # the site's recurring section-label red, close to its "TBS red" accent

SOURCE_NAME = "The Business Standard"

# Like Daily Star, TBS has no per-category listing page bounded to "today" -
# but unlike Daily Star, it does have a single rolling "/latest" Drupal view
# that lists every recent story site-wide (confirmed live: 195 cards on one
# unpaginated fetch, newest first, spanning from a few minutes ago out to
# ~1 day ago), each carrying a relative-time string ("6m", "1h", "1d") in a
# `.date` div - the per-category section pages (e.g. /economy) carry no date
# at all on their cards. So, same "single shared fetch, section is derived
# from each article URL's first path segment" technique as Daily Star's
# _section_slug()/parse_todays_news(), just sourced from /latest instead of
# /todays-news.
SECTION_DISPLAY_NAMES = {
    "bangladesh": "Bangladesh",
    "economy": "Economy",
    "world": "World+Biz",
    "worldbiz": "World+Biz",
    "sports": "Sports",
    "features": "Features",
    "tech": "Tech",
    "splash": "Splash",
    "offbeat": "Offbeat",
    "magazine": "Magazine",
    "supplement": "Supplement",
    "environment": "Environment",
    "long-read": "Long Read",
    "interviews": "Interviews",
    "thoughts": "Thoughts",
    # Confirmed live on /latest (2026-08-24) - narrower topical slugs that
    # sit alongside the top-level nav sections above, since sections here
    # are derived from each article URL's own first path segment rather
    # than a fixed nav list.
    "foreign-policy": "Foreign Policy",
    "nbr": "NBR",
    "infograph": "Infograph",
    "top-news": "Top News",
    "rohingya-crisis": "Rohingya Crisis",
}

# "videos" is TBS's video hub (TBS Today/Stories/World/etc, confirmed live
# via the homepage nav's #main-menu "Videos" submenu) - its article pages
# are a player + caption, not prose, the same "not usable for a text
# reading digest" reasoning as Daily Star's star-multimedia exclusion.
EXCLUDED_SECTION_SLUGS = {"videos"}

# Used only if the /latest fetch itself fails outright (defensive fallback) -
# a representative subset of the real top-level nav slugs seen live (see
# #main-menu on the homepage).
FALLBACK_SECTIONS = [
    ("bangladesh", "Bangladesh"),
    ("economy", "Economy"),
    ("world", "World+Biz"),
    ("sports", "Sports"),
    ("features", "Features"),
    ("tech", "Tech"),
    ("magazine", "Magazine"),
]

_session = config.make_session()

# The whole /latest feed lives on one URL, so every discover_sections()/
# list_articles() call in a single run shares one fetch+parse instead of
# re-requesting the same page once per section.
_listing_cache = {}


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def _section_slug(url):
    path = urlparse(url).path.strip("/")
    return path.split("/", 1)[0] if path else ""


def parse_latest(html, include_all=False):
    """Pure parsing step; takes /latest's raw HTML, returns a dict of
    {section_slug: [article dict, ...]}, deduped by URL across the whole
    page.

    include_all=True keeps EXCLUDED_SECTION_SLUGS sections (e.g. the
    "videos" hub) instead of dropping them - used only by
    scripts/discover_sections.py to audit the real nav; production grouping
    (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")

    grouped = {}
    seen_urls = set()
    for card in soup.select(".card"):
        link_tag = card.select_one(".card-title a[href]")
        if link_tag is None:
            continue

        url = urljoin(BASE_URL, link_tag["href"])
        if url in seen_urls:
            continue

        slug = _section_slug(url)
        if not slug or (not include_all and slug in EXCLUDED_SECTION_SLUGS):
            continue
        seen_urls.add(url)

        # Card thumbnails are lazysizes-lazyloaded: the real URL sits in
        # data-src, not src (src is left empty/absent).
        img_tag = card.select_one("img[data-src]")

        grouped.setdefault(slug, []).append(
            {
                "url": url,
                "headline": _text(link_tag),
                "summary": _text(card.select_one(".card-intro")),
                "listing_time": _text(card.select_one(".date")),
                "thumbnail": urljoin(BASE_URL, img_tag["data-src"]) if img_tag else None,
            }
        )

    return grouped


def _get_grouped_listing(include_all=False):
    cache_key = "grouped_all" if include_all else "grouped"
    if cache_key not in _listing_cache:
        html = _get(LATEST_URL)
        _listing_cache[cache_key] = parse_latest(html, include_all=include_all)
    return _listing_cache[cache_key]


def discover_sections(include_all=False):
    try:
        grouped = _get_grouped_listing(include_all=include_all)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", LATEST_URL)
        return list(FALLBACK_SECTIONS)

    if not grouped:
        logger.warning("No sections discovered on %s, using fallback list", LATEST_URL)
        return list(FALLBACK_SECTIONS)

    return [(slug, SECTION_DISPLAY_NAMES.get(slug, slug.replace("-", " ").title())) for slug in grouped]


def list_articles(slug, edition_date=None):
    grouped = _get_grouped_listing()
    return grouped.get(slug, [])


def _extract_author(author_field):
    # TBS's ld+json represents a multi-byline story (e.g. two reporters) as
    # a single Person whose own "name" is already a comma-joined string
    # ("Shaikh Abdullah, Abul Kashem"), unlike Daily Star's list-of-strings
    # dateline shape - so no list branch is needed here, just dict/string.
    if isinstance(author_field, dict):
        return author_field.get("name") or ""
    if isinstance(author_field, str):
        return author_field
    return ""


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML
    and the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")
    # The single ld+json block on a TBS article page bundles the
    # NewsArticle (plus Organization) into one schema.org "@graph" array
    # rather than emitting separate blocks - select_by_type() looks inside
    # @graph too. Unlike Daily Star's @graph, this one already carries both
    # datePublished (with a +06:00 offset) and image, so nothing here needs
    # to be pulled from elsewhere in the page.
    metadata = select_by_type(soup, "NewsArticle")

    paragraphs = []
    body_container = soup.select_one("div.section-content")
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    image_url = ""
    image_field = metadata.get("image")
    if isinstance(image_field, dict):
        image_url = image_field.get("url") or ""
    elif isinstance(image_field, str):
        image_url = image_field

    return {
        "url": url,
        "headline": _normalize(" ".join((metadata.get("headline") or "").split())),
        "author": _normalize(" ".join(_extract_author(metadata.get("author")).split())),
        "date_published": metadata.get("datePublished", ""),
        "image_url": image_url,
        "paragraphs": paragraphs,
    }


def fetch_article(url):
    html = _get(url)
    return parse_article(html, url)


def get_cover_logo_url():
    return COVER_LOGO_URL


def format_date(edition_date):
    return english_date.format_english_date(edition_date)
