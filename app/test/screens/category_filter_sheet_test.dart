import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/screens/category_filter_sheet.dart';

const _categories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'sports', label: 'Sports'),
];

void main() {
  testWidgets('renders one row per category, checked unless excluded', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryFilterSheet(
          allCategories: _categories,
          excludedKeys: const {'sports'},
          onToggle: (_, _) {},
        ),
      ),
    ));

    final mainTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Main'),
    );
    final sportsTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Sports'),
    );
    expect(mainTile.value, isTrue);
    expect(sportsTile.value, isFalse);
  });

  testWidgets('tapping a checked row calls onToggle with isChecked false', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryFilterSheet(
          allCategories: _categories,
          excludedKeys: const {},
          onToggle: (key, isChecked) {
            toggledKey = key;
            toggledValue = isChecked;
          },
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sports'));
    await tester.pump();

    expect(toggledKey, 'sports');
    expect(toggledValue, isFalse);
  });

  testWidgets('tapping an unchecked row calls onToggle with isChecked true', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryFilterSheet(
          allCategories: _categories,
          excludedKeys: const {'sports'},
          onToggle: (key, isChecked) {
            toggledKey = key;
            toggledValue = isChecked;
          },
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sports'));
    await tester.pump();

    expect(toggledKey, 'sports');
    expect(toggledValue, isTrue);
  });
}
