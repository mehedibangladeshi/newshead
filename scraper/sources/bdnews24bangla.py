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

BASE_URL = "https://bangla.bdnews24.com"
COVER_LOGO_URL = "https://bangla.bdnews24.com/frontend/assets/images/common/logo.png"
COVER_ACCENT_COLOR = (0, 0, 0)  # masthead wordmark is plain black-on-white

SOURCE_NAME = "বিডিনিউজ টোয়েন্টিফোর বাংলা"

# bangla.bdnews24.com's top nav (".mobile-navbar", reused desktop-side too)
# mixes real editorial verticals with a few things that aren't a good fit
# for a text digest:
#   - "tube"/"photostory" are pure video/photo hubs - confirmed live by
#     fetching a /tube article: it uses the exact same card markup as every
#     other section, so parse_articles would happily "discover" it, but its
#     div#contentDetails body has zero <p> tags (all video, no prose).
#   - "coronavirus-pandemic" is a long-dead 2020-era event page, not an
#     ongoing editorial vertical.
#   - a handful of nav links point at one-off event subpages nested under a
#     real section (e.g. "/sport/world-cup-2022", "/cricket/t20wc2022",
#     "/media_bn/image") - those are filtered out structurally by only
#     keeping single-path-segment hrefs, no explicit list needed.
EXCLUDED_SECTION_SLUGS = {
    "tube",
    "photostory",
    "coronavirus-pandemic",
}

# Used only if live discovery finds nothing (defensive fallback), in the
# order they're encountered in the real nav.
FALLBACK_SECTIONS = [
    ("bangladesh", "বাংলাদেশ"),
    ("samagrabangladesh", "সমগ্র বাংলাদেশ"),
    ("ctg", "চট্টগ্রাম"),
    ("world", "বিশ্ব"),
    ("politics", "রাজনীতি"),
    ("arts", "আর্টস"),
    ("glitz", "গ্লিটজ"),
    ("lifestyle", "লাইফস্টাইল"),
    ("tech", "টেক"),
    ("kidz", "কিডজ"),
    ("probash", "প্রবাস"),
    ("science", "বিজ্ঞান"),
    ("environment", "পরিবেশ"),
    ("health", "স্বাস্থ্য"),
    ("campus", "ক্যাম্পাস"),
    ("special", "সবিশেষ"),
    ("nareespandan", "নারীস্পন্দন"),
    ("cricket", "ক্রিকেট"),
    ("sport", "খেলা"),
    ("opinion", "মতামত"),
    ("finance-and-trade", "অর্থ ও বাণিজ্য"),
    ("business", "বাণিজ্য"),
    ("economy", "অর্থনীতি"),
    ("stocks", "পুঁজিবাজার"),
    ("corporate", "করপোরেট"),
    ("neighbour", "প্রতিবেশী"),
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

    Only single-path-segment links from ".mobile-navbar" are considered - a
    real top-level section is always exactly "/<slug>", so this structurally
    excludes the one-off event subpages nested under a section (e.g.
    "/sport/world-cup-2022") and the multimedia hub ("/media_bn/image")
    without needing an explicit deny entry for them.

    include_all=True bypasses EXCLUDED_SECTION_SLUGS (see its comment
    above) - used only by scripts/discover_sections.py to audit the real
    nav; production discovery (include_all=False) is unchanged."""
    soup = BeautifulSoup(html, "html.parser")
    nav = soup.select_one(".mobile-navbar") or soup

    sections = []
    seen_slugs = set()
    for link in nav.select("a[href]"):
        href = link["href"]
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != urlparse(BASE_URL).netloc:
            continue
        slug = parsed.path.strip("/")
        if not slug or "/" in slug or slug in seen_slugs:
            continue
        if not include_all and slug in EXCLUDED_SECTION_SLUGS:
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

    A section page has one big lead card (div.Cat-lead-wrapper, with a
    summary paragraph), a column of smaller cards alongside it
    (div.Cat-list, headline + thumbnail only), and a further paginated
    "আরও" (more) grid of cards (div.rm-container, also headline + thumbnail
    only) - confirmed live on /bangladesh, the lead+small-card pair alone
    covers only ~5 of a section's ~15+ stories. All three wrap the whole
    card in a single <a>.

    Confirmed live across several sections and articles: bdnews24 bangla's
    listing cards carry no time signal at all (no relative-time text, no
    absolute-datetime span, no data-* timestamp attribute anywhere in the
    card markup) - unlike samakal/jugantor's span.publishTime equivalents.
    listing_time is therefore always "" here; timestamps.py has no parser
    registered for this source and parse_published_at() already returns
    None for that (safe, matches the "never guess" contract)."""
    soup = BeautifulSoup(html, "html.parser")

    articles = []
    seen_urls = set()
    for card in soup.select(
        "div.Cat-lead-wrapper > a[href], div.Cat-list > a[href], "
        "div.rm-container > a[href]"
    ):
        title_tag = card.select_one("h1, h5")
        if not title_tag:
            continue

        url = urljoin(BASE_URL, card["href"])
        if url in seen_urls:
            continue
        seen_urls.add(url)

        summary_tag = card.select_one("div.CatMain-detail > p")
        img_tag = card.select_one("img")

        thumbnail = None
        if img_tag is not None:
            raw_thumbnail = img_tag.get("src")
            if raw_thumbnail:
                thumbnail = urljoin(BASE_URL, raw_thumbnail)

        articles.append(
            {
                "url": url,
                "headline": _text(title_tag),
                "summary": _text(summary_tag),
                "listing_time": "",
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

    # The ld+json "author" field is unreliable here - on every article
    # checked live it's a bug that just repeats the headline instead of a
    # byline. The real byline lives in the DOM instead, in the first
    # span.author inside div.detail-author-name (e.g. "নিজস্ব প্রতিবেদক" /
    # "স্পোর্টস ডেস্ক"); a second span.author right after it is always just
    # the outlet's own name ("বিডিনিউজ টোয়েন্টিফোর ডটকম"), not a byline, so
    # only the first one is used.
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
    return bengali_date.format_bengali_date(edition_date)
