import 'package:flutter/material.dart';

import '../data/article_repository.dart';
import '../models/news_article.dart';
import 'category_feed.dart';

const List<({String label, String key})> kCategories = [
  (label: 'Main', key: 'main'),
  (label: 'Politics', key: 'politics'),
  (label: 'World', key: 'world'),
  (label: 'Bangladesh', key: 'bangladesh'),
  (label: 'Sports', key: 'sports'),
  (label: 'Finance', key: 'finance'),
];

class HomeScreen extends StatefulWidget {
  final List<NewsArticle> articles;

  const HomeScreen({super.key, required this.articles});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // Large enough that a user could not plausibly swipe past either edge in a
  // session, so category switching loops seamlessly in both directions
  // (Finance -> Main, Main -> Finance) without true unbounded paging.
  // Rounded down to a multiple of the category count so it starts on Main.
  static const int _kLargePageBase = 100000;

  late final TabController _tabController;
  late final PageController _categoryPageController;
  bool _isSyncingFromPage = false;

  static const List<String> _weekdayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final n = kCategories.length;
    _tabController = TabController(length: n, vsync: this);
    _categoryPageController = PageController(initialPage: (_kLargePageBase ~/ n) * n);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _categoryPageController.dispose();
    super.dispose();
  }

  // Tapping a tab animates the TabController on its own first; once that
  // settles (indexIsChanging is false), animate the page view to the
  // nearest equivalent page for the tapped category. Ignored while we're
  // the ones driving the tab index from a page change (see
  // _onCategoryPageChanged), to avoid feeding back into a loop.
  void _onTabChanged() {
    if (_isSyncingFromPage || _tabController.indexIsChanging) return;
    final currentPage = _categoryPageController.page?.round() ??
        _categoryPageController.initialPage;
    final targetPage = _nearestPageForCategory(currentPage, _tabController.index);
    if (targetPage == currentPage) return;
    _categoryPageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  // The nearest page (forward or backward) that lands on categoryIndex,
  // so the tab-tap animation takes the shortest path around the loop.
  int _nearestPageForCategory(int currentPage, int categoryIndex) {
    final n = kCategories.length;
    final currentCategoryIndex = currentPage % n;
    var diff = categoryIndex - currentCategoryIndex;
    if (diff > n / 2) diff -= n;
    if (diff < -n / 2) diff += n;
    return currentPage + diff;
  }

  void _onCategoryPageChanged(int page) {
    _isSyncingFromPage = true;
    _tabController.index = page % kCategories.length;
    _isSyncingFromPage = false;
  }

  String _todayLabel() {
    final now = DateTime.now();
    final weekday = _weekdayNames[now.weekday - 1];
    final month = _monthNames[now.month - 1];
    return '$weekday, $month ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        elevation: 0,
        title: Text(_todayLabel()),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: kCategories.map((c) => Tab(text: c.label)).toList(),
        ),
      ),
      body: PageView.builder(
        controller: _categoryPageController,
        onPageChanged: _onCategoryPageChanged,
        itemBuilder: (context, page) {
          final category = kCategories[page % kCategories.length];
          return CategoryFeed(
            key: PageStorageKey(category.key),
            category: category.key,
            articles: articlesForCategory(widget.articles, category.key),
          );
        },
      ),
    );
  }
}
