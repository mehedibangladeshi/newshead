/// A selectable (key, label) pair for a filter dimension other than
/// category — e.g. one entry in the Language or Source filter list.
class FilterOption {
  final String key;
  final String label;

  const FilterOption({required this.key, required this.label});

  @override
  bool operator ==(Object other) =>
      other is FilterOption && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);
}
