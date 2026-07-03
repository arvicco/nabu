# Worklog

One line per completed packet: date · packet · commit · notes.

---

2026-07-03 · P0-1 · e35a163 · Ruby skeleton: Gemfile (budget-only), Rakefile, RuboCop, minitest+WebMock harness; net-blocked suite green.
2026-07-03 · P0-2 · 35099d1 · Thor CLI skeleton (bin/nabu, version + not-implemented stubs) and Nabu::Config with project-relative defaults + commented config/nabu.yml.
2026-07-03 · P0-4 · 6082c74 · Core primitives: Nabu::Error hierarchy (ParseError/FetchError), Open3-backed Nabu::Shell.run (argv-only, status+stderr on failure), Nabu::Normalize.nfc (UTF-8 NFC, raises on invalid bytes); NFD-Greek regression fixture.
2026-07-03 · P0-3 · a7d0d83 · GitHub Actions CI (.github/workflows/ci.yml): push+pull_request, ubuntu-latest, setup-ruby pinned to 3.3 with bundler-cache, rake test then rake lint as separate steps; concurrency cancels in-progress runs per ref.
2026-07-03 · gate · — · Phase 0 gate: Fable review of full phase diff — pass, no architecture deviations; suite 31/75 green, lint clean; branch pushed, PR opened.
2026-07-03 · P1-1 · — · Domain values in lib/nabu/model/: Passage/DocumentRef/SourceManifest as validating Data.define (keyword ctor, deep-frozen JSON annotations/metadata, non-NFC text rejected), DocumentRef(source_id, id, path, metadata), Nabu::ValidationError, Document plain class with <</append + Enumerable in sequence order, dup urn/sequence rejected; license_class closed enum exposed as SourceManifest::LICENSE_CLASSES.
2026-07-03 · P1-2 · — · Adapter contract: abstract Nabu::Adapter (fetch/discover/parse + self.manifest, instance manifest delegator, NotImplementedError names class+method); AdapterConformance module (hooks conformance_adapter/conformance_workdir, optional conformance_expected_source_id) asserting manifest validity, discover→parse round-trip, cross-set urn uniqueness, two-pass urn stability, NFC/non-empty passages, license class; hand-written TestAdapter rig + meta-tests running broken variants (dup/unstable urns, empty doc, wrong manifest) through anonymous test classes.
