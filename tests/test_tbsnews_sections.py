from scraper.sources.tbsnews import parse_latest

_HTML = """
<div class="card">
  <div class="card-title"><a href="https://www.tbsnews.net/bangladesh/one">Headline One</a></div>
  <div class="card-intro">Summary one</div>
  <div class="date">6m</div>
</div>
<div class="card">
  <div class="card-title"><a href="https://www.tbsnews.net/videos/two">Video headline</a></div>
  <div class="card-intro">Summary two</div>
  <div class="date">1h</div>
</div>
"""


def test_parse_latest_default_excludes_video_hub():
    grouped = parse_latest(_HTML)
    assert list(grouped.keys()) == ["bangladesh"]


def test_parse_latest_include_all_keeps_video_hub():
    grouped = parse_latest(_HTML, include_all=True)
    assert set(grouped.keys()) == {"bangladesh", "videos"}


def test_parse_latest_reads_data_src_thumbnail_and_listing_time():
    html = """
    <div class="card">
      <div class="card-title"><a href="https://www.tbsnews.net/sports/one">Headline</a></div>
      <img src="placeholder.png" data-src="https://www.tbsnews.net/real.jpg">
      <div class="date">1d</div>
    </div>
    """
    grouped = parse_latest(html)
    article = grouped["sports"][0]
    assert article["thumbnail"] == "https://www.tbsnews.net/real.jpg"
    assert article["listing_time"] == "1d"
