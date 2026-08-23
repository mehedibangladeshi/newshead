from scraper.sources.prothomalo import parse_sections

_HTML = """
<div id="navbar">
  <a href="https://www.prothomalo.com/bangladesh">বাংলাদেশ</a>
  <a href="https://www.prothomalo.com/video">ভিডিও</a>
</div>
"""


def test_parse_sections_default_applies_denylist():
    assert parse_sections(_HTML) == [("bangladesh", "বাংলাদেশ")]


def test_parse_sections_include_all_bypasses_denylist():
    assert parse_sections(_HTML, include_all=True) == [
        ("bangladesh", "বাংলাদেশ"),
        ("video", "ভিডিও"),
    ]
