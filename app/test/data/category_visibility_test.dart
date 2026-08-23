import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/category_visibility.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/news_article.dart';

const _categories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'politics', label: 'Politics'),
  AppCategory(key: 'sports', label: 'Sports'),
];

NewsArticle _articleIn(String category) => NewsArticle(
      id: 'id-$category',
      category: category,
      source: 'Test',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://example.com/i.jpg',
      articleUrl: 'https://example.com/a',
    );

void main() {
  test('keeps only categories that have at least one article', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('main'), _articleIn('politics')],
      excludedKeys: const {},
    );
    expect(result, [
      const AppCategory(key: 'main', label: 'Main'),
      const AppCategory(key: 'politics', label: 'Politics'),
    ]);
  });

  test('drops a category the reader has excluded even if it has articles', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('main'), _articleIn('politics')],
      excludedKeys: const {'politics'},
    );
    expect(result, [const AppCategory(key: 'main', label: 'Main')]);
  });

  test('preserves the fetched categories order, not article order', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('sports'), _articleIn('main'), _articleIn('politics')],
      excludedKeys: const {},
    );
    expect(result.map((c) => c.key), ['main', 'politics', 'sports']);
  });

  test('returns an empty list when every category is empty or excluded', () {
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: const [],
      excludedKeys: const {},
    );
    expect(result, isEmpty);
  });

  test('a category unknown to the excluded set defaults to visible', () {
    // Simulates a brand-new category the reader has never seen/excluded.
    final result = visibleCategories(
      fetchedCategories: _categories,
      articles: [_articleIn('main')],
      excludedKeys: const {'some-other-category-the-reader-excluded-earlier'},
    );
    expect(result, [const AppCategory(key: 'main', label: 'Main')]);
  });
}
