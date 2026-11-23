# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"
require "json"

module Ops
  # Nabu::Ops::InspectTextScrub + Store::InspectedTextScan: the live-rows
  # instrument for inspected-object passage text. The defective rows are
  # minted exactly as the pre-line-model rsti parse minted them — each
  # RS 17.238 transliteration value (the quarantine fixture, verbatim)
  # stringified with #to_s — so the scan meets the live shape, not a guess.
  class InspectTextScrubTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("rsti")
    QUARANTINE_TEXT = File.join(FIXTURES, "quarantine", "texts", "39ba4c2f-6d82-4b6c-a13b-6ded30136c42.json")

    def setup
      @catalog = store_test_db
      @source = Nabu::Store::Source.create(slug: "rsti", name: "RSTI", adapter_class: "Nabu::Adapters::Rsti",
                                           license_class: "nc")
    end

    # The pre-fix passages of RS 17.238: `line["value"].to_s` per line.
    def pre_fix_rs_17_238_texts
      text = JSON.parse(File.read(QUARANTINE_TEXT)).dig("ochre", "text")
      Nabu::Adapters::OchreJsonParser.sections(text)["transliteration"].flat_map do |surface|
        surface["lines"].select { |leaf| leaf["type"] == "line" && leaf["value"] }.map { |leaf| leaf["value"].to_s }
      end
    end

    def add_document(urn, texts, withdrawn: false, source: @source)
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: "t", language: "akk",
                                         content_sha256: "x", revision: 1, withdrawn: withdrawn)
      texts.each_with_index do |text, index|
        Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:#{index + 1}", sequence: index,
                                    language: "akk", text: text, text_normalized: text,
                                    content_sha256: "x", revision: 1)
      end
      doc
    end

    def scrub(**) = Nabu::Ops::InspectTextScrub.new(catalog: @catalog, slug: "rsti", **)

    def test_the_detector_is_the_conformance_invariants_own
      assert_same Nabu::InspectedText::PATTERN, AdapterConformance::INSPECTED_OBJECT_TEXT
    end

    def test_the_scan_finds_the_pre_fix_hash_text_and_nothing_else
      texts = pre_fix_rs_17_238_texts
      hashes = texts.count { |t| t.start_with?("{") }
      assert_operator hashes, :>=, 19, "the fixture reproduces the live Hash-text shape"
      add_document("urn:nabu:rsti:rs-17.238", texts)
      add_document("urn:nabu:rsti:rs-1.001", ["{restored} a-na", "[x] b-ri", "#2 line", " \n{\"k\" => 1}"])
      add_document("urn:nabu:rsti:rs-9.999", ['{"gone"=>1}'], withdrawn: true)
      other = Nabu::Store::Source.create(slug: "other", name: "Other", adapter_class: "X", license_class: "open")
      add_document("urn:nabu:other:1", ['{"k"=>1}'], source: other)

      hits = Nabu::Store::InspectedTextScan.new(db: @catalog).call(slug: "rsti")
      assert_equal hashes + 1, hits.size, "every Hash-shaped line + the whitespace-led one; editorial braces pass"
      assert_equal ["urn:nabu:rsti:rs-1.001:4"],
                   hits.select { |h| h.document_urn.end_with?("1.001") }.map(&:passage_urn)
      refute(hits.any? { |h| h.document_urn.include?("9.999") }, "withdrawn documents are not live rows")
      assert_empty Nabu::Store::InspectedTextScan.new(db: @catalog).call(slug: "absent")
    end

    def test_the_scan_report_counts_and_samples_and_points_at_scrub
      add_document("urn:nabu:rsti:rs-17.238", pre_fix_rs_17_238_texts)
      report = scrub(sample: 2).report
      assert_match(/inspect-shaped live passage\(s\) in 1 document\(s\)/, report)
      assert_match(/rs-17\.238:1  \{"i" ?=>/, report)
      assert_match(/… \d+ more/, report)
      assert_match(/SCRUB=1/, report)
    end

    def test_a_clean_source_reports_zero
      add_document("urn:nabu:rsti:rs-1.001", ["a-na"])
      assert_match(/— 0 inspect-shaped live passage\(s\) in 0 document\(s\)\z/, scrub(scrub: true).report)
    end

    # SCRUB=1 re-parses from canonical in memory and tells the truth about
    # the resync: RS 17.238 now quarantines (its held rows are shielded), a
    # document the current adapter parses clean is replaced, a vanished one
    # withdraws. Nothing is written.
    def test_scrub_diagnoses_each_document_and_prints_the_source_wide_command
      Dir.mktmpdir do |workdir|
        FileUtils.cp_r(File.join(FIXTURES, "."), workdir)
        %w[sets texts].each do |sub|
          Dir[File.join(FIXTURES, "quarantine", sub, "*")].each { |f| FileUtils.cp(f, File.join(workdir, sub)) }
        end
        add_document("urn:nabu:rsti:rs-17.238", pre_fix_rs_17_238_texts)
        add_document("urn:nabu:rsti:rs-1.001", ['{"i"=>"ta"}'])
        add_document("urn:nabu:rsti:rs-99.999", ['{"i"=>"ta"}'])
        before = StoreTestDB::Templates.digest(@catalog)

        tool = scrub(scrub: true, adapter: Nabu::Adapters::Rsti.new, workdir: workdir)
        outcomes = tool.verdicts.to_h { |v| [v.document_urn, v.outcome] }
        assert_equal({ "urn:nabu:rsti:rs-1.001" => :clean, "urn:nabu:rsti:rs-17.238" => :quarantines,
                       "urn:nabu:rsti:rs-99.999" => :absent }, outcomes)
        report = tool.report
        assert_match(/rs-17\.238 \(\d+ passage\(s\)\): now QUARANTINES/, report)
        assert_match(/only a FULL rebuild clears them/, report)
        assert_match(/piece order is unrecoverable/, report, "the quarantine reason rides")
        assert_includes report, "bin/nabu sync rsti --parse-only"
        assert_match(/no per-document sync path exists/, report)
        assert_equal before, StoreTestDB::Templates.digest(@catalog), "the instrument never writes"
      end
    end

    # An adapter that still emits the shape: the verdict says fix the
    # adapter first (a resync would reload the same text).
    def test_scrub_flags_an_adapter_that_still_emits_inspected_text
      add_document("urn:nabu:rsti:rs-1.001", ['{"i"=>"ta"}'])
      ref = Nabu::DocumentRef.new(source_id: "rsti", id: "urn:nabu:rsti:rs-1.001", path: "x", metadata: {})
      document = Nabu::Document.new(urn: ref.id, language: "akk", canonical_path: "x")
      document << Nabu::Passage.new(urn: "#{ref.id}:1", language: "akk", text: '{"i"=>"ta"}', sequence: 0)
      adapter = Struct.new(:ref, :document) do
        def discover(_workdir) = [ref].each
        def parse(_ref) = document
      end.new(ref, document)
      report = scrub(scrub: true, adapter: adapter, workdir: "x").report
      assert_match(/STILL inspect-shaped/, report)
      assert_match(/fix the adapter first/, report)
      refute_includes report, "--parse-only   #"
    end
  end
end
