import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newshead/data/category_filter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('readExcludedKeys returns an empty set when nothing is stored', () async {
    final store = SharedPreferencesCategoryFilterStore();
    expect(await store.readExcludedKeys(), isEmpty);
  });

  test('writeExcludedKeys then readExcludedKeys round-trips the same set', () async {
    final store = SharedPreferencesCategoryFilterStore();
    await store.writeExcludedKeys({'sports', 'entertainment'});
    expect(await store.readExcludedKeys(), {'sports', 'entertainment'});
  });

  test('writeExcludedKeys with an empty set clears previously stored keys', () async {
    final store = SharedPreferencesCategoryFilterStore();
    await store.writeExcludedKeys({'sports'});
    await store.writeExcludedKeys({});
    expect(await store.readExcludedKeys(), isEmpty);
  });
}
