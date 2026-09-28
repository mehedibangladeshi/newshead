# app/

Dev-loop commands (`flutter pub get`, `flutter run`, `flutter test`): see
`README.md`'s "App" section at the repo root. (`app/README.md` is unrelated
stock Flutter boilerplate, not project docs.)

## Release builds

Always build release APKs with `scripts/build_release_apk.sh` — never
`flutter build apk` directly. It splits the build into one APK per CPU
architecture instead of a single ~49MB universal one. See
`docs/release.md` (repo root) for why this is a script instead of a Gradle
flag.

## Theming

Single dark theme only, no light mode (`lib/theme/app_theme.dart`'s
`AppColors`/`AppTypography`). The Anton display font is for the wordmark and
category pills only — never for fetched article headlines/snippets, since
Anton has no Bengali glyphs and roughly half the sources publish in Bengali.

## Domain language

Read `CONTEXT.md` (repo root) for the "Visible Category" concept before
touching category-filtering UI — it's the one derived list that drives both
the pill bar and the swipeable feed, always ordered by the fetched
`categories` list, never re-sorted by the app.
