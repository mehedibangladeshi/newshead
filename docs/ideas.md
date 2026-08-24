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

## More scraper sources — researched candidate list (2026-08-24)

Tested ~20 Bangladeshi newspaper sites by curling each with a spoofed desktop
Chrome UA (matching `scraper/config.make_session()`'s UA) and checking for
`403`s / Cloudflare challenge headers (`server: cloudflare` +
`cf-mitigated: challenge`). This is a same-IP proxy for the CI-runner-IP
blocking already documented in `docs/test-plan.md` §2 for jugantor,
dhakatribune, and ittefaq — real confirmation for any of these still needs a
live scrape from GitHub Actions, not just a local curl.

**Confirmed not Cloudflare-blocked, not yet wired into the scraper** — safe
candidates for a future source-addition pass, roughly in order of
prominence: New Age (newagebd.net, EN), Financial Express
(thefinancialexpress.com.bd, EN), Dhaka Post (thedhakapost.com, EN),
Bangladesh Observer (observerbd.com, EN), BSS (bssnews.net, EN), Ajker
Patrika (ajkerpatrika.com, BN), Daily Inqilab (dailyinqilab.com, BN), Bhorer
Kagoj (bhorerkagoj.com, BN), Manab Zamin (mzamin.com, BN).

**Confirmed Cloudflare-blocked (403 / bot-challenge on every request)** —
don't attempt without a proxy/residential-IP strategy: bdnews24
(bdnews24.com, EN), Kaler Kantho (kalerkantho.com, BN), Bangladesh Pratidin
(bd-pratidin.com, BN), Jagonews24 (jagonews24.com, BN), RisingBD
(risingbd.com, BN), Daily Sun (daily-sun.com, EN), Banglanews24
(banglanews24.com, BN). Same category as the already-known-blocked jugantor,
dhakatribune, and ittefaq.

The Business Standard (tbsnews.net), Bangla Tribune (banglatribune.com), and
Samakal (samakal.com) — also confirmed clean — were picked from this same
research pass and added to the scraper directly (see `scraper/sources/`);
not listed above since they're no longer "future."
