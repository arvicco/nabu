# Site maintenance contract

This directory is the project's public academic face
(https://arvicco.github.io/nabu, GitHub Pages via
`.github/workflows/pages.yml`). It restates the repository documentation —
it is never the source of truth. **The catalog is the territory;
README/library.md are the map; this site is the printed map.**

## Previewing staged changes

`rake site:preview` serves the working tree at
`http://127.0.0.1:4747/nabu/` (watch mode — edits rebuild on refresh).
Port 4747 by default, `PORT=n` to override: 4000 and livereload's 35729
are deliberately avoided because this box previews sibling sites
(nabu-edubba) on the standard ports.

## Standing gate duty

At **every phase gate**, alongside the README/library.md truthfulness pass
(library.md §10 duty 1), the site is re-synced:

1. **Headline numbers — the single source of truth.** Every library-wide
   figure any page states (document / passage / language-code / source /
   registry / dictionary / gold & silver lemma totals, the desk count, and
   their as-of date) lives in ONE generated file, `site/_data/census.yml`,
   and every page renders it through Liquid (`{{ site.data.census.* }}`) —
   **never a hardcoded copy**. The routine, in order:

   1. **Bring the library up to date first** — the gate's syncs and
      re-parses are done, so the catalog is the state you are about to
      publish (the SSOT is "created from the up-to-date library, before the
      site refresh").
   2. **Regenerate the SSOT from the live catalog**: `bundle exec rake
      site:refresh` (= `site:data` — recomputes `census.yml` + `desks.yml`
      + `dates.yml` against the live catalog, stamped today — then
      `site:axes`). This is the ONLY number-entry step; the prose pages
      update themselves because they read the data.
   3. **Commit** the regenerated `site/_data/*.yml` and the axis pages.

   Two suite guards make this a red/green gate — drift fails the build,
   not a human's memory: `test/site/site_data_test.rb` pins the census /
   desks / dates SHAPE and that index.md reads the data; and
   `test/site/site_prose_ssot_test.rb` fails if any headline page stops
   reading the census SSOT, if any page carries a known-stale headline
   literal, or if a pure-headline page hardcodes a million-scale total.
   **A new headline figure a page needs = add a field to
   `Nabu::Ops::SiteData#census`** (and its shape assertion in
   site_data_test), regenerate, then reference `{{ site.data.census.NEW }}`
   — never type the number into prose.

   Page-local detail numbers stay hand-maintained (out of the SSOT, out of
   the guard): quickstart.md's measured on-disk sizes (`du -sh` the live
   canonical dirs when a listed shelf changes materially; keep consistent
   with `bin/nabu quickstart`); places.md's place-program census; the
   per-source rows on sources.md and the per-section counts on library.md
   — the last a standing future target (fold those into a generated table
   the way the headline figures now are).
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
5. **Dossier drift check** (P24-0): `bundle exec rake site:check` — the
   mechanical rider for duties 1–2 at the source grain: it flags
   presence/mention drift between the local/shelves/local-source dossier
   descriptions and docs/library.md (this site's library page is covered
   transitively, as the printed map). Exit 1 lists the findings; fix by
   re-running the idempotent seed (`bin/nabu list
   --export-source-dossiers`), writing the missing description, or adding
   the shelf's library.md row.
6. **News entry** (P19-3): every gate adds one dated post to
   `site/news/_posts/` (`YYYY-MM-DD-slug.md`) — what shipped, honest
   numbers with as-of dates, distilled from the gate's worklog line. The
   Atom feed (`/feed.xml`, jekyll-feed) carries it on deploy; nothing else
   to do. Gates that cut a tagged release follow the fuller checklist in
   docs/ops.md §12 (CITATION.cff version/date bump, GitHub release, DOI).
7. **Per-axis pages** (P37-9): the `site/axis/<name>.md` desk pages and the
   `/axis/` index are GENERATED — `bundle exec rake site:axes` reprojects
   them from the live registry (`config/axes.yml` + `config/sources.yml`),
   the curated `site/axis/_fragments.yml` (recipes, display notes, the
   desk's instruments — HAND-EDITED, never overwritten), and the live
   catalog counts (read-only, stamped with today's as-of date). Re-run it
   at every gate so the holdings numbers and the as-of dates refresh, and
   whenever an axis or a membership changes in the registry (a drift the
   suite already fails on — `test/site/axis_pages_test.rb` pins each page's
   persona, desc and member list to the registry; only the dated counts are
   free to drift). Commit the regenerated pages — they are static-site
   artifacts, deployed only on a push to `site/**`. New per-axis prose (a
   fresh CLI recipe, a display note) is a `_fragments.yml` edit followed by
   a regeneration.

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
