import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/news_article.dart';
import 'package:newshead/widgets/news_card.dart';

const article = NewsArticle(
  id: 'a1',
  category: 'politics',
  source: 'Jugantor',
  headline: 'Test headline',
  snippet: 'Test snippet text.',
  imageUrl: 'https://example.com/image.jpg',
  articleUrl: 'https://example.com/article',
);

// Synchronously fails to load, so errorBuilder fires without any real network I/O.
class FailingImageProvider extends ImageProvider<FailingImageProvider> {
  @override
  Future<FailingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(FailingImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(Exception('simulated image load failure')),
    );
  }
}

void main() {
  testWidgets('renders headline, source, and snippet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(
        article: article,
        imageProviderBuilder: (_) => FailingImageProvider(),
      ),
    ));
    await tester.pump();

    expect(find.text('Test headline'), findsOneWidget);
    expect(find.text('Jugantor'), findsOneWidget);
    expect(find.text('Test snippet text.'), findsOneWidget);
  });

  testWidgets('falls back to a placeholder icon when the image fails to load', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(
        article: article,
        imageProviderBuilder: (_) => FailingImageProvider(),
      ),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('never truncates a long headline', (tester) async {
    final longHeadline = List.filled(300, 'A').join();
    final longArticle = NewsArticle(
      id: 'a2',
      category: 'politics',
      source: 'Jugantor',
      headline: longHeadline,
      snippet: 'snippet',
      imageUrl: 'https://example.com/image.jpg',
      articleUrl: 'https://example.com/article',
    );
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(article: longArticle, imageProviderBuilder: (_) => FailingImageProvider()),
    ));
    await tester.pump();

    final headlineWidget = tester.widget<Text>(find.text(longHeadline));
    expect(headlineWidget.maxLines, isNull);
    expect(headlineWidget.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('shows the formatted publish timestamp when present', (tester) async {
    final withTimestamp = NewsArticle(
      id: 'a3',
      category: 'politics',
      source: 'Jugantor',
      headline: 'Headline',
      snippet: 'snippet',
      imageUrl: 'https://example.com/image.jpg',
      articleUrl: 'https://example.com/article',
      language: 'en',
      publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(article: withTimestamp, imageProviderBuilder: (_) => FailingImageProvider()),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.access_time), findsOneWidget);
  });

  testWidgets('hides the timestamp row when publishedAt is null', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewsCard(article: article, imageProviderBuilder: (_) => FailingImageProvider()),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.access_time), findsNothing);
  });

  Widget card({
    NewsArticle a = article,
    bool isSaved = false,
    VoidCallback? onToggleSave,
    VoidCallback? onShare,
  }) =>
      MaterialApp(
        home: NewsCard(
          article: a,
          isSaved: isSaved,
          onToggleSave: onToggleSave,
          onShare: onShare,
          imageProviderBuilder: (_) => FailingImageProvider(),
        ),
      );

  testWidgets('action icons are absent without callbacks', (tester) async {
    await tester.pumpWidget(card());
    await tester.pump();

    expect(find.byKey(const Key('saveButton')), findsNothing);
    expect(find.byKey(const Key('shareButton')), findsNothing);
  });

  testWidgets('action icons render and fire their callbacks without triggering parent tap', (tester) async {
    var saves = 0, shares = 0, parentTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: GestureDetector(
        onTap: () => parentTaps++,
        child: NewsCard(
          article: article,
          onToggleSave: () => saves++,
          onShare: () => shares++,
          imageProviderBuilder: (_) => FailingImageProvider(),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.tap(find.byKey(const Key('shareButton')));
    expect([saves, shares, parentTaps], [1, 1, 0]);
  });

  testWidgets('shows a filled bookmark when saved', (tester) async {
    await tester.pumpWidget(card(isSaved: true, onToggleSave: () {}));
    await tester.pump();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.pumpWidget(card(onToggleSave: () {}));
    await tester.pump();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('null publishedAt with callbacks shows icons but no clock', (tester) async {
    await tester.pumpWidget(card(onToggleSave: () {}, onShare: () {}));
    await tester.pump();

    expect(find.byKey(const Key('saveButton')), findsOneWidget);
    expect(find.byKey(const Key('shareButton')), findsOneWidget);
    expect(find.byIcon(Icons.access_time), findsNothing);
  });

  testWidgets('no overflow on a small surface with long text and actions', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = NewsArticle(
      id: 'a4',
      category: 'politics',
      source: 'Jugantor',
      headline: List.filled(30, 'Long headline words').join(' '),
      snippet: List.filled(200, 'snippet words').join(' '),
      imageUrl: 'https://example.com/image.jpg',
      articleUrl: 'https://example.com/article',
      language: 'en',
      publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    await tester.pumpWidget(card(a: long, onToggleSave: () {}, onShare: () {}));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('saveButton')), findsOneWidget);
  });
}
