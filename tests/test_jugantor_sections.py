from scraper.sources.jugantor import parse_sections

_HTML = """
<div class="desktopSubCategoryDiv">
  <a href="/tp-sports" aria-label="খেলা">খেলা</a>
  <a href="/tp-city" aria-label="নগর-মহানগর">নগর-মহানগর</a>
</div>
"""


def test_parse_sections_default_matches_include_all():
    # Jugantor has no curated allow/deny list — every "/tp-" link is already
    # "everything" — so include_all is a documented no-op here.
    assert parse_sections(_HTML) == parse_sections(_HTML, include_all=True)
    assert parse_sections(_HTML) == [
        ("tp-sports", "খেলা"),
        ("tp-city", "নগর-মহানগর"),
    ]
