import logging
import time
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from .. import config, english_date
from .text_utils import extract_text as _text
from .text_utils import normalize_text as _normalize

logger = logging.getLogger(__name__)

BASE_URL = "https://www.thedhakapost.com"

# Confirmed live: despite the domain name, www.thedhakapost.com IS the
# English edition by default - the homepage nav carries a "বাংলা সংস্করণ"
# ("Bangla version") link pointing at /bn, so the root site (and every
# section under it) is already English prose, not vice versa. There is no
# separate en.thedhakapost.com subdomain (DNS doesn't resolve) and
# /english / /en both 500.
COVER_LOGO_URL = "https://www.thedhakapost.com/assets/importent_images/logo.jpg"
COVER_ACCENT_COLOR = (176, 20, 34)  # sampled from the logo's red wordmark

SOURCE_NAME = "The Dhaka Post"

# Confirmed live (2026-08-24) via the homepage's single <nav class="top-nav">
# menu - a small flat list, no mega-menu subcategories like Dhaka Tribune's.
# "Technolgy" is the site's own nav-label typo for the tech section (its
# link's title attribute reads "Technology | The Dhaka Post" - used here
# for the display name instead of the misspelled visible label).
SECTION_DISPLAY_NAMES = {
    "national": "National",
    "politics": "Politics",
    "foreign-news": "Foreign News",
    "world": "World",
    "business": "Business",
    "sports": "Sports",
    "health": "Health",
    "education": "Education",
    "tech": "Technology",
    "entertainment": "Entertainment",
    "lifesyle": "Life-Style",  # site's own slug typo ("lifesyle", not "lifestyle")
    "weird": "Weird News",
    "interview": "Interview",
}

# No video/photo-hub nav items were found live - every section above is
# real prose (confirmed by fetching each one), so there's nothing to
# exclude. Kept as an empty set (rather than omitted) to match the other
# source modules' shape/expectations.
EXCLUDED_SECTION_SLUGS = set()

# Used only if the homepage fetch itself fails outright (defensive
# fallback), in the order they appear in the real nav.
FALLBACK_SECTIONS = [
    ("national", "National"),
    ("politics", "Politics"),
    ("world", "World"),
    ("business", "Business"),
    ("sports", "Sports"),
    ("health", "Health"),
    ("education", "Education"),
    ("tech", "Technology"),
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

    include_all=True keeps EXCLUDED_SECTION_SLUGS entries (currently none)
    instead of dropping them - used only by scripts/discover_sections.py to
    audit the real nav; production discovery (include_all=False) is
    unchanged."""
    soup = BeautifulSoup(html, "html.parser")
    nav = soup.select_one("nav.top-nav") or soup

    sections = []
    seen_slugs = set()
    for link in nav.select("a[href]"):
        href = link["href"]
        # Real section links are site-relative "./slug" hrefs; "" is Home
        # and "#" is the "More" dropdown toggle itself (its actual entries
        # - Entertainment, Life-Style, etc - are separate "./slug" <a> tags
        # inside the same nav, so nothing is lost by skipping "#").
        if not href.startswith("./"):
            continue
        slug = href[2:].strip("/")
        if not slug or slug in seen_slugs:
            continue
        if not include_all and slug in EXCLUDED_SECTION_SLUGS:
            continue
        seen_slugs.add(slug)
        sections.append((slug, SECTION_DISPLAY_NAMES.get(slug, _normalize(link.get_text(strip=True)))))

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
    for card in soup.select("div.n_post"):
        link_tag = card.select_one("h1 a[href]")
        if not link_tag:
            continue

        img_tag = card.select_one("img[src]")
        # Listing cards carry the update time in a bare <span> right under
        # the headline (e.g. "16 November, 2024 10:44 am") - no id/class of
        # its own, unlike the headline's <h1> or summary's <article>.
        time_tag = card.select_one("span")

        articles.append(
            {
                "url": urljoin(BASE_URL, link_tag["href"]),
                "headline": _text(link_tag),
                "summary": _text(card.select_one("article p")),
                "listing_time": _text(time_tag),
                "thumbnail": urljoin(BASE_URL, img_tag["src"]) if img_tag else None,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/{slug}"
    html = _get(section_url)
    return parse_articles(html)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict.

    Unlike TBS/Dhaka Tribune, Dhaka Post's article pages carry no ld+json
    NewsArticle block at all (only an Organization block), so everything
    here is hand-parsed straight from the DOM instead of going through
    ld_json.select_by_type()."""
    soup = BeautifulSoup(html, "html.parser")

    headline_tag = soup.select_one(".details h1")

    # "#rpt" is the site's own byline/credit slot just under the headline
    # (e.g. "UNB", "Online Desk") - a news-agency/desk credit rather than a
    # personal byline, but it's the closest thing to an author this site
    # exposes, same role as author on the other sources.
    author_tag = soup.select_one("#rpt")

    # Raw text is "Update : 16 November, 2024 10:44 am" - strip the label,
    # timestamps.py parses what's left. Confirmed live across sections that
    # the format is inconsistent about 24h-vs-12h ("15:00 pm" as well as
    # "10:44 am"), so the parser will need to handle both.
    date_tag = soup.select_one("#news_update_time")
    date_published = _text(date_tag)
    if date_published.startswith("Update"):
        date_published = date_published.split(":", 1)[-1].strip()

    image_tag = soup.select_one("img.details_img")
    image_url = urljoin(BASE_URL, image_tag["src"]) if image_tag and image_tag.get("src") else ""

    paragraphs = []
    body_container = soup.select_one(".details_view")
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = _text(p)
            if text:
                paragraphs.append(text)

    return {
        "url": url,
        "headline": _normalize(" ".join(_text(headline_tag).split())),
        "author": _normalize(" ".join(_text(author_tag).split())),
        "date_published": date_published,
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
