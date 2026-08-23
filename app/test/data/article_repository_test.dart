import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/article_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:newshead/models/app_category.dart';

class InMemoryArticleCache implements ArticleCache {
  String? stored;
  InMemoryArticleCache([this.stored]);

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String contents) async => stored = contents;
}

/// A fake cache whose [write] always throws, used to verify that a cache
/// write failure doesn't discard an already-successful, already-parsed
/// network fetch.
class ThrowingWriteArticleCache implements ArticleCache {
  String? stored;
  ThrowingWriteArticleCache([this.stored]);

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String contents) async {
    throw Exception('disk full');
  }
}

const _validJson = '''
{
  "generated_at": "2026-08-20",
  "categories": [
    {"key": "main", "label": "Main"},
    {"key": "politics", "label": "Politics"},
    {"key": "sports", "label": "Sports"}
  ],
  "articles": [
    {"id": "a1", "category": "politics", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"},
    {"id": "a2", "category": "sports", "source": "Ittefaq", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2"}
  ]
}
''';

const _jsonWithoutCategories = '''
{
  "generated_at": "2026-08-20",
  "articles": [
    {"id": "a1", "category": "politics", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"}
  ]
}
''';

const _jsonWithMalformedEntry = '''
{
  "generated_at": "2026-08-20",
  "articles": [
    {"id": "a1", "category": "politics", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"},
    {"id": "bad", "category": "sports"}
  ]
}
''';

const _jsonWithTimestamps = '''
{
  "generated_at": "2026-08-20",
  "categories": [{"key": "main", "label": "Main"}],
  "articles": [
    {"id": "a1", "category": "main", "source": "Prothom Alo", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1", "language": "bn", "publishedAt": "2026-08-23T10:00:00+06:00"},
    {"id": "a2", "category": "main", "source": "The Daily Star", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2", "language": "en", "publishedAt": "not-a-timestamp"},
    {"id": "a3", "category": "main", "source": "The Daily Star", "headline": "H3", "snippet": "S3", "imageUrl": "https://example.com/3.jpg", "articleUrl": "https://example.com/a3"}
  ]
}
''';

const _jsonWithNonStringLanguage = '''
{
  "generated_at": "2026-08-20",
  "categories": [{"key": "main", "label": "Main"}],
  "articles": [
    {"id": "a1", "category": "main", "source": "Test Source", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1", "language": 123}
  ]
}
''';

void main() {
  test('parseArticles parses all fields correctly', () {
    final articles = parseArticles(_validJson);
    expect(articles.length, 2);
    expect(articles[0].id, 'a1');
    expect(articles[0].category, 'politics');
    expect(articles[0].source, 'Jugantor');
    expect(articles[0].headline, 'H1');
    expect(articles[0].snippet, 'S1');
    expect(articles[0].imageUrl, 'https://example.com/1.jpg');
    expect(articles[0].articleUrl, 'https://example.com/a1');
  });

  test('parseArticles skips a malformed entry instead of crashing', () {
    final articles = parseArticles(_jsonWithMalformedEntry);
    expect(articles.length, 1);
    expect(articles[0].id, 'a1');
  });

  test('articlesForCategory filters by category without mutating the input list', () {
    final all = parseArticles(_validJson);
    final before = all.length;
    final sports = articlesForCategory(all, 'sports');
    expect(sports.length, 1);
    expect(sports[0].id, 'a2');
    expect(all.length, before);
  });

  test('articlesForCategory returns an empty list for an unmatched category', () {
    final all = parseArticles(_validJson);
    expect(articlesForCategory(all, 'finance'), isEmpty);
  });

  test('fetchArticles parses and caches a successful response', () async {
    final client = MockClient((request) async => http.Response(_validJson, 200));
    final cache = InMemoryArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.articles.length, 2);
    expect(result.rawBody, _validJson);
    expect(result.fromNetwork, isTrue);
    expect(cache.stored, _validJson);
  });

  test('fetchArticles falls back to the cache on a network error', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache(_validJson);

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.articles.length, 2);
    expect(result.fromNetwork, isFalse);
  });

  test('fetchArticles falls back to the cache on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final cache = InMemoryArticleCache(_validJson);

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.articles.length, 2);
    expect(result.fromNetwork, isFalse);
  });

  test('fetchArticles returns an empty list when there is no cache either', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.articles, isEmpty);
    expect(result.fromNetwork, isFalse);
  });

  test('fetchArticles returns an empty list instead of throwing when the '
      'cache is malformed and the network also fails', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache('this is not valid json {{{');

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.articles, isEmpty);
  });

  test('fetchArticles returns the freshly parsed articles even when caching '
      'the response fails', () async {
    final client = MockClient((request) async => http.Response(_validJson, 200));
    final cache = ThrowingWriteArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.articles.length, 2);
    expect(result.articles[0].id, 'a1');
    expect(result.fromNetwork, isTrue);
  });

  test('parseCategories parses every category in order', () {
    final categories = parseCategories(_validJson);
    expect(categories, [
      const AppCategory(key: 'main', label: 'Main'),
      const AppCategory(key: 'politics', label: 'Politics'),
      const AppCategory(key: 'sports', label: 'Sports'),
    ]);
  });

  test('parseCategories returns the default list when categories is missing', () {
    expect(parseCategories(_jsonWithoutCategories), kDefaultCategories);
  });

  test('fetchArticles returns parsed categories from a successful response', () async {
    final client = MockClient((request) async => http.Response(_validJson, 200));
    final cache = InMemoryArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.categories, [
      const AppCategory(key: 'main', label: 'Main'),
      const AppCategory(key: 'politics', label: 'Politics'),
      const AppCategory(key: 'sports', label: 'Sports'),
    ]);
  });

  test('fetchArticles falls back to kDefaultCategories when there is no cache and no network', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache();

    final result = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(result.categories, kDefaultCategories);
  });

  test('parseArticles parses language and publishedAt when present', () {
    final articles = parseArticles(_jsonWithTimestamps);
    expect(articles[0].language, 'bn');
    expect(articles[0].publishedAt, DateTime.parse('2026-08-23T10:00:00+06:00'));
  });

  test('parseArticles leaves publishedAt null for an unparseable timestamp', () {
    final articles = parseArticles(_jsonWithTimestamps);
    expect(articles[1].language, 'en');
    expect(articles[1].publishedAt, isNull);
  });

  test('parseArticles defaults language to en and publishedAt to null when both are absent', () {
    final articles = parseArticles(_jsonWithTimestamps);
    expect(articles[2].language, 'en');
    expect(articles[2].publishedAt, isNull);
  });

  test('parseArticles includes an article even when language is a non-string value', () {
    final articles = parseArticles(_jsonWithNonStringLanguage);
    expect(articles.length, 1);
    expect(articles[0].id, 'a1');
    expect(articles[0].language, 'en');
  });
}
