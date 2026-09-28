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

## Filter feed by source (mobile app)

Let the user filter the article feed by news source (e.g. show only Prothom
Alo + Daily Star), in addition to the existing category filter. Parked as an
idea, not designed in detail — needs a decision on UI placement (a source
picker alongside the category tabs? a multi-select sheet?) and whether the
choice persists across app restarts.

## More scraper sources — researched candidate list (2026-08-24)

Tested ~20 Bangladeshi newspaper sites by curling each with a spoofed desktop
Chrome UA (matching `scraper/config.make_session()`'s UA) and checking for
`403`s / Cloudflare challenge headers (`server: cloudflare` +
`cf-mitigated: challenge`). This is a same-IP proxy for the CI-runner-IP
blocking already documented in `docs/test-plan.md` §2 for jugantor,
dhakatribune, and ittefaq — real confirmation for any of these still needs a
live scrape from GitHub Actions, not just a local curl.

**Being added next (2026-08-24 session):** bdnews24 (bdnews24.com, EN),
bdnews24 Bangla (bangla.bdnews24.com, BN), and Dhaka Post
(thedhakapost.com, EN) — bdnews24/bdnews24 Bangla were previously listed in
the Cloudflare-blocked bucket below, but that finding predates the
residential self-hosted-runner fix and is being re-checked as part of this
addition; Dhaka Post was in the confirmed-clean bucket. See
`docs/test-plan.md` for the outcome.

**Confirmed not Cloudflare-blocked from a residential IP, not yet wired
into the scraper** — candidates for a future source-addition pass, roughly
in order of prominence: New Age (newagebd.net, EN), Bangladesh Observer
(observerbd.com, EN), BSS (bssnews.net, EN), Ajker Patrika
(ajkerpatrika.com, BN), Daily Inqilab (dailyinqilab.com, BN), Bhorer Kagoj
(bhorerkagoj.com, BN), Manab Zamin (mzamin.com, BN). (Financial Express was
in this bucket previously - see "2026-09-28 session" below, it's wired in
now.)

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
IP strategy (bdnews24 and bdnews24 Bangla removed from this list — see
"being added next" above, re-testing now that the residential runner is in
place): Bangladesh Pratidin (bd-pratidin.com, BN), Jagonews24
(jagonews24.com, BN), RisingBD (risingbd.com, BN), Daily Sun (daily-sun.com,
EN), Banglanews24 (banglanews24.com, BN). Same category as the
already-known-blocked jugantor, dhakatribune, ittefaq, and (per the
2026-08-24 CI run) banglatribune and samakal. (Kaler Kantho removed from
this list — see "2026-09-28 session" below: it's wired in now via the
`browser_client.py` Playwright fallback rather than a proxy, still flagged
at-risk pending CI confirmation.)

The Business Standard (tbsnews.net), Bangla Tribune (banglatribune.com),
and Samakal (samakal.com) were picked from this same research pass and
added to the scraper directly (see `scraper/sources/`), so they're not
listed in the two candidate buckets above. Of the three, only tbsnews
actually publishes from CI — see `docs/test-plan.md` §9's CI-confirmation
note for banglatribune/samakal.

**2026-08-24, CI-IP blocking fixed:** the scraper now runs on a Dockerized
self-hosted GitHub Actions runner with a residential IP (see
`docs/runner-setup-cachyos.md`, `docs/test-plan.md` §2) instead of
GitHub-hosted runners. Once that's confirmed working, the CI-IP caveat
above no longer applies — wiring in the "confirmed clean" candidates, or
re-testing the "confirmed blocked" set, only needs the normal
residential-IP check, not a separate CI-runner-IP confirmation pass. A
proxy/unblocker-API strategy was researched and rejected for cost reasons
(the pipeline's uncapped, non-incremental re-scraping would run
~$100+/month even after caching improvements) in favor of the residential
runner.

**2026-09-28 session — 6 new sources added:** thedissent.news, netra.news,
dailywaadaa.com, Financial Express (today.thefinancialexpress.com.bd),
Daily Kaler Kantho (kalerkantho.com), and Daily Naya Diganta
(dailynayadiganta.com). thedissent.news and netra.news are fact-checking/
investigative-journalism outlets rather than general newspapers, so a new
18th canonical category, "Fact-Check" (`fact_check`), was added for their
core content instead of forcing it into `miscellaneous`. netra.news and
kalerkantho.com are both Cloudflare-protected with a JS challenge (not a
plain IP-reputation block, confirmed live) - `scraper/browser_client.py`
(added in a prior session for jugantor) now also backs these two, so no
proxy strategy was needed after all for this class of block. Daily Naya
Diganta currently serves an invalid/self-signed TLS certificate; its source
module uses a locally-scoped `verify=False` session (not a global
relaxation of `config.make_session()`). Both Cloudflare-protected additions
(netra.news, kalerkantho.com) are unverified against the actual self-hosted
CI runner as of this session - confirm with `gh workflow run scrape.yml`
before trusting them long-term, per the caveat above.
