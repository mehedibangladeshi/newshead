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

# bdnews24.com's /archive listing cards prefix an English absolute datetime
# with a static "Published : " label, e.g.
# "Published : 24 Aug 2026, 11:55 PM" - a fixed 12-hour clock, no UTC offset
# (implicitly Bangladesh local time, like every other source here).
_BDNEWS24_PUBLISHED_RE = re.compile(
    r"(?P<day>\d{1,2})\s+(?P<month>[A-Za-z]{3,})\s+(?P<year>\d{4}),\s*"
    r"(?P<hour>\d{1,2}):(?P<minute>\d{2})\s*(?P<ampm>[AaPp][Mm])"
)

_MONTH_ABBREV_TO_NUM = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

# thedhakapost.com's listing/article-page datetimes are an English absolute
# "<day> <full month>, <year> <hour>:<minute> <am/pm>", e.g.
# "16 November, 2024 10:44 am" - but confirmed live to sometimes pair an
# already-24-hour hour with a spurious am/pm suffix, e.g.
# "3 November, 2024 15:00 pm". The regex below captures the hour as written
# and _parse_dhakapost_absolute() only applies the am/pm adjustment when the
# hour is still in 12-hour range, so a genuine 24-hour value like 15 is left
# alone regardless of the trailing am/pm text.
DHAKAPOST_ABSOLUTE_RE = re.compile(
    r"(?P<day>\d{1,2})\s+(?P<month>[A-Za-z]+),\s*(?P<year>\d{4})\s+"
    r"(?P<hour>\d{1,2}):(?P<minute>\d{2})\s*(?P<ampm>[AaPp][Mm])"
)

# thedissent.news's listing cards show a date-only English string with no
# time component at all, e.g. "24 September 2026" - confirmed live.
_ENGLISH_DATE_ONLY_RE = re.compile(
    r"^(?P<day>\d{1,2})\s+(?P<month>[A-Za-z]+)\s+(?P<year>\d{4})$"
)

# nayadiganta.com's and kalerkantho.com's listing/article pages both use a
# Bengali absolute datetime, 24-hour, no AM/PM marker - but disagree on
# where the comma goes ("<day> <month> <year>, <hour>:<minute>" vs.
# "<day> <month>, <year> <hour>:<minute>", both confirmed live), so this
# regex tolerates a comma after either the month or the year (or neither),
# and optional whitespace around the hour:minute colon (nayadiganta's own
# article-page format was seen with a stray space there).
_BENGALI_ABSOLUTE_24H_FLEXIBLE_RE = re.compile(
    r"(?P<day>[০-৯]{1,2})\s+(?P<month>[^\s,]+),?\s+(?P<year>[০-৯]{4}),?\s*"
    r"(?P<hour>[০-৯]{1,2})\s*:\s*(?P<minute>[০-৯]{2})"
)

# nayadiganta.com's listing cards show a Bengali relative phrase, combining
# up to two units, e.g. "১ ঘণ্টা ২১ মিনিট আগে" ("1 hour 21 minutes ago") or
# a single unit alone, e.g. "৫১ মিনিট আগে" ("51 minutes ago") - confirmed
# live.
_BENGALI_RELATIVE_UNIT_RE = re.compile(r"([০-৯]+)\s*(ঘণ্টা|মিনিট|দিন|সেকেন্ড|সপ্তাহ|মাস|বছর)")

_BENGALI_UNIT_SECONDS = {
    "সেকেন্ড": 1,
    "মিনিট": 60,
    "ঘণ্টা": 3600,
    "দিন": 86400,
    "সপ্তাহ": 604800,
    "মাস": 2592000,
    "বছর": 31536000,
}


def _parse_iso_offset(raw):
    """dhakatribune / ittefaq / dailywaadaa: an ISO-8601 string with a UTC
    offset already attached, e.g. "2026-08-23T12:58:59+06:00". netranews's
    date-only ISO strings (e.g. "2026-09-27", no time or offset at all) are
    also routed through this parser - fromisoformat leaves those naive, so
    they're localized to Dhaka time rather than left ambiguous."""
    if not raw or not isinstance(raw, str):
        return None
    try:
        result = datetime.fromisoformat(raw)
    except ValueError:
        return None
    return result if result.tzinfo is not None else result.replace(tzinfo=DHAKA_TZ)


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


def _parse_bdnews24_published(raw):
    """bdnews24.com: "Published : 24 Aug 2026, 11:55 PM" - English absolute
    datetime, 12-hour clock, static "Published : " prefix."""
    if not raw or not isinstance(raw, str):
        return None
    match = _BDNEWS24_PUBLISHED_RE.search(raw)
    if not match:
        return None
    month = _MONTH_ABBREV_TO_NUM.get(match.group("month")[:3].lower())
    if month is None:
        return None
    day = int(match.group("day"))
    year = int(match.group("year"))
    hour = int(match.group("hour"))
    minute = int(match.group("minute"))
    ampm = match.group("ampm").lower()
    if ampm == "pm" and hour != 12:
        hour += 12
    elif ampm == "am" and hour == 12:
        hour = 0
    try:
        return datetime(year, month, day, hour, minute, tzinfo=DHAKA_TZ)
    except ValueError:
        return None


