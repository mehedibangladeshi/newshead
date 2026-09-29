import logging
import time
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from .. import config
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://www.dailynayadiganta.com"
COVER_LOGO_URL = f"{BASE_URL}/assets/img/logo.png"

SOURCE_NAME = "দৈনিক নয়া দিগন্ত"

# Real nav confirmed live at /category/<slug>/<id> - "video" and "photo" are
# media hubs (not prose, excluded the same way every other source excludes
# its own), "latest" is a rolling aggregator, and "print-version" is a
# utility page, none of them real topical sections.
CORE_SECTION_SLUGS = {
    "national/2",
    "politics/19",
    "international/3",
    "country/4",
    "sports/6",
    "finance-n-commerce/13",
    "entertainment/7",
    "religion/27",
}

SECTION_DISPLAY_NAMES = {
    "national/2": "জাতীয়",
    "politics/19": "রাজনীতি",
    "international/3": "আন্তর্জাতিক",
    "country/4": "সারাদেশ",
    "sports/6": "খেলা",
    "finance-n-commerce/13": "অর্থ ও বাণিজ্য",
    "entertainment/7": "বিনোদন",
    "religion/27": "ধর্ম ও জীবন",
}

FALLBACK_SECTIONS = [(slug, name) for slug, name in SECTION_DISPLAY_NAMES.items()]

# dailynayadiganta.com currently serves an invalid/self-signed TLS
# certificate (confirmed live - a plain `requests.get` fails cert
# verification). This is scoped to this source's own session only, not a
# global relaxation of scraper/config.py's shared make_session() - every
# other source still verifies certificates normally.
_session = config.make_session()
_session.verify = False
requests.packages.urllib3.disable_warnings(requests.packages.urllib3.exceptions.InsecureRequestWarning)


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes raw nav-bearing page
    HTML, returns a list of (slug, section_name) or [] if none were found.

    include_all=True bypasses CORE_SECTION_SLUGS (keeps latest/video/photo/
    print-version too) - used only by scripts/discover_sections.py."""
    soup = BeautifulSoup(html, "html.parser")
    container = soup.select_one("nav.navbar") or soup

    sections = []
    seen_slugs = set()
    for link in container.select('a[href^="/category/"]'):
        slug = link["href"].removeprefix("/category/").strip("/")
        if not slug or slug in seen_slugs:
            continue
        if not include_all and slug not in CORE_SECTION_SLUGS:
            continue
        name = _normalize(link.get_text(strip=True))
        if not name:
            continue
        seen_slugs.add(slug)
        sections.append((slug, name))

    return sections


def discover_sections(include_all=False):
    try:
        html = _get(BASE_URL)
    except requests.RequestException:
        logger.warning("Could not reach %s, using fallback section list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    sections = parse_sections(html, include_all=include_all)
    if not sections:
        logger.warning("No sections discovered on %s, using fallback list", BASE_URL)
        return list(FALLBACK_SECTIONS)

    return sections


def parse_articles(html):
    """Pure parsing step for list_articles; takes raw category-page HTML,
    returns a list of article listing dicts."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    for card in soup.select("div.category-list-item"):
        link_tag = card.select_one("h5 a[href]")
        if link_tag is None:
            continue

        paragraphs = card.select("p.text-muted")
        summary_tag = paragraphs[0] if paragraphs else None
        time_tag = card.select_one("p.text-muted.small")
        img_tag = card.select_one("img[src]")

        articles.append(
            {
                "url": urljoin(BASE_URL, link_tag["href"]),
                "headline": _text(link_tag),
                "summary": _text(summary_tag),
                "listing_time": _text(time_tag),
                "thumbnail": urljoin(BASE_URL, img_tag["src"]) if img_tag else None,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/category/{slug}"
    html = _get(section_url)
    return parse_articles(html)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")

    headline_tag = soup.select_one("h1.entry-title")
    body_container = soup.select_one("article.pd-body")
    image_tag = soup.select_one('meta[property="og:image"]')

    paragraphs = []
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    return {
        "url": url,
        "headline": _text(headline_tag),
        "image_url": (image_tag.get("content") or "") if image_tag else "",
        "paragraphs": paragraphs,
    }


def fetch_article(url):
    html = _get(url)
    return parse_article(html, url)


def get_cover_logo_url():
    return COVER_LOGO_URL


