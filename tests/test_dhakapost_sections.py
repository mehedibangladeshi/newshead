from scraper.sources.dhakapost import parse_article, parse_articles, parse_sections

_NAV_HTML = """
<nav class="top-nav">
  <a href="">Home</a>
  <a href="./national">National</a>
  <a href="./world">World</a>
  <a href="#">More</a>
  <a href="./entertainment">Entertainment</a>
</nav>
"""


def test_parse_sections_skips_home_and_more_dropdown_toggle():
    assert parse_sections(_NAV_HTML) == [
        ("national", "National"),
        ("world", "World"),
        ("entertainment", "Entertainment"),
    ]


def test_parse_sections_include_all_is_same_as_default():
    # No EXCLUDED_SECTION_SLUGS exist for this source yet, so include_all
    # currently makes no difference - this pins that down.
    assert parse_sections(_NAV_HTML, include_all=True) == parse_sections(_NAV_HTML)


_LISTING_HTML = """
<div class="col-md-12 p_left p_right n_post">
  <div class="col-xs-4 p_left p_right">
    <img alt="Electricity from Nepal" class="img-responsive" src="./assets/news_images/2024/11/16/mob/nepal-electricity.jpg">
  </div>
  <div class="col-xs-8">
    <h1><a href="national/2024/11/16/2770">Electricity from Nepal to reach Bangladesh via Indian grid</a></h1>
    <span>16 November, 2024 10:44 am</span>
    <article class="hidden-xs hidden-sm">
      <p>Electricity generated in Nepal will now reach Bangladesh via the Indian grid&#8230;</p>
    </article>
  </div>
</div>
"""


def test_parse_articles_reads_card_fields():
    articles = parse_articles(_LISTING_HTML)
    assert len(articles) == 1
    article = articles[0]
    assert article["url"] == "https://www.thedhakapost.com/national/2024/11/16/2770"
    assert article["headline"] == "Electricity from Nepal to reach Bangladesh via Indian grid"
    assert article["summary"].startswith("Electricity generated in Nepal")
    assert article["listing_time"] == "16 November, 2024 10:44 am"
    assert article["thumbnail"] == (
        "https://www.thedhakapost.com/assets/news_images/2024/11/16/mob/nepal-electricity.jpg"
    )


def test_parse_articles_skips_cards_without_a_headline_link():
    assert parse_articles('<div class="n_post"><span>no headline here</span></div>') == []


# Modeled on the real article-page DOM (Dhaka Post carries no ld+json
# NewsArticle block, only Organization, so fetch_article hand-parses the
# DOM instead of going through ld_json.select_by_type()).
_ARTICLE_HTML = """
<div class="main_section details">
  <div class="col-md-12">
    <span id="news_update_time">Update : 16 November, 2024 10:44 am</span>
  </div>
  <div class="col-md-12"><h1>Electricity from Nepal to reach Bangladesh via Indian grid</h1></div>
  <div class="col-md-12" id="rpt">UNB</div>
  <div class="col-md-12">
    <img alt="cover" class="details_img" src="./assets/news_images/2024/11/16/nepal-electricity.jpg">
  </div>
  <div class="col-md-12 details_view" style="text-align: justify">
    <p>Electricity generated in Nepal will now reach Bangladesh via the Indian grid.</p>
    <div style="margin: 10px 0"><script>(adsbygoogle = window.adsbygoogle || []).push({});</script></div>
    <p>A second paragraph of real prose.</p>
  </div>
</div>
"""


def test_parse_article_reads_headline_author_date_image_and_paragraphs():
    article = parse_article(_ARTICLE_HTML, "https://www.thedhakapost.com/national/2024/11/16/2770")
    assert article["url"] == "https://www.thedhakapost.com/national/2024/11/16/2770"
    assert article["headline"] == "Electricity from Nepal to reach Bangladesh via Indian grid"
    assert article["author"] == "UNB"
    assert article["date_published"] == "16 November, 2024 10:44 am"
    assert article["image_url"] == "https://www.thedhakapost.com/assets/news_images/2024/11/16/nepal-electricity.jpg"
    assert article["paragraphs"] == [
        "Electricity generated in Nepal will now reach Bangladesh via the Indian grid.",
        "A second paragraph of real prose.",
    ]
