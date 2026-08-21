import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'data/article_repository.dart';
import 'models/news_article.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<NewsArticle> articles = [];
  try {
    final jsonString = await rootBundle.loadString('assets/articles.json');
    articles = parseArticles(jsonString);
  } catch (e) {
    debugPrint('Failed to load articles.json: $e');
    articles = [];
  }

  runApp(NewsReelsApp(articles: articles));
}

class NewsReelsApp extends StatelessWidget {
  final List<NewsArticle> articles;

  const NewsReelsApp({super.key, required this.articles});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Reels Prototype',
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      home: HomeScreen(articles: articles),
    );
  }
}
