import logging
import time
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

from .. import config, english_date
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://dailywaadaa.com"
COVER_LOGO_URL = (
    "https://images.assettype.com/dailywaadaa/2026-06-08/6dcehos7/DW-web-files-beta-logo.png"
)
COVER_ACCENT_COLOR = (72, 96, 188)  # sampled from a section tag's background, #4860BC

SOURCE_NAME = "Daily Waadaa"

# Like dailystar.py, Daily Waadaa's homepage has no real nav in its server-
# rendered HTML (a Quintype "Arrow" theme - the menu is client-hydrated) -
# "section" here is derived from each article URL's first path segment
# instead, e.g. /bangladesh/2026/09/28/... -> "bangladesh". Slugs confirmed
# live by sampling the homepage's own article links.
SECTION_DISPLAY_NAMES = {
    "bangladesh": "Bangladesh",
    "politics": "Politics",
    "world": "World",
    "south-asia": "South Asia",
    "business": "Business",
    "economy": "Economy",
    "banking": "Banking",
    "the-trade-off": "The Trade-Off",
    "cricket": "Cricket",
    "football": "Football",
    "sports": "Sports",
    "crime": "Crime",
    "feature": "Feature",
    "lifestyle": "Lifestyle",
    "long-read": "Long Read",
    "analysis": "Analysis",
    "opinion": "Opinion",
    "arts": "Arts",
    "fact-check": "Fact Check",
}

# "latest" is a rolling aggregator landing page, not a real section - same
# reasoning as dailystar.py's EXCLUDED_SECTION_SLUGS.
EXCLUDED_SECTION_SLUGS = {"latest"}

FALLBACK_SECTIONS = [
    ("bangladesh", "Bangladesh"),
    ("politics", "Politics"),
    ("world", "World"),
    ("business", "Business"),
    ("sports", "Sports"),
]

_session = config.make_session()

_listing_cache = {}


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def _section_slug(url):
    path = urlparse(url).path.strip("/")
    return path.split("/", 1)[0] if path else ""


def _image_url(img_tag):
    if img_tag is None:
        return None
    src = img_tag.get("src") or ""
    if src.startswith("data:"):
        return None
    return f"https:{src}" if src.startswith("//") else src


def parse_homepage(html, include_all=False):
    """Pure parsing step; takes the homepage's raw HTML, returns a dict of
    {section_slug: [article dict, ...]}, deduped by URL.

    include_all=True keeps EXCLUDED_SECTION_SLUGS sections (e.g. the
    "latest" aggregator) instead of dropping them - used only by
    scripts/discover_sections.py; production grouping is unchanged."""
    soup = BeautifulSoup(html, "html.parser")

    grouped = {}
    seen_urls = set()
    for link_tag in soup.select('[data-test-id="headline"] a[href]'):
        url = link_tag["href"]
        parsed = urlparse(url)
        if parsed.netloc and parsed.netloc not in ("dailywaadaa.com", "www.dailywaadaa.com"):
            continue
        if url in seen_urls:
            continue

        slug = _section_slug(url)
        if not slug or (not include_all and slug in EXCLUDED_SECTION_SLUGS):
            continue
        seen_urls.add(url)

        card = link_tag.find_parent(attrs={"data-test-id": "story-card"})
        summary_tag = card.select_one('[data-test-id="subheadline"]') if card else None
        time_tag = card.select_one("time[datetime]") if card else None
        img_tag = card.select_one("img") if card else None

        grouped.setdefault(slug, []).append(
            {
                "url": url,
                "headline": _text(link_tag),
                "summary": _text(summary_tag),
                "listing_time": time_tag.get("datetime", "") if time_tag else "",
                "thumbnail": _image_url(img_tag),
            }
        )

    return grouped


def _get_grouped_listing(include_all=False):
    cache_key = "grouped_all" if include_all else "grouped"
    if cache_key not in _listing_cache:
        html = _get(BASE_URL)
        _listing_cache[cache_key] = parse_homepage(html, include_all=include_all)
    return _listing_cache[cache_key]


def discover_sections(include_all=False):
    try:
        grouped = _get_grouped_listing(include_all=include_all)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    if not grouped:
        logger.warning("No sections discovered on %s, using fallback list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    return [(slug, SECTION_DISPLAY_NAMES.get(slug, slug.replace("-", " ").title())) for slug in grouped]


def list_articles(slug, edition_date=None):
    grouped = _get_grouped_listing()
    return grouped.get(slug, [])


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")

    headline_tag = soup.select_one('[data-testid="story-headline"]') or soup.select_one("h1")
    author_tag = soup.select_one('[data-test-id="author-name"]')
    time_tag = soup.select_one("time[datetime]")
    image_tag = soup.select_one('meta[property="og:image"]')

    paragraphs = []
    for text_block in soup.select('[data-test-id="text"]'):
        for p in text_block.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    return {
        "url": url,
        "headline": _text(headline_tag),
        "author": _normalize(_text(author_tag)),
        "date_published": time_tag.get("datetime", "") if time_tag else "",
        "image_url": (image_tag.get("content") or "") if image_tag else "",
        "paragraphs": paragraphs,
    }


def fetch_article(url):
    html = _get(url)
    return parse_article(html, url)


def get_cover_logo_url():
    return COVER_LOGO_URL


def format_date(edition_date):
    return english_date.format_english_date(edition_date)
