import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/auto_scroll.dart';
import 'package:newshead/models/news_article.dart';
import 'package:newshead/screens/category_feed.dart';

const articles = [
  NewsArticle(
    id: 'p1',
    category: 'politics',
    source: 'Jugantor',
    headline: 'First headline',
    snippet: 'First snippet.',
    imageUrl: 'https://example.com/1.jpg',
    articleUrl: 'https://example.com/article1',
  ),
  NewsArticle(
    id: 'p2',
    category: 'politics',
    source: 'Ittefaq',
    headline: 'Second headline',
    snippet: 'Second snippet.',
    imageUrl: 'https://example.com/2.jpg',
    articleUrl: 'https://example.com/article2',
  ),
];

void main() {
  testWidgets('vertical drag advances to the next article in the category', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CategoryFeed(
        category: 'politics',
        articles: articles,
        isSaved: (_) => false,
        onToggleSave: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.text('First headline'), findsOneWidget);
    expect(find.text('Second headline'), findsNothing);

    await tester.drag(find.byType(CategoryFeed), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('First headline'), findsNothing);
    expect(find.text('Second headline'), findsOneWidget);
  });

  testWidgets('shows a placeholder when the category has no articles', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CategoryFeed(
        category: 'finance',
        articles: const [],
        isSaved: (_) => false,
        onToggleSave: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.text('No stories yet'), findsOneWidget);
  });

  Widget feed({
    bool autoScroll = false,
    bool isActive = true,
    void Function(NewsArticle)? onToggleSave,
    void Function(NewsArticle)? onShare,
  }) => MaterialApp(
    home: CategoryFeed(
      category: 'politics',
      articles: articles,
      isSaved: (_) => false,
      onToggleSave: onToggleSave ?? (_) {},
      onShare: onShare,
      autoScroll: autoScroll,
      isActive: isActive,
    ),
  );

  final dwell = dwellFor(articles[0]) + const Duration(milliseconds: 500);

  testWidgets('auto-scroll advances after the dwell time', (tester) async {
    await tester.pumpWidget(feed(autoScroll: true));
    await tester.pump(dwell);
    await tester.pumpAndSettle();
    expect(find.text('Second headline'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not advance when auto-scroll is off or feed inactive', (tester) async {
    await tester.pumpWidget(feed());
    await tester.pump(dwell);
    expect(find.text('First headline'), findsOneWidget);
    await tester.pumpWidget(feed(autoScroll: true, isActive: false));
    await tester.pump(dwell);
    expect(find.text('First headline'), findsOneWidget);
  });

  testWidgets('a pointer held down pauses auto-scroll', (tester) async {
    await tester.pumpWidget(feed(autoScroll: true));
    final g = await tester.startGesture(tester.getCenter(find.byType(CategoryFeed)));
    await tester.pump(dwell);
    expect(find.text('First headline'), findsOneWidget);
    await g.up();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('save and share icons call their callbacks', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(feed(
      onToggleSave: (a) => log.add('save ${a.id}'),
      onShare: (a) => log.add('share ${a.id}'),
    ));
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.tap(find.byKey(const Key('shareButton')));
    expect(log, ['save p1', 'share p1']);
  });
}
