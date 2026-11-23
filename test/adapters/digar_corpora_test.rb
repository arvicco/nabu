# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::DigarCorpora: the National Library of Estonia's
# DIGAR corpus of freely usable publications — 3,416 Estonian-language
# books as EstNLTK token tables, joined to the ERB national-bibliography
# MARC dump that ships beside them. The fixture (README) holds five real
# tables and trimmed copies of every metadata-zip member:
#
# - b17885899 — 1819 Riga hymn sheet, Fraktur, bad OCR (74 % unsolved),
#   MARC 542 Vabakasutus;
# - b1275075x — 1923 Tallinn children's verse, a conjectured imprint
#   place, NO 542 rights field (trimmed to 300 tokens);
# - b20396119 — 193-? picture book: a u-digit 008 date, the digitizer's
#   stamp on every page, absent from Tinits's processed ERB table;
# - b1623912x — 1841 Jenowewa: an image-only PDF, stamps alone (skip
#   at parse, by rule);
# - b10014949 — a header-only table (skip at discovery, by rule).
class DigarCorporaTest < Minitest::Test
  include AdapterConformance

  HYMN = "urn:nabu:digar-corpora:b17885899"
  VERSE = "urn:nabu:digar-corpora:b1275075x"
  DOLLHOUSE = "urn:nabu:digar-corpora:b20396119"
  JENOWEWA = "urn:nabu:digar-corpora:b1623912x"

  def conformance_adapter = Nabu::Adapters::DigarCorpora.new

  def conformance_workdir = Nabu::TestSupport.fixtures("digar-corpora")

  def conformance_expected_source_id = "digar-corpora"

  def refs
    @refs ||= conformance_adapter.discover(conformance_workdir).to_a
  end

  def documents
    @documents ||= begin
      adapter = conformance_adapter
      refs.each_with_object({}) do |ref, out|
        out[ref.id] = adapter.parse(ref)
      rescue Nabu::DocumentSkipped
        nil
      end
    end
  end

  def test_discovery_takes_every_non_empty_table_and_counts_the_header_only_one
    assert_equal [VERSE, JENOWEWA, HYMN, DOLLHOUSE], refs.map(&:id)
    skips = conformance_adapter.discovery_skips(conformance_workdir)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized, "the metadata zip's five members are known sidecars, never documents"
    assert_match(/header-only/, skips.notes.first)
  end

  def test_a_stamp_only_table_skips_by_rule_at_parse
    ref = refs.find { |r| r.id == JENOWEWA }
    error = assert_raises(Nabu::DocumentSkipped) { conformance_adapter.parse(ref) }
    assert_match(/stamp-only/, error.reason)
  end

  def test_a_stray_file_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(conformance_workdir, "processed_*")), dir)
      File.write(File.join(dir, "processed_txt_tsv", "surprise.tsv"), "x\n")
      skips = conformance_adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_includes skips.notes, "unrecognized file processed_txt_tsv/surprise.tsv"
    end
  end

  def test_the_hymn_sheet_record
    doc = documents.fetch(HYMN)
    assert_equal "et", doc.language
    assert_equal "Enne pihti : Pärrast pühha öhtosöma-aega", doc.title
    meta = doc.metadata
    assert_equal({ "not_before" => 1819, "not_after" => 1819, "raw" => "ERB 008 s1819; 1819", "class" => "edition" },
                 meta["date"])
    assert_equal "Riia", meta["place"], "the 260 imprint place, supplied brackets dropped"
    assert_equal "W. F. Häcker", meta["printer"]
    assert_nil meta["publisher"], "s. n. (sine nomine) mints nothing"
    assert_equal ["est"], meta["languages"], "no 041: the 008 language"
    assert_equal "Vabakasutus", meta["rights"]
    assert_equal "https://creativecommons.org/publicdomain/mark/1.0/", meta["rights_url"]
    assert_includes meta["notes"], "Fraktuur."
    assert_equal "http://digar.nlib.ee/show/nlib-digar:136499", meta["digar_url"]
    assert_in_delta 0.742, meta["ocr_unsolved_share"]
    assert_equal "machine-ocr", meta["text_nature"]
    assert_match(/OCR-i kvaliteet võib olla ebaühtlane/, meta["ocr_note"])
  end

  def test_the_hymn_sheet_passages
    doc = documents.fetch(HYMN)
    assert_equal ["#{HYMN}:1", "#{HYMN}:2"], doc.map(&:urn)
    assert_equal({ "rows" => [0, 137] }, doc.first.annotations)
    assert_includes doc.first.text, "Jesus minno rööm ja illo"
    assert(doc.all? { |p| p.language == "et" })
  end

  def test_a_conjectured_place_and_an_absent_rights_field
    meta = documents.fetch(VERSE).metadata
    assert_equal "Tallinn", meta["place"]
    assert meta["place_conjectural"], "the cataloguer's [Tallinn? :] conjecture is flagged"
    assert_equal "Ühiselu", meta["printer"]
    assert_nil meta["rights"], "the record carries no 542"
    assert_equal "Grünfeldt, Peeter", meta["author"]
    assert_equal "1865-1937", meta["author_dates"]
    assert_equal [{ "name" => "Awendt, Theodor", "dates" => "1889-", "role" => "illustreerija" }],
                 meta["contributors"]
    assert_equal({ "genre" => %w[lastekirjandus luuletused] }, meta["facets"])
    assert_equal 4, meta["stamps_dropped"]
  end

  def test_a_u_digit_date_widens_to_the_decade_and_the_cut_bracket_heals
    doc = documents.fetch(DOLLHOUSE)
    assert_equal "Nuku majake : värsid lastele", doc.title, "a supplied bracket the $c split cut loses its brackets"
    meta = doc.metadata
    assert_equal({ "not_before" => 1930, "not_after" => 1939, "raw" => "ERB 008 s193u; 193-?", "class" => "edition" },
                 meta["date"])
    assert_nil meta["place"], "S.l. (sine loco) mints no place"
    assert_equal "J. Oro", meta["statement_of_responsibility"]
    assert_equal 11, meta["stamps_dropped"]
    refute_includes doc.map(&:text).join(" "), "Rahvusraamatukogu digitaalarhiiv DIGAR"
  end

  def test_the_translation_record_reads_the_language_field
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(conformance_workdir, "processed_*")), dir)
      # Jenowewa's table is stamps alone; give it one real sentence so the
      # record (041 $aest$hger, 752 $dPärnu.) reaches a document.
      path = File.join(dir, "processed_pdf_tsv", "b1623912x.pdf.txt.tsv")
      File.write(path, "#{File.foreach(path).first}0\tJenowewa#{"\t" * 10}\n1\t.#{"\t" * 10}\n")
      adapter = conformance_adapter
      ref = adapter.discover(dir).find { |r| r.id == JENOWEWA }
      meta = adapter.parse(ref).metadata
      assert_equal ["est"], meta["languages"]
      assert_equal ["ger"], meta["original_languages"]
      assert_equal "Perno", meta["place"]
      assert_equal "Pärnu", meta["place_normalized"]
      assert_equal "F. W. Borm", meta["publisher"]
      assert_equal "[2.] uuesti läbi vaadatud ja parandatud tr", meta["edition"]
    end
  end

  def test_the_manifest_reads_the_stricter_license
    manifest = Nabu::Adapters::DigarCorpora.manifest
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 3\.0 EE/, manifest.license)
    assert_match(/Peeter Tinits/, manifest.credit)
  end
end
