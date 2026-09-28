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

/// Distinct source names present in the currently fetched articles, minus
/// excluded ones. Order follows first appearance in `fetchedArticles`.
List<String> visibleSources({
  required List<NewsArticle> fetchedArticles,
  required Set<String> excludedKeys,
}) {
  final sources = <String>[];
  for (final article in fetchedArticles) {
    if (!sources.contains(article.source)) sources.add(article.source);
  }
  return sources.where((s) => !excludedKeys.contains(s)).toList();
}

/// Distinct language codes present in the currently fetched articles, minus
/// excluded ones. Order follows first appearance in `fetchedArticles`.
/// Display labels ("English"/"Bangla") are a UI-layer concern, not this
/// pure data layer's.
List<String> visibleLanguages({
  required List<NewsArticle> fetchedArticles,
  required Set<String> excludedKeys,
}) {
  final languages = <String>[];
  for (final article in fetchedArticles) {
    if (!languages.contains(article.language)) languages.add(article.language);
  }
  return languages.where((l) => !excludedKeys.contains(l)).toList();
}