def _parse_dhakapost_absolute(raw):
    """thedhakapost.com: "16 November, 2024 10:44 am" - but confirmed live
    to sometimes carry an already-24-hour hour with a spurious am/pm suffix
    (e.g. "3 November, 2024 15:00 pm"), so the am/pm adjustment is only
    applied when the hour is still ambiguous (1-12)."""
    if not raw or not isinstance(raw, str):
        return None
    match = DHAKAPOST_ABSOLUTE_RE.search(raw)
    if not match:
        return None
    try:
        month = datetime.strptime(match.group("month")[:3], "%b").month
    except ValueError:
        return None
    day = int(match.group("day"))
    year = int(match.group("year"))
    hour = int(match.group("hour"))
    minute = int(match.group("minute"))
    ampm = match.group("ampm").lower()
    if 1 <= hour <= 12:
        if ampm == "pm" and hour != 12:
            hour += 12
        elif ampm == "am" and hour == 12:
            hour = 0
    try:
        return datetime(year, month, day, hour, minute, tzinfo=DHAKA_TZ)
    except ValueError:
        return None


def _parse_english_date_only(raw):
    """thedissent.news: a date-only English string with no time, e.g.
    "24 September 2026" - the result is midnight Dhaka time, the best
    precision this source's listing actually offers."""
    if not raw or not isinstance(raw, str):
        return None
    match = _ENGLISH_DATE_ONLY_RE.match(raw.strip())
    if not match:
        return None
    try:
        month = datetime.strptime(match.group("month")[:3], "%b").month
    except ValueError:
        return None
    day = int(match.group("day"))
    year = int(match.group("year"))
    try:
        return datetime(year, month, day, tzinfo=DHAKA_TZ)
    except ValueError:
        return None


def _parse_bengali_absolute_24h_flexible(raw):
    """nayadiganta / kalerkantho: a Bengali absolute datetime, 24-hour, no
    AM/PM marker, comma placement varying by page - see
    _BENGALI_ABSOLUTE_24H_FLEXIBLE_RE."""
    if not raw or not isinstance(raw, str):
        return None
    match = _BENGALI_ABSOLUTE_24H_FLEXIBLE_RE.search(raw)
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


def _parse_bengali_relative(raw, anchor):
    """nayadiganta: a Bengali relative phrase off the listing card's own
    "ago" text, e.g. "১ ঘণ্টা ২১ মিনিট আগে". anchor is the scrape run's own
    start time - the result is necessarily approximate, rounded to
    whatever granularity the site's own listing already used."""
    if not raw or not isinstance(raw, str) or anchor is None:
        return None
    matches = _BENGALI_RELATIVE_UNIT_RE.findall(raw)
    if not matches:
        return None
    total_seconds = 0
    for n, unit in matches:
        total_seconds += int(n.translate(_BN_TO_ASCII_DIGITS)) * _BENGALI_UNIT_SECONDS[unit]
    return anchor - timedelta(seconds=total_seconds)


_ISO_OFFSET_SOURCES = ("dhakatribune", "ittefaq", "banglatribune", "dailywaadaa", "netranews")

_SOURCE_PARSERS = {
    **{name: (lambda raw, anchor: _parse_iso_offset(raw)) for name in _ISO_OFFSET_SOURCES},
    "prothomalo": lambda raw, anchor: _parse_epoch_ms(raw),
    "jugantor": lambda raw, anchor: _parse_bengali_absolute(raw),
    "dailystar": lambda raw, anchor: _parse_relative_english(raw, anchor),
    "tbsnews": lambda raw, anchor: _parse_relative_abbrev(raw, anchor),
    "samakal": lambda raw, anchor: _parse_bengali_absolute_24h(raw),
    "bdnews24": lambda raw, anchor: _parse_bdnews24_published(raw),
    "dhakapost": lambda raw, anchor: _parse_dhakapost_absolute(raw),
    "thedissent": lambda raw, anchor: _parse_english_date_only(raw),
    "nayadiganta": lambda raw, anchor: _parse_bengali_relative(raw, anchor),
    "kalerkantho": lambda raw, anchor: _parse_bengali_absolute_24h_flexible(raw),
    # bdnews24bangla's and financialexpress's listing cards carry no time
    # signal at all (confirmed live: always an empty string) - left
    # unregistered, which already returns None safely via the .get() below.
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
