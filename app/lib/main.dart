import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data/article_cache.dart';
import 'data/article_repository.dart';
import 'models/app_category.dart';
import 'models/news_article.dart';
import 'screens/home_screen.dart';

final Uri kArticlesUrl = Uri.parse('https://mehedibangladeshi.github.io/newshead/articles.json');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final documentsDir = await getApplicationDocumentsDirectory();
  final cache = FileArticleCache('${documentsDir.path}/articles_cache.json');
  final client = http.Client();

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
  ));
}

class NewsHeadApp extends StatelessWidget {
  final List<NewsArticle> initialArticles;
  final List<AppCategory> initialCategories;
  final String? initialRawBody;
  final Uri sourceUrl;
  final http.Client client;
  final ArticleCache cache;

  const NewsHeadApp({
    super.key,
    required this.initialArticles,
    required this.initialCategories,
    required this.initialRawBody,
    required this.sourceUrl,
    required this.client,
    required this.cache,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHead',
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      home: HomeScreen(
        initialArticles: initialArticles,
        initialCategories: initialCategories,
        initialRawBody: initialRawBody,
        sourceUrl: sourceUrl,
        client: client,
        cache: cache,
      ),
    );
  }
}
