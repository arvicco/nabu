# Site maintenance contract

This directory is the project's public academic face
(https://arvicco.github.io/nabu, GitHub Pages via
`.github/workflows/pages.yml`). It restates the repository documentation —
it is never the source of truth. **The catalog is the territory;
README/library.md are the map; this site is the printed map.**

## Standing gate duty

At **every phase gate**, alongside the README/library.md truthfulness pass
(library.md §10 duty 1), the site is re-synced:

1. **Headline numbers** (index.md, library.md, tools.md, languages.md):
   documents/passages totals, dictionary entries, gold-lemma rows and
   language count, dated-document coverage — copied from the freshly
   refreshed docs/library.md header, **never re-derived**. Update every
   "as of" date to the gate date. quickstart.md carries measured on-disk
   sizes (the starter shelf and the growth table) — re-measure (`du -sh`
   of the live canonical dirs) when a listed shelf changes materially,
   and keep it consistent with what `bin/nabu quickstart` prints.
   faq.md restates a few of these figures (starter-shelf and full-build
   sizes, source/document counts, the class percentages) — re-check its
   dated numbers against quickstart.md/library.md/index.md at the same
   pass, and keep its answers truthful when postures, funnels, or the
   citation story (a DOI is planned) change.
2. **New shelves/sources**: a new synced source gets its row/paragraph on
   library.md + sources.md (upstream link, license, class). A source
   flipped from pending to live moves out of the "awaiting first
   synchronization" table.
3. **New tools/flags**: tools.md gains or amends its subsection, with a
   real command (+ README-sourced output snippet where one exists — never
   invent output).
4. **License changes** (a license_watch alarm, a class change): sources.md
   updated immediately, not just at gates — same trigger rule as
   library.md §10 duty 4.
5. **News entry** (P19-3): every gate adds one dated post to
   `site/news/_posts/` (`YYYY-MM-DD-slug.md`) — what shipped, honest
   numbers with as-of dates, distilled from the gate's worklog line. The
   Atom feed (`/feed.xml`, jekyll-feed) carries it on deploy; nothing else
   to do. Gates that cut a tagged release follow the fuller checklist in
   docs/ops.md §12 (CITATION.cff version/date bump, GitHub release, DOI).

## Hard rules

- **Project documentation only.** No corpus texts, no dictionary entries,
  no passage content beyond short illustrative snippets already published
  in README/library.md. (The external-access licensing rulings are NOT
  triggered by this site.)
- Academic register: no exclamation marks, no marketing voice, no emoji;
  measured claims with numbers and dates; upstream projects credited.
- Numbers always carry their as-of date and come from library.md/README
  (which read them from the live catalog).

## Build

Self-contained: `site/Gemfile` (jekyll ~> 4.3), never added to the app's
Gemfile. Local check:

    cd site && BUNDLE_PATH=vendor/bundle bundle install
    BUNDLE_PATH=vendor/bundle bundle exec jekyll build

Deployment: `.github/workflows/pages.yml` (push to main touching `site/**`,
or manual dispatch) builds with actions/jekyll-build-pages from `site/` and
deploys via actions/deploy-pages. Enabling Pages (Settings → Pages →
Source: GitHub Actions) is an owner action.
