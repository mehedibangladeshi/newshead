import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/article_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';

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
  "articles": [
    {"id": "a1", "category": "politics", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"},
    {"id": "a2", "category": "sports", "source": "Ittefaq", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2"}
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

    final articles = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(articles.length, 2);
    expect(cache.stored, _validJson);
  });

  test('fetchArticles falls back to the cache on a network error', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache(_validJson);

    final articles = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(articles.length, 2);
  });

  test('fetchArticles falls back to the cache on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final cache = InMemoryArticleCache(_validJson);

    final articles = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(articles.length, 2);
  });

  test('fetchArticles returns an empty list when there is no cache either', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache();

    final articles = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(articles, isEmpty);
  });

  test('fetchArticles returns an empty list instead of throwing when the '
      'cache is malformed and the network also fails', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final cache = InMemoryArticleCache('this is not valid json {{{');

    final articles = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(articles, isEmpty);
  });

  test('fetchArticles returns the freshly parsed articles even when caching '
      'the response fails', () async {
    final client = MockClient((request) async => http.Response(_validJson, 200));
    final cache = ThrowingWriteArticleCache();

    final articles = await fetchArticles(
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client,
      cache: cache,
    );

    expect(articles.length, 2);
    expect(articles[0].id, 'a1');
  });
}
