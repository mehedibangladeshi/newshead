from scraper.sources.nayadiganta import parse_article, parse_articles, parse_sections

_NAV_HTML = """
<nav class="navbar static-top">
  <a href="/">হোম</a>
  <a href="/latest">সর্বশেষ</a>
  <a href="/category/national/2">জাতীয়</a>
  <a href="/category/country/4">সারাদেশ</a>
  <a href="/video">ভিডিও</a>
</nav>
"""

_LISTING_HTML = """
<div class="category-list-item">
  <div class="row">
    <div class="col-sm-7">
      <h5><a href="/post/country/1056976">ঠাকুরগাঁওয়ে ডিজিটাল কৃষক কার্ড</a></h5>
      <p class="text-muted mb-0">প্রান্তিক কৃষকদের সঠিক তালিকা তৈরি।</p>
      <p class="text-muted small mb-0 mt-3">১ ঘণ্টা ২১ মিনিট আগে</p>
    </div>
    <div class="col-sm-5">
      <img src="/_next/image?url=https%3A%2F%2Ffile.dailynayadiganta.com%2Fimg.webp" />
    </div>
  </div>
</div>
"""

_ARTICLE_HTML = """
<meta property="og:image" content="https://file.dailynayadiganta.com/og.webp">
<h1 class="entry-title">সোনারগাঁওয়ে ট্রলারডুবি</h1>
<div class="pd-byline-row">
  <div class="pd-byline-left">
    <span>সোনারগাঁও (নারায়ণগঞ্জ) সংবাদদাতা</span>
    <time>প্রকাশ: ২৬ সেপ্টেম্বর ২০২৬, ১১: ৩২</time>
  </div>
</div>
<article class="pd-body">
  <p>নারায়ণগঞ্জের সোনারগাঁওয়ে দুর্ঘটনা ঘটেছে।</p>
  <p>উদ্ধারকারী দল ঘটনাস্থলে পৌঁছেছে।</p>
</article>
"""


def test_parse_sections_default_excludes_latest_and_video():
    assert parse_sections(_NAV_HTML) == [
        ("national/2", "জাতীয়"),
        ("country/4", "সারাদেশ"),
    ]


def test_parse_sections_include_all_is_a_no_op_for_non_category_nav_items():
    # "/latest" and "/video" aren't "/category/<slug>" links at all (a
    # different URL shape entirely, unlike dhakatribune's curated allow/
    # deny list over one shared shape), so include_all changes nothing here
    # - same documented no-op as jugantor's parse_sections.
    assert parse_sections(_NAV_HTML) == parse_sections(_NAV_HTML, include_all=True)


def test_parse_articles_reads_headline_summary_relative_time_and_thumbnail():
    articles = parse_articles(_LISTING_HTML)
    assert articles == [
        {
            "url": "https://www.dailynayadiganta.com/post/country/1056976",
            "headline": "ঠাকুরগাঁওয়ে ডিজিটাল কৃষক কার্ড",
            "summary": "প্রান্তিক কৃষকদের সঠিক তালিকা তৈরি।",
            "listing_time": "১ ঘণ্টা ২১ মিনিট আগে",
            "thumbnail": "https://www.dailynayadiganta.com/_next/image?url=https%3A%2F%2Ffile.dailynayadiganta.com%2Fimg.webp",
        }
    ]


def test_parse_article_reads_headline_byline_and_body():
    detail = parse_article(_ARTICLE_HTML, "https://www.dailynayadiganta.com/post/country/1056421")
    assert detail["headline"] == "সোনারগাঁওয়ে ট্রলারডুবি"
    assert detail["author"] == "সোনারগাঁও (নারায়ণগঞ্জ) সংবাদদাতা"
    assert detail["date_published"] == "প্রকাশ: ২৬ সেপ্টেম্বর ২০২৬, ১১: ৩২"
    assert detail["image_url"] == "https://file.dailynayadiganta.com/og.webp"
    assert detail["paragraphs"] == [
        "নারায়ণগঞ্জের সোনারগাঁওয়ে দুর্ঘটনা ঘটেছে।",
        "উদ্ধারকারী দল ঘটনাস্থলে পৌঁছেছে।",
    ]
