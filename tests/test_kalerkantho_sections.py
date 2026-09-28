from scraper.sources.kalerkantho import parse_article, parse_articles, parse_sections

_NAV_HTML = """
<nav class="navbar static-top">
  <a href="/online/national">জাতীয়</a>
  <a href="/online/Politics">রাজনীতি</a>
  <a href="/epaper">ই-পেপার</a>
</nav>
"""

_LISTING_HTML = """
<div class="col-6 col-xl-3">
  <div class="row position-relative">
    <div class="col-12">
      <img src="https://asset.kalerkantho.com/news_images/1.jpg" />
    </div>
    <div class="col-12">
      <h3 class="mt-2 lh-base">প্রধানমন্ত্রীর সঙ্গে চীনা রাষ্ট্রদূতের বিদায়ি সাক্ষাৎ</h3>
      <div class="text-muted small mb-2 text-truncate-3 d-none d-xl-block">প্রধানমন্ত্রী তারেক রহমানের সঙ্গে বিদায়ি সাক্ষাৎ।</div>
      <small class="text-muted">২৮ সেপ্টেম্বর, ২০২৬ ১৪:২৪</small>
    </div>
    <a class="stretched-link" href="/online/national/2026/09/28/1745298"></a>
  </div>
</div>
"""

_ARTICLE_HTML = """
<meta property="og:image" content="https://asset.kalerkantho.com/news_images/1.jpg">
<div class="row details-module__Vu_sVW__sectionArea">
  <div class="col-12">
    <h1 class="fw-bold display-6 mt-3 lh-base">প্রধানমন্ত্রীর সঙ্গে চীনা রাষ্ট্রদূতের বিদায়ি সাক্ষাৎ</h1>
    <div class="row mt-3">
      <div class="col-12 col-xl-8">
        <span class="fw-bold text-dark">অনলাইন ডেস্ক</span>
        <time class="text-black-50">প্রকাশ: ২৮ সেপ্টেম্বর, ২০২৬ ১৪:২৪ | আপডেট: ২৮ সেপ্টেম্বর, ২০২৬ ১৬:০১</time>
      </div>
    </div>
    <article class="details-module__Vu_sVW__detailsBody news-details-content">
      <p>প্রধানমন্ত্রী তারেক রহমানের সঙ্গে বিদায়ি সাক্ষাৎ করেছেন।</p>
    </article>
  </div>
</div>
"""


def test_parse_sections_default_excludes_utility_pages():
    assert parse_sections(_NAV_HTML) == [
        ("national", "জাতীয়"),
        ("Politics", "রাজনীতি"),
    ]


def test_parse_articles_reads_stretched_link_headline_and_time():
    articles = parse_articles(_LISTING_HTML)
    assert articles == [
        {
            "url": "https://www.kalerkantho.com/online/national/2026/09/28/1745298",
            "headline": "প্রধানমন্ত্রীর সঙ্গে চীনা রাষ্ট্রদূতের বিদায়ি সাক্ষাৎ",
            "summary": "প্রধানমন্ত্রী তারেক রহমানের সঙ্গে বিদায়ি সাক্ষাৎ।",
            "listing_time": "২৮ সেপ্টেম্বর, ২০২৬ ১৪:২৪",
            "thumbnail": "https://asset.kalerkantho.com/news_images/1.jpg",
        }
    ]


def test_parse_article_takes_only_published_half_of_the_publish_update_time():
    detail = parse_article(_ARTICLE_HTML, "https://www.kalerkantho.com/online/national/2026/09/28/1745298")
    assert detail["headline"] == "প্রধানমন্ত্রীর সঙ্গে চীনা রাষ্ট্রদূতের বিদায়ি সাক্ষাৎ"
    assert detail["author"] == "অনলাইন ডেস্ক"
    assert detail["date_published"] == "প্রকাশ: ২৮ সেপ্টেম্বর, ২০২৬ ১৪:২৪"
    assert detail["image_url"] == "https://asset.kalerkantho.com/news_images/1.jpg"
    assert detail["paragraphs"] == ["প্রধানমন্ত্রী তারেক রহমানের সঙ্গে বিদায়ি সাক্ষাৎ করেছেন।"]
