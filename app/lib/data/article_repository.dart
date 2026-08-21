import 'dart:convert';

import 'package:flutter/foundation.dart';
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

class ArticlesFetchResult {
  final List<NewsArticle> articles;
  // The raw response/cache body this came from, so a later fetch can tell
  // whether the source actually returned new content.
  final String? rawBody;
  // True only when this result came from a fresh, successful network
  // response — false for cache fallback (network error/non-200) or empty.
  final bool fromNetwork;

  const ArticlesFetchResult({
    required this.articles,
    required this.rawBody,
    required this.fromNetwork,
  });
}

Future<ArticlesFetchResult> fetchArticles({
  required Uri sourceUrl,
  required http.Client client,
  required ArticleCache cache,
}) async {
  try {
    final response = await client.get(sourceUrl);
    if (response.statusCode == 200) {
      final articles = parseArticles(response.body);
      try {
        await cache.write(response.body);
      } catch (_) {
        // Best-effort cache write; a failure here shouldn't discard a
        // successful fetch that's already been parsed.
      }
      return ArticlesFetchResult(
        articles: articles,
        rawBody: response.body,
        fromNetwork: true,
      );
    }
    debugPrint('fetchArticles: unexpected status ${response.statusCode} from $sourceUrl');
  } catch (error) {
    debugPrint('fetchArticles: network fetch of $sourceUrl failed: $error');
  }

  final cached = await cache.read();
  if (cached != null) {
    try {
      return ArticlesFetchResult(
        articles: parseArticles(cached),
        rawBody: cached,
        fromNetwork: false,
      );
    } catch (error) {
      debugPrint('fetchArticles: failed to parse cached articles: $error');
      return const ArticlesFetchResult(articles: [], rawBody: null, fromNetwork: false);
    }
  }
  return const ArticlesFetchResult(articles: [], rawBody: null, fromNetwork: false);
}
