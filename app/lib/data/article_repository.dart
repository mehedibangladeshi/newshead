import 'dart:convert';

import '../models/news_article.dart';

List<NewsArticle> parseArticles(String jsonString) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final rawArticles = decoded['articles'] as List<dynamic>? ?? [];

  final articles = <NewsArticle>[];
  for (final raw in rawArticles) {
    try {
      final map = raw as Map<String, dynamic>;
      articles.add(NewsArticle(
        id: map['id'] as String,
        category: map['category'] as String,
        source: map['source'] as String,
        headline: map['headline'] as String,
        snippet: (map['snippet'] as String?) ?? '',
        imageUrl: map['imageUrl'] as String,
        articleUrl: map['articleUrl'] as String,
      ));
    } catch (_) {
      continue;
    }
  }
  return articles;
}

List<NewsArticle> articlesForCategory(List<NewsArticle> all, String category) {
  return all.where((a) => a.category == category).toList();
}
