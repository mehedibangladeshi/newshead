import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/screens/home_screen.dart';

class InMemoryArticleCache implements ArticleCache {
  String? stored;
  InMemoryArticleCache([this.stored]);

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String contents) async => stored = contents;
}

const _twoCategories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'politics', label: 'Politics'),
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
    {"id": "a1", "category": "main", "source": "Jugantor", "headline": "H1", "snippet": "S1", "imageUrl": "https://example.com/1.jpg", "articleUrl": "https://example.com/a1"}
  ]
}
''';

void main() {
  testWidgets('renders one pill per initial category with the correct labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: const [],
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsOneWidget);
  });

  testWidgets('pull-to-refresh with a different-length category list re-renders the pill bar', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => http.Response(_threeCategoriesJson, 200),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: const [],
          initialCategories: _twoCategories,
          initialRawBody: null,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: client,
          cache: InMemoryArticleCache(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsOneWidget);
    expect(find.text('Sports'), findsNothing);

    // Trigger the RefreshIndicator's pull gesture inside the visible
    // CategoryFeed (which wires onRefresh to HomeScreen._handleRefresh),
    // following the drag-gesture style used in category_feed_test.dart.
    await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
  });
}
