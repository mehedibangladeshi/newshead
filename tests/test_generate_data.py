from scraper.generate_data import (
    classify_article_category,
    classify_category,
    make_article_id,
    truncate_snippet,
    SECTION_CATEGORY_MAP,
)


def test_classify_category_matches_english_keywords():
    assert classify_category("Government announces new cabinet", "News") == "politics"
    assert classify_category("Local team wins the football match", "Sports") == "sports"
    assert classify_category("Stock market surges on trade deal", "Business") == "business"
    assert classify_category("UN summit opens in Geneva", "World") == "world"
    assert classify_category("Dhaka city council approves budget", "City") == "city"


def test_classify_category_matches_bengali_keywords():
    assert classify_category("রাজনীতি নিয়ে বিতর্ক", "রাজনীতি") == "politics"
    assert classify_category("ক্রিকেট দল ঘোষণা", "খেলা") == "sports"


def test_classify_category_returns_none_when_no_keyword_matches():
    assert classify_category("A quiet Tuesday brought nothing newsworthy today", "Weekend Roundup") is None


def test_classify_category_checks_section_name_too():
    assert classify_category("Weekly roundup", "Sports") == "sports"


def test_truncate_snippet_leaves_short_text_untouched():
    assert truncate_snippet("Short summary.") == "Short summary."


def test_truncate_snippet_truncates_long_text_at_a_word_boundary():
    long_text = "word " * 50
    result = truncate_snippet(long_text, max_length=20)
    assert len(result) <= 21
    assert result.endswith("…")


def test_truncate_snippet_handles_empty_text():
    assert truncate_snippet("") == ""
    assert truncate_snippet(None) == ""


def test_make_article_id_is_stable_and_prefixed_with_source_slug():
    id1 = make_article_id("jugantor", "https://example.com/article")
    id2 = make_article_id("jugantor", "https://example.com/article")
    assert id1 == id2
    assert id1.startswith("jugantor-")


def test_make_article_id_differs_for_different_urls():
    id1 = make_article_id("jugantor", "https://example.com/a")
    id2 = make_article_id("jugantor", "https://example.com/b")
    assert id1 != id2


def test_classify_article_category_uses_explicit_mapping_when_present():
    SECTION_CATEGORY_MAP.setdefault("testsource", {})["tech"] = "technology"
    try:
        # Headline would keyword-match "sports" if the mapping weren't
        # checked first — explicit mapping must win outright.
        result = classify_article_category("testsource", "tech", "Tech", "Cricket team wins")
        assert result == "technology"
    finally:
        del SECTION_CATEGORY_MAP["testsource"]


def test_classify_article_category_falls_back_to_keywords_when_unmapped():
    result = classify_article_category("testsource", "unmapped-section", "Sports", "Local team wins the match")
    assert result == "sports"


def test_classify_article_category_returns_none_when_neither_matches():
    result = classify_article_category(
        "testsource", "unmapped-section", "Weekend Roundup",
        "A quiet Tuesday brought nothing newsworthy today",
    )
    assert result is None


from scraper.generate_data import interleave_by_source


def test_interleave_by_source_round_robins_without_a_cap():
    articles = (
        [{"category": "sports", "source": "A", "id": f"a{i}"} for i in range(5)]
        + [{"category": "sports", "source": "B", "id": f"b{i}"} for i in range(2)]
    )
    result = interleave_by_source(articles)
    ids = [a["id"] for a in result]
    # Round-robin across sources: A,B,A,B,A,A,A — every article kept, none
    # capped, but B's 2 articles aren't pushed to the back of the list.
    assert ids == ["a0", "b0", "a1", "b1", "a2", "a3", "a4"]
    assert len(result) == 7


def test_interleave_by_source_keeps_every_article_for_a_single_source():
    articles = [{"category": "main", "source": "A", "id": f"a{i}"} for i in range(20)]
    result = interleave_by_source(articles)
    assert len(result) == 20


from scraper.generate_data import (
    build_output,
    CATEGORY_DEFINITIONS,
    LANGUAGE_DISPLAY_NAMES,
    SOURCE_DISPLAY_NAMES,
)


def test_build_output_includes_ordered_category_definitions():
    output = build_output("2026-08-23", [])
    assert output["generated_at"] == "2026-08-23"
    assert output["categories"] == [
        {"key": key, "label": label} for key, label in CATEGORY_DEFINITIONS
    ]
    assert output["categories"][0]["key"] == "main"


def test_build_output_includes_alphabetically_sorted_languages():
    output = build_output("2026-08-23", [])
    assert output["languages"] == [
        {"key": "bn", "label": "Bangla"},
        {"key": "en", "label": "English"},
    ]


def test_build_output_includes_alphabetically_sorted_sources():
    output = build_output("2026-08-23", [])
    expected = sorted(
        ({"key": name, "label": name} for name in SOURCE_DISPLAY_NAMES.values()),
        key=lambda d: d["label"].casefold(),
    )
    assert output["sources"] == expected
    assert len(output["sources"]) == len(SOURCE_DISPLAY_NAMES)


