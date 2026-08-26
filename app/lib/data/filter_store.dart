import 'package:shared_preferences/shared_preferences.dart';

/// The reader's filter choice for one filter dimension (category, language,
/// or source), stored as the set of *excluded* keys — never the checked
/// ones. See CONTEXT.md's "Visible Category" entry for why: an empty store
/// means everything is checked, and a key the store has never seen defaults
/// to visible.
abstract class FilterStore {
  Future<Set<String>> readExcludedKeys();
  Future<void> writeExcludedKeys(Set<String> keys);
}

class SharedPreferencesFilterStore implements FilterStore {
  final String prefKey;

  const SharedPreferencesFilterStore({required this.prefKey});

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

const kExcludedCategoryKeysPrefKey = 'excluded_category_keys';
const kExcludedLanguageKeysPrefKey = 'excluded_language_keys';
const kExcludedSourceKeysPrefKey = 'excluded_source_keys';
