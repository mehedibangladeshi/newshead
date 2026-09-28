"""Shared headless-browser fetch, for sources whose Cloudflare (or similar)
protection blocks plain `requests` traffic with a JS challenge.

Reusable pattern: a source's `_get(url)` should try its normal `requests`
session first, and only fall back to `get_html()` here on failure, e.g.:

    def _get(url):
        time.sleep(config.REQUEST_DELAY_SECONDS)
        try:
            response = _session.get(url, timeout=config.REQUEST_TIMEOUT)
            response.raise_for_status()
            return response.text
        except requests.RequestException:
            return browser_client.get_html(url)

This keeps the fast path fast, auto-recovers if the block is lifted, and
only pays for a browser page load when it's actually needed.
"""

import atexit
import threading

from playwright.sync_api import sync_playwright

from . import config

_lock = threading.Lock()
_playwright = None
_browser = None


def _ensure_browser():
    global _playwright, _browser
    with _lock:
        if _browser is None:
            _playwright = sync_playwright().start()
            _browser = _playwright.chromium.launch(headless=True)
            atexit.register(_shutdown)
    return _browser


def _shutdown():
    global _playwright, _browser
    if _browser is not None:
        _browser.close()
        _browser = None
    if _playwright is not None:
        _playwright.stop()
        _playwright = None


def get_html(url, timeout_ms=30000, extra_wait_ms=0):
    browser = _ensure_browser()
    page = browser.new_page(user_agent=config.USER_AGENT)
    try:
        # "networkidle" never fires on ad-heavy news pages (trackers keep
        # polling); "domcontentloaded" is enough since these are
        # server-rendered pages, not client-side-rendered SPAs.
        page.goto(url, timeout=timeout_ms, wait_until="domcontentloaded")
        # kalerkantho.com's /online/<section> listing pages are the
        # exception: confirmed live to render an empty shell at
        # domcontentloaded and fetch their actual story cards client-side
        # afterwards (its own article pages don't have this problem - only
        # listing pages do). extra_wait_ms lets a source opt into a fixed
        # settle delay for cases like this instead of every source paying
        # for it.
        if extra_wait_ms:
            page.wait_for_timeout(extra_wait_ms)
        return page.content()
    finally:
        page.close()
