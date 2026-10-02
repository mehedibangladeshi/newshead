import 'dart:async';

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
          allSources: const [],
          excludedSourceKeys: const {},
          onSourceToggle: (_, _) {},
          allLanguages: const [],
          excludedLanguageKeys: const {},
          onLanguageToggle: (_, _) {},
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
          allSources: const [],
          excludedSourceKeys: const {},
          onSourceToggle: (_, _) {},
          allLanguages: const [],
          excludedLanguageKeys: const {},
          onLanguageToggle: (_, _) {},
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
          allSources: const [],
          excludedSourceKeys: const {},
          onSourceToggle: (_, _) {},
          allLanguages: const [],
          excludedLanguageKeys: const {},
          onLanguageToggle: (_, _) {},
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sports'));
    await tester.pump();

    expect(toggledKey, 'sports');
    expect(toggledValue, isTrue);
  });

  testWidgets('filter sections are in order: Categories, Language, Sources', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryFilterSheet(
          allCategories: _categories,
          excludedKeys: const {},
          onToggle: (_, _) {},
          allSources: const ['bbc', 'cnn'],
          excludedSourceKeys: const {},
          onSourceToggle: (_, _) {},
          allLanguages: const ['en', 'bn'],
          excludedLanguageKeys: const {},
          onLanguageToggle: (_, _) {},
        ),
      ),
    ));

    final categoriesY = tester.getTopLeft(find.text('Categories')).dy;
    final languageY = tester.getTopLeft(find.text('Language')).dy;
    final sourcesY = tester.getTopLeft(find.text('Sources')).dy;

    expect(categoriesY < languageY, isTrue, reason: 'Categories should appear before Language');
    expect(languageY < sourcesY, isTrue, reason: 'Language should appear before Sources');
  });

  Widget sheet({DateTime? lastUpdated, Future<bool> Function()? onRefresh}) => MaterialApp(
        home: Scaffold(
          body: CategoryFilterSheet(
            allCategories: _categories,
            excludedKeys: const {},
            onToggle: (_, _) {},
            allSources: const [],
            excludedSourceKeys: const {},
            onSourceToggle: (_, _) {},
            allLanguages: const [],
            excludedLanguageKeys: const {},
            onLanguageToggle: (_, _) {},
            lastUpdated: lastUpdated,
            onRefresh: onRefresh,
          ),
        ),
      );

  testWidgets('refresh caption hidden when onRefresh is null', (tester) async {
    await tester.pumpWidget(sheet());
    expect(find.byKey(const Key('sheetRefreshButton')), findsNothing);
    expect(find.textContaining('Updated'), findsNothing);
  });

  testWidgets('refresh caption shows relative time', (tester) async {
    await tester.pumpWidget(sheet(
      lastUpdated: DateTime.now().subtract(const Duration(hours: 2)),
      onRefresh: () async => true,
    ));
    expect(find.text('Updated 2h ago'), findsOneWidget);
  });

  testWidgets('refresh button shows spinner while pending, then just now', (tester) async {
    final c = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(sheet(
      lastUpdated: DateTime.now().subtract(const Duration(hours: 2)),
      onRefresh: () {
        calls++;
        return c.future;
      },
    ));
    await tester.tap(find.byKey(const Key('sheetRefreshButton')));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Refreshing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    c.complete(true);
    await tester.pump();
    expect(find.text('Updated just now'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('failed refresh leaves the caption unchanged', (tester) async {
    await tester.pumpWidget(sheet(
      lastUpdated: DateTime.now().subtract(const Duration(hours: 2)),
      onRefresh: () async => false,
    ));
    await tester.tap(find.byKey(const Key('sheetRefreshButton')));
    await tester.pump();
    expect(find.text('Updated 2h ago'), findsOneWidget);
  });
}
