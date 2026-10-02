import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/auto_scroll.dart';
import '../models/news_article.dart';
import '../widgets/empty_state.dart';
import '../widgets/news_card.dart';
import 'article_web_view_screen.dart';

class CategoryFeed extends StatefulWidget {
  final String category;
  final List<NewsArticle> articles;
  final bool hasActiveFilters;
  final bool Function(NewsArticle) isSaved;
  final void Function(NewsArticle) onToggleSave;
  final void Function(NewsArticle)? onShare;
  final bool autoScroll;
  // True only for the category page currently on screen.
  final bool isActive;

  const CategoryFeed({
    super.key,
    required this.category,
    required this.articles,
    this.hasActiveFilters = false,
    required this.isSaved,
    required this.onToggleSave,
    this.onShare,
    this.autoScroll = false,
    this.isActive = true,
  });

  @override
  State<CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends State<CategoryFeed>
    with AutomaticKeepAliveClientMixin<CategoryFeed>, WidgetsBindingObserver {
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
  late int _page;
  Timer? _timer;
  bool _resumed = true;
  bool _pointerDown = false;
  bool _articleOpen = false;

  @override
  void initState() {
    super.initState();
    final length = widget.articles.length;
    _page = length == 0 ? 0 : (_kLargePageBase ~/ length) * length;
    _pageController = PageController(initialPage: _page);
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!widget.autoScroll || !widget.isActive || !_resumed || _pointerDown || _articleOpen) return;
    if (widget.articles.isEmpty) return;
    _timer = Timer(
      dwellFor(widget.articles[_page % widget.articles.length]),
      () {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      },
    );
  }


  @override
  void didUpdateWidget(CategoryFeed old) {
    super.didUpdateWidget(old);
    if (old.autoScroll != widget.autoScroll ||
        old.isActive != widget.isActive) {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _schedule();
  }

  Future<void> _openArticle(NewsArticle article) async {
    _articleOpen = true;
    _schedule();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArticleWebViewScreen(articleUrl: article.articleUrl),
      ),
    );
    _articleOpen = false;
    if (mounted) _schedule();
  }

  static void _share(NewsArticle a) => SharePlus.instance.share(
    ShareParams(text: '${a.headline}\n${a.articleUrl}'),
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return widget.articles.isEmpty
        ? ListView(
            children: [
              SizedBox(
                height: 400,
                child: EmptyState(hasActiveFilters: widget.hasActiveFilters),
              ),
            ],
          )
        : Listener(
            onPointerDown: (_) {
              _pointerDown = true;
              _schedule();
            },
            onPointerUp: (_) {
              _pointerDown = false;
              _schedule();
            },
            onPointerCancel: (_) {
              _pointerDown = false;
              _schedule();
            },
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) {
                _page = page;
                _schedule();
              },
              scrollDirection: Axis.vertical,
              itemCount: _kItemCount,
              itemBuilder: (context, index) {
                final article = widget.articles[index % widget.articles.length];
                return GestureDetector(
                  onTap: () => _openArticle(article),
                  child: NewsCard(
                    article: article,
                    isSaved: widget.isSaved(article),
                    onToggleSave: () => widget.onToggleSave(article),
                    onShare: () => (widget.onShare ?? _share)(article),
                  ),
                );
              },
            ),
          );
  }
}
