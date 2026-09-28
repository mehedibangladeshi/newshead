from scraper.sources.dailywaadaa import parse_article, parse_homepage

_HOMEPAGE_HTML = """
<div data-test-id="story-card">
  <div data-test-id="default-story-content">
    <div data-test-id="headline">
      <a aria-label="headline" href="https://dailywaadaa.com/bangladesh/2026/09/28/rooppur-1">
        <h3>Rooppur nuclear fuel transport disrupted</h3>
      </a>
    </div>
    <div data-test-id="subheadline">The land dispute may explain why.</div>
    <div><time class="arr__timeago" datetime="2026-09-28T05:18:50.167Z">4 hours ago</time></div>
  </div>
  <img class="qt-image" src="//media.assettype.com/dailywaadaa/thumb.jpg" />
</div>
<div data-test-id="story-card">
  <div data-test-id="headline">
    <a aria-label="headline" href="https://dailywaadaa.com/latest/2026/09/28/aggregator-item">
      <h3>Aggregator-only item</h3>
    </a>
  </div>
</div>
"""

_ARTICLE_HTML = """
<meta property="og:image" content="https://media.assettype.com/photo.jpg">
<article>
  <h1 data-testid="story-headline"><bdi>Rooppur nuclear fuel transport disrupted</bdi></h1>
  <div data-test-id="author-name"><a href="/author/waada-desk">Waadaa Desk</a></div>
  <time class="arr__timeago" datetime="2026-09-28T05:18:50.167Z">28 Sep 2026, 5:18 am</time>
  <div data-test-id="text"><p>Uranium transport has been disrupted.</p></div>
  <div data-test-id="text"><p>A new date has been proposed.</p></div>
</article>
"""


def test_parse_homepage_default_excludes_latest_aggregator():
    grouped = parse_homepage(_HOMEPAGE_HTML)
    assert list(grouped.keys()) == ["bangladesh"]
    assert grouped["bangladesh"] == [
        {
            "url": "https://dailywaadaa.com/bangladesh/2026/09/28/rooppur-1",
            "headline": "Rooppur nuclear fuel transport disrupted",
            "summary": "The land dispute may explain why.",
            "listing_time": "2026-09-28T05:18:50.167Z",
            "thumbnail": "https://media.assettype.com/dailywaadaa/thumb.jpg",
        }
    ]


def test_parse_homepage_include_all_keeps_latest_aggregator():
    grouped = parse_homepage(_HOMEPAGE_HTML, include_all=True)
    assert set(grouped.keys()) == {"bangladesh", "latest"}


def test_parse_article_reads_scoped_body_and_iso_time():
    detail = parse_article(_ARTICLE_HTML, "https://dailywaadaa.com/bangladesh/2026/09/28/rooppur-1")
    assert detail["headline"] == "Rooppur nuclear fuel transport disrupted"
    assert detail["author"] == "Waadaa Desk"
    assert detail["date_published"] == "2026-09-28T05:18:50.167Z"
    assert detail["image_url"] == "https://media.assettype.com/photo.jpg"
    assert detail["paragraphs"] == [
        "Uranium transport has been disrupted.",
        "A new date has been proposed.",
    ]
