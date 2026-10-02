import 'package:flutter/material.dart';

import '../models/app_category.dart';
import '../theme/app_theme.dart';

/// Maps a stored language code to its display label. UI-layer concern only —
/// the data layer (category_visibility.dart) deals in raw codes.
String languageLabel(String code) {
  switch (code) {
    case 'bn':
      return 'Bangla';
    case 'en':
    default:
      return 'English';
  }
}

/// Opens the combined category/source/language filter as a modal bottom
/// sheet. Always lists every fetched category/source/language (not just the
/// currently-visible ones) — see this feature's plan for why: it's a stable
/// settings surface, not a live view, and an item with zero stories today
/// can still be pre-picked for whenever it next has one.
Future<void> showCategoryFilterSheet({
  required BuildContext context,
  required List<AppCategory> allCategories,
  required Set<String> excludedKeys,
  required void Function(String categoryKey, bool isChecked) onToggle,
  required List<String> allSources,
  required Set<String> excludedSourceKeys,
  required void Function(String sourceKey, bool isChecked) onSourceToggle,
  required List<String> allLanguages,
  required Set<String> excludedLanguageKeys,
  required void Function(String languageKey, bool isChecked) onLanguageToggle,
  DateTime? lastUpdated,
  Future<bool> Function()? onRefresh,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => CategoryFilterSheet(
      allCategories: allCategories,
      excludedKeys: excludedKeys,
      onToggle: onToggle,
      allSources: allSources,
      excludedSourceKeys: excludedSourceKeys,
      onSourceToggle: onSourceToggle,
      allLanguages: allLanguages,
      excludedLanguageKeys: excludedLanguageKeys,
      onLanguageToggle: onLanguageToggle,
      lastUpdated: lastUpdated,
      onRefresh: onRefresh,
    ),
  );
}

String _updatedLabel(DateTime? t) {
  if (t == null) return 'Not updated yet';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Updated just now';
  if (d.inMinutes < 60) return 'Updated ${d.inMinutes}m ago';
  if (d.inHours < 24) return 'Updated ${d.inHours}h ago';
  return 'Updated ${d.inDays}d ago';
}

class CategoryFilterSheet extends StatefulWidget {
  final List<AppCategory> allCategories;
  final Set<String> excludedKeys;
  final void Function(String categoryKey, bool isChecked) onToggle;
  final List<String> allSources;
  final Set<String> excludedSourceKeys;
  final void Function(String sourceKey, bool isChecked) onSourceToggle;
  final List<String> allLanguages;
  final Set<String> excludedLanguageKeys;
  final void Function(String languageKey, bool isChecked) onLanguageToggle;
  final DateTime? lastUpdated;
  // Resolves true when fresh data came from the network.
  final Future<bool> Function()? onRefresh;

  const CategoryFilterSheet({
    super.key,
    this.lastUpdated,
    this.onRefresh,
    required this.allCategories,
    required this.excludedKeys,
    required this.onToggle,
    required this.allSources,
    required this.excludedSourceKeys,
    required this.onSourceToggle,
    required this.allLanguages,
    required this.excludedLanguageKeys,
    required this.onLanguageToggle,
  });

  @override
  State<CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<CategoryFilterSheet> {
  late Set<String> _excludedKeys;
  late Set<String> _excludedSourceKeys;
  late Set<String> _excludedLanguageKeys;
  bool _refreshing = false;
  DateTime? _justRefreshed;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      if (await widget.onRefresh!()) _justRefreshed = DateTime.now();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _excludedKeys = {...widget.excludedKeys};
    _excludedSourceKeys = {...widget.excludedSourceKeys};
    _excludedLanguageKeys = {...widget.excludedLanguageKeys};
  }

  Widget _refreshRow() {
    const accent = AppColors.accent;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _updatedLabel(_justRefreshed ?? widget.lastUpdated),
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            key: const Key('sheetRefreshButton'),
            onPressed: _refreshing ? null : _refresh,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: _refreshing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(_refreshing ? 'Refreshing…' : 'Refresh'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const Text(
              'Filter your feed',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "Unchecked items are hidden right away. Your picks stay put next time you open the app.",
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11.5),
            ),
            if (widget.onRefresh != null) _refreshRow(),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _FilterSection(
                    label: 'Categories',
                    initiallyExpanded: true,
                    itemKeys: [for (final c in widget.allCategories) c.key],
                    itemLabels: {for (final c in widget.allCategories) c.key: c.label},
                    excludedKeys: _excludedKeys,
                    onToggle: (key, isChecked) {
                      setState(() {
                        if (isChecked) {
                          _excludedKeys.remove(key);
                        } else {
                          _excludedKeys.add(key);
                        }
                      });
                      widget.onToggle(key, isChecked);
                    },
                  ),
                  const SizedBox(height: 14),
                  _FilterSection(
                    label: 'Language',
                    itemKeys: widget.allLanguages,
                    itemLabels: {for (final l in widget.allLanguages) l: languageLabel(l)},
                    excludedKeys: _excludedLanguageKeys,
                    onToggle: (key, isChecked) {
                      setState(() {
                        if (isChecked) {
                          _excludedLanguageKeys.remove(key);
                        } else {
                          _excludedLanguageKeys.add(key);
                        }
                      });
                      widget.onLanguageToggle(key, isChecked);
                    },
                  ),
                  const SizedBox(height: 14),
                  _FilterSection(
                    label: 'Sources',
                    itemKeys: widget.allSources,
                    itemLabels: {for (final s in widget.allSources) s: s},
                    excludedKeys: _excludedSourceKeys,
                    onToggle: (key, isChecked) {
                      setState(() {
                        if (isChecked) {
                          _excludedSourceKeys.remove(key);
                        } else {
                          _excludedSourceKeys.add(key);
                        }
                      });
                      widget.onSourceToggle(key, isChecked);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One collapsible checkbox-list section shared by the Categories/Sources/
/// Language sections above. `itemKeys` is the stable identity used for
/// exclusion tracking; `itemLabels` maps each key to its display text.
class _FilterSection extends StatelessWidget {
  final String label;
  final bool initiallyExpanded;
  final List<String> itemKeys;
  final Map<String, String> itemLabels;
  final Set<String> excludedKeys;
  final void Function(String key, bool isChecked) onToggle;

  const _FilterSection({
    required this.label,
    this.initiallyExpanded = false,
    required this.itemKeys,
    required this.itemLabels,
    required this.excludedKeys,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (itemKeys.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      children: [
        for (final key in itemKeys)
          CheckboxListTile(
            value: !excludedKeys.contains(key),
            title: Text(itemLabels[key] ?? key, style: const TextStyle(color: AppColors.textPrimary)),
            activeColor: AppColors.accent,
            controlAffinity: ListTileControlAffinity.trailing,
            onChanged: (checked) => onToggle(key, checked ?? true),
          ),
      ],
    );
  }
}
