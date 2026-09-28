import '../models/news_article.dart';

bool matchesQuery(NewsArticle article, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  return article.headline.toLowerCase().contains(q) ||
      article.snippet.toLowerCase().contains(q);
}
