import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data/article_cache.dart';
import 'data/article_repository.dart';
import 'data/filter_store.dart';
import 'models/app_category.dart';
import 'models/filter_option.dart';
import 'models/news_article.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

final Uri kArticlesUrl = Uri.parse('https://mehedibangladeshi.github.io/newshead/articles.json');

// NetworkImage has no connect timeout by default, so a black-holed
// connection (packets dropped, no response, no RST) hangs indefinitely —
// the article's image never loads and never surfaces the widget's own
// broken-image fallback for the rest of the app session. Bounding the
// connect phase lets a stuck request fail and free its ImageCache slot for
// a retry on the next rebuild.
class _TimeoutHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 15);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TimeoutHttpOverrides();
  SystemChrome.setSystemUIOverlayStyle(kSystemOverlayStyle);

  final documentsDir = await getApplicationDocumentsDirectory();
  final cache = FileArticleCache('${documentsDir.path}/articles_cache.json');
  final client = http.Client();
  final categoryFilterStore = SharedPreferencesFilterStore(prefKey: kExcludedCategoryKeysPrefKey);
  final languageFilterStore = SharedPreferencesFilterStore(prefKey: kExcludedLanguageKeysPrefKey);
  final sourceFilterStore = SharedPreferencesFilterStore(prefKey: kExcludedSourceKeysPrefKey);

  final result = await fetchArticles(
    sourceUrl: kArticlesUrl,
    client: client,
    cache: cache,
  );

  runApp(NewsHeadApp(
    initialArticles: result.articles,
    initialCategories: result.categories,
    initialLanguages: result.languages,
    initialSources: result.sources,
    initialRawBody: result.rawBody,
    sourceUrl: kArticlesUrl,
    client: client,
    cache: cache,
    categoryFilterStore: categoryFilterStore,
    languageFilterStore: languageFilterStore,
    sourceFilterStore: sourceFilterStore,
  ));
}

class NewsHeadApp extends StatelessWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final List<FilterOption> initialLanguages;
  final List<FilterOption> initialSources;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;
  final FilterStore categoryFilterStore;
  final FilterStore languageFilterStore;
  final FilterStore sourceFilterStore;

  const NewsHeadApp({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialLanguages,
    required this.initialSources,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
    required this.categoryFilterStore,
    required this.languageFilterStore,
    required this.sourceFilterStore,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHead',
      theme: buildAppTheme(),
      home: HomeScreen(
        initialArticles: initialArticles,
        initialCategories: initialCategories,
        initialLanguages: initialLanguages,
        initialSources: initialSources,
        initialRawBody: initialRawBody,
        sourceUrl: sourceUrl,
        client: client,
        cache: cache,
        categoryFilterStore: categoryFilterStore,
        languageFilterStore: languageFilterStore,
        sourceFilterStore: sourceFilterStore,
      ),
    );
  }
}
