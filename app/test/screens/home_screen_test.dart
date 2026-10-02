import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:newshead/data/auto_scroll.dart';
import 'package:newshead/data/category_filter_store.dart';
import 'package:newshead/data/saved_articles_store.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/news_article.dart';
import 'package:newshead/screens/home_screen.dart';
import 'package:newshead/screens/saved_screen.dart';

class InMemoryArticleCache implements ArticleCache {
  String? stored;
  InMemoryArticleCache([this.stored]);

  @override
  Future<DateTime?> savedAt() async => null;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String contents) async => stored = contents;
}

class InMemoryExcludedKeysStore implements ExcludedKeysStore {
  Set<String> stored;
  InMemoryExcludedKeysStore([Set<String>? initial]) : stored = initial ?? {};

  @override
  Future<Set<String>> readExcludedKeys() async => stored;

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async => stored = keys;
}

class InMemorySavedArticlesStore implements SavedArticlesStore {
  List<NewsArticle> stored;
  InMemorySavedArticlesStore([List<NewsArticle>? initial]) : stored = initial ?? [];

  @override
  Future<List<NewsArticle>> readSaved() async => stored;

  @override
  Future<void> writeSaved(List<NewsArticle> articles) async => stored = articles;
}

class InMemoryAutoScrollStore implements AutoScrollStore {
  bool stored = false;

  @override
  Future<bool> readEnabled() async => stored;

  @override
  Future<void> writeEnabled(bool enabled) async => stored = enabled;
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
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Politics'), findsNothing);
  });

  testWidgets('refreshing from the filter sheet with a different category list re-renders the pill bar', (tester) async {
    final client = MockClient((request) async => http.Response(_threeCategoriesJson, 200));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: client,
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Sports'), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheetRefreshButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
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
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
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
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore({'politics'}),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
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
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
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
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('NEWSHEAD'), findsOneWidget);
  });

  testWidgets('auto-scroll button flips the icon and persists', (tester) async {
    final store = InMemoryAutoScrollStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: store,
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('autoScrollButton')));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(store.stored, true);

    // Unmount so the feed's pending auto-scroll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saving a card then opening Saved lists it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _oneArticleInMain,
          initialCategories: _twoCategories,
          initialRawBody: null,
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: InMemoryAutoScrollStore(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('savedButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SavedScreen), findsOneWidget);
    expect(find.text('H1'), findsOneWidget);
  });

  testWidgets('auto-scroll pauses when Saved screen is open', (tester) async {
    final store = InMemoryAutoScrollStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialArticles: _articlesInMainAndPolitics,
          initialCategories: _twoCategories,
          initialRawBody: null,
          initialFromNetwork: true,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: MockClient((request) async => http.Response('{}', 200)),
          cache: InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: InMemorySavedArticlesStore(),
          autoScrollStore: store,
        ),
      ),
    );
    await tester.pump();

    // Enable auto-scroll
    await tester.tap(find.byKey(const Key('autoScrollButton')));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Capture the first article headline
    final firstHeadline = find.text('H1');
    expect(firstHeadline, findsOneWidget);

    // Open Saved screen
    await tester.tap(find.byKey(const Key('savedButton')));
    await tester.pump();

    // Pump for 25 seconds without settling to let auto-scroll timer advance
    // If auto-scroll were still active, it would advance the feed
    await tester.pump(const Duration(seconds: 25));

    // Go back to home screen
    await tester.pageBack();
    await tester.pump();

    // Verify the first article headline is still visible (feed did not advance)
    expect(find.text('H1'), findsOneWidget);

    // Cleanup: dispose timers
    await tester.pumpWidget(const SizedBox());
  });

  Widget home({
    List<NewsArticle> articles = _oneArticleInMain,
    bool fromNetwork = true,
    http.Client? client,
    InMemorySavedArticlesStore? saved,
    InMemoryAutoScrollStore? auto,
    InMemoryArticleCache? cache,
    DateTime Function()? now,
  }) =>
      MaterialApp(
        home: HomeScreen(
          initialArticles: articles,
          initialCategories: _twoCategories,
          initialRawBody: null,
          initialFromNetwork: fromNetwork,
          sourceUrl: Uri.parse('https://example.com/articles.json'),
          client: client ?? MockClient((request) async => http.Response('{}', 200)),
          cache: cache ?? InMemoryArticleCache(),
          filterStore: InMemoryExcludedKeysStore(),
          sourceFilterStore: InMemoryExcludedKeysStore(),
          languageFilterStore: InMemoryExcludedKeysStore(),
          savedStore: saved ?? InMemorySavedArticlesStore(),
          autoScrollStore: auto ?? InMemoryAutoScrollStore(),
          now: now ?? DateTime.now,
        ),
      );

  group('save toast', () {
    testWidgets('save shows Saved + VIEW, VIEW opens Saved', (tester) async {
      await tester.pumpWidget(home());
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.text('VIEW'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedScreen), findsOneWidget);
    });

    testWidgets('unsave shows Removed + UNDO, UNDO re-saves', (tester) async {
      final store = InMemorySavedArticlesStore();
      await tester.pumpWidget(home(saved: store));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Removed from saved'), findsOneWidget);
      expect(store.stored, isEmpty);
      await tester.tap(find.text('UNDO'));
      await tester.pump();
      expect(store.stored.map((a) => a.id), ['a1']);
      expect(find.byIcon(Icons.bookmark), findsWidgets);
    });
  });

  group('auto-scroll pill', () {
    testWidgets('hidden while searching', (tester) async {
      await tester.pumpWidget(home());
      await tester.pump();
      expect(find.byKey(const Key('autoScrollButton')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('autoScrollButton')), findsNothing);
    });
  });

  group('resume refresh', () {
    Future<int> resumeAfter(WidgetTester tester, Duration elapsed) async {
      var calls = 0;
      var t = DateTime(2026, 1, 1);
      await tester.pumpWidget(home(
        client: MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
        now: () => t,
      ));
      await tester.pump();
      t = t.add(elapsed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return calls;
    }

    testWidgets('stale data refreshes silently', (tester) async {
      expect(await resumeAfter(tester, const Duration(minutes: 31)), 1);
    });

    testWidgets('fresh data does not refetch', (tester) async {
      expect(await resumeAfter(tester, const Duration(minutes: 5)), 0);
    });
  });
}
