import logging
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

from .. import config
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://thedissent.news"
COVER_LOGO_URL = "https://asset.thedissent.news/assets/images/logo.svg"

SOURCE_NAME = "The Dissent"

# A fact-checking/media-watch outlet, not a general newspaper - this is its
# whole real section list (confirmed live), not a curated subset of a larger
# nav like dhakatribune's CORE_SECTION_SLUGS. "about", "career", "contact",
# "privacy-policy", and "terms-of-use" are utility pages, excluded the same
# way every other source excludes its own non-prose nav items.
CORE_SECTION_SLUGS = {
    "current-affairs",
    "digital-investigations",
    "disinformation-actors",
    "fact-checks",
    "media-watches",
    "opinions",
}

SECTION_DISPLAY_NAMES = {
    "current-affairs": "Current Affairs",
    "digital-investigations": "Digital Investigations",
    "disinformation-actors": "Disinformation Actors",
    "fact-checks": "Fact Checks",
    "media-watches": "Media Watches",
    "opinions": "Opinions",
}

FALLBACK_SECTIONS = [(slug, name) for slug, name in SECTION_DISPLAY_NAMES.items()]

_session = config.make_session()


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes raw homepage HTML,
    returns a list of (slug, section_name) or [] if none were found.

    include_all=True returns every single-segment relative link found
    (including utility pages like "about") - used only by
    scripts/discover_sections.py to audit the real nav; production
    discovery (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")

    sections = []
    seen_slugs = set()
    for link in soup.select("a[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc:
            continue
        slug = parsed.path.strip("/")
        if not slug or "/" in slug or slug in seen_slugs:
            continue
        if not include_all and slug not in CORE_SECTION_SLUGS:
            continue
        seen_slugs.add(slug)
        sections.append((slug, SECTION_DISPLAY_NAMES.get(slug, slug.replace("-", " ").title())))

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


def parse_articles(html, slug):
    """Pure parsing step for list_articles; takes a section page's raw HTML
    and that section's own slug (to scope the link-href prefix), returns a
    list of article listing dicts."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    seen_urls = set()
    for link_tag in soup.select(f'a[href^="/{slug}/"]'):
        title_tag = link_tag.select_one('[class^="_title_"]')
        if title_tag is None:
            continue

        url = urljoin(BASE_URL, link_tag["href"])
        if url in seen_urls:
            continue
        seen_urls.add(url)

        date_tag = link_tag.select_one('[class^="_date_"]')
        img_tag = link_tag.select_one("img[src]")

        articles.append(
            {
                "url": url,
                "headline": _text(title_tag),
                "summary": "",
                "listing_time": _text(date_tag),
                "thumbnail": img_tag["src"] if img_tag else None,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/{slug}"
    html = _get(section_url)
    return parse_articles(html, slug)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")

    article_container = soup.select_one('[class^="_article_"]') or soup
    headline_tag = article_container.select_one('h4[class^="_title_"]')
    body_container = article_container.select_one('[class^="_body_"]')
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


