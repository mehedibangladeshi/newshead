import '../models/app_category.dart';
import '../models/news_article.dart';

/// The one list that drives both the pill bar and the swipeable feed: a
/// fetched category is visible only if it has at least one article *and*
/// the reader hasn't excluded it. Always in the fetched list's own order.
List<AppCategory> visibleCategories({
  required List<AppCategory> fetchedCategories,
  required List<NewsArticle> articles,
  required Set<String> excludedKeys,
}) {
  final categoriesWithArticles = articles.map((a) => a.category).toSet();
  return fetchedCategories
      .where((c) => categoriesWithArticles.contains(c.key))
      .where((c) => !excludedKeys.contains(c.key))
      .toList();
}

/// Articles surviving the reader's Language and Source filters, independent
/// of and applied before the category filter — an article is hidden if
/// either its language or its source is excluded.
List<NewsArticle> visibleArticles({
  required List<NewsArticle> articles,
  required Set<String> excludedLanguageKeys,
  required Set<String> excludedSourceKeys,
}) {
  return articles
      .where((a) => !excludedLanguageKeys.contains(a.language))
      .where((a) => !excludedSourceKeys.contains(a.source))
      .toList();
}
