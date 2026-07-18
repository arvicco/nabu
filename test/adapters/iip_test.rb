# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# IIP adapter tests (P30-6): discovery over the cloned epidoc-files/ tree,
# the iip-epidoc ordinal line grain (no <lb n> exists upstream), the
# transcription→diplomatic layer ladder, the metadata-only records, the
# NFC exemption riding on the honest arc mapping, the header facets/date/
# findspot, and the filename-only identity. Includes the shared
# AdapterConformance suite; fixtures are 6 whole real records
# (test/fixtures/iip/README.md).
class IipTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("iip")

  ALL_URNS = %w[
    urn:nabu:iip:abur0001 urn:nabu:iip:caes0022 urn:nabu:iip:caes0371
    urn:nabu:iip:dabb0001 urn:nabu:iip:hkur0001 urn:nabu:iip:jeru0490
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Iip.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "iip"
  end

  # caes0371 has no edition divs at all — a catalogued object with no
  # machine-readable text, marked by the parser itself (the isicily
  # text_layer:none precedent), never a blanket override.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_quotes_the_archival_license_bytes
    manifest = Nabu::Adapters::Iip.manifest
    assert_equal "iip", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/Creative Commons Attribution-NonCommercial 4\.0 International License/,
                 manifest.license, "the archival copies' own words, verbatim")
    assert_match(/no LICENSE file/i, manifest.license,
                 "the honest absence: the repo root and GitHub license field carry nothing")
    assert_match(%r{10\.26300/pz1d-st89}, manifest.license, "the DOI-link attribution requirement")
    assert_equal "iip-epidoc", manifest.parser_family
    assert_equal "https://github.com/Brown-University-Library/iip-texts", manifest.upstream_url
  end

  def test_remote_probe_is_the_git_default_over_the_repo_url
    assert_equal :git, Nabu::Adapters::Iip.remote_probe_strategy
    assert_equal ["https://github.com/Brown-University-Library/iip-texts"],
                 Nabu::Adapters::Iip.upstream_repo_urls
  end

  def test_no_reference_edges_because_the_corpus_carries_no_concordances
    refute Nabu::Adapters::Iip.reference_edges?,
           "census 2026-07-18: the only idno/@type corpus-wide is IIP itself — " \
           "there is nothing to mint edges from"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_record_file_sorted
    refs = Nabu::Adapters::Iip.new.discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id)
  end

  def test_discover_skips_non_record_xml_and_counts_it
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "epidoc-files"))
      FileUtils.cp(File.join(FIXTURES, "epidoc-files", "abur0001.xml"),
                   File.join(dir, "epidoc-files", "abur0001.xml"))
      # The repo keeps a template beside the records (census 2026-07-18:
      # aaTestFile.xml — its very name breaks the <site><nnnn> shape).
      File.write(File.join(dir, "epidoc-files", "aaTestFile.xml"), "<TEI/>")
      adapter = Nabu::Adapters::Iip.new
      assert_equal ["urn:nabu:iip:abur0001"], adapter.discover(dir).to_a.map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule, "the template is skipped by rule, visibly"
      assert_predicate skips, :clean?
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Iip.new.discover(dir).to_a
    end
  end

  # --- the ordinal line grain -------------------------------------------------

  def test_greek_invocation_lines_with_implicit_first_line
    document = parse("urn:nabu:iip:abur0001")
    assert_equal "grc", document.language
    assert_equal "Abur 0001", document.title
    assert_equal (1..10).map { |n| "urn:nabu:iip:abur0001:#{n}" }, document.map(&:urn),
                 "no <lb> carries @n anywhere in IIP — lines are ordinal; the text " \
                 "before the first <lb/> is line 1"
    assert_equal "Κύριε Ἰησοῦ Χριστέ μνήσθητι", document.first.text,
                 "expan reads abbr+ex expanded"
    assert_equal "τοῦ δούλου σου […]ά", document.to_a[1].text,
                 "supplied reads through; the gap marker fuses with the following bare orig"
    assert_equal "τόπῳ τούτῳ", document.to_a.last.text
    assert_equal 10, document.to_a[1].annotations["leiden"]["supplied_chars"]
    assert_equal 1, document.to_a[1].annotations["leiden"]["gaps"].size
  end

  def test_break_no_delimits_lines_like_any_lb
    document = parse("urn:nabu:iip:abur0001")
    assert_equal ["πρεσβυτέρου καί πάν", "των τῶν προσκυ"],
                 document.to_a[3..4].map(&:text),
                 "<lb break=\"no\"/> still opens a new line (the print-margin rule): πάν|των"
  end

  def test_textparts_take_ordinal_path_segments_and_restart_line_numbers
    document = parse("urn:nabu:iip:caes0022")
    assert_equal "lat", document.language
    assert_equal %w[
      urn:nabu:iip:caes0022:p1:1
      urn:nabu:iip:caes0022:p1:2
      urn:nabu:iip:caes0022:p1:3
      urn:nabu:iip:caes0022:p1:4
      urn:nabu:iip:caes0022:p2:1
    ], document.map(&:urn),
                 "only 44 of 132 textparts corpus-wide carry @n — the path segment is the " \
                 "textpart's ORDINAL (p1, p2…), uniform for all; the stray <lb/> BETWEEN " \
                 "the two textparts mints nothing"
    assert_equal "Sexto […]", document.first.text
    assert_equal "[…] legato Augusti pro praetore Syriae Palaestinae", document.to_a[1].text
    assert_equal "cher", document.to_a.last.text
    assert_equal({ "subtype" => "section", "n" => "a" },
                 document.first.annotations["textpart"],
                 "upstream's own labels ride as an annotation, not as urn material")
    assert_equal 36, document.to_a[1].annotations["leiden"]["supplied_chars"]
  end

  def test_choice_of_two_unclears_reads_the_first
    document = parse("urn:nabu:iip:jeru0490")
    assert_equal ["[…]יר· בן ·א[…]", "י·אד"], document.map(&:text),
                 "choice(unclear ד | unclear ג) keeps the first reading; the " \
                 "word-dividing-dot <g> keeps its text; U+0387 folds to U+00B7 under NFC"
    assert_equal 1, document.to_a.last.annotations["leiden"]["unclear_chars"]
    assert document.first.text.unicode_normalized?(:nfc),
           "he maps to heb, which is NOT NFC-exempt — the boundary normalizes"
  end

  # --- languages (honest mapping) ---------------------------------------------

  def test_document_language_maps_the_main_lang_honestly
    assert_equal "grc", parse("urn:nabu:iip:abur0001").language
    assert_equal "arc", parse("urn:nabu:iip:dabb0001").language
    assert_equal "heb", parse("urn:nabu:iip:jeru0490").language
    assert_equal "lat", parse("urn:nabu:iip:caes0022").language
    assert_equal "und", parse("urn:nabu:iip:caes0371").language,
                 "upstream's explicit \"x-unknown\" is und, never a guess"
  end

  def test_passage_language_is_the_document_language_not_the_div_tag
    document = parse("urn:nabu:iip:dabb0001")
    assert_equal ["arc"], document.map(&:language).uniq,
                 "dabb0001's edition div says lang=\"heb\" on an arc record — upstream tags " \
                 "Hebrew-SCRIPT editions heb regardless of language, so the curated " \
                 "textLang/@mainLang is the only honest per-passage language"
  end

  def test_aramaic_text_is_byte_verbatim_under_the_nfc_exemption
    document = parse("urn:nabu:iip:dabb0001")
    assert_equal "אלעזר בר רבה עבד עמודיה דעל מן", document.first.text
    greek_inline = document.to_a.last
    assert_equal "Ῥούστικος ἔκτισεν כפתה ופצ ימיה […]", greek_inline.text,
                 "arc is on Normalize::NFC_EXEMPT_LANGUAGES: the file's U+1F7B (upsilon+oxia) " \
                 "survives byte-verbatim where NFC would rewrite it to U+03CD — foreign Greek " \
                 "spans read through inline"
    refute greek_inline.text.unicode_normalized?(:nfc)
    assert greek_inline.text.valid_encoding?
  end

  def test_other_langs_ride_as_metadata
    assert_equal ["grc"], parse("urn:nabu:iip:dabb0001").metadata["other_languages"]
    assert_nil parse("urn:nabu:iip:jeru0490").metadata["other_languages"],
               "jeru0490's otherLangs is the empty string — an honest absence"
  end

  # --- the layer ladder -------------------------------------------------------

  def test_a_diplomatic_only_record_falls_back_and_says_so
    document = parse("urn:nabu:iip:hkur0001")
    assert_equal "arc", document.language
    assert_equal "diplomatic", document.metadata["text_layer"],
                 "no transcription div exists — the letters-only diplomatic edition is " \
                 "the record's only machine-readable text (361 records corpus-wide)"
    assert_equal ["urn:nabu:iip:hkur0001:1"], document.map(&:urn),
                 "the leading <lb/> before any text opens no phantom empty line"
    assert_equal "אלעזר בר יודן בר סוסו", document.first.text
    assert_equal 1, document.first.annotations["leiden"]["unclear_chars"]
  end

  def test_a_record_with_no_editions_is_metadata_only
    document = parse("urn:nabu:iip:caes0371")
    assert_equal 0, document.size
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "caes0371", document.title
  end

  def test_a_transcription_record_carries_no_layer_marker
    assert_nil parse("urn:nabu:iip:abur0001").metadata["text_layer"],
               "transcription is the default citable layer — only deviations are marked"
  end

  # --- header metadata --------------------------------------------------------

  def test_facets_strip_the_taxonomy_hash_and_keep_the_raw_pointer
    metadata = parse("urn:nabu:iip:abur0001").metadata
    assert_equal({ "values" => ["invocation"], "raw" => "#invocation" },
                 metadata.dig("facets", "genre"))
    assert_equal({ "values" => ["christian"], "raw" => "#christian" },
                 metadata.dig("facets", "religion"))
    assert_equal({ "values" => ["mosaic"], "raw" => "#mosaic" },
                 metadata.dig("facets", "object_type"))
    assert_equal({ "values" => ["tessellated"], "raw" => "#tessellated" },
                 metadata.dig("facets", "execution"))
  end

  def test_unhashed_multi_token_facets_survive_as_written
    metadata = parse("urn:nabu:iip:hkur0001").metadata
    assert_equal({ "values" => %w[dedicatory building], "raw" => "dedicatory building" },
                 metadata.dig("facets", "genre"),
                 "upstream writes some class/ana values without the # pointer — tokens " \
                 "either way, raw verbatim")
    assert_equal({ "values" => %w[floor mosaic], "raw" => "floor mosaic" },
                 metadata.dig("facets", "object_type"))
  end

  def test_date_rides_with_signed_years_and_the_period
    metadata = parse("urn:nabu:iip:jeru0490").metadata
    assert_equal(-100, metadata.dig("date", "not_before"), "notBefore=\"-0100\" is 100 BCE, signed")
    assert_equal 100, metadata.dig("date", "not_after")
    assert_equal "1st Century BCE to 1st Century CE", metadata.dig("date", "raw")
    assert_equal "http://n2t.net/ark:/99152/p0m63njgvtd http://n2t.net/ark:/99152/p0m63njbxb9",
                 metadata.dig("date", "period"), "Periodo URIs verbatim, both of them"
    assert_equal({ "raw" => "Date Unknown", "period" => "Unknown" },
                 parse("urn:nabu:iip:caes0371").metadata["date"],
                 "no notBefore/notAfter — the honest boundless date")
    assert_equal "Talmudic", parse("urn:nabu:iip:abur0001").metadata.dig("date", "period")
  end

  def test_findspot_rides_with_the_geo_kept_verbatim
    metadata = parse("urn:nabu:iip:abur0001").metadata
    assert_equal({ "region" => "Judaea", "settlement" => "Bethennim",
                   "site" => "Church complex", "locus" => "Room A",
                   "geo" => "31.565,35.1288" }, metadata["place"],
                 "settlement text excludes its embedded <geo> child; geo stays verbatim")
    assert_equal({ "region" => "Coastal Plain", "settlement" => "Caesarea" },
                 parse("urn:nabu:iip:caes0371").metadata["place"],
                 "empty site elements are honest absences")
  end

  def test_summary_rides_as_metadata
    assert_equal "Bethennim (Khirbet Abu Rish), 300 CE - 700 CE. Mosaic. Invocation.",
                 parse("urn:nabu:iip:abur0001").metadata["summary"]
  end

  # --- identity ---------------------------------------------------------------

  def test_urn_mismatch_is_a_parse_error
    parser = Nabu::Adapters::IipEpidocParser.new
    error = assert_raises(Nabu::ParseError) do
      parser.parse(File.join(FIXTURES, "epidoc-files", "abur0001.xml"),
                   urn: "urn:nabu:iip:zzzz9999")
    end
    assert_match(/urn mismatch/, error.message)
  end

  def test_in_file_idno_drift_is_a_parse_error
    # 29 records corpus-wide carry a publicationStmt idno naming a DIFFERENT
    # record (all four arch000N say jeri0017) — upstream copy-paste drift,
    # quarantined never repaired. Reproduced with real bytes under a
    # different filename: the file is byte-verbatim abur0001, whose in-file
    # idno then disagrees with the name discover minted the urn from.
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "epidoc-files"))
      FileUtils.cp(File.join(FIXTURES, "epidoc-files", "abur0001.xml"),
                   File.join(dir, "epidoc-files", "abcd0002.xml"))
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::IipEpidocParser.new.parse(
          File.join(dir, "epidoc-files", "abcd0002.xml"), urn: "urn:nabu:iip:abcd0002"
        )
      end
      assert_match(/idno/, error.message)
    end
  end

  def test_a_record_without_a_publication_idno_is_not_drift
    # jeru0490 carries NO publicationStmt idno (the 3,744-record norm);
    # absence is never quarantined — the filename is the identity.
    assert_equal "urn:nabu:iip:jeru0490", parse("urn:nabu:iip:jeru0490").urn
  end

  private

  def parse(urn)
    adapter = Nabu::Adapters::Iip.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "no ref #{urn}"
    adapter.parse(ref)
  end
end
