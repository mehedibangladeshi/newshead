import 'package:flutter/material.dart';

import '../models/news_article.dart';
import '../widgets/news_card.dart';
import 'article_web_view_screen.dart';

class CategoryFeed extends StatefulWidget {
  final String category;
  final List<NewsArticle> articles;

  const CategoryFeed({super.key, required this.category, required this.articles});

  @override
  State<CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends State<CategoryFeed>
    with AutomaticKeepAliveClientMixin<CategoryFeed> {
  // Large enough that a user could not plausibly swipe past either edge in a
  // session, so the feed loops seamlessly in both directions without true
  // unbounded paging. Rounded down to a multiple of the article count so the
  // feed always starts on the first article.
  static const int _kLargePageBase = 100000;

  PageController? _pageController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.articles.isNotEmpty) {
      final n = widget.articles.length;
      _pageController = PageController(initialPage: (_kLargePageBase ~/ n) * n);
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.articles.isEmpty) {
      return const Center(child: Text('No stories yet'));
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemBuilder: (context, index) {
        final article = widget.articles[index % widget.articles.length];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArticleWebViewScreen(articleUrl: article.articleUrl),
            ),
          ),
          child: NewsCard(article: article),
        );
      },
    );
  }
}
