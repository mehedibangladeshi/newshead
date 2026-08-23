from scraper.sources.dhakatribune import parse_sections

_HTML = """
<div id="main_menu">
  <a href="https://www.dhakatribune.com/world">World</a>
  <a href="https://www.dhakatribune.com/magazine">Magazine</a>
</div>
"""


def test_parse_sections_default_applies_core_allowlist():
    assert parse_sections(_HTML) == [("world", "World")]


def test_parse_sections_include_all_bypasses_allowlist():
    assert parse_sections(_HTML, include_all=True) == [
        ("world", "World"),
        ("magazine", "Magazine"),
    ]
