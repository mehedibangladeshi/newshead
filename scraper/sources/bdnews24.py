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

# bdnews24.com (no subdomain) is the English edition; the Bengali edition
# lives at bangla.bdnews24.com and already has its own module
# (bdnews24bangla.py) - confirmed live by each domain's <html lang="..">
# attribute and by the "English"/"বাংলা" cross-links each edition's header
# carries to the other domain. Oddly, bdnews24.com's own root "/" renders a
# Bengali doorway page (probably geo/cookie-based), but every named section
# path (e.g. /sport, /world, /archive) consistently serves English content -
# discovery below never touches "/", only "/archive".
BASE_URL = "https://bdnews24.com"
ARCHIVE_URL = f"{BASE_URL}/archive"

COVER_LOGO_URL = "https://bdnews24.com/frontend/assets/images/common/b-logo.png"
COVER_ACCENT_COLOR = (0, 0, 0)  # masthead wordmark is plain black-on-white

SOURCE_NAME = "bdnews24.com"

# Confirmed live: a section page itself (e.g. /sport, /world) has a lead
# card (div.Cat-lead-wrapper), a column of small cards (div.Cat-list) and a
# paginated "Read More" grid (div.rm-container) - but none of the three
# carries any time signal anywhere in its markup, same finding as the
# sibling bdnews24bangla module. The one page on this site that does carry
# a real per-article timestamp is "/archive" (labelled "Recent" in the
# header nav): a single rolling feed of the newest stories site-wide, each
# card stamped with a "Published : <date>, <time>" span - so, same
# "single shared fetch, section derived from each article URL's first path
# segment" technique as tbsnews's parse_latest/_section_slug.
#
# /archive?page=2 (GET) returns a second, genuinely distinct batch of
# stories continuing right where page 1 left off - confirmed live by
# comparing the two pages' first-card URLs and times. But page=3 and beyond
# come back byte-for-byte identical to page=2 (confirmed by diffing pages
# 3/5/8/10), i.e. real pagination only works via the site's own POST-based
# "load more"/date-range search (CSRF-tokened, not worth replicating here) -
# so this module fetches exactly these two GET pages and no further.
ARCHIVE_PAGE_URLS = [ARCHIVE_URL, f"{ARCHIVE_URL}?page=2"]

# Confirmed live via bdnews24.com/sport's full nav (header dropdown +
# mega-menu): the real top-level editorial verticals, keyed by each
# section's own URL slug (which is what /archive's card links and this
# module's _section_slug() group by).
SECTION_DISPLAY_NAMES = {
    "bangladesh": "Bangladesh",
    "politics": "Politics",
    "campus": "Campus",
    "education": "Education",
    "environment": "Environment",
    "health": "Health",
    "fashion": "Fashion",
    "people": "People",
    "automobile": "Automobile",
    "aviation": "Aviation",
    "world": "World",
    "science": "Science",
    "sport": "Sport",
    "cricket": "Cricket",
    "neighbours": "Neighbours",
    "business": "Business",
    "economy": "Economy",
    "opinion": "Opinion",
    "technology": "Technology",
    "lifestyle": "Lifestyle",
    "entertainment": "Entertainment",
}

# "media-en" is the site's photo-essay hub (confirmed live: its /archive
# cards are labelled category "Image" and link to /media-en/image/<id>
# pages that are a picture gallery, not prose) and "sponsored" is paid
# advertorial content (confirmed live in the same /archive feed) - neither
# is a good fit for a text digest, same "not usable for reading" reasoning
# as tbsnews's videos exclusion. "tube" (video hub), "stripe" (comic strip),
# "mobile" (app promo page) and "hello" (a separate lifestyle microsite at
# hello.bdnews24.com) are the same kind of non-prose nav entry, confirmed
# live in bdnews24.com/sport's header nav even though none of them happened
# to surface in the /archive sample used to build this module.
EXCLUDED_SECTION_SLUGS = {"media-en", "sponsored", "tube", "stripe", "mobile", "hello"}

# Used only if both /archive fetches fail outright (defensive fallback) - a
# representative subset of the real top-level nav slugs seen live.
FALLBACK_SECTIONS = [
    ("bangladesh", "Bangladesh"),
    ("politics", "Politics"),
    ("world", "World"),
    ("sport", "Sport"),
    ("cricket", "Cricket"),
    ("business", "Business"),
    ("economy", "Economy"),
    ("technology", "Technology"),
    ("entertainment", "Entertainment"),
]

