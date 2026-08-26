# Handoff: Language & Source filters for NewsHead

## Repo
`/home/mehedi/Documents/projects/newshead`, branch `dev`, all changes below are **uncommitted working-tree changes** (`git status --short` confirms nothing has been committed yet).

## What this session did

Implemented two new filter dimensions in the Flutter app — Language and Source — alongside the existing Category filter, following a `grill-with-docs`/`domain-modeling` interview with the user (transcript has the full Q&A) and then `superpowers:test-driven-development`.

Design decisions locked in during the grilling session (all confirmed by the user):
1. One bottom sheet, three stacked sections (Category / Language / Source) — not tabs, not separate icons.
2. The three filter dimensions are fully **independent** and **AND-combined** — no linking between Language and Source checkboxes even though every source maps to exactly one language today.
3. The list of available languages/sources comes from a **new backend manifest** (`languages`/`sources` arrays in `articles.json`, emitted by `scraper/generate_data.py`), not derived client-side from fetched articles.
4. Manifest ordering is **alphabetical by label** (computed at build time via `casefold()`), not hand-curated like categories.
5. Language labels are English: "Bangla" / "English".
6. The persistence store was **generalized**: `CategoryFilterStore` → generic `FilterStore(prefKey)`, reused for all three dimensions with distinct shared_preferences keys.
7. A category's tab disappears if it has zero articles after **all three** filters combine (not just category exclusion).
8. Source filter option keys are the **display-name string itself** (e.g. `"Bangla Tribune"`, matching `article.source`), not the backend's internal slug.
9. The filter-icon badge dot lights up if **any** of the three excluded-sets is non-empty.

Full rationale for each decision is in the conversation transcript, not duplicated here.

### Files changed (uncommitted)
```
 M CONTEXT.md                                       (new domain terms: Filter Dimension, Filter Option)
 M app/lib/data/article_repository.dart             (parseLanguages/parseSources, extended ArticlesFetchResult)
 D app/lib/data/category_filter_store.dart           -> replaced by:
?? app/lib/data/filter_store.dart                    (generic FilterStore/SharedPreferencesFilterStore)
 M app/lib/data/category_visibility.dart             (added visibleArticles())
 M app/lib/main.dart                                 (wires 3 FilterStore instances, initialLanguages/initialSources)
?? app/lib/models/filter_option.dart                 (new {key,label} model for language/source options)
 D app/lib/screens/category_filter_sheet.dart         -> replaced by:
?? app/lib/screens/filter_sheet.dart                 (3-section bottom sheet: Category/Language/Source)
 M app/lib/screens/home_screen.dart                  (wires 3 excluded-sets, combined badge, _applyExcludedKeys)
 M scraper/generate_data.py                          (LANGUAGE_DISPLAY_NAMES, build_output emits languages/sources)
 + matching test files for every lib/ file above (app/test/... mirrors app/lib/... 1:1, repo convention)
```

Run `git diff --stat` for exact line counts, `git diff <file>` for the actual diffs — not reproduced here.

## Current state / what's NOT done

- **Python/scraper side is fully verified**: `.venv/bin/python -m pytest tests/ -q` → **93 passed**, run on this machine.
- **Flutter/Dart side is UNVERIFIED.** This machine has no Flutter or Dart SDK installed (`flutter`/`dart` not on PATH, no SDK found under `/opt`, `/snap`, or the one candidate backup directory checked — it was empty). All Dart test files were written first (TDD red/green intent) and the implementation was written to match them, but:
  - `flutter test` has never actually been run.
  - `flutter analyze` has never been run.
  - The app has never been launched/screenshotted to confirm the UI actually works (three-section bottom sheet layout, checkbox behavior, badge, etc.).
  - I only hand-verified brace/paren balance and that embedded JSON test fixtures parse — not equivalent to real compilation.

This is exactly why the user invoked `/handoff` — to continue this on a machine that has a working Flutter setup.

