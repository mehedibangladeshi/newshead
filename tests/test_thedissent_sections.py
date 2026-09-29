from scraper.sources.thedissent import parse_article, parse_articles, parse_sections

_NAV_HTML = """
<a href="/current-affairs">Current Affairs</a>
<a href="/fact-checks">Fact Checks</a>
<a href="/about">About</a>
<a href="/current-affairs/some-story">Some Story</a>
"""

_LISTING_HTML = """
<a href="/current-affairs/baridhara-road-crash">
  <div class="_item_1bwkmh">
    <img src="https://static.thedissent.news/image.jpg" />
    <div class="_info_lojt13">
      <div class="_date_lojt13">24 September 2026</div>
      <div class="_title_lojt13">Baridhara Road Crash Death</div>
    </div>
  </div>
</a>
"""

_ARTICLE_HTML = """
<meta property="og:image" content="https://static.thedissent.news/image.jpg">
<div class="_article_1edcvt">
  <h4 class="_title_1rz71x">Baridhara Road Crash Death</h4>
  <div class="_authors_1kbvhs">
    <div class="_author-name_q18jvc">Azaharul Islam</div>
  </div>
  <div class="_date_12ybvm">24 September 2026</div>
  <div class="_body_1q212c">
    <p>The truck driver was seventeen years old.</p>
    <p>Settlement was reached out of court.</p>
  </div>
</div>
"""


def test_parse_sections_default_excludes_utility_pages():
    assert parse_sections(_NAV_HTML) == [
        ("current-affairs", "Current Affairs"),
        ("fact-checks", "Fact Checks"),
    ]


def test_parse_sections_include_all_keeps_utility_pages():
    sections = parse_sections(_NAV_HTML, include_all=True)
    assert ("about", "About") in sections


def test_parse_articles_scoped_to_section_prefix():
    articles = parse_articles(_LISTING_HTML, "current-affairs")
    assert articles == [
        {
            "url": "https://thedissent.news/current-affairs/baridhara-road-crash",
            "headline": "Baridhara Road Crash Death",
            "summary": "",
            "listing_time": "24 September 2026",
            "thumbnail": "https://static.thedissent.news/image.jpg",
        }
    ]


def test_parse_article_reads_scoped_headline_author_and_body():
    detail = parse_article(_ARTICLE_HTML, "https://thedissent.news/current-affairs/baridhara-road-crash")
    assert detail["headline"] == "Baridhara Road Crash Death"
    assert detail["image_url"] == "https://static.thedissent.news/image.jpg"
    assert detail["paragraphs"] == [
        "The truck driver was seventeen years old.",
        "Settlement was reached out of court.",
    ]