_session = config.make_session()

# The whole /archive feed lives on two fixed URLs (see ARCHIVE_PAGE_URLS),
# so every discover_sections()/list_articles() call in a single run shares
# one pair of fetches+parses instead of re-requesting them once per section.
_listing_cache = {}


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def _section_slug(url):
    path = urlparse(url).path.strip("/")
    return path.split("/", 1)[0] if path else ""


def parse_archive(html, include_all=False):
    """Pure parsing step; takes one /archive page's raw HTML, returns a dict
    of {section_slug: [article dict, ...]}, deduped by URL within this page.

    include_all=True keeps EXCLUDED_SECTION_SLUGS sections (e.g. the
    "media-en" photo hub) instead of dropping them - used only by
    scripts/discover_sections.py to audit the real nav; production grouping
    (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")

    grouped = {}
    for card in soup.select("div.SubCat-wrapper > a[href]"):
        title_tag = card.select_one("h5")
        if title_tag is None:
            continue

        url = urljoin(BASE_URL, card["href"])
        slug = _section_slug(url)
        if not slug or (not include_all and slug in EXCLUDED_SECTION_SLUGS):
            continue

        # Listing cards here carry no summary text at all (confirmed live:
        # div.SubcatList-detail only ever has the category label, headline
        # and publish-time - unlike tbsnews/samakal's listing cards).
        img_tag = card.select_one("img")

        grouped.setdefault(slug, []).append(
            {
                "url": url,
                "headline": _text(title_tag),
                "summary": "",
                "listing_time": _text(card.select_one("span.publish-time")),
                "thumbnail": urljoin(BASE_URL, img_tag["src"]) if img_tag and img_tag.get("src") else None,
            }
        )

    return grouped


def _merge_grouped(pages):
    merged = {}
    seen_urls = set()
    for grouped in pages:
        for slug, articles in grouped.items():
            for article in articles:
                if article["url"] in seen_urls:
                    continue
                seen_urls.add(article["url"])
                merged.setdefault(slug, []).append(article)
    return merged


def _get_grouped_listing(include_all=False):
    cache_key = "grouped_all" if include_all else "grouped"
    if cache_key not in _listing_cache:
        pages = []
        for url in ARCHIVE_PAGE_URLS:
            try:
                html = _get(url)
            except requests.RequestException:
                logger.warning("Could not reach %s, skipping this archive page", url)
                continue
            pages.append(parse_archive(html, include_all=include_all))
        _listing_cache[cache_key] = _merge_grouped(pages)
    return _listing_cache[cache_key]


def discover_sections(include_all=False):
    grouped = _get_grouped_listing(include_all=include_all)
    if not grouped:
        logger.warning("No sections discovered on %s, using fallback list", ARCHIVE_URL)
        return list(FALLBACK_SECTIONS)

    return [(slug, SECTION_DISPLAY_NAMES.get(slug, slug.replace("-", " ").title())) for slug in grouped]


def list_articles(slug, edition_date=None):
    grouped = _get_grouped_listing()
    return grouped.get(slug, [])


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")
    metadata = select_by_type(soup, "NewsArticle")

    paragraphs = []
    body_container = soup.select_one("div#contentDetails")
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    # The ld+json "author" field is unreliable on bdnews24 - on every
    # article checked live it's a bug that just repeats the headline
    # instead of a byline (same bug as the sibling bdnews24bangla module).
    # The real byline lives in the DOM instead, in the first span.author
    # inside div.detail-author-name (e.g. "Staff Correspondent", "Reuters");
    # a second span.author sometimes present right after it is always just
    # the outlet's own name ("bdnews24.com"), not a byline, so only the
    # first one is used.
    author = _text(soup.select_one("div.detail-author-name span.author"))

    headline = _text(soup.select_one("h1")) or metadata.get("headline") or ""

    image_url = ""
    image_field = metadata.get("image")
    if isinstance(image_field, dict):
        image_url = image_field.get("url") or ""
    elif isinstance(image_field, str):
        image_url = image_field

    return {
        "url": url,
        "headline": _normalize(" ".join(headline.split())),
        "author": _normalize(" ".join(author.split())),
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
