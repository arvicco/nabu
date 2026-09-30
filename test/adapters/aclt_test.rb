# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"

module Adapters
  # ACLT (P110-2, Q110): the Annotated Corpus of Luwian Texts —
  # Yakubovich's edition, delivered by Arkhangelskiy as Tsakorpus
  # per-inscription JSON (personal grant → research_private). Fixtures
  # are three real files copied whole from the emailed archive: the
  # YALE seal (one clause, both representations), TRAGANA (LOCRIS)
  # (the parenthetical-title slug case), and the KARKAMIŠ B39a
  # upstream tombstone (zero analyzed words — skip-by-rule).
  class AcltTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("aclt")

    def conformance_adapter = Nabu::Adapters::Aclt.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "aclt"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).filter_map do |ref|
        conformance_adapter.parse(ref)
      rescue Nabu::DocumentSkipped
        nil
      end
    end

    def doc(suffix) = documents.find { |d| d.urn.end_with?(":#{suffix}") } || flunk("#{suffix} missing")

    def test_discovers_one_document_per_inscription_titled_slug
      assert_equal %w[urn:nabu:aclt:karkamiš.b39a urn:nabu:aclt:tragana.(locris)
                      urn:nabu:aclt:yale.seal],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_clause_passage_pairs_the_two_representations
      d = doc("yale.seal")
      assert_equal "hlu", d.language
      assert_equal "YALE seal", d.title
      assert_equal 1, d.passages.size
      p1 = d.passages.first
      assert_equal "Lawadas(sa)", p1.text, "the broad transcription is the text"
      assert_equal "la-wa/i-tà-sa", p1.annotations["signs"],
                   "the sign-by-sign transliteration rides as the signs layer"
      assert_equal "1", p1.annotations["line"]
      assert_equal "Lawada-", p1.annotations["lemmas"]
      assert_equal "Lawada (PN)", p1.annotations["gloss"]
    end

    def test_region_rides_as_facet_and_metadata
      d = doc("yale.seal")
      assert_equal "Seals", d.metadata["region"]
      assert_equal({ "value" => "Seals" }, d.metadata.dig("facets", "region"))
      assert_equal "Miscellaneous", doc("tragana.(locris)").metadata["region"]
    end

    def test_upstream_tombstone_skips_by_rule
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id.end_with?("karkamiš.b39a") }
      error = assert_raises(Nabu::DocumentSkipped) { adapter.parse(ref) }
      assert_match(/no analyzed words/, error.reason)
    end

    def test_awaiting_acquisition_card_names_the_drop_path
      Dir.mktmpdir do |root|
        workdir = File.join(root, "canonical", "aclt")
        FileUtils.mkdir_p(workdir)
        error = assert_raises(Nabu::ManualDrop::AwaitingAcquisition) do
          Nabu::Adapters::Aclt.new.fetch(workdir)
        end
        assert_match(/luwian_aclt\.7z/, error.message)
        assert_match(%r{incoming/aclt}, error.message)
      end
    end

    def test_drop_ingests_and_extracts_the_json_tree
      Dir.mktmpdir do |root|
        workdir = File.join(root, "canonical", "aclt")
        drop = File.join(root, "incoming", "aclt")
        FileUtils.mkdir_p(workdir)
        FileUtils.mkdir_p(drop)
        archive = File.join(drop, "luwian_aclt.7z")
        build_7z(archive)

        report = Nabu::Adapters::Aclt.new.fetch(workdir)
        refute_nil report.sha
        json = Dir.glob(File.join(workdir, "luwian_aclt", "json", "*.json"))
        assert_equal 1, json.size, "the archive's json tree extracts beside the held archive"

        # Idempotent re-fetch on the held ingest: no-op, tree intact.
        report2 = Nabu::Adapters::Aclt.new.fetch(workdir)
        assert_equal report.sha, report2.sha
      end
    end

    private

    # A minimal REAL 7z (bsdtar --format 7zip over the YALE seal fixture,
    # the archive's own luwian_aclt/json/ layout) ships as a fixture —
    # the fetch test's drop.
    def build_7z(target)
      FileUtils.cp(File.join(FIXTURES, "mini-luwian_aclt.7z"), target)
    end
  end
end
