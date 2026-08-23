import 'package:shared_preferences/shared_preferences.dart';

/// The reader's category filter choice, stored as the set of *excluded*
/// category keys — never the checked ones. See CONTEXT.md's "Visible
/// Category" entry for why: an empty store means everything is checked,
/// and a category the store has never seen defaults to visible.
abstract class CategoryFilterStore {
  Future<Set<String>> readExcludedKeys();
  Future<void> writeExcludedKeys(Set<String> keys);
}

const _kExcludedCategoryKeysPref = 'excluded_category_keys';

class SharedPreferencesCategoryFilterStore implements CategoryFilterStore {
  @override
  Future<Set<String>> readExcludedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kExcludedCategoryKeysPref) ?? const []).toSet();
  }

  @override
  Future<void> writeExcludedKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kExcludedCategoryKeysPref, keys.toList());
  }
}
