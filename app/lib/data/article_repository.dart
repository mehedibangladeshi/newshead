import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_category.dart';
import '../models/filter_option.dart';
import '../models/news_article.dart';
import 'article_cache.dart';

const kDefaultCategories = [AppCategory(key: 'main', label: 'Main')];

List<AppCategory> parseCategories(String jsonString) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final rawCategories = decoded['categories'] as List<dynamic>?;
  if (rawCategories == null || rawCategories.isEmpty) return kDefaultCategories;

  final categories = <AppCategory>[];
  for (final raw in rawCategories) {
    try {
      final map = raw as Map<String, dynamic>;
      categories.add(AppCategory(
        key: map['key'] as String,
        label: map['label'] as String,
      ));
    } catch (_) {
      continue;
    }
  }
  return categories.isEmpty ? kDefaultCategories : categories;
}

List<FilterOption> _parseFilterOptions(String jsonString, String field) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final rawOptions = decoded[field] as List<dynamic>?;
  if (rawOptions == null) return const [];

  final options = <FilterOption>[];
  for (final raw in rawOptions) {
    try {
      final map = raw as Map<String, dynamic>;
      options.add(FilterOption(
        key: map['key'] as String,
        label: map['label'] as String,
      ));
    } catch (_) {
      continue;
    }
  }
  return options;
}

List<FilterOption> parseLanguages(String jsonString) => _parseFilterOptions(jsonString, 'languages');

List<FilterOption> parseSources(String jsonString) => _parseFilterOptions(jsonString, 'sources');

DateTime? _tryParsePublishedAt(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

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
        language: map['language'] is String ? map['language'] as String : 'en',
        publishedAt: _tryParsePublishedAt(map['publishedAt']),
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
  final List<AppCategory> categories;
  final List<FilterOption> languages;
  final List<FilterOption> sources;
  // The raw response/cache body this came from, so a later fetch can tell
  // whether the source actually returned new content.
  final String? rawBody;
  // True only when this result came from a fresh, successful network
  // response — false for cache fallback (network error/non-200) or empty.
  final bool fromNetwork;

  const ArticlesFetchResult({
    required this.articles,
    required this.categories,
    required this.languages,
    required this.sources,
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
    final response = await client.get(sourceUrl).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final articles = parseArticles(response.body);
      final categories = parseCategories(response.body);
      final languages = parseLanguages(response.body);
      final sources = parseSources(response.body);
      try {
        await cache.write(response.body);
      } catch (_) {
        // Best-effort cache write; a failure here shouldn't discard a
        // successful fetch that's already been parsed.
      }
      return ArticlesFetchResult(
        articles: articles,
        categories: categories,
        languages: languages,
        sources: sources,
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
        categories: parseCategories(cached),
        languages: parseLanguages(cached),
        sources: parseSources(cached),
        rawBody: cached,
        fromNetwork: false,
      );
    } catch (error) {
      debugPrint('fetchArticles: failed to parse cached articles: $error');
      return const ArticlesFetchResult(
        articles: [],
        categories: kDefaultCategories,
        languages: [],
        sources: [],
        rawBody: null,
        fromNetwork: false,
      );
    }
  }
  return const ArticlesFetchResult(
    articles: [],
    categories: kDefaultCategories,
    languages: [],
    sources: [],
    rawBody: null,
    fromNetwork: false,
  );
}
