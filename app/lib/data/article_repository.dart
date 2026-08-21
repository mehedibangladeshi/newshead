import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/news_article.dart';
import 'article_cache.dart';

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

Future<List<NewsArticle>> fetchArticles({
  required Uri sourceUrl,
  required http.Client client,
  required ArticleCache cache,
}) async {
  try {
    final response = await client.get(sourceUrl);
    if (response.statusCode == 200) {
      await cache.write(response.body);
      return parseArticles(response.body);
    }
  } catch (_) {
    // Fall through to the cache below.
  }

  final cached = await cache.read();
  if (cached != null) {
    return parseArticles(cached);
  }
  return [];
}
