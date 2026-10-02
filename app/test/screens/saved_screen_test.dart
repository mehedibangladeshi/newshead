import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/news_article.dart';
import 'package:newshead/screens/saved_screen.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

NewsArticle _a(String id) => NewsArticle(
  id: id, category: 'main', source: 'Src', headline: 'Headline $id', snippet: '',
  imageUrl: 'https://e.com/$id.jpg', articleUrl: 'https://e.com/$id',
  publishedAt: DateTime.utc(2026, 8, 23),
);

Widget _app(List<NewsArticle> list, List<String> log) => MaterialApp(
  home: SavedScreen(
    initialSaved: list,
    onRemove: (a) => log.add('remove ${a.id}'),
    onRestore: (a, i) => log.add('restore ${a.id}@$i'),
    imageProviderBuilder: (_) => MemoryImage(_png),
  ),
);

void main() {
  testWidgets('renders rows', (tester) async {
    await tester.pumpWidget(_app([_a('1'), _a('2')], []));
    expect(find.text('Headline 1'), findsOneWidget);
    expect(find.text('Headline 2'), findsOneWidget);
    expect(find.textContaining('Src · '), findsNWidgets(2));
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_app([], []));
    expect(find.text('No saved news yet'), findsOneWidget);
  });

  testWidgets('swipe removes, undo restores at same index', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app([_a('1'), _a('2')], log));
    await tester.drag(find.text('Headline 2'), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(find.text('Headline 2'), findsNothing);
    expect(find.text('Removed from saved'), findsOneWidget);
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(find.text('Headline 2'), findsOneWidget);
    expect(log, ['remove 2', 'restore 2@1']);
  });

  testWidgets('bookmark button removes', (tester) async {
    await tester.pumpWidget(_app([_a('1')], []));
    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(find.text('No saved news yet'), findsOneWidget);
  });

  testWidgets('snackbar auto-dismisses after duration', (tester) async {
    await tester.pumpWidget(_app([_a('1')], []));
    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(find.text('Removed from saved'), findsOneWidget);
    // Wait for snackbar duration (2.5 seconds) plus margin.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Removed from saved'), findsNothing);
  });
}
