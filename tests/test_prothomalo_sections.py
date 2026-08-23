import json
from datetime import datetime
from zoneinfo import ZoneInfo

from scraper.sources.prothomalo import parse_articles, parse_sections

DHAKA_TZ = ZoneInfo("Asia/Dhaka")

_HTML = """
<div id="navbar">
  <a href="https://www.prothomalo.com/bangladesh">বাংলাদেশ</a>
  <a href="https://www.prothomalo.com/video">ভিডিও</a>
</div>
"""


def test_parse_sections_default_applies_denylist():
    assert parse_sections(_HTML) == [("bangladesh", "বাংলাদেশ")]


def test_parse_sections_include_all_bypasses_denylist():
    assert parse_sections(_HTML, include_all=True) == [
        ("bangladesh", "বাংলাদেশ"),
        ("video", "ভিডিও"),
    ]


def _static_page_html(stories):
    payload = {"qt": {"data": {"collection": {"items": [
        {"type": "story", "story": story} for story in stories
    ]}}}}
    return '<script type="application/json" id="static-page">' + json.dumps(payload) + "</script>"


def test_parse_articles_propagates_the_raw_published_at_epoch_into_listing_time():
    published = datetime(2026, 8, 23, 10, 0, tzinfo=DHAKA_TZ)
    epoch_ms = int(published.timestamp() * 1000)
    html = _static_page_html([
        {
            "url": "https://www.prothomalo.com/bangladesh/abc123",
            "headline": "Headline",
            "subheadline": "Summary",
            "published-at": epoch_ms,
            "hero-image-s3-key": None,
        }
    ])

    articles = parse_articles(html, "2026-08-23")

    assert len(articles) == 1
    assert articles[0]["listing_time"] == epoch_ms
