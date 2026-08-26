import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:newshead/data/filter_store.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/filter_option.dart';
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

class InMemoryFilterStore implements FilterStore {
  Set<String> stored;
  InMemoryFilterStore([Set<String>? initial]) : stored = initial ?? {};

  @override
  Future<Set<String>> readExcludedKeys() async => stored;

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async => stored = keys;
}

const _twoCategories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'politics', label: 'Politics'),
];

const _twoLanguages = [
  FilterOption(key: 'bn', label: 'Bangla'),
  FilterOption(key: 'en', label: 'English'),
];

const _twoSources = [
  FilterOption(key: 'Jugantor', label: 'Jugantor'),
  FilterOption(key: 'The Daily Star', label: 'The Daily Star'),
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

// Same two categories, but each is served by a different language AND a
// different source, so excluding either one on its own empties exactly one
// category's tab.
const _articlesInMainAndPoliticsByDifferentSources = [
  NewsArticle(
    id: 'a1',
    category: 'main',
    source: 'Jugantor',
    headline: 'H1',
    snippet: 'S1',
    imageUrl: 'https://example.com/1.jpg',
    articleUrl: 'https://example.com/a1',
    language: 'bn',
  ),
  NewsArticle(
    id: 'a2',
    category: 'politics',
    source: 'The Daily Star',
    headline: 'H2',
    snippet: 'S2',
    imageUrl: 'https://example.com/2.jpg',
    articleUrl: 'https://example.com/a2',
    language: 'en',
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

Widget _buildHomeScreen({
  List<NewsArticle> initialArticles = _oneArticleInMain,
  List<AppCategory> initialCategories = _twoCategories,
  List<FilterOption> initialLanguages = _twoLanguages,
  List<FilterOption> initialSources = _twoSources,
  http.Client? client,
  FilterStore? categoryFilterStore,
  FilterStore? languageFilterStore,
  FilterStore? sourceFilterStore,
}) {
  return MaterialApp(
    home: HomeScreen(
      initialArticles: initialArticles,
      initialCategories: initialCategories,
      initialLanguages: initialLanguages,
      initialSources: initialSources,
      initialRawBody: null,
      sourceUrl: Uri.parse('https://example.com/articles.json'),
      client: client ?? MockClient((request) async => http.Response('{}', 200)),
      cache: InMemoryArticleCache(),
      categoryFilterStore: categoryFilterStore ?? InMemoryFilterStore(),
      languageFilterStore: languageFilterStore ?? InMemoryFilterStore(),
      sourceFilterStore: sourceFilterStore ?? InMemoryFilterStore(),
    ),
  );
}

void main() {
  testWidgets('renders one pill per category that actually has an article', (tester) async {
    await tester.pumpWidget(_buildHomeScreen());
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('tapping the refresh button with a different category list re-renders the pill bar', (tester) async {
    final client = MockClient((request) async => http.Response(_threeCategoriesJson, 200));

    await tester.pumpWidget(_buildHomeScreen(client: client));
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
    await tester.pumpWidget(_buildHomeScreen(initialArticles: _articlesInMainAndPolitics));
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

  testWidgets('unchecking a language in the filter sheet hides the category only that language feeds', (tester) async {
    await tester.pumpWidget(_buildHomeScreen(
      initialArticles: _articlesInMainAndPoliticsByDifferentSources,
    ));
    await tester.pump();

    expect(find.text('Politics'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'English'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('unchecking a source in the filter sheet hides the category only that source feeds', (tester) async {
    await tester.pumpWidget(_buildHomeScreen(
      initialArticles: _articlesInMainAndPoliticsByDifferentSources,
    ));
    await tester.pump();

    expect(find.text('Politics'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'The Daily Star'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('the filter icon shows a badge dot once a category is excluded', (tester) async {
    await tester.pumpWidget(_buildHomeScreen(
      initialArticles: const [],
      categoryFilterStore: InMemoryFilterStore({'politics'}),
    ));
    await tester.pump();
    await tester.pump(); // let readExcludedKeys()'s Futures resolve

    expect(find.byKey(const Key('filterActiveBadge')), findsOneWidget);
  });

  testWidgets('the filter icon shows a badge dot once a language is excluded', (tester) async {
    await tester.pumpWidget(_buildHomeScreen(
      initialArticles: const [],
      languageFilterStore: InMemoryFilterStore({'bn'}),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('filterActiveBadge')), findsOneWidget);
  });

  testWidgets('the filter icon shows a badge dot once a source is excluded', (tester) async {
    await tester.pumpWidget(_buildHomeScreen(
      initialArticles: const [],
      sourceFilterStore: InMemoryFilterStore({'Jugantor'}),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('filterActiveBadge')), findsOneWidget);
  });

  testWidgets('the filter icon shows no badge dot when nothing is excluded', (tester) async {
    await tester.pumpWidget(_buildHomeScreen(initialArticles: const []));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('filterActiveBadge')), findsNothing);
  });

  testWidgets('shows the brand mark instead of a date', (tester) async {
    await tester.pumpWidget(_buildHomeScreen());
    await tester.pump();

    expect(find.text('NEWSHEAD'), findsOneWidget);
  });
}