def test_language_display_names_covers_every_language_used_by_a_source():
    from scraper.generate_data import SOURCE_LANGUAGE

    for language_code in SOURCE_LANGUAGE.values():
        assert language_code in LANGUAGE_DISPLAY_NAMES


def test_build_output_includes_the_given_articles():
    articles = [{"id": "a1", "category": "main"}]
    output = build_output("2026-08-23", articles)
    assert output["articles"] == articles


def test_category_definitions_has_16_categories_plus_main():
    assert len(CATEGORY_DEFINITIONS) == 17
    assert CATEGORY_DEFINITIONS[0] == ("main", "Main")


def test_classify_article_category_maps_new_sections_explicitly():
    # Two real (source, section) pairs per source from the finalized
    # SECTION_CATEGORY_MAP: one obvious, one less obvious.
    assert classify_article_category("jugantor", "tp-sports", "খেলা", "Some headline") == "sports"
    assert classify_article_category("jugantor", "tp-window", "Window", "Some headline") == "lifestyle"

    assert classify_article_category("prothomalo", "sports", "Sports", "Some headline") == "sports"
    assert classify_article_category("prothomalo", "lifestyle", "Lifestyle", "Some headline") == "lifestyle"

    assert classify_article_category("dhakatribune", "sport/cricket", "Cricket", "Some headline") == "sports"
    assert classify_article_category(
        "dhakatribune", "arts-and-letters/poetry", "Poetry", "Some headline"
    ) == "arts_literature"

    assert classify_article_category("dailystar", "sports", "Sports", "Some headline") == "sports"
    assert classify_article_category("dailystar", "ds", "DS", "Some headline") == "miscellaneous"

    assert classify_article_category("ittefaq", "sports", "খেলা", "Some headline") == "sports"
    assert classify_article_category("ittefaq", "probash", "প্রবাস", "Some headline") == "expat"


def test_classify_category_matches_new_category_keywords():
    # One assertion per new category added in Task 14, using headline text
    # that actually contains one of that category's chosen keywords.
    assert classify_category("Popular actor announces new film", "Entertainment") == "entertainment"
    assert classify_category("New fashion week begins downtown", "Lifestyle") == "lifestyle"
    assert classify_category("This editorial explains the issue", "Opinion") == "opinion"
    assert classify_category("New technology unveiled at expo", "Tech") == "tech"
    assert classify_category("New hospital opens downtown", "Health") == "health"
    assert classify_category("Local university announces new dean", "Education") == "education"
    assert classify_category("Community gathers for evening prayer service", "Religion") == "religion"
    assert classify_category("New poetry collection published this month", "Arts") == "arts_literature"
    assert classify_category("Remittance inflows rise this quarter", "Expat") == "expat"
    assert classify_category("Dhaka traffic causes delays downtown", "City") == "city"
    assert classify_category("Nationwide protests planned for next week", "Country") == "country"


def test_section_category_map_values_are_all_valid_category_keys():
    # A mistyped/removed category value in any source's SECTION_CATEGORY_MAP
    # silently vanishes from interleave_by_source's CATEGORIES + ["main"]
    # iteration with no error - this catches that regression cheaply.
    valid_keys = {key for key, _label in CATEGORY_DEFINITIONS}
    for source_slug, section_map in SECTION_CATEGORY_MAP.items():
        for section_slug, category in section_map.items():
            assert category in valid_keys, (
                f"{source_slug!r}[{section_slug!r}] maps to unknown category {category!r}"
            )


from datetime import datetime
from zoneinfo import ZoneInfo

from scraper.generate_data import build_article, SOURCE_LANGUAGE

DHAKA_TZ = ZoneInfo("Asia/Dhaka")


def test_build_article_includes_language_for_a_bengali_source():
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": ""}
    article = build_article("jugantor", "Jugantor", "main", item, "", None)
    assert article["language"] == "bn"


def test_build_article_includes_language_for_an_english_source():
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": ""}
    article = build_article("dailystar", "The Daily Star", "main", item, "", None)
    assert article["language"] == "en"


def test_source_language_covers_every_configured_source():
    from scraper import config

    for source_slug in config.SOURCES:
        assert source_slug in SOURCE_LANGUAGE


def test_build_article_includes_a_parsed_published_at():
    item = {
        "url": "https://example.com/a",
        "headline": "H",
        "summary": "S",
        "listing_time": "2026-08-23T12:58:59+06:00",
    }
    article = build_article("dhakatribune", "Dhaka Tribune", "main", item, "", None)
    assert article["publishedAt"] == "2026-08-23T12:58:59+06:00"


def test_build_article_leaves_published_at_none_when_unparseable():
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": ""}
    article = build_article("dhakatribune", "Dhaka Tribune", "main", item, "", None)
    assert article["publishedAt"] is None


def test_build_article_uses_run_started_at_to_anchor_dailystar_relative_time():
    anchor = datetime(2026, 8, 23, 14, 0, tzinfo=DHAKA_TZ)
    item = {"url": "https://example.com/a", "headline": "H", "summary": "S", "listing_time": "2 hours ago"}
    article = build_article("dailystar", "The Daily Star", "main", item, "", anchor)
    assert article["publishedAt"] == "2026-08-23T12:00:00+06:00"
