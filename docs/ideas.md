# Ideas backlog

Not scheduled, not designed in detail — just parked for later.

## Manual dark-mode toggle for the article WebView

`article_web_view_screen.dart` auto-injects a CSS invert filter on every
article page so external sites roughly match the app's dark theme (see
`_darkModeInjectionScript`). If the generic invert filter ever looks wrong
on a specific page (broken embeds, weird color casts), consider adding a
manual toggle button in the WebView screen's app bar that lets the user
switch the filter off/on per page, instead of (or in addition to) applying
it automatically everywhere.
