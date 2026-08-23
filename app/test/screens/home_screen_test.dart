import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:newshead/data/category_filter_store.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/news_article.dart';
import 'package:newshead/screens/home_screen.dart';

class InMemoryArticleCache implements ArticleCache {
  String? stored;
  InMemoryArticleCache([this.stored]);

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String contents) async => stored = contents;
}

class InMemoryCategoryFilterStore implements CategoryFilterStore {
  Set<String> stored;
  InMemoryCategoryFilterStore([Set<String>? initial]) : stored = initial ?? {};

  @override
  Future<Set<String>> readExcludedKeys() async => stored;

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async => stored = keys;
}

const _twoCategories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'politics', label: 'Politics'),
];

const _oneArticleInMain = [
  NewsArticle(
    id: 'a1',
    category: 'main',
    source: 'Jugantor',
    headline: 'H1',
    snippet: 'S1',
    imageUrl: 'https://example.com/1.jpg',
    articleUrl: 'https://example.com/a1',
  ),
];

const _articlesInMainAndPolitics = [
  NewsArticle(
    id: 'a1',
    category: 'main',
    source: 'Jugantor',
    headline: 'H1',
    snippet: 'S1',
    imageUrl: 'https://example.com/1.jpg',
    articleUrl: 'https://example.com/a1',
  ),
  NewsArticle(
    id: 'a2',
    category: 'politics',
    source: 'Jugantor',
    headline: 'H2',
    snippet: 'S2',
    imageUrl: 'https://example.com/2.jpg',
    articleUrl: 'https://example.com/a2',
  ),
];

const _threeCategoriesJson = '''
{
  "generated_at": "2026-08-23",
  "categories": [
    {"key": "main", "label": "Main"},
    {"key": "politics", "label": "Politics"},
    {"key": "sports", "label": "Sports"}
  ],
  "articles": [
    {"id": "a1", "category": "main", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"},
    {"id": "a2", "category": "politics", "source": "Jugantor", "headline": "H2", "snippet": "S2", "imageUrl": "https://example.com/2.jpg", "articleUrl": "https://example.com/a2"},
    {"id": "a3", "category": "sports", "source": "Jugantor", "headline": "H3", "snippet": "S3", "imageUrl": "https://example.com/3.jpg", "articleUrl": "https://example.com/a3"}
  ]
}
''';

void main() {
  testWidgets('renders one pill per category that actually has an article', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('tapping the refresh button with a different category list re-renders the pill bar', (tester) async {
    final client = MockClient((request) async => http.Response(_threeCategoriesJson, 200));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: client,
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Sports'), findsNothing);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
  });

  testWidgets('unchecking a category in the filter sheet immediately hides its pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _articlesInMainAndPolitics,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Politics'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Politics'));
    await tester.pumpAndSettle();

    // Dismiss the sheet by tapping the scrim, to inspect the feed beneath it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('the filter icon shows a badge dot once a category is excluded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: const [],
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore({'politics'}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(); // let readExcludedKeys()'s Future resolve

    expect(find.byKey(const Key('filterActiveBadge')), findsOneWidget);
  });

  testWidgets('the filter icon shows no badge dot when nothing is excluded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: const [],
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('filterActiveBadge')), findsNothing);
  });

  testWidgets('shows the brand mark instead of a date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryCategoryFilterStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('NEWSHEAD'), findsOneWidget);
  });
}
