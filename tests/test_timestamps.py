from datetime import datetime
from zoneinfo import ZoneInfo

from scraper.timestamps import parse_published_at

DHAKA_TZ = ZoneInfo("Asia/Dhaka")


def test_parse_published_at_dhakatribune_iso_offset():
    result = parse_published_at("dhakatribune", "2026-08-23T12:58:59+06:00", None)
    assert result == "2026-08-23T12:58:59+06:00"


def test_parse_published_at_ittefaq_iso_offset():
    result = parse_published_at("ittefaq", "2026-08-23T14:45:30+06:00", None)
    assert result == "2026-08-23T14:45:30+06:00"


def test_parse_published_at_dhakatribune_returns_none_for_garbage():
    assert parse_published_at("dhakatribune", "not a date", None) is None


def test_parse_published_at_dhakatribune_returns_none_for_missing_value():
    assert parse_published_at("dhakatribune", "", None) is None
    assert parse_published_at("dhakatribune", None, None) is None


def test_parse_published_at_prothomalo_epoch_ms():
    # epoch_ms=0 is 1970-01-01T00:00:00Z, i.e. 06:00 in Asia/Dhaka (UTC+6).
    assert parse_published_at("prothomalo", 0, None) == "1970-01-01T06:00:00+06:00"


def test_parse_published_at_prothomalo_returns_none_for_non_numeric():
    assert parse_published_at("prothomalo", "not-a-number", None) is None
    assert parse_published_at("prothomalo", None, None) is None


def test_parse_published_at_jugantor_bengali_am():
    result = parse_published_at("jugantor", "২৩ আগস্ট ২০২৬, ০৫:২১ এএম", None)
    parsed = datetime.fromisoformat(result)
    assert (parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute) == (
        2026,
        8,
        23,
        5,
        21,
    )


def test_parse_published_at_jugantor_bengali_pm():
    result = parse_published_at("jugantor", "২৩ আগস্ট ২০২৬, ০৫:২১ পিএম", None)
    parsed = datetime.fromisoformat(result)
    assert parsed.hour == 17


def test_parse_published_at_jugantor_bengali_12am_is_midnight():
    result = parse_published_at("jugantor", "০১ জানুয়ারি ২০২৬, ১২:০০ এএম", None)
    parsed = datetime.fromisoformat(result)
    assert parsed.hour == 0


def test_parse_published_at_jugantor_returns_none_for_unrecognized_text():
    assert parse_published_at("jugantor", "unknown format", None) is None
    assert parse_published_at("jugantor", "", None) is None


def test_parse_published_at_jugantor_returns_none_for_unrecognized_ampm():
    assert parse_published_at("jugantor", "২৩ আগস্ট ২০২৬, ০৫:২১ অজানা", None) is None


def test_parse_published_at_dailystar_hours_ago():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "2 hours ago", anchor) == "2026-08-23T12:00:00+06:00"


def test_parse_published_at_dailystar_minutes_ago():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "45 minutes ago", anchor) == "2026-08-23T13:15:00+06:00"


def test_parse_published_at_dailystar_yesterday():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "Yesterday", anchor) == "2026-08-22T14:00:00+06:00"


def test_parse_published_at_dailystar_just_now():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "Just now", anchor) == "2026-08-23T14:00:00+06:00"


def test_parse_published_at_dailystar_returns_none_without_an_anchor():
    assert parse_published_at("dailystar", "2 hours ago", None) is None


def test_parse_published_at_dailystar_returns_none_for_unrecognized_text():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    assert parse_published_at("dailystar", "sometime", anchor) is None


def test_parse_published_at_returns_none_for_an_unknown_source():
    assert parse_published_at("madeup", "2026-08-23T12:00:00+06:00", None) is None
