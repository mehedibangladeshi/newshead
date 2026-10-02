import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_article.dart';

abstract class SavedArticlesStore {
  /// Newest-saved first.
  Future<List<NewsArticle>> readSaved();
  Future<void> writeSaved(List<NewsArticle> articles);
}

class SharedPreferencesSavedArticlesStore implements SavedArticlesStore {
  const SharedPreferencesSavedArticlesStore();

  @override
  Future<List<NewsArticle>> readSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = <NewsArticle>[];
    for (final raw in prefs.getStringList(kSavedArticlesPref) ?? const <String>[]) {
      try {
        saved.add(NewsArticle.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return saved;
  }

  @override
  Future<void> writeSaved(List<NewsArticle> articles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      kSavedArticlesPref,
      articles.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }
}

const kSavedArticlesPref = 'saved_articles';
