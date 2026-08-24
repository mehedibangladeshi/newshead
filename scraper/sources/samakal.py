import logging
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

from .. import bengali_date, config
from .ld_json import select_by_type
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://samakal.com"
COVER_LOGO_URL = "https://samakal.com/frontend/media/common/logo.png"
COVER_ACCENT_COLOR = (0, 0, 0)  # masthead wordmark is plain black-on-white

SOURCE_NAME = "সমকাল"

# Samakal's top-level nav mixes real editorial verticals with a few entries
# that aren't a good fit for a text digest - "latest/news" (a rolling
# aggregate of every other section, would just duplicate them), "whole-
# country" (a dropdown of division pages, not its own listing page in the
# same card markup) and "video-gallery"/"photogallery" (no prose body).
# Same "curated allowlist" spirit as Ittefaq's CORE_SECTION_SLUGS.
CORE_SECTION_SLUGS = {
    "bangladesh",
    "politics",
    "economics",
    "international",
    "sports",
    "entertainment",
    "crime",
    "opinion",
    "capital",
    "lifestyle",
}

# Used only if live discovery finds nothing (defensive fallback), in the
# order they're encountered in the real nav.
FALLBACK_SECTIONS = [
    ("bangladesh", "বাংলাদেশ"),
    ("politics", "রাজনীতি"),
    ("economics", "অর্থনীতি"),
    ("international", "বিশ্ব"),
    ("sports", "খেলা"),
    ("entertainment", "বিনোদন"),
    ("crime", "অপরাধ"),
    ("opinion", "মতামত"),
]

_session = config.make_session()


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes the homepage's raw
    HTML, returns a list of (slug, section_name) or [] if none were found.

    include_all=True bypasses CORE_SECTION_SLUGS (see its comment above) -
    used only by scripts/discover_sections.py to audit the real nav;
    production discovery (include_all=False) is unchanged.

    Only direct children of the top-level <ul class="navbar-nav"> are
    considered, so links buried inside the "সারাদেশ" division dropdown or
    the "অন্যান্য" megamenu (nested further down the DOM) aren't picked up
    as if they were top-level sections."""
    soup = BeautifulSoup(html, "html.parser")

    sections = []
    seen_slugs = set()
    for link in soup.select("ul.navbar-nav > li.nav-item > a.nav-link[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != "samakal.com":
            continue
        slug = parsed.path.strip("/")
        if not slug or slug in seen_slugs:
            continue
        if not include_all and slug not in CORE_SECTION_SLUGS:
            continue
        name = _text(link)
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
    """Pure parsing step for list_articles; takes raw section-page HTML,
    returns a list of article listing dicts.

    A section page has one big lead card (div.DCatLead, with a summary
    paragraph), a row of smaller cards (div.Catcards, headline only), and -
    confirmed live on /politics, easy to miss since the lead+small-card
    rows alone only cover 5 of a section's ~15 stories - a further list of
    div.CatListNews cards nested inside div.CatSubList-area, each with its
    own summary (div.ListDesc > p) and span.publishTime. All three wrap the
    whole card in a single <a>."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    seen_urls = set()
    for card in soup.select(
        "div.DCatLead > a[href], div.Catcards > a[href], "
        "div.CatSubList-area div.CatListNews > a[href]"
    ):
        title_tag = card.select_one("h1, h3")
        if not title_tag:
            continue

        url = urljoin(BASE_URL, card["href"])
        if url in seen_urls:
            continue
        seen_urls.add(url)

        summary_tag = card.select_one("p.CatDesc, div.ListDesc > p")
        time_tag = card.select_one("span.publishTime")
        img_tag = card.select_one("img")

        thumbnail = None
        if img_tag is not None:
            # Listing images are lazy-loaded: src is a shared lo-res
            # placeholder, data-src holds the real image.
            raw_thumbnail = img_tag.get("data-src") or img_tag.get("src")
            if raw_thumbnail:
                thumbnail = urljoin(BASE_URL, raw_thumbnail)

        articles.append(
            {
                "url": url,
                "headline": _text(title_tag),
                "summary": _text(summary_tag),
                "listing_time": _text(time_tag),
                "thumbnail": thumbnail,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/{slug}"
    html = _get(section_url)
    return parse_articles(html)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML
    and the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")
    metadata = select_by_type(soup, "NewsArticle")

    paragraphs = []
    body_container = soup.select_one("div#contentDetails")
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    # The ld+json "author" field is unreliable on Samakal - on many pages
    # (e.g. the sports desk one used to build this module) it's a bug that
    # just repeats the headline instead of a byline. The real byline, when
    # the story has one, lives in div.writter instead; prefer that and only
    # fall back to ld+json if it's missing.
    author = _text(soup.select_one("div.writter"))
    if not author:
        author_field = metadata.get("author")
        if isinstance(author_field, dict):
            author = author_field.get("name") or ""
        elif isinstance(author_field, str):
            author = author_field

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
    return bengali_date.format_bengali_date(edition_date)
