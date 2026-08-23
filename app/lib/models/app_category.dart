class AppCategory {
  final String key;
  final String label;

  const AppCategory({required this.key, required this.label});

  @override
  bool operator ==(Object other) =>
      other is AppCategory && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);
}
