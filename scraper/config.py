import os

import requests

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
REQUEST_TIMEOUT = 15
REQUEST_DELAY_SECONDS = 0.7

# Each entry is a module under scraper/sources/ exposing:
#   discover_sections() -> list[(slug, section_name)]
#   list_articles(slug, edition_date) -> list[dict]
#   fetch_article(url) -> dict
#   get_cover_logo_url() -> str
SOURCES = [
    "jugantor",
    "prothomalo",
    "dhakatribune",
    "dailystar",
    "ittefaq",
    "tbsnews",
    "banglatribune",
    "samakal",
]


def make_session():
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    return session
