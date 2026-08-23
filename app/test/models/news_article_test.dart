import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/news_article.dart';

void main() {
  test('NewsArticle stores all fields as provided', () {
    const article = NewsArticle(
      id: 'a1',
      category: 'politics',
      source: 'Jugantor',
      headline: 'Sample headline',
      snippet: 'Sample snippet text.',
      imageUrl: 'https://example.com/image.jpg',
      articleUrl: 'https://example.com/article',
    );

    expect(article.id, 'a1');
    expect(article.category, 'politics');
    expect(article.source, 'Jugantor');
    expect(article.headline, 'Sample headline');
    expect(article.snippet, 'Sample snippet text.');
    expect(article.imageUrl, 'https://example.com/image.jpg');
    expect(article.articleUrl, 'https://example.com/article');
  });

  test('language defaults to en and publishedAt defaults to null when omitted', () {
    const article = NewsArticle(
      id: 'a1',
      category: 'politics',
      source: 'Jugantor',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://example.com/i.jpg',
      articleUrl: 'https://example.com/a',
    );

    expect(article.language, 'en');
    expect(article.publishedAt, isNull);
  });

  test('stores language and publishedAt when provided', () {
    final publishedAt = DateTime.utc(2026, 8, 23, 10, 0);
    final article = NewsArticle(
      id: 'a1',
      category: 'politics',
      source: 'Jugantor',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://example.com/i.jpg',
      articleUrl: 'https://example.com/a',
      language: 'bn',
      publishedAt: publishedAt,
    );

    expect(article.language, 'bn');
    expect(article.publishedAt, publishedAt);
  });
}
