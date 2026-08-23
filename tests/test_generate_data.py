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
    assert classify_category("Stock market surges on trade deal", "Business") == "finance"
    assert classify_category("UN summit opens in Geneva", "World") == "world"
    assert classify_category("Dhaka city council approves budget", "City") == "bangladesh"


def test_classify_category_matches_bengali_keywords():
    assert classify_category("রাজনীতি নিয়ে বিতর্ক", "রাজনীতি") == "politics"
    assert classify_category("ক্রিকেট দল ঘোষণা", "খেলা") == "sports"


def test_classify_category_returns_none_when_no_keyword_matches():
    assert classify_category("A completely unrelated headline about weather", "Opinion") is None


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
    result = classify_article_category("testsource", "unmapped-section", "Opinion", "A completely unrelated headline")
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
