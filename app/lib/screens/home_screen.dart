import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/article_cache.dart';
import '../data/article_repository.dart';
import '../data/article_search.dart';
import '../data/auto_scroll.dart';
import '../data/category_filter_store.dart';
import '../data/category_visibility.dart';
import '../data/saved_articles_store.dart';
import '../models/app_category.dart';
import '../models/news_article.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/empty_state.dart';
import 'category_feed.dart';
import 'category_filter_sheet.dart';
import 'saved_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final bool initialFromNetwork;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;
  final ExcludedKeysStore filterStore;
  final ExcludedKeysStore sourceFilterStore;
  final ExcludedKeysStore languageFilterStore;
  final SavedArticlesStore savedStore;
  final AutoScrollStore autoScrollStore;
  // Injectable clock so the resume-staleness check is testable.
  final DateTime Function() now;

  const HomeScreen({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.initialFromNetwork,
    required this.sourceUrl,
    required this.client,
    required this.cache,
    required this.filterStore,
    required this.sourceFilterStore,
    required this.languageFilterStore,
    required this.savedStore,
    required this.autoScrollStore,
    this.now = DateTime.now,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
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
  // One key per visible pill, used to scroll the newly-selected pill into
  // view (see _onTabIndexChangedForPillBar). Rebuilt alongside the
  // TabController/PageController whenever the visible-category count
  // changes.
  late List<GlobalKey> _pillKeys;
  // Tracks the last tab index we already reacted to, so the pill-scroll
  // listener (which fires on every TabController notification, including
  // the extra one when an animateTo settles) only acts once per genuine
  // index change.
  int? _lastPillScrollIndex;
  bool _isRefreshing = false;
  DateTime? _lastFetchedAt;
  static const _staleAfter = Duration(minutes: 30);

  late List<NewsArticle> _articles;
  late List<AppCategory> _categories;
  Set<String> _excludedCategoryKeys = {};
  Set<String> _excludedSourceKeys = {};
  Set<String> _excludedLanguageKeys = {};
  // Newest-saved first.
  List<NewsArticle> _saved = [];
  bool _autoScroll = false;
  late List<AppCategory> _visibleCategories;
  late bool _isOffline;
  String? _lastRawBody;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  // Bumped on every successful refresh so each CategoryFeed remounts fresh
  // (fresh PageController at the first article) instead of keeping its old
  // scroll position over reordered/changed content.
  int _refreshGeneration = 0;
  bool _overlayOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _articles = widget.initialArticles;
    _categories = widget.initialCategories;
    _lastRawBody = widget.initialRawBody;
    _isOffline = widget.initialArticles.isEmpty && !widget.initialFromNetwork;
    _visibleCategories = visibleCategories(
      fetchedCategories: _categories,
      articles: _articles,
      excludedKeys: _excludedCategoryKeys,
    );
    _initControllers(_visibleCategories.length);
    if (widget.initialFromNetwork) {
      _lastFetchedAt = widget.now();
    } else {
      // Cache-only cold start: the cache file's age is when we last fetched.
      widget.cache.savedAt().then((t) {
        if (mounted && _lastFetchedAt == null) setState(() => _lastFetchedAt = t);
      });
    }
    _loadExcludedCategoryKeys();
    _loadExcludedSourceKeys();
    _loadExcludedLanguageKeys();
    _loadSaved();
    widget.autoScrollStore.readEnabled().then((v) {
      if (mounted) setState(() => _autoScroll = v);
    });
  }

  Future<void> _loadSaved() async {
    final stored = await widget.savedStore.readSaved();
    if (!mounted) return;
    setState(() => _saved = stored);
  }

  bool _isSaved(NewsArticle a) => _saved.any((s) => s.id == a.id);

  void _toggleSaved(NewsArticle a) {
    final index = _saved.indexWhere((s) => s.id == a.id);
    final saved = index < 0;
    setState(() {
      if (saved) {
        _saved = [a, ..._saved];
      } else {
        _saved = _saved.where((s) => s.id != a.id).toList();
      }
    });
    widget.savedStore.writeSaved(_saved);
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2500),
        persist: false,
        content: Row(children: [
          Icon(
            saved ? Icons.bookmark : Icons.bookmark_remove_outlined,
            size: 18,
            color: saved ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(saved ? 'Saved' : 'Removed from saved')),
        ]),
        action: saved
            ? SnackBarAction(label: 'VIEW', onPressed: _openSaved)
            : SnackBarAction(label: 'UNDO', onPressed: () => _restoreSaved(a, index)),
      ));
  }

  void _toggleAutoScroll() {
    setState(() => _autoScroll = !_autoScroll);
    widget.autoScrollStore.writeEnabled(_autoScroll);
  }

  void _removeSaved(NewsArticle a) {
    setState(() => _saved = _saved.where((s) => s.id != a.id).toList());
    widget.savedStore.writeSaved(_saved);
  }

  void _restoreSaved(NewsArticle a, int index) {
    if (_isSaved(a)) return;
    setState(() => _saved = [..._saved]..insert(index.clamp(0, _saved.length), a));
    widget.savedStore.writeSaved(_saved);
  }

  Future<void> _openSaved() async {
    setState(() => _overlayOpen = true);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SavedScreen(
        initialSaved: _saved,
        onRemove: _removeSaved,
        onRestore: _restoreSaved,
      ),
    ));
    if (mounted) setState(() => _overlayOpen = false);
  }

  Future<void> _loadExcludedCategoryKeys() async {
    final stored = await widget.filterStore.readExcludedKeys();
    if (!mounted) return;
    _applyExcludedKeys(stored);
  }

  Future<void> _loadExcludedSourceKeys() async {
    final stored = await widget.sourceFilterStore.readExcludedKeys();
    if (!mounted) return;
    setState(() {
      _excludedSourceKeys = stored;
    });
  }

  Future<void> _loadExcludedLanguageKeys() async {
    final stored = await widget.languageFilterStore.readExcludedKeys();
    if (!mounted) return;
    setState(() {
      _excludedLanguageKeys = stored;
    });
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

  void _handleSourceFilterToggle(String sourceKey, bool isChecked) {
    final next = {..._excludedSourceKeys};
    if (isChecked) {
      next.remove(sourceKey);
    } else {
      next.add(sourceKey);
    }
    setState(() {
      _excludedSourceKeys = next;
    });
    widget.sourceFilterStore.writeExcludedKeys(next);
  }

  void _handleLanguageFilterToggle(String languageKey, bool isChecked) {
    final next = {..._excludedLanguageKeys};
    if (isChecked) {
      next.remove(languageKey);
    } else {
      next.add(languageKey);
    }
    setState(() {
      _excludedLanguageKeys = next;
    });
    widget.languageFilterStore.writeExcludedKeys(next);
  }

  Future<void> _openFilterSheet() async {
    setState(() => _overlayOpen = true);
    await showCategoryFilterSheet(
      context: context,
      allCategories: _categories,
      excludedKeys: _excludedCategoryKeys,
      onToggle: _handleFilterToggle,
      allSources: visibleValues(
        fetchedArticles: _articles,
        keyOf: (a) => a.source,
        excludedKeys: const {},
      ),
      excludedSourceKeys: _excludedSourceKeys,
      onSourceToggle: _handleSourceFilterToggle,
      allLanguages: visibleValues(
        fetchedArticles: _articles,
        keyOf: (a) => a.language,
        excludedKeys: const {},
      ),
      excludedLanguageKeys: _excludedLanguageKeys,
      onLanguageToggle: _handleLanguageFilterToggle,
      lastUpdated: _lastFetchedAt,
      onRefresh: () => _handleRefresh(),
    );
    if (mounted) setState(() => _overlayOpen = false);
  }

  void _initControllers(int n) {
    _tabController = TabController(length: n, vsync: this);
    _categoryPageController = PageController(
      initialPage: n == 0 ? 0 : (_kLargePageBase ~/ n) * n,
    );
    _pillKeys = List.generate(n, (_) => GlobalKey());
    _lastPillScrollIndex = null;
    _tabController.addListener(_onTabChanged);
    _tabController.addListener(_onTabIndexChangedForPillBar);
  }

  void _disposeControllers() {
    _tabController.removeListener(_onTabChanged);
    _tabController.removeListener(_onTabIndexChangedForPillBar);
    _tabController.dispose();
    _categoryPageController.dispose();
  }

  // Fires on every TabController notification (both a pill tap's animateTo
  // and a swipe's direct `_tabController.index = ...` assignment in
  // _onCategoryPageChanged) and, on a genuine index change, scrolls the
  // newly-selected pill into view within the horizontal pill bar.
  void _onTabIndexChangedForPillBar() {
    final index = _tabController.index;
    if (_lastPillScrollIndex == index) return;
    _lastPillScrollIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _pillKeys.length) return;
      final pillContext = _pillKeys[index].currentContext;
      if (pillContext == null) return;
      Scrollable.ensureVisible(
        pillContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _isRefreshing) return;
    final t = _lastFetchedAt;
    if (t == null || widget.now().difference(t) > _staleAfter) {
      _handleRefresh(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeControllers();
    _searchController.dispose();
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
    // Re-derive each feed's isActive.
    setState(() {});
  }

  // Pulled from any category feed. Re-fetches from the shared source; if the
  // server returned byte-identical content to last time (nothing new to
  // show), the order is shuffled per category so the pull still visibly
  // "does something" instead of looking like a no-op.
  Future<bool> _handleRefresh({bool silent = false}) async {
    setState(() {
      _isRefreshing = true;
    });
    try {
      final result = await fetchArticles(
        sourceUrl: widget.sourceUrl,
        client: widget.client,
        cache: widget.cache,
      );

      if (!result.fromNetwork) {
        if (mounted && !silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not refresh — check your connection'),
            ),
          );
        }
        return false;
      }

      var articles = result.articles;
      if (result.rawBody == _lastRawBody) {
        articles = articles.toList()..shuffle();
      }

      if (!mounted) return true;
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
        _isOffline = false;
        _lastFetchedAt = widget.now();
        if (nextVisible.length != _visibleCategories.length) {
          _disposeControllers();
          _initControllers(nextVisible.length);
        }
        _visibleCategories = nextVisible;
      });
      return true;
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _isOffline || _visibleCategories.isEmpty || _isSearching
          ? null
          : _AutoScrollPill(on: _autoScroll, onTap: _toggleAutoScroll),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: AppColors.background,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _isSearching
                      ? [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: 'Search articles',
                                border: InputBorder.none,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: _closeSearch,
                            icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          ),
                        ]
                      : [
                          const BrandMark(),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _openSearch,
                                icon: const Icon(Icons.search, color: AppColors.textSecondary),
                              ),
                              IconButton(
                                onPressed: _openFilterSheet,
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(Icons.tune, color: AppColors.textSecondary),
                                    if (_excludedCategoryKeys.isNotEmpty ||
                                        _excludedSourceKeys.isNotEmpty ||
                                        _excludedLanguageKeys.isNotEmpty)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          key: const Key('filterActiveBadge'),
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: const Key('savedButton'),
                                tooltip: 'Saved',
                                onPressed: _openSaved,
                                icon: const Icon(Icons.bookmark_border, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _isOffline
                ? _OfflineState(onRetry: _handleRefresh)
                : _visibleCategories.isEmpty
                ? EmptyState(hasActiveFilters: _excludedCategoryKeys.isNotEmpty)
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
                      final visibleSourceKeys = visibleValues(
                        fetchedArticles: _articles,
                        keyOf: (a) => a.source,
                        excludedKeys: _excludedSourceKeys,
                      ).toSet();
                      final visibleLanguageKeys = visibleValues(
                        fetchedArticles: _articles,
                        keyOf: (a) => a.language,
                        excludedKeys: _excludedLanguageKeys,
                      ).toSet();
                      return CategoryFeed(
                        key: PageStorageKey('${category.key}#$_refreshGeneration'),
                        category: category.key,
                        isSaved: _isSaved,
                        onToggleSave: _toggleSaved,
                        autoScroll: _autoScroll && !_overlayOpen,
                        isActive: page % _visibleCategories.length == _tabController.index,
                        hasActiveFilters: _excludedSourceKeys.isNotEmpty ||
                            _excludedLanguageKeys.isNotEmpty ||
                            _searchQuery.isNotEmpty,
                        articles: articlesForCategory(_articles, category.key)
                            .where((a) => visibleSourceKeys.contains(a.source))
                            .where((a) => visibleLanguageKeys.contains(a.language))
                            .where((a) => matchesQuery(a, _searchQuery))
                            .toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _isOffline || _visibleCategories.isEmpty
          ? null
          : ColoredBox(
              color: AppColors.background,
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
                                key: _pillKeys[i],
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

class _AutoScrollPill extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _AutoScrollPill({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: on ? 'Stop auto-scroll' : 'Start auto-scroll',
      excludeSemantics: true,
      child: Tooltip(
        message: on ? 'Stop auto-scroll' : 'Start auto-scroll',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('autoScrollButton'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: ShapeDecoration(
                    shape: CircleBorder(
                      side: BorderSide(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    color: Colors.black.withValues(alpha: 0.15),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Icon(
                      on ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey<bool>(on),
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _OfflineState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "You're offline",
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check your connection and try again.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
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
          style:
              AppColors.pillLabelStyle.copyWith(
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
