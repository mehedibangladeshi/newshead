from scraper import browser_client


def test_get_html_returns_rendered_content():
    html = browser_client.get_html("data:text/html,<html><body>ok</body></html>")
    assert "ok" in html
