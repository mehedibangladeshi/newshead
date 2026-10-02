import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/news_article.dart';

void main() {
  test('toJson/fromJson round-trips including publishedAt', () {
    final a = NewsArticle(
      id: 'a1',
      category: 'main',
      source: 'Jugantor',
      headline: 'H',
      snippet: 'S',
      imageUrl: 'https://e.com/1.jpg',
      articleUrl: 'https://e.com/a1',
      language: 'bn',
      publishedAt: DateTime.utc(2026, 8, 23, 10),
    );
    final b = NewsArticle.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
    expect(b.publishedAt, a.publishedAt);
  });

  test('null publishedAt round-trips and missing required field throws', () {
    const a = NewsArticle(
      id: 'a1', category: 'main', source: 's', headline: 'h', snippet: '',
      imageUrl: 'i', articleUrl: 'u',
    );
    expect(NewsArticle.fromJson(a.toJson()).publishedAt, isNull);
    expect(() => NewsArticle.fromJson({'id': 'x'}), throwsA(anything));
  });
}
