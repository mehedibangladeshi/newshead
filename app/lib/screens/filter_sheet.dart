import 'package:flutter/material.dart';

import '../models/app_category.dart';
import '../models/filter_option.dart';
import '../theme/app_theme.dart';

/// Opens the combined Category/Language/Source filter as a modal bottom
/// sheet. Always lists every fetched option per dimension (not just the
/// currently-visible ones) — see this feature's plan for why: it's a stable
/// settings surface, not a live view, and an option with zero stories today
/// can still be pre-picked for whenever it next has one.
Future<void> showFilterSheet({
  required BuildContext context,
  required List<AppCategory> allCategories,
  required Set<String> excludedCategoryKeys,
  required void Function(String categoryKey, bool isChecked) onToggleCategory,
  required List<FilterOption> allLanguages,
  required Set<String> excludedLanguageKeys,
  required void Function(String languageKey, bool isChecked) onToggleLanguage,
  required List<FilterOption> allSources,
  required Set<String> excludedSourceKeys,
  required void Function(String sourceKey, bool isChecked) onToggleSource,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => FilterSheet(
      allCategories: allCategories,
      excludedCategoryKeys: excludedCategoryKeys,
      onToggleCategory: onToggleCategory,
      allLanguages: allLanguages,
      excludedLanguageKeys: excludedLanguageKeys,
      onToggleLanguage: onToggleLanguage,
      allSources: allSources,
      excludedSourceKeys: excludedSourceKeys,
      onToggleSource: onToggleSource,
    ),
  );
}

class FilterSheet extends StatefulWidget {
  final List<AppCategory> allCategories;
  final Set<String> excludedCategoryKeys;
  final void Function(String categoryKey, bool isChecked) onToggleCategory;
  final List<FilterOption> allLanguages;
  final Set<String> excludedLanguageKeys;
  final void Function(String languageKey, bool isChecked) onToggleLanguage;
  final List<FilterOption> allSources;
  final Set<String> excludedSourceKeys;
  final void Function(String sourceKey, bool isChecked) onToggleSource;

  const FilterSheet({
    super.key,
    required this.allCategories,
    required this.excludedCategoryKeys,
    required this.onToggleCategory,
    required this.allLanguages,
    required this.excludedLanguageKeys,
    required this.onToggleLanguage,
    required this.allSources,
    required this.excludedSourceKeys,
    required this.onToggleSource,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Set<String> _excludedCategoryKeys;
  late Set<String> _excludedLanguageKeys;
  late Set<String> _excludedSourceKeys;

  @override
  void initState() {
    super.initState();
    _excludedCategoryKeys = {...widget.excludedCategoryKeys};
    _excludedLanguageKeys = {...widget.excludedLanguageKeys};
    _excludedSourceKeys = {...widget.excludedSourceKeys};
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
              "Unchecked options are hidden right away. Your picks stay put next time you open the app.",
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ..._sectionTiles(
                    heading: 'Category',
                    options: [for (final c in widget.allCategories) (key: c.key, label: c.label)],
                    excludedKeys: _excludedCategoryKeys,
                    onToggle: (key, isChecked) {
                      setState(() {
                        if (isChecked) {
                          _excludedCategoryKeys.remove(key);
                        } else {
                          _excludedCategoryKeys.add(key);
                        }
                      });
                      widget.onToggleCategory(key, isChecked);
                    },
                  ),
                  ..._sectionTiles(
                    heading: 'Language',
                    options: [for (final l in widget.allLanguages) (key: l.key, label: l.label)],
                    excludedKeys: _excludedLanguageKeys,
                    onToggle: (key, isChecked) {
                      setState(() {
                        if (isChecked) {
                          _excludedLanguageKeys.remove(key);
                        } else {
                          _excludedLanguageKeys.add(key);
                        }
                      });
                      widget.onToggleLanguage(key, isChecked);
                    },
                  ),
                  ..._sectionTiles(
                    heading: 'Source',
                    options: [for (final s in widget.allSources) (key: s.key, label: s.label)],
                    excludedKeys: _excludedSourceKeys,
                    onToggle: (key, isChecked) {
                      setState(() {
                        if (isChecked) {
                          _excludedSourceKeys.remove(key);
                        } else {
                          _excludedSourceKeys.add(key);
                        }
                      });
                      widget.onToggleSource(key, isChecked);
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

  List<Widget> _sectionTiles({
    required String heading,
    required List<({String key, String label})> options,
    required Set<String> excludedKeys,
    required void Function(String key, bool isChecked) onToggle,
  }) {
    if (options.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          heading,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      for (final option in options)
        CheckboxListTile(
          value: !excludedKeys.contains(option.key),
          title: Text(option.label, style: const TextStyle(color: AppColors.textPrimary)),
          activeColor: AppColors.accent,
          controlAffinity: ListTileControlAffinity.trailing,
          onChanged: (checked) => onToggle(option.key, checked ?? true),
        ),
    ];
  }
}
