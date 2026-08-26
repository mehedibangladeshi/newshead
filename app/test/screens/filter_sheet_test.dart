import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/app_category.dart';
import 'package:newshead/models/filter_option.dart';
import 'package:newshead/screens/filter_sheet.dart';

const _categories = [
  AppCategory(key: 'main', label: 'Main'),
  AppCategory(key: 'sports', label: 'Sports'),
];

const _languages = [
  FilterOption(key: 'bn', label: 'Bangla'),
  FilterOption(key: 'en', label: 'English'),
];

const _sources = [
  FilterOption(key: 'Jugantor', label: 'Jugantor'),
  FilterOption(key: 'The Daily Star', label: 'The Daily Star'),
];

Widget _buildSheet({
  Set<String> excludedCategoryKeys = const {},
  Set<String> excludedLanguageKeys = const {},
  Set<String> excludedSourceKeys = const {},
  void Function(String, bool)? onToggleCategory,
  void Function(String, bool)? onToggleLanguage,
  void Function(String, bool)? onToggleSource,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FilterSheet(
        allCategories: _categories,
        excludedCategoryKeys: excludedCategoryKeys,
        onToggleCategory: onToggleCategory ?? (_, _) {},
        allLanguages: _languages,
        excludedLanguageKeys: excludedLanguageKeys,
        onToggleLanguage: onToggleLanguage ?? (_, _) {},
        allSources: _sources,
        excludedSourceKeys: excludedSourceKeys,
        onToggleSource: onToggleSource ?? (_, _) {},
      ),
    ),
  );
}

void main() {
  testWidgets('renders one row per category, checked unless excluded', (tester) async {
    await tester.pumpWidget(_buildSheet(excludedCategoryKeys: const {'sports'}));

    final mainTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Main'),
    );
    final sportsTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Sports'),
    );
    expect(mainTile.value, isTrue);
    expect(sportsTile.value, isFalse);
  });

  testWidgets('renders one row per language, checked unless excluded', (tester) async {
    await tester.pumpWidget(_buildSheet(excludedLanguageKeys: const {'bn'}));

    final bnTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Bangla'),
    );
    final enTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'English'),
    );
    expect(bnTile.value, isFalse);
    expect(enTile.value, isTrue);
  });

  testWidgets('renders one row per source, checked unless excluded', (tester) async {
    await tester.pumpWidget(_buildSheet(excludedSourceKeys: const {'Jugantor'}));

    final jugantorTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Jugantor'),
    );
    final dailyStarTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'The Daily Star'),
    );
    expect(jugantorTile.value, isFalse);
    expect(dailyStarTile.value, isTrue);
  });

  testWidgets('tapping a checked category row calls onToggleCategory with isChecked false', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(_buildSheet(
      onToggleCategory: (key, isChecked) {
        toggledKey = key;
        toggledValue = isChecked;
      },
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sports'));
    await tester.pump();

    expect(toggledKey, 'sports');
    expect(toggledValue, isFalse);
  });

  testWidgets('tapping a checked language row calls onToggleLanguage with isChecked false', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(_buildSheet(
      onToggleLanguage: (key, isChecked) {
        toggledKey = key;
        toggledValue = isChecked;
      },
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Bangla'));
    await tester.pump();

    expect(toggledKey, 'bn');
    expect(toggledValue, isFalse);
  });

  testWidgets('tapping a checked source row calls onToggleSource with isChecked false', (tester) async {
    String? toggledKey;
    bool? toggledValue;
    await tester.pumpWidget(_buildSheet(
      onToggleSource: (key, isChecked) {
        toggledKey = key;
        toggledValue = isChecked;
      },
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'The Daily Star'));
    await tester.pump();

    expect(toggledKey, 'The Daily Star');
    expect(toggledValue, isFalse);
  });

  testWidgets('shows a Language and a Source section heading', (tester) async {
    await tester.pumpWidget(_buildSheet());

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
  });
}
