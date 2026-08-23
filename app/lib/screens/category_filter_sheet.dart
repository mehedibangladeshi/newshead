import 'package:flutter/material.dart';

import '../models/app_category.dart';

/// Opens the category filter as a modal bottom sheet. Always lists every
/// fetched category (not just the currently-visible ones) — see this
/// feature's plan for why: it's a stable settings surface, not a live
/// view, and a category with zero stories today can still be pre-picked
/// for whenever it next has one.
Future<void> showCategoryFilterSheet({
  required BuildContext context,
  required List<AppCategory> allCategories,
  required Set<String> excludedKeys,
  required void Function(String categoryKey, bool isChecked) onToggle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF171310),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => CategoryFilterSheet(
      allCategories: allCategories,
      excludedKeys: excludedKeys,
      onToggle: onToggle,
    ),
  );
}

class CategoryFilterSheet extends StatefulWidget {
  final List<AppCategory> allCategories;
  final Set<String> excludedKeys;
  final void Function(String categoryKey, bool isChecked) onToggle;

  const CategoryFilterSheet({
    super.key,
    required this.allCategories,
    required this.excludedKeys,
    required this.onToggle,
  });

  @override
  State<CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<CategoryFilterSheet> {
  late Set<String> _excludedKeys;

  @override
  void initState() {
    super.initState();
    _excludedKeys = {...widget.excludedKeys};
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
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const Text(
              'Filter your feed',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "Unchecked categories are hidden right away. Your picks stay put next time you open the app.",
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in widget.allCategories)
                    CheckboxListTile(
                      value: !_excludedKeys.contains(category.key),
                      title: Text(category.label, style: const TextStyle(color: Colors.white)),
                      activeColor: const Color(0xFFE1483A),
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (checked) {
                        final isChecked = checked ?? true;
                        setState(() {
                          if (isChecked) {
                            _excludedKeys.remove(category.key);
                          } else {
                            _excludedKeys.add(category.key);
                          }
                        });
                        widget.onToggle(category.key, isChecked);
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
