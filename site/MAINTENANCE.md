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
      + `dates.yml` against the live catalog, stamped today, projects
      `mcp.yml` — the MCP page's tool list, pinned demo tag and demo
      license table — from the server's tool registry, `server.json` and
      the demo plan, and renders
      `site/llms.txt` — the agent entry file — from those SSOT files — then
      `site:axes`, then `site:sources`). This is the ONLY number-entry step; the prose pages
      update themselves because they read the data. The same task writes
      the per-source grain, `sources.yml`: one row per live public source
      (documents / passages / dictionary entries, license class, a
      holdings cell for /sources/, the du-measured canonical size), the
      /library/ collection-table totals summed over the hand-curated shelf
      map `site/_data/shelf_members.yml`, and the disk totals /quickstart/
      cites (one `du` walk of the canonical tree; a worktree run points
      `NABU_SITE_CANONICAL` at the main checkout's tree, beside
      `NABU_AXES_CATALOG` / `NABU_SITE_FULLTEXT`). A newly wired source that
      holds documents must join a shelf in that map — the suite fails
      until it does.
   3. **Commit** the regenerated `site/_data/*.yml`, `site/llms.txt` and
      the axis pages.

   Two suite guards make this a red/green gate — drift fails the build,
   not a human's memory: `test/site/site_data_test.rb` pins the census /
   desks / dates SHAPE and that index.md reads the data; and
   `test/site/site_prose_ssot_test.rb` fails if any headline page stops
   reading the census SSOT, if any page carries a known-stale headline
   literal, or if a pure-headline page hardcodes a million-scale total —
   and, at the per-source grain, if a /library/ collection-table size, a
   /sources/ holdings cell or a /quickstart/ MB/GB figure is typed by hand.
   `site/llms.txt` is guarded the same way: site_data_test regenerates it
   from the committed census + desks files and fails on any difference (a
   hand edit or a skipped refresh), and site_prose_ssot_test refuses a
   headline figure typed into its template (`Nabu::Ops::LlmsTxt`).
   `/llms-full.txt` (the navigation pages as plain text) needs no refresh
   step: Jekyll renders it at build from the pages' own rendered content
   (`site/zz-llms-full.txt` + `_includes/plain_text.html`), so it carries
   exactly the figures the pages render. Its file name must sort after
   every page it reads (Jekyll renders pages in name order) —
   `test/site/agent_discovery_test.rb` guards that, the figure-free
   template, and the sitemap/robots.txt/JSON-LD wiring.
   **A new headline figure a page needs = add a field to
   `Nabu::Ops::SiteData#census`** (and its shape assertion in
   site_data_test), regenerate, then reference `{{ site.data.census.NEW }}`
   — never type the number into prose.

   Page-local detail numbers stay hand-maintained (out of the SSOT, out of
   the guard): quickstart.md's measured on-disk sizes (`du -sh` the live
   canonical dirs when a listed shelf changes materially; keep consistent
   with `bin/nabu quickstart`); places.md's place-program census; the
   dated first-sync counts in the /sources/ contents cells.
2. **New shelves/sources**: the /sources/ corpus table is GENERATED —
   `bundle exec rake site:sources` (ridden by `site:refresh`) writes
   `site/_includes/sources_table.md`, one row per live public source
   (registry membership, the same rule as `sources.yml`; blocked holdings
   never), with the hand prose from `site/_data/source_notes.yml` (keyed
   by slug: `upstream` / `contents` / `license`, plus `with:` to fold
   sibling sources into one row). A newly wired source appears at the next
   refresh with an honest "Description pending." row; write its note to
   fill it in, then regenerate. `test/site/sources_table_test.rb` fails the
   suite when the committed table misses a live public source, lists a
   blocked one, or when a note names a source that is no longer live and
   public. A new synced source still gets its row/paragraph on
   library.md by hand.
3. **New tools/flags**: tools.md gains or amends its subsection, with a
   real command (+ README-sourced output snippet where one exists — never
   invent output).
4. **License changes** (a license_watch alarm, a class change): the
   source's note in `site/_data/source_notes.yml` (then `rake
   site:sources`) updated immediately, not just at gates — same trigger rule as
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
8. **Rendered read-back** (owner rule 2026-09-18 — a raw `{{ … }}` shipped
   live in a post's front matter and a baseurl-less link sat broken for
   weeks; "even one leak should have been caught"): after any site edit,
   BUILD and read the OUTPUT, not just the source — `bundle exec jekyll
   build` in `site/`, then grep `_site/**/*.html` for literal `{{` / `{%`
   and click-check any page you touched (or `rake site:preview`). Two suite
   guards hold the mechanical half permanently: front matter must be
   Liquid-free (Jekyll never renders it there) and internal links must
   ride `relative_url` (both in `test/site/site_prose_ssot_test.rb`) —
   but prose sanity ("does the page read correctly as rendered?") is the
   review, every time.
9. **Taught commands, executed** (`bundle exec rake docs:verify`): the
   quickstart walkthroughs (this site's and docs/quickstart.md), the README
   install block and the MCP registration recipes run in a throwaway
   fresh-clone sandbox, one OK/FAIL verdict line per documented claim
   (plan: `config/docs_verify.yml`). Offline mode at every gate; the
   network mode (`rake "docs:verify[network]"` — the real starter-shelf
   sync, ten to fifteen minutes) whenever a gate touched the quickstart
   path, its pages, or the sync/enable surface. The suite's drift guard
   (`test/docs_verify_coverage_test.rb`) fails on any newly documented
   command the plan neither verifies nor ignores with a reason.

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
