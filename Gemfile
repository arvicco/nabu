# frozen_string_literal: true

source "https://rubygems.org"

# Ruby constraint: CI pins 3.3, local dev runs newer interpreters.
# Do not use `~>` here — both 3.3 and 4.x must satisfy this.
ruby ">= 3.3"

# Approved dependency budget (see CLAUDE.md). Ask before adding anything.
# stdlib extraction (ruby-core, zero deps) — no longer a default gem on
# Ruby 3.4+; the bosworth-csv parser family needs it (P12-3).
gem "csv"
gem "faraday"
gem "nokogiri"
gem "sequel"
# The gem bundles its own SQLite engine; the floor pins the engine the
# fts governor and connection profile were re-verified against (2.10.2 →
# SQLite 3.54.1), so a fresh install never resolves an older engine.
gem "sqlite3", ">= 2.10.2"
gem "thor"

group :development, :test do
  gem "minitest"
  gem "rake"
  gem "rubocop"
  gem "webmock"
end
