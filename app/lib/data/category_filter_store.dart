import 'package:shared_preferences/shared_preferences.dart';

/// A reader filter choice, stored as the set of *excluded* keys — never the
/// checked ones. See CONTEXT.md's "Visible Category" entry for why: an
/// empty store means everything is checked, and a key the store has never
/// seen defaults to visible.
abstract class ExcludedKeysStore {
  Future<Set<String>> readExcludedKeys();
  Future<void> writeExcludedKeys(Set<String> keys);
}

class SharedPreferencesKeySetStore implements ExcludedKeysStore {
  const SharedPreferencesKeySetStore(this.prefKey);

  final String prefKey;

  @override
  Future<Set<String>> readExcludedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(prefKey) ?? const []).toSet();
  }

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefKey, keys.toList());
  }
}

const kExcludedCategoryKeysPref = 'excluded_category_keys';
const kExcludedSourceKeysPref = 'excluded_source_keys';
const kExcludedLanguageKeysPref = 'excluded_language_keys';
