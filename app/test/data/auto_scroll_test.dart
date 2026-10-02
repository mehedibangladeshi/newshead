import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/auto_scroll.dart';
import 'package:newshead/models/news_article.dart';
import 'package:shared_preferences/shared_preferences.dart';

NewsArticle _a(int words, {String language = 'en'}) => NewsArticle(
  id: 'x', category: 'main', source: 's',
  headline: List.filled(words, 'w').join(' '), snippet: '',
  imageUrl: '', articleUrl: '', language: language,
);

void main() {
  test('short English article clamps to 6s', () {
    expect(dwellFor(_a(2)), const Duration(seconds: 6));
  });

  test('30-word English article is 12s', () {
    expect(dwellFor(_a(30)), const Duration(seconds: 12));
  });

  test('long Bengali article clamps to 20s', () {
    expect(dwellFor(_a(60, language: 'bn')), const Duration(seconds: 20));
  });

  test('Bengali dwells longer than English for the same words', () {
    expect(dwellFor(_a(20, language: 'bn')), greaterThan(dwellFor(_a(20))));
  });

  test('store defaults to false and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesAutoScrollStore();
    expect(await store.readEnabled(), false);
    await store.writeEnabled(true);
    expect(await store.readEnabled(), true);
  });
}
