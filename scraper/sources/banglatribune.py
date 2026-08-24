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

BASE_URL = "https://www.banglatribune.com"
COVER_LOGO_URL = "https://cdn.banglatribune.net/contents/themes/public/style/images/logo.png"
COVER_ACCENT_COLOR = (204, 0, 0)  # sampled from the site's masthead red

SOURCE_NAME = "বাংলা ট্রিবিউন"

# Bangla Tribune runs on the same "Witter" CMS as its sister outlet Dhaka
# Tribune (confirmed via matching markup: div.each cards, a.link_overlay,
# article.jw_detail_content_holder, an "x-powered-by: Witter" response
# header) - so, like dhakatribune.py, its nav mixes real editorial verticals
# with a few non-content catch-alls that a generic filter rule can't tell
# apart from real sections. This is a curated allowlist instead.
# Excluded from #main_menu's real links: "আজকের-খবর" (today's-news, the
# aggregator/front-page link - deliberately excluded, same rationale as
# dhakatribune's "latest-news"; "national" is the first genuine topical
# section and stands in as this source's "main") and "others" (a generic
# catch-all, confirmed against the live nav dump).
CORE_SECTION_SLUGS = {
    "national",
    "politics",
    "law-and-crime",
    "country",
    "foreign",
    "exclusive",
    "business",
    "entertainment",
    "sport",
    "tech-and-gadget",
    "educations",
    "health",
    "lifestyle",
    "literature",
}

# Used only if live discovery finds nothing (defensive fallback), in the
# order they're encountered in the real nav.
FALLBACK_SECTIONS = [
    ("national", "জাতীয়"),
    ("politics", "রাজনীতি"),
    ("law-and-crime", "আইন ও অপরাধ"),
    ("country", "দেশ"),
    ("foreign", "আন্তর্জাতিক"),
    ("business", "অর্থ-বাণিজ্য"),
    ("entertainment", "বিনোদন"),
    ("sport", "খেলা"),
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

    include_all=True bypasses CORE_SECTION_SLUGS, returning every nav link
    found (including the aggregator and catch-alls) - used only by
    scripts/discover_sections.py to audit the real nav; production
    discovery (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")
    container = soup.select_one("#main_menu") or soup

    sections = []
    seen_slugs = set()
    for link in container.select("a[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != "www.banglatribune.com":
            continue
        slug = parsed.path.strip("/")
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
    """Pure parsing step for list_articles; takes raw section-page HTML,
    returns a list of article listing dicts."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    for card in soup.select("div.each"):
        link_tag = card.select_one("a.link_overlay[href]")
        title_tag = card.select_one(".title_holder .title")
        if not link_tag or not title_tag:
            continue

        # Site's own class name, not a typo we introduced (dhakatribune.py
        # has the identical "summery" spelling - same CMS).
        summary_tag = card.select_one(".summery")
        time_tag = card.select_one("span.time")
        listing_time = ""
        if time_tag is not None:
            listing_time = time_tag.get("data-published") or _text(time_tag)

        img_tag = card.select_one(".image img")
        thumbnail = None
        if img_tag is not None:
            raw_thumbnail = img_tag.get("data-src") or img_tag.get("src")
            if raw_thumbnail:
                thumbnail = urljoin(BASE_URL, raw_thumbnail)

        articles.append(
            {
                "url": urljoin(BASE_URL, link_tag["href"]),
                "headline": _text(title_tag),
                "summary": _text(summary_tag),
                "listing_time": listing_time,
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
    body_container = soup.select_one("article.jw_detail_content_holder")
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    author = ""
    author_field = metadata.get("author")
    if isinstance(author_field, dict):
        author = author_field.get("name") or ""
    elif isinstance(author_field, str):
        author = author_field

    image_url = ""
    image_field = metadata.get("image")
    if isinstance(image_field, dict):
        image_url = image_field.get("url") or ""
    elif isinstance(image_field, str):
        image_url = image_field

    return {
        "url": url,
        "headline": _normalize(" ".join((metadata.get("headline") or "").split())),
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
