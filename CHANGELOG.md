# Changelog

## [1.1.0] - 2026-09-28
### Added
- Live headline/snippet search over the loaded feed.
- Combined category/source/language filter sheet, with source and language
  exclusion persisted across sessions.
- Full-screen offline state with retry when the initial load has no data
  and no network.

### Fixed
- Dhaka Post listing times were occasionally wrong; timestamp span
  selection now matches the actual pattern instead of the first span.
- Ittefaq's editorial section no longer gets force-mapped into "main"; it
  now routes to opinion via the existing section map.
- Articles now render in the source site's own default styling instead of
  a forced dark-mode CSS invert.

## [1.0.2] - 2026-08-23
See git history for details.

## [1.0.1] - 2026-08-23
See git history for details.
