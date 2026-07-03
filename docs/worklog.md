# Worklog

One line per completed packet: date · packet · commit · notes.

---

2026-07-03 · P0-1 · 20e673e · Ruby skeleton: Gemfile (budget-only), Rakefile, RuboCop, minitest+WebMock harness; net-blocked suite green.
2026-07-03 · P0-2 · — · Thor CLI skeleton (bin/nabu, version + not-implemented stubs) and Nabu::Config with project-relative defaults + commented config/nabu.yml.
2026-07-03 · P0-4 · — · Core primitives: Nabu::Error hierarchy (ParseError/FetchError), Open3-backed Nabu::Shell.run (argv-only, status+stderr on failure), Nabu::Normalize.nfc (UTF-8 NFC, raises on invalid bytes); NFD-Greek regression fixture.
