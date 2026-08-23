import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/article_cache.dart';
import '../data/article_repository.dart';
import '../models/app_category.dart';
import '../models/news_article.dart';
import 'category_feed.dart';

class HomeScreen extends StatefulWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;

  const HomeScreen({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Large enough that a user could not plausibly swipe past either edge in a
  // session, so category switching loops seamlessly in both directions
  // (Finance -> Main, Main -> Finance) without true unbounded paging.
  // Rounded down to a multiple of the category count so it starts on Main.
  static const int _kLargePageBase = 100000;

  late TabController _tabController;
  late PageController _categoryPageController;
  bool _isSyncingFromPage = false;

  late List<NewsArticle> _articles;
  late List<AppCategory> _categories;
  String? _lastRawBody;
  // Bumped on every successful refresh so each CategoryFeed remounts fresh
  // (fresh PageController at the first article) instead of keeping its old
  // scroll position over reordered/changed content.
  int _refreshGeneration = 0;

  static const List<String> _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _articles = widget.initialArticles;
    _categories = widget.initialCategories;
    _lastRawBody = widget.initialRawBody;
    _initControllers(_categories.length);
  }

  void _initControllers(int n) {
    _tabController = TabController(length: n, vsync: this);
    _categoryPageController = PageController(
      initialPage: (_kLargePageBase ~/ n) * n,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _disposeControllers() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _categoryPageController.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  // Tapping a tab animates the TabController on its own first; once that
  // settles (indexIsChanging is false), animate the page view to the
  // nearest equivalent page for the tapped category. Ignored while we're
  // the ones driving the tab index from a page change (see
  // _onCategoryPageChanged), to avoid feeding back into a loop.
  void _onTabChanged() {
    if (_isSyncingFromPage || _tabController.indexIsChanging) return;
    final currentPage =
        _categoryPageController.page?.round() ??
        _categoryPageController.initialPage;
    final targetPage = _nearestPageForCategory(
      currentPage,
      _tabController.index,
    );
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
    final n = _categories.length;
    final currentCategoryIndex = currentPage % n;
    var diff = categoryIndex - currentCategoryIndex;
    if (diff > n / 2) diff -= n;
    if (diff < -n / 2) diff += n;
    return currentPage + diff;
  }

  void _onCategoryPageChanged(int page) {
    _isSyncingFromPage = true;
    _tabController.index = page % _categories.length;
    _isSyncingFromPage = false;
  }

  String _todayLabel() {
    final now = DateTime.now();
    final weekday = _weekdayNames[now.weekday - 1];
    final month = _monthNames[now.month - 1];
    return '$weekday, $month ${now.day}';
  }

  // Pulled from any category feed. Re-fetches from the shared source; if the
  // server returned byte-identical content to last time (nothing new to
  // show), the order is shuffled per category so the pull still visibly
  // "does something" instead of looking like a no-op.
  Future<void> _handleRefresh() async {
    final result = await fetchArticles(
      sourceUrl: widget.sourceUrl,
      client: widget.client,
      cache: widget.cache,
    );

    if (!result.fromNetwork) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh — check your connection'),
          ),
        );
      }
      return;
    }

    var articles = result.articles;
    if (result.rawBody == _lastRawBody) {
      articles = articles.toList()..shuffle();
    }

    if (!mounted) return;
    setState(() {
      _articles = articles;
      _lastRawBody = result.rawBody;
      _refreshGeneration++;
      if (result.categories.length != _categories.length) {
        _disposeControllers();
        _initControllers(result.categories.length);
      }
      _categories = result.categories;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The date sits in its own row, in normal layout flow, so it
          // never shares space with the status bar / notch / Dynamic
          // Island, and the image below never starts underneath them.
          ColoredBox(
            color: const Color(0xFF121212),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Text(
                  _todayLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _categoryPageController,
              onPageChanged: _onCategoryPageChanged,
              itemBuilder: (context, page) {
                final category = _categories[page % _categories.length];
                return CategoryFeed(
                  key: PageStorageKey('${category.key}#$_refreshGeneration'),
                  category: category.key,
                  articles: articlesForCategory(_articles, category.key),
                  onRefresh: _handleRefresh,
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: const Color(0xFF121212),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ListenableBuilder(
                listenable: _tabController,
                builder: (context, _) {
                  return Row(
                    children: [
                      for (var i = 0; i < _categories.length; i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                          child: _CategoryPill(
                            label: _categories[i].label,
                            selected: _tabController.index == i,
                            onTap: () => _tabController.animateTo(i),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : Colors.white70,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
