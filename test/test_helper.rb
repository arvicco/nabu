# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"

# The suite must never touch the network. No allowlist.
WebMock.disable_net_connect!

# Every git the suite runs (tests and the code under test alike) gets
# auto-gc and auto-maintenance OFF, through git's env-config channel. A
# commit in a throwaway repo otherwise may DETACH a background gc/maintenance
# that repacks loose objects while a local clone copies them ("fatal: failed
# to copy file") or leaves objects/maintenance.lock behind as mktmpdir's
# cleanup walks the tree (ENOENT). Timing-dependent, so it surfaces under
# load — two tests had already pinned `-c gc.auto=0` by hand; this closes the
# whole class. Appends to any GIT_CONFIG_COUNT already in the environment.
module Nabu
  module TestSupport
    GIT_TEST_CONFIG = { "gc.auto" => "0", "maintenance.auto" => "false" }.freeze

    def self.isolate_git_background_work!(env = ENV)
      base = Integer(env.fetch("GIT_CONFIG_COUNT", "0"), 10)
      present = (0...base).to_h { |i| [env["GIT_CONFIG_KEY_#{i}"], env["GIT_CONFIG_VALUE_#{i}"]] }
      return if GIT_TEST_CONFIG.all? { |key, value| present[key] == value } # inherited from a parent run

      GIT_TEST_CONFIG.each_with_index do |(key, value), offset|
        env["GIT_CONFIG_KEY_#{base + offset}"] = key
        env["GIT_CONFIG_VALUE_#{base + offset}"] = value
      end
      env["GIT_CONFIG_COUNT"] = (base + GIT_TEST_CONFIG.size).to_s
    end
  end
end
Nabu::TestSupport.isolate_git_background_work!

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

    # The strict-skip gate (owner rule 2026-09-03: a local run with
    # skips is a FAILURE, never "everything's just dandy"). Skips exist
    # so PUBLIC clones without the restricted no-redistribution bytes
    # stay green — never so the owner's box can silently under-test.
    # On a box that carries the restricted-fixtures lane at all
    # (local/fixtures/ present, non-empty) every skip escalates to a
    # failure naming what was missing. NABU_ALLOW_SKIPS=1 is the
    # deliberate escape hatch; NABU_STRICT_SKIPS=1 forces the gate on.
    module StrictSkips
      def self.enforce?
        return false if ENV["NABU_ALLOW_SKIPS"] == "1"
        return true if ENV["NABU_STRICT_SKIPS"] == "1"

        Dir.exist?(LOCAL_FIXTURES_ROOT) && !Dir.empty?(LOCAL_FIXTURES_ROOT)
      end

      def skip(message = nil, _backtrace = caller)
        unless StrictSkips.enforce?
          super
          return
        end

        flunk "skip escalated to FAILURE (this box carries local/fixtures/, so every skip " \
              "is missing coverage — owner rule 2026-09-03; NABU_ALLOW_SKIPS=1 is the " \
              "deliberate escape hatch): #{message}"
      end
    end
  end
end

Minitest::Test.prepend(Nabu::TestSupport::StrictSkips)
