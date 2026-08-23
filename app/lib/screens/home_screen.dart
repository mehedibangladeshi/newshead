import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/article_cache.dart';
import '../data/article_repository.dart';
import '../data/category_filter_store.dart';
import '../data/category_visibility.dart';
import '../models/app_category.dart';
import '../models/news_article.dart';
import '../widgets/brand_mark.dart';
import 'category_feed.dart';
import 'category_filter_sheet.dart';

class HomeScreen extends StatefulWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;
  final CategoryFilterStore filterStore;

  const HomeScreen({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
    required this.filterStore,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // TickerProviderStateMixin (not SingleTickerProviderStateMixin): a
  // refresh or filter change that changes the visible-category count
  // disposes and recreates the TabController (see _initControllers below),
  // vending a second ticker over this State's lifetime.
  // Large enough that a user could not plausibly swipe past either edge in
  // a session, so category switching loops seamlessly in both directions
  // without true unbounded paging. Rounded down to a multiple of the
  // category count so it starts on the first visible category.
  static const int _kLargePageBase = 100000;

  late TabController _tabController;
  late PageController _categoryPageController;
  bool _isSyncingFromPage = false;

  late List<NewsArticle> _articles;
  late List<AppCategory> _categories;
  Set<String> _excludedCategoryKeys = {};
  late List<AppCategory> _visibleCategories;
  String? _lastRawBody;
  // Bumped on every successful refresh so each CategoryFeed remounts fresh
  // (fresh PageController at the first article) instead of keeping its old
  // scroll position over reordered/changed content.
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _articles = widget.initialArticles;
    _categories = widget.initialCategories;
    _lastRawBody = widget.initialRawBody;
    _visibleCategories = visibleCategories(
      fetchedCategories: _categories,
      articles: _articles,
      excludedKeys: _excludedCategoryKeys,
    );
    _initControllers(_visibleCategories.length);
    _loadExcludedCategoryKeys();
  }

  Future<void> _loadExcludedCategoryKeys() async {
    final stored = await widget.filterStore.readExcludedKeys();
    if (!mounted) return;
    _applyExcludedKeys(stored);
  }

  void _applyExcludedKeys(Set<String> excludedKeys) {
    final nextVisible = visibleCategories(
      fetchedCategories: _categories,
      articles: _articles,
      excludedKeys: excludedKeys,
    );
    setState(() {
      _excludedCategoryKeys = excludedKeys;
      if (nextVisible.length != _visibleCategories.length) {
        _disposeControllers();
        _initControllers(nextVisible.length);
      }
      _visibleCategories = nextVisible;
    });
  }

  void _handleFilterToggle(String categoryKey, bool isChecked) {
    final next = {..._excludedCategoryKeys};
    if (isChecked) {
      next.remove(categoryKey);
    } else {
      next.add(categoryKey);
    }
    _applyExcludedKeys(next);
    widget.filterStore.writeExcludedKeys(next);
  }

  void _openFilterSheet() {
    showCategoryFilterSheet(
      context: context,
      allCategories: _categories,
      excludedKeys: _excludedCategoryKeys,
      onToggle: _handleFilterToggle,
    );
  }

  void _initControllers(int n) {
    _tabController = TabController(length: n, vsync: this);
    _categoryPageController = PageController(
      initialPage: n == 0 ? 0 : (_kLargePageBase ~/ n) * n,
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
    final n = _visibleCategories.length;
    final currentCategoryIndex = currentPage % n;
    var diff = categoryIndex - currentCategoryIndex;
    if (diff > n / 2) diff -= n;
    if (diff < -n / 2) diff += n;
    return currentPage + diff;
  }

  void _onCategoryPageChanged(int page) {
    _isSyncingFromPage = true;
    _tabController.index = page % _visibleCategories.length;
    _isSyncingFromPage = false;
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
    final nextVisible = visibleCategories(
      fetchedCategories: result.categories,
      articles: articles,
      excludedKeys: _excludedCategoryKeys,
    );
    setState(() {
      _articles = articles;
      _lastRawBody = result.rawBody;
      _refreshGeneration++;
      _categories = result.categories;
      if (nextVisible.length != _visibleCategories.length) {
        _disposeControllers();
        _initControllers(nextVisible.length);
      }
      _visibleCategories = nextVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: const Color(0xFF121212),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const BrandMark(),
                    IconButton(
                      onPressed: _openFilterSheet,
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.tune, color: Colors.white70),
                          if (_excludedCategoryKeys.isNotEmpty)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                key: const Key('filterActiveBadge'),
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE1483A),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _visibleCategories.isEmpty
                ? const Center(
                    child: Text(
                      'No stories yet',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : PageView.builder(
                    // Keyed on the controller's identity so a controller swap
                    // (see _applyExcludedKeys/_handleRefresh, which create a
                    // brand-new PageController when the visible-category
                    // count changes) forces a full remount of this widget.
                    key: ObjectKey(_categoryPageController),
                    controller: _categoryPageController,
                    onPageChanged: _onCategoryPageChanged,
                    itemBuilder: (context, page) {
                      final category = _visibleCategories[page % _visibleCategories.length];
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
      bottomNavigationBar: _visibleCategories.isEmpty
          ? null
          : ColoredBox(
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
                            for (var i = 0; i < _visibleCategories.length; i++)
                              Padding(
                                padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                                child: _CategoryPill(
                                  label: _visibleCategories[i].label,
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
