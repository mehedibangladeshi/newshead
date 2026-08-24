from scraper.sources.bdnews24bangla import parse_article, parse_articles, parse_sections

_NAV_HTML = """
<div class="mobile-navbar">
  <a href="#">হোম</a>
  <a href="/bangladesh">বাংলাদেশ</a>
  <a href="/sport/world-cup-2022">কাতার বিশ্বকাপ ২০২২</a>
  <a href="/tube">টিউব</a>
  <a href="/opinion">মতামত</a>
</div>
"""


def test_parse_sections_skips_toggle_and_nested_event_subpage():
    assert parse_sections(_NAV_HTML) == [
        ("bangladesh", "বাংলাদেশ"),
        ("opinion", "মতামত"),
    ]


def test_parse_sections_include_all_bypasses_excluded_slugs_but_not_nested_paths():
    # include_all bypasses EXCLUDED_SECTION_SLUGS (so "tube" reappears) but
    # multi-path-segment hrefs like "/sport/world-cup-2022" are filtered
    # structurally, not via the deny list, so they stay excluded either way.
    assert parse_sections(_NAV_HTML, include_all=True) == [
        ("bangladesh", "বাংলাদেশ"),
        ("tube", "টিউব"),
        ("opinion", "মতামত"),
    ]


# Modeled on the real /bangladesh section page DOM: one lead card with a
# summary paragraph, a column of smaller cards with headline+thumbnail
# only, and a further paginated "আরও" grid, also headline+thumbnail only.
# None of the three card shapes carry any listing-time signal anywhere in
# their markup - confirmed live across several sections.
_ARTICLES_HTML = """
<div class="Cat-lead-wrapper">
  <a href="bangladesh/db558adec64d">
    <div class="CatMain-img">
      <img alt="lead" class="img-fluid" src="https://media-stg.assettype.com/lead.jpg">
    </div>
    <div class="CatMain-detail">
      <h1>Lead headline</h1>
      <p>Lead summary</p>
    </div>
  </a>
</div>
<div class="Cat-list">
  <a href="bangladesh/de36ac8c2650">
    <div class="row">
      <div class="catlist-head"><h5>Small card headline</h5></div>
      <div class="catlist-img"><img alt="small" class="img-fluid" src="https://media-stg.assettype.com/small.jpg"></div>
    </div>
  </a>
</div>
<div class="rm-container">
  <a href="https://bangla.bdnews24.com/bangladesh/c881612f1f6e">
    <div class="row">
      <div class="rm-pic"><img alt="more" class="img-fluid" src="https://media-stg.assettype.com/more.jpg"></div>
      <div class="rm-subCat"><h5>Read-more headline</h5></div>
    </div>
  </a>
</div>
"""


def test_parse_articles_reads_all_three_card_shapes():
    articles = parse_articles(_ARTICLES_HTML)
    assert [a["url"] for a in articles] == [
        "https://bangla.bdnews24.com/bangladesh/db558adec64d",
        "https://bangla.bdnews24.com/bangladesh/de36ac8c2650",
        "https://bangla.bdnews24.com/bangladesh/c881612f1f6e",
    ]
    assert articles[0]["headline"] == "Lead headline"
    assert articles[0]["summary"] == "Lead summary"
    assert articles[0]["thumbnail"] == "https://media-stg.assettype.com/lead.jpg"
    assert articles[1]["headline"] == "Small card headline"
    assert articles[1]["summary"] == ""
    assert articles[2]["headline"] == "Read-more headline"
    # No time signal exists anywhere in this source's listing markup.
    assert all(a["listing_time"] == "" for a in articles)


def test_parse_articles_skips_cards_without_a_headline():
    assert parse_articles('<div class="Cat-list"><a href="x"><img src="y"></a></div>') == []


# Modeled on the real article-page DOM: an ld+json NewsArticle block whose
# "author" field is a confirmed bug (it just repeats the headline), so the
# real byline is read from the DOM's div.detail-author-name instead - its
# first span.author is the actual byline, a second one right after is
# always just the outlet's own name, not a byline.
_ARTICLE_HTML = """
<script type="application/ld+json">
{"@type": "NewsArticle", "headline": "Ld json headline", "datePublished": "2026-08-24 23:33:01",
 "author": {"@type": "Person", "name": "Ld json headline"},
 "image": {"@type": "ImageObject", "url": "https://media-stg.assettype.com/cover.jpg"}}
</script>
<div class="details-title">
  <h1>Real headline</h1>
</div>
<div class="detail-author-name">
  <span class="author">নিজস্ব প্রতিবেদক</span>
  <span class="author">বিডিনিউজ টোয়েন্টিফোর ডটকম</span>
</div>
<div class="details-brief" id="contentDetails">
  <p>First paragraph of real prose.</p>
  <p>Second paragraph of real prose.</p>
</div>
"""


def test_parse_article_prefers_dom_byline_over_buggy_ld_json_author():
    article = parse_article(_ARTICLE_HTML, "https://bangla.bdnews24.com/bangladesh/db558adec64d")
    assert article["url"] == "https://bangla.bdnews24.com/bangladesh/db558adec64d"
    assert article["headline"] == "Real headline"
    assert article["author"] == "নিজস্ব প্রতিবেদক"
    assert article["date_published"] == "2026-08-24 23:33:01"
    assert article["image_url"] == "https://media-stg.assettype.com/cover.jpg"
    assert article["paragraphs"] == [
        "First paragraph of real prose.",
        "Second paragraph of real prose.",
    ]
