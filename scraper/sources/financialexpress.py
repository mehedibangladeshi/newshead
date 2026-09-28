import logging
import re
import time
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

from .. import config, english_date
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://today.thefinancialexpress.com.bd"
COVER_LOGO_URL = f"{BASE_URL}/img/logo.png"
COVER_ACCENT_COLOR = (0, 48, 74)  # sampled from an article headline's inline style, #00304a

SOURCE_NAME = "The Financial Express"

# Real nav confirmed live (fetched a section page directly, not guessed from
# the homepage digest) - excludes special/anniversary/budget one-off pages
# ("special-issues", "budget-2026-27", "golden-jubilee-of-independence",
# "32nd-anniversary-issue-*") the same way dhakatribune's CORE_SECTION_SLUGS
# excludes its own catch-alls.
CORE_SECTION_SLUGS = {
    "first-page",
    "politics-policies",
    "metro-news",
    "views-opinion",
    "editorial",
    "views-reviews",
    "last-page",
    "stock-corporate",
    "country",
    "world",
    "sports",
    "trade-market",
    "education-youth",
    "features-analysis",
    "lifestyle",
    "tech-express",
}

FALLBACK_SECTIONS = [
    ("first-page", "FIRST PAGE"),
    ("country", "COUNTRY"),
    ("world", "WORLD"),
    ("sports", "SPORTS"),
    ("editorial", "EDITORIAL"),
]

# "Neil Ray   |September 28, 2026 00:00:00" - author and an English absolute
# datetime (24-hour, with seconds) sharing one byline paragraph, confirmed
# live on an article page.
_BYLINE_RE = re.compile(
    r"^(?P<author>[^|]+?)\s*\|\s*"
    r"(?P<month>[A-Za-z]+)\s+(?P<day>\d{1,2}),\s*(?P<year>\d{4})\s+"
    r"(?P<hour>\d{1,2}):(?P<minute>\d{2}):(?P<second>\d{2})$"
)

_session = config.make_session()


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes raw homepage/section-
    page HTML (the nav is identical on every page), returns a list of
    (slug, section_name) or [] if none were found."""
    soup = BeautifulSoup(html, "html.parser")
    container = soup.select_one("nav.navbar") or soup

    sections = []
    seen_slugs = set()
    for link in container.select("a[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != "today.thefinancialexpress.com.bd":
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
    returns a list of article listing dicts.

    Unlike every other source, a section page here has no per-article card
    wrapper: each story is a flat <h2> headline, <p> summary, then
    <a class="readmore"> link, repeated - so articles are found by scanning
    the "read more" links and reading back their preceding siblings. No
    thumbnail is present on listing pages (confirmed live) - image comes
    from fetch_article's og:image instead, same fallback generate_data.py's
    enrich_item() already applies to any source missing one."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    for link_tag in soup.select("a.readmore[href]"):
        headline_tag = link_tag.find_previous_sibling("h2")
        summary_tag = link_tag.find_previous_sibling("p")
        if headline_tag is None:
            continue

        articles.append(
            {
                "url": link_tag["href"],
                "headline": _text(headline_tag),
                "summary": _text(summary_tag),
                "listing_time": "",
                "thumbnail": None,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/{slug}"
    html = _get(section_url)
    return parse_articles(html)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")

    headline_tag = soup.select_one("h1.single-heading")
    body_container = soup.select_one("div.left-bar")
    image_tag = soup.select_one('meta[property="og:image"]')

    author = ""
    date_published = ""
    paragraphs = []
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if not text or text.startswith("/"):
                continue
            match = _BYLINE_RE.match(text)
            if match:
                author = match.group("author").strip()
                date_published = (
                    f"{match.group('month')} {match.group('day')}, {match.group('year')} "
                    f"{match.group('hour')}:{match.group('minute')}:{match.group('second')}"
                )
                continue
            paragraphs.append(text)

    return {
        "url": url,
        "headline": _text(headline_tag),
        "author": _normalize(author),
        "date_published": date_published,
        "image_url": (image_tag.get("content") or "").strip() if image_tag else "",
        "paragraphs": paragraphs,
    }


def fetch_article(url):
    html = _get(url)
    return parse_article(html, url)


def get_cover_logo_url():
    return COVER_LOGO_URL


def format_date(edition_date):
    return english_date.format_english_date(edition_date)