## Plan for the next session (on the Flutter-equipped machine)

1. **Sync the working tree.** These are uncommitted changes on the `dev` branch — pull/copy the working tree as-is (do not `git stash`/discard). Confirm `git status --short` matches the file list above before doing anything else.
2. **Verify Flutter/Dart tooling**: `flutter --version`, `dart --version`. Run `flutter pub get` in `app/`.
3. **Static checks first** (cheap, catches typos/type errors fast):
   ```
   cd app
   dart analyze
   ```
   Fix anything flagged — the Dart records syntax used in `filter_sheet.dart` (`List<({String key, String label})>`) requires SDK `^3.12.2`+ per `pubspec.yaml`; confirm the installed SDK satisfies that.
4. **Run the full test suite**:
   ```
   flutter test
   ```
   Expect it to cover (at minimum) these new/changed test files — treat any failure here as the real signal, not the analysis in this handoff doc:
   - `test/models/filter_option_test.dart`
   - `test/data/filter_store_test.dart`
   - `test/data/category_visibility_test.dart` (new `visibleArticles` group)
   - `test/data/article_repository_test.dart` (new `parseLanguages`/`parseSources`/fetch tests)
   - `test/screens/filter_sheet_test.dart`
   - `test/screens/home_screen_test.dart` (rewritten — new `_buildHomeScreen` helper, new required constructor params)
   - Run the **whole** suite (`flutter test`, not just the new files) to catch any regression in untouched files that reference the old `CategoryFilterStore`/`category_filter_sheet.dart` API — there should be none left (a repo-wide grep found none), but the compiler is the final word.
5. **Fix-forward, following TDD discipline** (invoke `superpowers:test-driven-development` again — see below): if a test fails because the implementation is wrong, fix the implementation, not the test. If a test fails because the test itself has a bug (e.g. a wrong expected value), fix the test but double check against the design decisions listed above first.
6. **Manually run the app** and click through the golden path per this repo's CLAUDE.md convention ("For UI or frontend changes, start the dev server and use the feature in a browser/app before reporting complete"):
   - Open the filter sheet (tune icon) — confirm three sections render: Category, Language, Source.
   - Uncheck a language → confirm articles/category tabs update live, confirm persists across app restart (shared_preferences).
   - Uncheck a source → same checks.
   - Confirm the badge dot appears/disappears correctly for all three dimensions independently.
   - Confirm `articles.json` at the repo root still has the old shape plus new `languages`/`sources` arrays if you regenerate it (`python -m scraper.generate_data` or however the scraper is normally invoked) — the committed `articles.json` at repo root was NOT regenerated this session, only the generator code was changed and unit-tested.
7. Once green and manually verified, follow `superpowers:finishing-a-development-branch` to decide commit/PR strategy — **nothing has been committed yet**, so this is also the point to actually commit (per this repo's CLAUDE.md commit-message convention — see that file).

## Suggested skills for the next session

- `superpowers:test-driven-development` — resume in the RED/GREEN/REFACTOR discipline already established; do not weaken this once real test output is available.
- `superpowers:verification-before-completion` — do not report anything as "passing"/"working" without pasting actual `flutter test`/`flutter analyze`/manual-run output as evidence, given this session could only claim things were "hand-verified."
- `superpowers:systematic-debugging` — if `flutter test` or `flutter analyze` surfaces failures, use this instead of ad hoc guessing.
- `run` — for launching/screenshotting the app to confirm the UI golden path (step 6 above).
- `superpowers:finishing-a-development-branch` — once verified, to decide how to land the work (commit/PR).

## Where to find more detail

- Full grilling Q&A and rationale: this session's conversation transcript (not re-derivable from the diff alone — e.g. *why* independent AND-combined filters were chosen over linked ones).
- Domain vocabulary: `CONTEXT.md` at repo root (already updated with "Filter Dimension" and "Filter Option" entries).
- Actual code changes: `git diff` in the repo (uncommitted).
