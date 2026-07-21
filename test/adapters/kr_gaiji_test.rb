# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::KrGaiji (P37-3) — KR-Gaiji, the Kanseki Repository's
  # not-yet-encoded characters, registered as a FEATURE MODULE row (the P34-1
  # bridging precedent), not a text source: it mints no documents, and its
  # charlist feeds the reading-mode gaiji resolution map (config/gaiji/
  # kanripo.tsv). The row exists to give the owner the sanctioned GitFetch
  # path so the curated map can be refreshed; the shared conformance suite
  # (which asserts non-empty passages) deliberately does not apply.
  class KrGaijiTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("kr-gaiji")

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["kr-gaiji"]
      refute_nil entry, "kr-gaiji must be registered in config/sources.yml"
      refute entry.enabled, "a feature module serves no documents — enabled stays false permanently"
      assert_equal "manual", entry.sync_policy
      assert_equal "kr-gaiji", entry.adapter_class.manifest.id
    end

    def test_manifest_is_the_kanripo_grant_attribution
      manifest = Nabu::Adapters::KrGaiji.manifest
      assert_equal "attribution", manifest.license_class, "CC BY SA org grant → attribution, the kanripo posture"
      assert_includes manifest.license, "CC BY SA 4.0"
      assert_equal "gaiji-charlist", manifest.parser_family
      assert_equal "https://github.com/kanripo/KR-Gaiji", manifest.upstream_url
    end

    def test_discover_yields_no_documents_by_design
      adapter = Nabu::Adapters::KrGaiji.new
      assert_empty adapter.discover(FIXTURES).to_a,
                   "a feature module mints no documents — its charlist feeds the display gaiji map"
      Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
    end

    def test_parse_is_unreachable_and_says_so
      ref = Nabu::DocumentRef.new(source_id: "kr-gaiji", id: "urn:nabu:kr-gaiji:x", path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::KrGaiji.new.parse(ref) }
      assert_match(/feature module/, error.message)
    end

    def test_fetch_cone_skips_the_image_tree
      assert_equal ["charlist.org.txt", "README.md"], Nabu::Adapters::KrGaiji::SPARSE_PATHS,
                   "the 5,232-PNG images/ tree the resolution never needs stays outside the cone"
    end

    # The fixture is real KR-Gaiji rows chosen to cover every mapping class the
    # census found — the honesty evidence, not fabricated. Column 3 is the
    # "unicode or IDS representation" (present only for faithful codepoints);
    # column 4 the lossy "normalized version".
    def test_fixture_charlist_carries_the_census_classes
      rows = File.readlines(File.join(FIXTURES, "charlist.org.txt"), encoding: "UTF-8")
                 .reject { |l| l.start_with?("#") }
                 .map { |l| l.chomp.split("\t", -1) }
      by_id = rows.to_h { |f| [f[0], f] }
      assert_equal "𫠦", by_id["KR0001"][2], "a faithful single-codepoint ref (col3 present)"
      assert_empty by_id["KR0002"][2], "a normalized-only ref carries no col3 codepoint"
      assert_equal "若", by_id["KR0002"][3], "…only the lossy col4 substitute"
      assert_empty by_id["KR0809"][2], "the parser's own &KR0809; example is image-only"
      assert_empty by_id["KR0809"][3], "…no col4 either — placeholder is the only honest render"
    end
  end
end
