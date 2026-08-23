from scraper.sources.ittefaq import parse_sections

_HTML = """
<a href="https://www.ittefaq.com.bd/national">জাতীয়</a>
<a href="https://www.ittefaq.com.bd/jobs">চাকরি</a>
"""


def test_parse_sections_default_applies_core_allowlist():
    assert parse_sections(_HTML) == [("national", "জাতীয়")]


def test_parse_sections_include_all_bypasses_allowlist():
    assert parse_sections(_HTML, include_all=True) == [
        ("national", "জাতীয়"),
        ("jobs", "চাকরি"),
    ]
