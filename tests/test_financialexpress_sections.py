from scraper.sources.financialexpress import parse_article, parse_articles, parse_sections

_NAV_HTML = """
<nav class="navbar navbar-default">
  <ul class="nav navbar-nav">
    <li><a href="https://today.thefinancialexpress.com.bd/first-page">FIRST PAGE</a></li>
    <li><a href="https://today.thefinancialexpress.com.bd/country">COUNTRY</a></li>
    <li><a href="https://today.thefinancialexpress.com.bd/archive">ARCHIVE</a></li>
    <li><a href="https://today.thefinancialexpress.com.bd/budget-2026-27">BudgetFY27</a></li>
  </ul>
</nav>
"""

_LISTING_HTML = """
<div class="left-bar">
  <h2>Sylhet road in deplorable state</h2>
  <p>Allegations have that massive irregularities...</p>
  <a class="btn readmore btn-sm" href="https://today.thefinancialexpress.com.bd/country/sylhet-road-1">Read more</a>
</div>
"""

_ARTICLE_HTML = """
<meta property="og:image" content="https://today.thefinancialexpress.com.bd/uploads/1.jpg">
<h1 class="single-heading">All hell broke loose on Thursday night</h1>
<div class="col-lg-9 left-bar">
  <p>/ EDITORIAL</p>
  <p>Neil Ray   |September 28, 2026 00:00:00</p>
  <p>The country has been a witness to vandalism.</p>
  <p>More than two hundred people took part.</p>
</div>
"""


def test_parse_sections_excludes_archive_and_budget_utility_pages():
    assert parse_sections(_NAV_HTML) == [
        ("first-page", "FIRST PAGE"),
        ("country", "COUNTRY"),
    ]


def test_parse_sections_include_all_keeps_utility_pages():
    sections = parse_sections(_NAV_HTML, include_all=True)
    assert ("archive", "ARCHIVE") in sections
    assert ("budget-2026-27", "BudgetFY27") in sections


def test_parse_articles_reads_flat_headline_summary_readmore_triplet():
    articles = parse_articles(_LISTING_HTML)
    assert articles == [
        {
            "url": "https://today.thefinancialexpress.com.bd/country/sylhet-road-1",
            "headline": "Sylhet road in deplorable state",
            "summary": "Allegations have that massive irregularities...",
            "listing_time": "",
            "thumbnail": None,
        }
    ]


def test_parse_article_splits_byline_from_body_and_skips_section_label():
    detail = parse_article(_ARTICLE_HTML, "https://today.thefinancialexpress.com.bd/editorial/x")
    assert detail["headline"] == "All hell broke loose on Thursday night"
    assert detail["author"] == "Neil Ray"
    assert detail["date_published"] == "September 28, 2026 00:00:00"
    assert detail["image_url"] == "https://today.thefinancialexpress.com.bd/uploads/1.jpg"
    assert detail["paragraphs"] == [
        "The country has been a witness to vandalism.",
        "More than two hundred people took part.",
    ]
