# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"

# The suite must never touch the network. No allowlist.
WebMock.disable_net_connect!

require "nabu"

# Shared test support: the adapter conformance suite and its test rig.
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

module Nabu
  # Test-only helpers.
  module TestSupport
    FIXTURES_ROOT = File.expand_path("fixtures", __dir__)

    # Fixture directory for +source+ (its test/fixtures/<source> subdir).
    # Overridable via NABU_FIXTURE_DIR so `rake fixtures:check` can point an
    # adapter test at a freshly fetched copy WITHOUT touching the checked-in
    # fixtures: the override replaces the fixtures ROOT, and <root>/<source>/...
    # mirrors the committed layout. Unset (the normal suite) → the committed
    # fixtures, byte-for-byte the previous behaviour.
    def self.fixtures(source)
      File.join(ENV.fetch("NABU_FIXTURE_DIR", FIXTURES_ROOT), source)
    end

    # P84-7: RESTRICTED-source fixtures — real upstream bytes that MUST NOT
    # enter the public repo (INT-NC no-redistribution: the IvdNT Dutch
    # corpora). They live under the gitignored instance root local/fixtures/
    # <source>/, never test/fixtures/. An adapter test resolves its fixture
    # dir here and `skip`s every data-bearing case when the dir is absent —
    # so CI and other users pass WITHOUT the bytes, while the owner's local
    # suite (bytes present) tests against reality. Overridable for the same
    # reason as +fixtures+.
    LOCAL_FIXTURES_ROOT = File.join(Nabu::Config::PROJECT_ROOT, "local", "fixtures")

    def self.local_fixtures(source)
      File.join(ENV.fetch("NABU_LOCAL_FIXTURE_DIR", LOCAL_FIXTURES_ROOT), source)
    end

    # Present AND non-empty — a bare directory is treated as absent, so a
    # stray mkdir never turns a skip into a hard failure.
    def self.local_fixtures?(source)
      dir = local_fixtures(source)
      Dir.exist?(dir) && !Dir.empty?(dir)
    end
  end
end
