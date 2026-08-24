"""Normalize each source's raw listing-time signal into a publishedAt
instant.

Every source module's list_articles() already captures a raw per-article
time signal into item["listing_time"] (see scraper/sources/*.py) — this
module is the one place that knows how to turn each source's particular
raw shape into a real, timezone-aware datetime, or None if it can't be
parsed confidently. Never guess: an unparseable value returns None rather
than a wrong instant.
"""
import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from . import bengali_date

DHAKA_TZ = ZoneInfo("Asia/Dhaka")

_BN_TO_ASCII_DIGITS = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")
_BN_MONTH_TO_NUM = {name: num for num, name in bengali_date.MONTH_NAMES.items()}

_BENGALI_ABSOLUTE_RE = re.compile(
    r"(?P<day>[০-৯]{1,2})\s+(?P<month>\S+)\s+(?P<year>[০-৯]{4}),\s*"
    r"(?P<hour>[০-৯]{1,2}):(?P<minute>[০-৯]{2})\s*(?P<ampm>\S+)"
)

# Matches both "2 hours ago" (the generic phrase this was first written
# against) and thedailystar.net's actual live markup, confirmed by fetching
# it directly: "1 MIN(s)", "5 HOUR(s)" — an abbreviated unit, an optional
# literal "(s)" plural marker, and no "ago" suffix at all.
_RELATIVE_ENGLISH_RE = re.compile(
    r"(?P<n>\d+)\s*(?P<unit>sec|min|hour|day|week|month|year)[a-z]*"
    r"\s*(?:\(s\))?\s*(?:ago)?",
    re.IGNORECASE,
)

_UNIT_SECONDS = {
    "sec": 1,
    "min": 60,
    "hour": 3600,
    "day": 86400,
    "week": 604800,
    "month": 2592000,
    "year": 31536000,
}

# tbsnews.net's /latest cards use a single-letter abbreviated relative time
# with no space and no "ago", e.g. "6m", "1h", "1d" - distinct enough from
# _RELATIVE_ENGLISH_RE's word-unit phrases to need its own regex. Case-
# sensitive on purpose: the site only ever emits lowercase s/m/h/d, and
# case-folding "M" into "m" (minutes) would be a silent bug if a month/
# capitalized unit ever showed up.
_RELATIVE_ABBREV_RE = re.compile(r"^(?P<n>\d+)(?P<unit>[smhd])$")

_UNIT_ABBREV_SECONDS = {"s": 1, "m": 60, "h": 3600, "d": 86400}

# samakal.com's listing cards use a Bengali absolute datetime with no AM/PM
# marker, 24-hour clock, separated by a pipe, e.g.
# "২৩ আগস্ট ২০২৬ | ২২:৫০" ("23 August 2026 | 22:50") - unlike jugantor's
# 12-hour + এএম/পিএম format, so it needs its own regex/parser.
_BENGALI_ABSOLUTE_24H_RE = re.compile(
    r"(?P<day>[০-৯]{1,2})\s+(?P<month>\S+)\s+(?P<year>[০-৯]{4})\s*\|\s*"
    r"(?P<hour>[০-৯]{1,2}):(?P<minute>[০-৯]{2})"
)


def _parse_iso_offset(raw):
    """dhakatribune / ittefaq: an ISO-8601 string with a UTC offset already
    attached, e.g. "2026-08-23T12:58:59+06:00"."""
    if not raw or not isinstance(raw, str):
        return None
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return None


def _parse_epoch_ms(raw):
    """prothomalo: a Quintype CMS `published-at` epoch-millisecond int."""
    if not isinstance(raw, (int, float)):
        return None
    try:
        return datetime.fromtimestamp(raw / 1000, tz=DHAKA_TZ)
    except (OverflowError, OSError, ValueError):
        return None


