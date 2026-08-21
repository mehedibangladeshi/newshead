import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/article_repository.dart';

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
}
