# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Ops
  # Nabu::Ops::DossierDrift (P24-0): the `rake site:check` gate rider —
  # presence/mention drift between the local-source dossier descriptions
  # and docs/library.md, never verbatim equality. Red on drift, green on
  # match.
  class DossierDriftTest < Minitest::Test
    Entry = Struct.new(:enabled)

    FakeRegistry = Struct.new(:entries_by_slug) do
      def slugs = entries_by_slug.keys
      def [](slug) = entries_by_slug[slug]
    end

    LIBRARY_MD = <<~MD
      ## Latin inscriptions

      | **Source** | `edh`, license: `attribution` |

      Epitaphs and dedications. Also mentions `lexica` in passing.
    MD

    def with_rig(registry:, dossiers: {}, library: LIBRARY_MD)
      Dir.mktmpdir do |dir|
        shelf_dir = File.join(dir, "local-source")
        FileUtils.mkdir_p(shelf_dir)
        shelf = Nabu::SourceShelf.new(dir: shelf_dir)
        dossiers.each { |slug, description| shelf.write!(Nabu::SourceDossier.new(slug: slug, description: description)) }
        library_md = File.join(dir, "library.md")
        File.write(library_md, library)
        yield Nabu::Ops::DossierDrift.new(shelf_dir: shelf_dir, registry: FakeRegistry.new(registry),
                                          library_md: library_md)
      end
    end

    def test_green_when_dossiers_and_library_cover_each_other
      registry = { "edh" => Entry.new(true), "lexica" => Entry.new(true), "pending" => Entry.new(false) }
      dossiers = { "edh" => "Latin inscriptions.", "lexica" => "The reference shelf.", "pending" => nil }
      with_rig(registry: registry, dossiers: dossiers) do |check|
        assert_empty check.findings
      end
    end

    def test_flags_a_registered_source_without_a_dossier
      with_rig(registry: { "edh" => Entry.new(true) }) do |check|
        findings = check.findings
        assert_equal %w[edh], findings.map(&:slug)
        assert_match(/no dossier/, findings.first.message)
      end
    end

    def test_flags_a_library_mentioned_shelf_whose_dossier_has_no_description
      with_rig(registry: { "edh" => Entry.new(true) }, dossiers: { "edh" => nil }) do |check|
        findings = check.findings
        assert_equal 1, findings.size
        assert_match(/no description/, findings.first.message)
      end
    end

    def test_flags_an_enabled_described_shelf_the_library_never_mentions
      registry = { "damaskini" => Entry.new(true) }
      with_rig(registry: registry, dossiers: { "damaskini" => "Balkan Slavic damaskini." }) do |check|
        findings = check.findings
        assert_equal 1, findings.size
        assert_match(/never\s+mentions/, findings.first.message)
      end
    end

    def test_tolerates_a_described_but_disabled_shelf_off_the_map
      registry = { "pending" => Entry.new(false) }
      with_rig(registry: registry, dossiers: { "pending" => "Awaiting first sync." }) do |check|
        assert_empty check.findings, "pending shelves join the map when they go live (MAINTENANCE duty 2)"
      end
    end

    def test_flags_a_malformed_dossier
      registry = { "edh" => Entry.new(true) }
      with_rig(registry: registry) do |check|
        File.write(File.join(File.dirname(check.instance_variable_get(:@library_md)), "local-source", "edh.md"),
                   "not a dossier")
        findings = check.findings
        assert_equal 1, findings.size
        assert_match(/malformed/, findings.first.message)
      end
    end

    def test_reports_an_unseeded_shelf_as_one_loud_finding
      Dir.mktmpdir do |dir|
        check = Nabu::Ops::DossierDrift.new(shelf_dir: File.join(dir, "missing"),
                                            registry: FakeRegistry.new({ "edh" => Entry.new(true) }),
                                            library_md: File.join(dir, "library.md"))
        findings = check.findings
        assert_equal 1, findings.size
        assert_match(/not seeded/, findings.first.message)
      end
    end
  end
end
