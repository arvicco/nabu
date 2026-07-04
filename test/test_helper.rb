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
  end
end
