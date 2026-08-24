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

**Confirmed not Cloudflare-blocked from a residential IP, not yet wired
into the scraper** — candidates for a future source-addition pass, roughly
in order of prominence: New Age (newagebd.net, EN), Financial Express
(thefinancialexpress.com.bd, EN), Dhaka Post (thedhakapost.com, EN),
Bangladesh Observer (observerbd.com, EN), BSS (bssnews.net, EN), Ajker
Patrika (ajkerpatrika.com, BN), Daily Inqilab (dailyinqilab.com, BN), Bhorer
Kagoj (bhorerkagoj.com, BN), Manab Zamin (mzamin.com, BN).

**Important caveat added 2026-08-24, after a real CI run:** "confirmed
clean" above only means clean from a residential IP — it is *not* a
reliable predictor of GitHub Actions runner behavior. Two of the three
sources added this session (Bangla Tribune, Samakal — see below) tested
clean residentially but turned out to be Cloudflare-blocked from CI runner
IPs anyway. Before wiring any of the above into the scraper, budget for an
actual `gh workflow run scrape.yml` to confirm CI behavior, not just a
local curl test.

**Confirmed Cloudflare-blocked (403 / bot-challenge on every request, from
both a residential IP and CI)** — don't attempt without a proxy/residential-
IP strategy: bdnews24 (bdnews24.com, EN), Kaler Kantho (kalerkantho.com,
BN), Bangladesh Pratidin (bd-pratidin.com, BN), Jagonews24
(jagonews24.com, BN), RisingBD (risingbd.com, BN), Daily Sun
(daily-sun.com, EN), Banglanews24 (banglanews24.com, BN). Same category as
the already-known-blocked jugantor, dhakatribune, ittefaq, and (per the
2026-08-24 CI run) banglatribune and samakal.

The Business Standard (tbsnews.net), Bangla Tribune (banglatribune.com),
and Samakal (samakal.com) were picked from this same research pass and
added to the scraper directly (see `scraper/sources/`), so they're not
listed in the two candidate buckets above. Of the three, only tbsnews
actually publishes from CI — see `docs/test-plan.md` §9's CI-confirmation
note for banglatribune/samakal.
