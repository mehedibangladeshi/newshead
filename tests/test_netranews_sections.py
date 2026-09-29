from scraper.sources.netranews import discover_sections, parse_article, parse_articles

_LISTING_HTML = """
<article class="ntr-rpx-card ntr-rpx-card--lead">
  <a class="ntr-rpx-card-media" href="/2026/mandi-village-came-under-attack-en/">
    <img class="ntr-rpx-card-img" src="/content/images/2026/09/photo.jpg" />
  </a>
  <div class="ntr-rpx-card-body">
    <h2 class="ntr-rpx-card-title"><a href="/2026/mandi-village-came-under-attack-en/">A corpse was found</a></h2>
    <p class="ntr-rpx-card-deck">When hundreds of people attacked a Mandi village.</p>
    <div class="ntr-rpx-card-meta">
      <time class="ntr-rpx-card-date" datetime="2026-09-27">September 27th 2026</time>
    </div>
  </div>
</article>
"""

_ARTICLE_HTML = """
<meta property="og:image" content="https://netra.news/og-image.jpg">
<article class="article tag-netra-report">
  <h1>A corpse was found, then a Mandi village came under attack</h1>
  <a class="ntr-article-author-name" href="/authors/iffat/">Iffat Ara Munia</a>
  <time class="ntr-article-date ntr-pub-date" datetime="2026-09-27">September 27th 2026</time>
  <section class="gh-content gh-canvas">
    <p>A man disappeared from a village in Sherpur.</p>
    <p>Eight days later his corpse was found.</p>
  </section>
</article>
"""


def test_discover_sections_returns_fixed_taxonomy():
    sections = discover_sections()
    assert ("netra-report", "Reports") in sections
    assert ("short-video", "Video") not in sections


def test_discover_sections_is_deterministic_across_calls():
    # CORE_SECTION_SLUGS is a set - discover_sections() must iterate a
    # stable-ordered structure instead, since sections[0] becomes "Main".
    assert discover_sections() == discover_sections()


def test_parse_articles_reads_card_fields():
    articles = parse_articles(_LISTING_HTML)
    assert articles == [
        {
            "url": "https://netra.news/2026/mandi-village-came-under-attack-en/",
            "headline": "A corpse was found",
            "summary": "When hundreds of people attacked a Mandi village.",
            "listing_time": "2026-09-27",
            "thumbnail": "https://netra.news/content/images/2026/09/photo.jpg",
        }
    ]


def test_parse_article_reads_headline_author_date_and_body():
    detail = parse_article(_ARTICLE_HTML, "https://netra.news/2026/mandi-village-came-under-attack-en/")
    assert detail["headline"] == "A corpse was found, then a Mandi village came under attack"
    assert detail["image_url"] == "https://netra.news/og-image.jpg"
    assert detail["paragraphs"] == [
        "A man disappeared from a village in Sherpur.",
        "Eight days later his corpse was found.",
    ]
