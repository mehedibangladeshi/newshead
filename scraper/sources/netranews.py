import logging
import time
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from .. import browser_client, config, english_date
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://netra.news"
COVER_LOGO_URL = "https://netra.news/content/images/2026/04/netra-news-logooooo.svg"
COVER_ACCENT_COLOR = (0, 0, 0)  # Ghost theme masthead is plain black-on-white, like thedissent.news

SOURCE_NAME = "Netra News"

# An investigative-journalism outlet, not a general newspaper - this is its
# whole real tag taxonomy (its own footer calls these "Our journalism"),
# same reasoning as thedissent.py's CORE_SECTION_SLUGS. "short-video" and
# "video" are media hubs, excluded (confirmed with user: the app has no
# video playback capability - see docs/ideas.md/CONTEXT.md notes on this).
CORE_SECTION_SLUGS = {
    "netra-report",
    "netra-analysis",
    "opinion",
    "interactive",
    "interview",
    "feature-photo-story",
}

SECTION_DISPLAY_NAMES = {
    "netra-report": "Reports",
    "netra-analysis": "Analysis",
    "opinion": "Opinion",
    "interactive": "Interactive",
    "interview": "Interview",
    "feature-photo-story": "Feature/Photo Story",
}

FALLBACK_SECTIONS = [(slug, name) for slug, name in SECTION_DISPLAY_NAMES.items()]

_session = config.make_session()


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    try:
        response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
        response.raise_for_status()
        return response.text
    except requests.RequestException:
        # netra.news sits behind Cloudflare, confirmed blocking this
        # runner's IP with a JS challenge - same fallback jugantor.py uses.
        logger.info("netranews: falling back to browser fetch for %s", url)
        return browser_client.get_html(url)


def discover_sections(include_all=False):
    # Iterates SECTION_DISPLAY_NAMES (insertion-ordered) rather than the
    # CORE_SECTION_SLUGS set directly - set iteration order isn't
    # guaranteed, and sections[0]'s identity matters (it becomes "Main").
    return [
        (slug, name)
        for slug, name in SECTION_DISPLAY_NAMES.items()
        if include_all or slug in CORE_SECTION_SLUGS
    ]


def parse_articles(html):
    """Pure parsing step for list_articles; takes raw tag-page HTML,
    returns a list of article listing dicts."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    for card in soup.select('article[class*="ntr-rpx-card"]'):
        headline_tag = card.select_one("h2.ntr-rpx-card-title a[href]")
        if headline_tag is None:
            continue

        summary_tag = card.select_one("p.ntr-rpx-card-deck")
        time_tag = card.select_one("time.ntr-rpx-card-date")
        img_tag = card.select_one("img.ntr-rpx-card-img")

        articles.append(
            {
                "url": urljoin(BASE_URL, headline_tag["href"]),
                "headline": _text(headline_tag),
                "summary": _text(summary_tag),
                "listing_time": time_tag.get("datetime", "") if time_tag else "",
                "thumbnail": urljoin(BASE_URL, img_tag["src"]) if img_tag else None,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/tags/{slug}/"
    html = _get(section_url)
    return parse_articles(html)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict.

    netra.news actually publishes bilingual English/Bengali content sharing
    the same tags (confirmed live via each article's own <html lang="..">),
    but generate_data.py's SOURCE_LANGUAGE is a single per-source flag with
    no per-article override - so this source is registered as "en" (most
    tag pages sampled were English-language), same simplification as
    thedissent.py."""
    soup = BeautifulSoup(html, "html.parser")

    article = soup.select_one("article") or soup
    headline_tag = article.select_one("h1")
    author_tag = article.select_one("a.ntr-article-author-name")
    time_tag = article.select_one("time.ntr-article-date")
    body_container = article.select_one("section.gh-content")
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
