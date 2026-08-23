from scripts.discover_sections import render_report


def test_render_report_lists_every_section_grouped_by_source():
    results = {
        "jugantor": [("tp-sports", "খেলা"), ("tp-city", "নগর-মহানগর")],
        "prothomalo": [("bangladesh", "বাংলাদেশ")],
    }
    report = render_report(results)
    assert "## jugantor (2 sections)" in report
    assert "- `tp-sports` — খেলা" in report
    assert "- `tp-city` — নগর-মহানগর" in report
    assert "## prothomalo (1 sections)" in report
    assert "- `bangladesh` — বাংলাদেশ" in report


def test_render_report_handles_a_source_with_no_sections():
    report = render_report({"dailystar": []})
    assert "## dailystar (0 sections)" in report
