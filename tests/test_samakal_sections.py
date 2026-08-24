from scraper.sources.samakal import parse_articles, parse_sections

_NAV_HTML = """
<ul class="navbar-nav">
  <li class="nav-item"><a class="nav-link" href="https://samakal.com/politics">রাজনীতি</a></li>
  <li class="nav-item"><a class="nav-link" href="https://samakal.com/video-gallery">ভিডিও</a></li>
</ul>
"""


def test_parse_sections_default_applies_core_allowlist():
    assert parse_sections(_NAV_HTML) == [("politics", "রাজনীতি")]


def test_parse_sections_include_all_bypasses_allowlist():
    assert parse_sections(_NAV_HTML, include_all=True) == [
        ("politics", "রাজনীতি"),
        ("video-gallery", "ভিডিও"),
    ]


# Regression coverage for a bug the section page's lead card + small-card
# rows alone missed entirely: a further row of cards nested inside
# div.CatSubList-area > div.CatListNews, which carry their own summary in
# div.ListDesc > p rather than p.CatDesc.
_ARTICLES_HTML = """
<div class="DCatLead">
  <a href="https://samakal.com/politics/article/1">
    <h1>Lead headline</h1>
    <p class="CatDesc">Lead summary</p>
    <span class="publishTime">২৩ আগস্ট ২০২৬ | ১০:০০</span>
  </a>
</div>
<div class="Catcards">
  <a href="https://samakal.com/politics/article/2">
    <h3>Small card headline</h3>
    <span class="publishTime">২৩ আগস্ট ২০২৬ | ০৯:০০</span>
  </a>
</div>
<div class="CatSubList-area">
  <div class="CatListNews">
    <a href="https://samakal.com/politics/article/3">
      <h3>Sub list headline</h3>
      <div class="ListDesc"><p>Sub list summary</p></div>
      <span class="publishTime">২৩ আগস্ট ২০২৬ | ০৮:০৫</span>
    </a>
  </div>
</div>
"""


def test_parse_articles_includes_sub_list_cards():
    articles = parse_articles(_ARTICLES_HTML)
    urls = [a["url"] for a in articles]
    assert urls == [
        "https://samakal.com/politics/article/1",
        "https://samakal.com/politics/article/2",
        "https://samakal.com/politics/article/3",
    ]
    assert articles[2]["summary"] == "Sub list summary"
    assert articles[2]["listing_time"] == "২৩ আগস্ট ২০২৬ | ০৮:০৫"
