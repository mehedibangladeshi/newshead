import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data/article_cache.dart';
import 'data/article_repository.dart';
import 'data/category_filter_store.dart';
import 'models/app_category.dart';
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
  final filterStore = SharedPreferencesCategoryFilterStore();

  final result = await fetchArticles(
    sourceUrl: kArticlesUrl,
    client: client,
    cache: cache,
  );

  runApp(NewsHeadApp(
    initialArticles: result.articles,
    initialCategories: result.categories,
    initialRawBody: result.rawBody,
    sourceUrl: kArticlesUrl,
    client: client,
    cache: cache,
    filterStore: filterStore,
  ));
}

class NewsHeadApp extends StatelessWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;
  final CategoryFilterStore filterStore;

  const NewsHeadApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHead',
      theme: buildAppTheme(),
      home: HomeScreen(
        initialArticles: initialArticles,
        initialCategories: initialCategories,
        initialRawBody: initialRawBody,
        sourceUrl: sourceUrl,
        client: client,
        cache: cache,
        filterStore: filterStore,
      ),
    );
  }
}