def _parse_bengali_absolute(raw):
    """jugantor: a full Bengali-language absolute datetime, e.g.
    "২৩ আগস্ট ২০২৬, ০৫:২১ এএম" ("23 August 2026, 05:21 AM")."""
    if not raw or not isinstance(raw, str):
        return None
    match = _BENGALI_ABSOLUTE_RE.search(raw)
    if not match:
        return None
    month = _BN_MONTH_TO_NUM.get(match.group("month"))
    if month is None:
        return None
    day = int(match.group("day").translate(_BN_TO_ASCII_DIGITS))
    year = int(match.group("year").translate(_BN_TO_ASCII_DIGITS))
    hour = int(match.group("hour").translate(_BN_TO_ASCII_DIGITS))
    minute = int(match.group("minute").translate(_BN_TO_ASCII_DIGITS))
    ampm = match.group("ampm")
    if ampm.startswith("প"):  # পিএম = PM
        if hour != 12:
            hour += 12
    elif ampm.startswith("এ"):  # এএম = AM
        if hour == 12:
            hour = 0
    else:
        return None
    try:
        return datetime(year, month, day, hour, minute, tzinfo=DHAKA_TZ)
    except ValueError:
        return None


def _parse_relative_english(raw, anchor):
    """dailystar: a relative phrase off the page's own listing card, e.g.
    "2 hours ago". anchor is the scrape run's own start time — the result
    is necessarily approximate, rounded to whatever granularity the site's
    own listing already used."""
    if not raw or not isinstance(raw, str) or anchor is None:
        return None
    text = raw.strip().lower()
    if text in ("just now", "moments ago"):
        return anchor
    if text == "yesterday":
        return anchor - timedelta(days=1)
    match = _RELATIVE_ENGLISH_RE.search(text)
    if not match:
        return None
    n = int(match.group("n"))
    unit = match.group("unit").lower()
    return anchor - timedelta(seconds=n * _UNIT_SECONDS[unit])


def _parse_relative_abbrev(raw, anchor):
    """tbsnews: a single-letter abbreviated relative time off /latest's own
    card, e.g. "6m", "1h", "1d". anchor is the scrape run's own start time -
    the result is necessarily approximate, rounded to whatever granularity
    the site's own listing already used."""
    if not raw or not isinstance(raw, str) or anchor is None:
        return None
    match = _RELATIVE_ABBREV_RE.match(raw.strip())
    if not match:
        return None
    n = int(match.group("n"))
    unit = match.group("unit").lower()
    try:
        return anchor - timedelta(seconds=n * _UNIT_ABBREV_SECONDS[unit])
    except OverflowError:
        return None


def _parse_bengali_absolute_24h(raw):
    """samakal: a Bengali absolute datetime with no AM/PM marker, e.g.
    "২৩ আগস্ট ২০২৬ | ২২:৫০"."""
    if not raw or not isinstance(raw, str):
        return None
    match = _BENGALI_ABSOLUTE_24H_RE.search(raw)
    if not match:
        return None
    month = _BN_MONTH_TO_NUM.get(match.group("month"))
    if month is None:
        return None
    day = int(match.group("day").translate(_BN_TO_ASCII_DIGITS))
    year = int(match.group("year").translate(_BN_TO_ASCII_DIGITS))
    hour = int(match.group("hour").translate(_BN_TO_ASCII_DIGITS))
    minute = int(match.group("minute").translate(_BN_TO_ASCII_DIGITS))
    try:
        return datetime(year, month, day, hour, minute, tzinfo=DHAKA_TZ)
    except ValueError:
        return None


_SOURCE_PARSERS = {
    "dhakatribune": lambda raw, anchor: _parse_iso_offset(raw),
    "ittefaq": lambda raw, anchor: _parse_iso_offset(raw),
    "prothomalo": lambda raw, anchor: _parse_epoch_ms(raw),
    "jugantor": lambda raw, anchor: _parse_bengali_absolute(raw),
    "dailystar": lambda raw, anchor: _parse_relative_english(raw, anchor),
    "banglatribune": lambda raw, anchor: _parse_iso_offset(raw),
    "tbsnews": lambda raw, anchor: _parse_relative_abbrev(raw, anchor),
    "samakal": lambda raw, anchor: _parse_bengali_absolute_24h(raw),
}


def parse_published_at(source_slug, raw, run_started_at):
    """Returns an ISO-8601 string (with UTC offset) for the given source's
    raw listing-time signal, or None if it's missing/unparseable. Never
    raises — an unrecognized shape is exactly the case this returns None
    for."""
    parser = _SOURCE_PARSERS.get(source_slug)
    if parser is None:
        return None
    result = parser(raw, run_started_at)
    return result.isoformat() if result is not None else None
