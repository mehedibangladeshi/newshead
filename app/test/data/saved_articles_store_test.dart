import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/saved_articles_store.dart';
import 'package:newshead/models/news_article.dart';
import 'package:shared_preferences/shared_preferences.dart';

NewsArticle _a(String id) => NewsArticle(
  id: id, category: 'main', source: 's', headline: 'h$id', snippet: '',
  imageUrl: 'i', articleUrl: 'u',
);

void main() {
  const store = SharedPreferencesSavedArticlesStore();

  test('empty by default', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await store.readSaved(), isEmpty);
  });

  test('round-trips in order', () async {
    SharedPreferences.setMockInitialValues({});
    await store.writeSaved([_a('2'), _a('1')]);
    expect((await store.readSaved()).map((a) => a.id), ['2', '1']);
  });

  test('skips malformed entries', () async {
    SharedPreferences.setMockInitialValues({
      kSavedArticlesPref: ['not json', '{"id":1}', '{"id":"ok","category":"c","source":"s","headline":"h","imageUrl":"i","articleUrl":"u"}'],
    });
    expect((await store.readSaved()).map((a) => a.id), ['ok']);
  });
}
