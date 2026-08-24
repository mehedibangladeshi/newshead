from scraper.sources.banglatribune import parse_articles, parse_sections

_NAV_HTML = """
<a href="https://www.banglatribune.com/national">জাতীয়</a>
<a href="https://www.banglatribune.com/others">অন্যান্য</a>
"""


def test_parse_sections_default_applies_core_allowlist():
    assert parse_sections(_NAV_HTML) == [("national", "জাতীয়")]


def test_parse_sections_include_all_bypasses_allowlist():
    assert parse_sections(_NAV_HTML, include_all=True) == [
        ("national", "জাতীয়"),
        ("others", "অন্যান্য"),
    ]


_ARTICLES_HTML = """
<div class="each">
  <a class="link_overlay" href="https://www.banglatribune.com/national/article/1">
    <div class="title_holder"><span class="title">Headline</span></div>
    <span class="summery">Summary</span>
    <span class="time" data-published="2026-08-23T12:58:59+06:00">3 hours ago</span>
  </a>
</div>
"""


def test_parse_articles_prefers_data_published_over_display_text():
    articles = parse_articles(_ARTICLES_HTML)
    assert len(articles) == 1
    assert articles[0]["listing_time"] == "2026-08-23T12:58:59+06:00"
