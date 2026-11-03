# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"

module Adapters
  # Suda On Line English translations over the maintainer's banked entry
  # export (CC BY-NC-SA → nc). Fixture: a trimmed re-pack of the export
  # (test/fixtures/suda-translations/README.md — grains, keying, recipe).
  class SudaTranslationsTest < Minitest::Test
    include AdapterConformance

    SLUG = "suda-translations"
    FIXTURES = File.expand_path("../fixtures/suda-translations", __dir__)

    def conformance_adapter = Nabu::Adapters::SudaTranslations.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = SLUG

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(letter) = documents.find { |d| d.urn == "urn:nabu:#{SLUG}:#{letter}" } || flunk("#{letter} missing")

    def test_manifest_is_nc_with_the_sol_statement
      manifest = Nabu::Adapters::SudaTranslations.manifest
      assert_equal "nc", manifest.license_class
      assert_match(/Attribution-NonCommercial-ShareAlike/, manifest.license)
    end

    def test_one_document_per_adler_letter_the_misspelled_directory_excluded
      assert_equal %w[urn:nabu:suda-translations:alpha urn:nabu:suda-translations:epsilon
                      urn:nabu:suda-translations:nu],
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_discovery_skips_count_index_pages_and_the_mis_keyed_directory
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 4, skips.skipped_by_rule, "3 letter index pages + omicrioniota/8"
      assert_equal 0, skips.unrecognized
      assert(skips.notes.any? { |n| n.include?("omicrioniota/8") })
    end

    def test_letter_document_shape
      d = doc("nu")
      assert_equal "en", d.language
      assert_equal "Suda On Line: English translations, Adler ν", d.title
      assert_equal "ν", d.metadata["adler_letter"]
      assert_equal "grc", d.metadata["translated_from"]
      assert_equal "urn:cts:greekLit:tlg9010.tlg001.1st1K-grc1", d.metadata["translation_of"]
      assert_equal "3.Ν", d.metadata["first1k_chapter"]
      assert_equal 2, d.metadata["entry_count"]
    end

    def test_passages_are_entries_keyed_by_adler_number
      d = doc("nu")
      assert_equal %w[urn:nabu:suda-translations:nu:27 urn:nabu:suda-translations:nu:28], d.passages.map(&:urn)
      p27 = d.passages.first
      assert_equal 27, p27.sequence
      assert p27.text.start_with?("A city.[1]\nAlso"), p27.text[0, 40]
      a = p27.annotations
      assert_equal "ν 27", a["adler"]
      assert_equal "nu,27", a["sol_key"]
      assert_equal "3.Ν.27", a["first1k_candidate"]
      assert_equal "Ναξία", a["headword"]
      assert_equal "Naxia; Naxos, Naxus", a["translated_headword"]
      assert_equal "David Mirhady", a["translator"]
      assert_equal 6, a["vetters"].size
      assert_equal "high", a["vetting_status"]
      assert a["greek_original"].start_with?("Ναξία: πόλις.")
      assert_includes a["keywords"], "geography"
    end

    def test_no_match_page_skips_inside_its_letter_and_is_named
      d = doc("epsilon")
      assert_equal %w[urn:nabu:suda-translations:epsilon:1], d.passages.map(&:urn)
      assert_equal [{ "file" => "sol-entries/epsilon/4079",
                      "reason" => "no translation record (the CGI's no-matches answer)" }],
                   d.metadata["skipped_entries"]
      assert_equal "2.E", d.metadata["first1k_chapter"], "First1K labels epsilon with a Latin E"
    end

    def test_placeholder_greek_rides_absent
      p1 = doc("alpha").passages.first
      assert_equal "urn:nabu:suda-translations:alpha:1", p1.urn
      refute p1.annotations.key?("greek_original")
      assert_equal "Ἂ ἄ", p1.annotations["headword"]
    end

    def test_letter_without_a_first1k_chapter_carries_no_candidate
      assert_nil Nabu::Adapters::SudaTranslations::FIRST1K_CHAPTERS["zeta"]
      assert_equal "ζ", Nabu::Adapters::SudaTranslations::LETTERS["zeta"]
      assert_equal 27, Nabu::Adapters::SudaTranslations::LETTERS.size
    end

    def test_fetch_is_a_manual_drop_of_the_banked_zip
      Dir.mktmpdir do |root|
        workdir = File.join(root, "canonical", SLUG)
        FileUtils.mkdir_p(workdir)
        drop = Nabu::Adapters::SudaTranslations.drop_dir(workdir)
        assert_equal File.join(root, "incoming", SLUG), drop
        assert_raises(Nabu::ManualDrop::AwaitingAcquisition) { conformance_adapter.fetch(workdir) }

        FileUtils.mkdir_p(drop)
        FileUtils.cp(File.join(FIXTURES, "solEntries.zip"), drop)
        report = conformance_adapter.fetch(workdir)
        assert File.file?(File.join(workdir, "solEntries.zip"))
        assert_equal Nabu::ManualDrop.pin(workdir), report.sha
        assert_equal 3, conformance_adapter.discover(workdir).count
      end
    end

    def test_a_non_zip_drop_is_refused
      Dir.mktmpdir do |root|
        workdir = File.join(root, "canonical", SLUG)
        drop = Nabu::Adapters::SudaTranslations.drop_dir(workdir)
        FileUtils.mkdir_p(drop)
        File.write(File.join(drop, "solEntries.zip"), "<html>login</html>")
        error = assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) }
        assert_match(/refused/, error.message)
      end
    end
  end
end
