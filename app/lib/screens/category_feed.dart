import 'package:flutter/material.dart';

import '../models/news_article.dart';
import '../widgets/news_card.dart';
import 'article_web_view_screen.dart';

class CategoryFeed extends StatefulWidget {
  final String category;
  final List<NewsArticle> articles;

  const CategoryFeed({
    super.key,
    required this.category,
    required this.articles,
  });

  @override
  State<CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends State<CategoryFeed>
    with AutomaticKeepAliveClientMixin<CategoryFeed> {
  // Mirrors home_screen.dart's _kLargePageBase technique: a large enough
  // base that a user could not plausibly swipe past either edge in a
  // session, so the vertical article feed loops seamlessly in both
  // directions. Unlike home_screen.dart's horizontal PageView (which omits
  // itemCount for forward-only infinite paging), this PageView is given a
  // large *finite* itemCount so backward swiping is also unbounded in
  // practice, since itemCount: null only supports paging forward forever.
  static const int _kLargePageBase = 100000;
  static const int _kItemCount = _kLargePageBase * 2;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final length = widget.articles.length;
    _pageController = PageController(
      initialPage: length == 0 ? 0 : (_kLargePageBase ~/ length) * length,
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return widget.articles.isEmpty
        ? ListView(
            children: const [
              SizedBox(
                height: 400,
                child: Center(child: Text('No stories yet')),
              ),
            ],
          )
        : PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _kItemCount,
            itemBuilder: (context, index) {
              final article =
                  widget.articles[index % widget.articles.length];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ArticleWebViewScreen(articleUrl: article.articleUrl),
                  ),
                ),
                child: NewsCard(article: article),
              );
            },
          );
  }
}
