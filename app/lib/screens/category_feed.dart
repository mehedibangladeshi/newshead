import 'package:flutter/material.dart';

import '../models/news_article.dart';
import '../widgets/news_card.dart';
import 'article_web_view_screen.dart';

class CategoryFeed extends StatefulWidget {
  final String category;
  final List<NewsArticle> articles;
  final Future<void> Function() onRefresh;

  const CategoryFeed({
    super.key,
    required this.category,
    required this.articles,
    required this.onRefresh,
  });

  @override
  State<CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends State<CategoryFeed>
    with AutomaticKeepAliveClientMixin<CategoryFeed> {
  // Bounded (not an infinite loop): RefreshIndicator only ever triggers when
  // the scroll position is at its true minimum extent, which an endlessly
  // wrapping PageView never reaches. Stopping at the first/last article is
  // the tradeoff that makes pull-to-refresh able to fire at all.
  final PageController _pageController = PageController();

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

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: const Color(0xFF1E1E1E),
      child: widget.articles.isEmpty
          ? ListView(
              // A plain Center isn't scrollable, so pull-to-refresh has
              // nothing to drag against; ListView keeps the gesture working
              // even when this category currently has no stories.
              physics: const AlwaysScrollableScrollPhysics(),
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
              itemCount: widget.articles.length,
              // Keeps the vertical swipe-between-articles paging behavior
              // while still letting RefreshIndicator detect a pull past the
              // very first article.
              physics: const PageScrollPhysics().applyTo(
                const AlwaysScrollableScrollPhysics(),
              ),
              itemBuilder: (context, index) {
                final article = widget.articles[index];
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
            ),
    );
  }
}
