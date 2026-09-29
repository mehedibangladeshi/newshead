import logging
import re
import time
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from .. import browser_client, config

logger = logging.getLogger(__name__)

BASE_URL = "https://www.kalerkantho.com"
COVER_LOGO_URL = "https://asset.kalerkantho.com/files/share_logo.png"
SOURCE_NAME = "কালের কণ্ঠ"

# Real nav confirmed live at /online/<slug> - "Islamic-lifestylie" is kept
# verbatim (a typo/label mismatch on the live site itself, not ours to
# "fix" - see the category-mapping note in generate_data.py).
CORE_SECTION_SLUGS = {
    "national",
    "country-news",
    "dhaka",
    "chattogram",
    "Politics",
    "Court",
    "campus-online",
    "world",
    "sport",
    "entertainment",
    "business",
    "Islamic-lifestylie",
    "lifestyle",
    "shuvosangho",
}

SECTION_DISPLAY_NAMES = {
    "national": "জাতীয়",
    "country-news": "সারাবাংলা",
    "dhaka": "রাজধানী",
    "chattogram": "দ্বিতীয় রাজধানী",
    "Politics": "রাজনীতি",
    "Court": "আইন-আদালত",
    "campus-online": "শিক্ষা",
    "world": "বিশ্ব",
    "sport": "খেলা",
    "entertainment": "বিনোদন",
    "business": "বাণিজ্য",
    "Islamic-lifestylie": "অনলাইন",
    "lifestyle": "জীবনযাপন",
    "shuvosangho": "বসুন্ধরা শুভসংঘ",
}

FALLBACK_SECTIONS = [(slug, name) for slug, name in SECTION_DISPLAY_NAMES.items()]

# "প্রকাশ: ২৮ সেপ্টেম্বর, ২০২৬ ১৪:২৪" (listing cards) and
# "প্রকাশ: সোমবার, ২৮ সেপ্টেম্বর, ২০২৬ ১৪:২৪ | আপডেট: ..." (article pages) -
# a Bengali absolute datetime, 24-hour, with the comma placement varying by
# page (after the month on listing cards, after the year on nayadiganta's
# equivalent format) - the regex tolerates both, see timestamps.py.
_session = config.make_session()

# kalerkantho.com's /online/<section> listing pages render an empty shell at
# domcontentloaded and fetch their real story cards client-side afterwards
# (confirmed live - see browser_client.get_html's extra_wait_ms); its
# article pages have the same race on first paint (a headline/body mismatch
# was observed briefly reflecting a "next story" widget before settling),
# so both listing and article fetches use the same settle delay.
_BROWSER_WAIT_MS = 4000


def _get(url):
    time.sleep(config.REQUEST_DELAY_SECONDS)
    try:
        response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
        response.raise_for_status()
        return response.text
    except requests.RequestException:
        # kalerkantho.com's Cloudflare has been blocking this runner's IP
        # with a JS challenge (confirmed live); a real browser can pass
        # that where plain requests can't - same fallback jugantor.py uses.
        logger.info("kalerkantho: falling back to browser fetch for %s", url)
        return browser_client.get_html(url, extra_wait_ms=_BROWSER_WAIT_MS)


def parse_sections(html, include_all=False):
    """Pure parsing step for discover_sections; takes raw nav-bearing page
    HTML, returns a list of (slug, section_name) or [] if none were found.

    include_all is accepted for interface parity with other source modules'
    discovery bypass but only ever returns CORE_SECTION_SLUGS here - this
    is already the site's own full topical nav, there's no larger catch-all
    superset to expose."""
    soup = BeautifulSoup(html, "html.parser")
    nav = soup.select_one("nav.navbar") or soup

    sections = []
    seen_slugs = set()
    for link in nav.select('a[href^="/online/"]'):
        slug = link["href"].removeprefix("/online/").strip("/")
        if not slug or slug in seen_slugs:
            continue
        if not include_all and slug not in CORE_SECTION_SLUGS:
            continue
        seen_slugs.add(slug)
        sections.append((slug, SECTION_DISPLAY_NAMES.get(slug, slug)))

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
    returns a list of article listing dicts. Every card's real link is an
    invisible Bootstrap "stretched-link" overlay anchor, not a link wrapping
    the headline text itself (confirmed live)."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    for link_tag in soup.select("a.stretched-link[href]"):
        card = link_tag.parent
        headline_tag = card.select_one("h1, h2, h3")
        if headline_tag is None:
            continue

        summary_tag = card.select_one(".text-truncate-3")
        time_tag = card.select_one("small.text-muted")
        img_tag = card.select_one("img[src]")

        articles.append(
            {
                "url": urljoin(BASE_URL, link_tag["href"]),
                "headline": headline_tag.get_text(strip=True),
                "summary": summary_tag.get_text(strip=True) if summary_tag else "",
                "listing_time": time_tag.get_text(strip=True) if time_tag else "",
                "thumbnail": img_tag["src"] if img_tag else None,
            }
        )

    return articles


def list_articles(slug, edition_date=None):
    section_url = f"{BASE_URL}/online/{slug}"
    html = _get(section_url)
    return parse_articles(html)


def parse_article(html, url):
    """Pure parsing step for fetch_article; takes raw article-page HTML and
    the article's URL, returns the article detail dict."""
    soup = BeautifulSoup(html, "html.parser")

    section_area = soup.select_one('[class*="sectionArea"]') or soup
    headline_tag = section_area.select_one("h1")
    body_container = section_area.select_one('article[class*="detailsBody"]')
    image_tag = soup.select_one('meta[property="og:image"]')

    paragraphs = []
    if body_container is not None:
        for p in body_container.find_all("p"):
            text = p.get_text(strip=True)
            if text:
                paragraphs.append(text)

    return {
        "url": url,
        "headline": headline_tag.get_text(strip=True) if headline_tag else "",
        "image_url": (image_tag.get("content") or "") if image_tag else "",
        "paragraphs": paragraphs,
    }


def fetch_article(url):
    html = _get(url)
    return parse_article(html, url)


def get_cover_logo_url():
    return COVER_LOGO_URL
