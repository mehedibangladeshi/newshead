import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newshead/data/filter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('readExcludedKeys returns an empty set when nothing is stored', () async {
    final store = SharedPreferencesFilterStore(prefKey: 'excluded_category_keys');
    expect(await store.readExcludedKeys(), isEmpty);
  });

  test('writeExcludedKeys then readExcludedKeys round-trips the same set', () async {
    final store = SharedPreferencesFilterStore(prefKey: 'excluded_category_keys');
    await store.writeExcludedKeys({'sports', 'entertainment'});
    expect(await store.readExcludedKeys(), {'sports', 'entertainment'});
  });

  test('writeExcludedKeys with an empty set clears previously stored keys', () async {
    final store = SharedPreferencesFilterStore(prefKey: 'excluded_category_keys');
    await store.writeExcludedKeys({'sports'});
    await store.writeExcludedKeys({});
    expect(await store.readExcludedKeys(), isEmpty);
  });

  test('two stores with different pref keys do not share state', () async {
    final categoryStore = SharedPreferencesFilterStore(prefKey: 'excluded_category_keys');
    final languageStore = SharedPreferencesFilterStore(prefKey: 'excluded_language_keys');

    await categoryStore.writeExcludedKeys({'sports'});
    await languageStore.writeExcludedKeys({'bn'});

    expect(await categoryStore.readExcludedKeys(), {'sports'});
    expect(await languageStore.readExcludedKeys(), {'bn'});
  });
}
