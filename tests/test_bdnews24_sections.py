from scraper.sources.bdnews24 import parse_archive, parse_article

_ARCHIVE_HTML = """
<div class="SubCat-wrapper">
  <a href="https://bdnews24.com/bangladesh/4849bc5172bf">
    <div class="row">
      <div class="col-md-4 col-4"><img src="https://media-stg.assettype.com/one.jpg"></div>
      <div class="col-md-8 col-8">
        <div class="SubcatList-detail">
          <span class="category-arch">Bangladesh</span>
          <h5>Headline one</h5>
          <span class="publish-time">Published : 24 Aug 2026, 11:55 PM</span>
        </div>
      </div>
    </div>
  </a>
</div>
<div class="SubCat-wrapper">
  <a href="https://bdnews24.com/media-en/image/07e6c2da19eb">
    <div class="row">
      <div class="col-md-4 col-4"><img src="https://media-stg.assettype.com/two.jpg"></div>
      <div class="col-md-8 col-8">
        <div class="SubcatList-detail">
          <span class="category-arch">Image</span>
          <h5>Photo gallery headline</h5>
          <span class="publish-time">Published : 24 Aug 2026, 06:26 PM</span>
        </div>
      </div>
    </div>
  </a>
</div>
"""


def test_parse_archive_default_excludes_photo_hub():
    grouped = parse_archive(_ARCHIVE_HTML)
    assert list(grouped.keys()) == ["bangladesh"]


def test_parse_archive_include_all_keeps_photo_hub():
    grouped = parse_archive(_ARCHIVE_HTML, include_all=True)
    assert set(grouped.keys()) == {"bangladesh", "media-en"}


def test_parse_archive_reads_headline_thumbnail_and_listing_time():
    grouped = parse_archive(_ARCHIVE_HTML)
    article = grouped["bangladesh"][0]
    assert article["url"] == "https://bdnews24.com/bangladesh/4849bc5172bf"
    assert article["headline"] == "Headline one"
    assert article["summary"] == ""
    assert article["listing_time"] == "Published : 24 Aug 2026, 11:55 PM"
    assert article["thumbnail"] == "https://media-stg.assettype.com/one.jpg"


def test_parse_archive_skips_cards_without_a_headline():
    assert parse_archive('<div class="SubCat-wrapper"><a href="x"><img src="y"></a></div>') == {}


# Modeled on the real article-page DOM: an ld+json NewsArticle block whose
# "author" field is a confirmed bug (it just repeats the headline), so the
# real byline is read from the DOM's div.detail-author-name instead - its
# first span.author is the actual byline, a second one right after is
# always just the outlet's own name, not a byline.
_ARTICLE_HTML = """
<script type="application/ld+json">
{"@type": "NewsArticle", "headline": "Ld json headline", "datePublished": "2026-08-24 23:55:35",
 "author": {"@type": "Person", "name": "Ld json headline"},
 "image": {"@type": "ImageObject", "url": "https://media-stg.assettype.com/cover.jpg"}}
</script>
<div class="details-title">
  <h1>Real headline</h1>
</div>
<div class="detail-author-name">
  <span class="author">Staff Correspondent</span>
  <span class="author">bdnews24.com</span>
</div>
<div class="details-brief" id="contentDetails">
  <p>First paragraph of real prose.</p>
  <p>Second paragraph of real prose.</p>
</div>
"""


def test_parse_article_prefers_dom_byline_over_buggy_ld_json_author():
    article = parse_article(_ARTICLE_HTML, "https://bdnews24.com/bangladesh/4849bc5172bf")
    assert article["url"] == "https://bdnews24.com/bangladesh/4849bc5172bf"
    assert article["headline"] == "Real headline"
    assert article["author"] == "Staff Correspondent"
    assert article["date_published"] == "2026-08-24 23:55:35"
    assert article["image_url"] == "https://media-stg.assettype.com/cover.jpg"
    assert article["paragraphs"] == [
        "First paragraph of real prose.",
        "Second paragraph of real prose.",
    ]
