from scraper.generate_data import (
    classify_category,
    make_article_id,
    truncate_snippet,
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
