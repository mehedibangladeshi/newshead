from scraper.sources.dailystar import parse_todays_news

_HTML = """
<div class="views-row">
  <div class="card-title"><a href="https://www.thedailystar.net/news/one">Headline One</a></div>
  <div class="card-intro">Summary one</div>
  <div class="card-info">2 hours ago</div>
</div>
<div class="views-row">
  <div class="card-title"><a href="https://www.thedailystar.net/star-multimedia/two">Video headline</a></div>
  <div class="card-intro">Summary two</div>
  <div class="card-info">3 hours ago</div>
</div>
"""


def test_parse_todays_news_default_excludes_video_hub():
    grouped = parse_todays_news(_HTML)
    assert list(grouped.keys()) == ["news"]


def test_parse_todays_news_include_all_keeps_video_hub():
    grouped = parse_todays_news(_HTML, include_all=True)
    assert set(grouped.keys()) == {"news", "star-multimedia"}
