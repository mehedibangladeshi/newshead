import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data/article_cache.dart';
import 'data/article_repository.dart';
import 'models/news_article.dart';
import 'screens/home_screen.dart';

final Uri kArticlesUrl = Uri.parse('https://mehedibangladeshi.github.io/newshead/articles.json');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final documentsDir = await getApplicationDocumentsDirectory();
  final cache = FileArticleCache('${documentsDir.path}/articles_cache.json');

  final articles = await fetchArticles(
    sourceUrl: kArticlesUrl,
    client: http.Client(),
    cache: cache,
  );

  runApp(NewsHeadApp(articles: articles));
}

class NewsHeadApp extends StatelessWidget {
  final List<NewsArticle> articles;

  const NewsHeadApp({super.key, required this.articles});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHead',
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      home: HomeScreen(articles: articles),
    );
  }
}
