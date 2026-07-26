# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Elephantine adapter tests (P47-1): the island's 4,000-year multilingual
# documentary corpus (Berlin ERC project, elephantine.smb.museum) — TEI P5
# against a project DTD, NOT EpiDoc; the new `elephantine-tei` family.
#
# What is exercised, all against WHOLE real files (fixture README):
# - per-document language from msContents textLang/@mainLang mapped to the
#   registry's Egyptian-family convention (arc / grc / egy-Egyd — the
#   papyri-ddbdp precedent for Demotic), incl. the census's trailing-space
#   taxonomy id and the space-separated script+lang <ab xml:lang> pairs;
# - line-grain passages from <lb> milestones inside <ab>, page-scoped by the
#   <pb n> milestones (R.1 … V.vso.1 — spaces in upstream @n fold to dots,
#   the oracc label rule), duplicates taking the house :b2 disambiguator;
# - the diplomatic Leiden idiom (gap → […], del → ⟦…⟧, surplus → {…},
#   supplied/unclear/damage read through and counted);
# - the readable predicate: citable lines need a letter/digit — an
#   all-lacunae flagged edition (100141) and a catalog-only record (100009)
#   are METADATA-ONLY documents ("text_layer" => "none", the EDR precedent),
#   never quarantines;
# - the -en translation sibling lane (the aes -de / oracc -en mold): one
#   parallel document per record with a readable English translation div,
#   suffix-aligned line urns, DocumentSkipped when the div is empty;
# - the licence pin (per-file CC BY-SA 3.0 — drift is a LOUD ParseError),
#   identity cross-check (root xml:id vs caller urn), TM id capture, and the
#   EDH/EDR-shaped structured dating for the timeline lane.
class ElephantineTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("elephantine")

  ORIGINAL_URNS = %w[
    urn:nabu:elephantine:002881 urn:nabu:elephantine:100007
    urn:nabu:elephantine:100009 urn:nabu:elephantine:100117
    urn:nabu:elephantine:100141 urn:nabu:elephantine:307762
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Elephantine.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "elephantine"
  end

  # 100141 (all-lacunae edition — the site's text flag lies) and 100009
  # (catalog-only, self-closed divs) parse to metadata-only documents,
  # marked by the parser itself — never a blanket override.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_records_the_per_file_grant_and_the_site_discrepancy
    manifest = Nabu::Adapters::Elephantine.manifest
    assert_equal "elephantine", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 3\.0/, manifest.license, "the per-document in-file grant governs (D46-a)")
    assert_match(/CC BY-NC-SA 3\.0 DE/, manifest.license,
                 "the site legal notice's contradicting claim, recorded verbatim (D47-d)")
    assert_equal "elephantine-tei", manifest.parser_family
    assert_equal "https://elephantine.smb.museum", manifest.upstream_url
  end

  def test_remote_probe_heads_a_record_not_a_git_remote
    assert_equal :http_zip, Nabu::Adapters::Elephantine.remote_probe_strategy
    targets = Nabu::Adapters::Elephantine.http_probe_targets
    assert_equal 1, targets.size
    assert_match(%r{/xml/elephantine_erc_db_\d{6}\.tei\.xml\z}, targets.first.zip_url)
    assert_equal Nabu::ElephantineFetch::STATE_FILE, targets.first.state_file
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_original_and_translation_refs_sorted
    refs = conformance_adapter.discover(FIXTURES).to_a
    expected = ORIGINAL_URNS.flat_map { |urn| [urn, "#{urn}-en"] }.sort
    assert_equal expected, refs.map(&:id)
    refs.each { |ref| assert_equal "elephantine", ref.source_id }
  end

  def test_discover_without_translations_yields_only_originals
    refs = Nabu::Adapters::Elephantine.new.discover(FIXTURES).to_a
    assert_equal ORIGINAL_URNS, refs.map(&:id)
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Elephantine.new.discover(dir).to_a
    end
  end

  def test_discovery_skips_count_authority_files_by_rule
    skips = Nabu::Adapters::Elephantine.new.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule, "elephantine_erc_db_places.tei.xml is an authority file, not a record"
    assert_equal 0, skips.unrecognized
    assert_predicate skips, :clean?
  end

  # --- language minting (the registry's Egyptian-family convention) -----------

  def test_document_languages_map_main_lang_to_registry_codes
    expected = {
      "urn:nabu:elephantine:002881" => "grc",      # grc-Grek
      "urn:nabu:elephantine:307762" => "arc",      # arc-Armi (Imperial Aramaic, Hebrew script)
      "urn:nabu:elephantine:100007" => "egy-Egyd", # egy-x-demp-Egyd-x-Egydmd
      "urn:nabu:elephantine:100117" => "egy-Egyd", # egy-x-demr-Egyd-x-Egydlt
      "urn:nabu:elephantine:100009" => "egy-Egyd"
    }
    expected.each do |urn, language|
      assert_equal language, parse(urn).language, urn
    end
  end

  def test_trailing_space_taxonomy_id_still_maps
    assert_equal "egy-Egyd", parse("urn:nabu:elephantine:100141").language,
                 "mainLang=\"egy-x-dempr-Egyd-x-Egydmdlt \" carries the census's trailing space"
  end

  # --- the Aramaic legal exemplar (RTL, damage idiom, del, choice) ------------

  def test_aramaic_document_line_urns_are_page_scoped
    document = parse("urn:nabu:elephantine:307762")
    recto = (1..15).map { |n| "urn:nabu:elephantine:307762:R.#{n}" }
    verso = ["urn:nabu:elephantine:307762:V.vso.1", "urn:nabu:elephantine:307762:V.vso.2"]
    assert_equal recto + verso, document.map(&:urn),
                 "upstream <lb n=\"vso 1\"> folds its space to a dot (the oracc label rule)"
    document.each { |passage| assert_equal "arc", passage.language }
  end

  def test_aramaic_plain_line_reads_verbatim
    document = parse("urn:nabu:elephantine:307762")
    line4 = document.find { |p| p.urn.end_with?(":R.4") }
    assert_equal "ואנה בעלה מנ יומא זנה ועד עלמ הנעלת לי תמת בידה לבש 1 זי עמר שוה כספ",
                 line4.text
  end

  def test_erasure_reads_in_leiden_double_brackets
    document = parse("urn:nabu:elephantine:307762")
    line5 = document.find { |p| p.urn.end_with?(":R.5") }
    assert_includes line5.text, "⟦חפנ 1⟧", "<del rend=\"erasure\"> is kept, wrapped (CelticLeiden)"
    assert line5.annotations["leiden"]["cancelled"]
  end

  def test_choice_reads_corr_over_sic
    document = parse("urn:nabu:elephantine:307762")
    line7 = document.find { |p| p.urn.end_with?(":R.7") }
    assert_includes line7.text, "בעדה", "sic ו / corr ד — the editor's correction is the reading"
  end

  def test_damage_and_supplied_ride_the_leiden_annotations
    document = parse("urn:nabu:elephantine:307762")
    line1 = document.first
    leiden = line1.annotations["leiden"]
    assert_operator leiden["supplied_chars"], :>, 0
    assert_operator leiden["damaged_chars"], :>, 0
  end

  def test_aramaic_metadata_titles_tm_and_place
    document = parse("urn:nabu:elephantine:307762")
    assert_equal "Document of Wifehood Between Ananiah son of Azariah, servant of Yaho, " \
                 "and Meshullam son of Zaccur for his dauther Tamet", document.title,
                 "the msItem modern title (upstream's own typo kept verbatim)"
    metadata = document.metadata
    assert_equal "89454", metadata["tm_nr"], "the Trismegistos link's quick= id"
    assert_equal "Pap. New York, Brooklyn Museum 47.218.89 (+ 47.218.152 + 47.218.155 frag. 4)",
                 metadata["inventory"]
    assert_equal "New York, Brooklyn Museum", metadata["repository"]
    assert_equal "ספר אנתו", metadata["title_original"]
    assert_equal({ "ancient" => "Elephantine / Syene" }, metadata["place"])
    assert_match(/Marriage contract of the dowry/, metadata["summary"])
    assert_equal "documentary | vertical format | marriage contract",
                 metadata["facets"]["genre"]["value"]
    assert_equal "papyrus", metadata["facets"]["object_type"]["value"]
    refute metadata.key?("date"), "both origDate elements are empty — no date key minted"
  end

  # --- the Greek exemplar (4-digit id, in-text date, structured dating) -------

  def test_greek_document_pads_the_id_and_drops_the_lost_lines_notation
    document = parse("urn:nabu:elephantine:002881")
    assert_equal "grc", document.language
    assert_equal "contract of marriage", document.title
    expected = (1..12).map { |n| "urn:nabu:elephantine:002881:concave.#{n}" }
    assert_equal expected, document.map(&:urn),
                 "the whitespace-only first <ab> yields nothing; line 12+y is dash notation " \
                 "(no letters) and is not citable"
    assert_match(/\Aὁμολογεῖ /, document.first.text)
    document.each { |passage| assert_equal "grc", passage.language }
  end

  def test_greek_structured_dating_rides_the_timeline_shape
    metadata = parse("urn:nabu:elephantine:002881").metadata
    assert_equal(-246, metadata["date"]["not_before"],
                 "origin origDate @notBefore-custom, the EDH/EDR signed-year shape")
  end

  def test_demotic_nested_date_bounds_are_read
    metadata = parse("urn:nabu:elephantine:100117").metadata
    assert_equal({ "not_before" => -31, "not_after" => 395 }, metadata["date"])
  end

  # --- the Demotic exemplars (damage idiom, empty lb @n, gap markers) ---------

  def test_demotic_name_list_lines_and_lacunae
    document = parse("urn:nabu:elephantine:100117")
    expected = (1..8).map { |n| "urn:nabu:elephantine:100117:convex.#{n}" }
    assert_equal expected, document.map(&:urn)
    assert_equal "PꜢ-ḫy sꜣ Ḥr-pa-ꜣs.t", document.to_a[1].text
    line5 = document.to_a[4]
    assert_equal "Ꜣpllny sꜣ Ghrꜣn[…]", line5.text,
                 "damage reads through; gap contributes the house […] marker"
    assert_equal [{ "extent" => "unknown", "reason" => "lost" }],
                 line5.annotations["leiden"]["gaps"]
    surplus = document.to_a[2]
    assert_includes surplus.text, "{m}", "surplus reason=\"repeated\" wraps in Leiden braces"
  end

  def test_empty_lb_n_lines_take_positional_suffixes
    document = parse("urn:nabu:elephantine:100007")
    expected = %w[R.l1 R.x+2 R.x+3 R.x+4 R.x+5 R.x+6 V.l1 V.x+1ff.]
               .map { |ref| "urn:nabu:elephantine:100007:#{ref}" }
    assert_equal expected, document.map(&:urn),
                 "<lb n=\"\"/> label lines mint positional l<k>; the gap/unclear-only lines " \
                 "(R.x+1, R.x+7ff.) are not citable"
    assert_equal "new text", document.first.text
    weaver = document.find { |p| p.urn.end_with?(":R.x+3") }
    assert_equal "sḫt mnḫ.t", weaver.text, "rs type=\"title\" keeps its text; inline <note> drops"
  end

  # --- the readable predicate (never trust the site flag) ---------------------

  def test_all_lacunae_flagged_edition_is_metadata_only
    document = parse("urn:nabu:elephantine:100141")
    assert_empty document.to_a
    assert_equal "none", document.metadata["text_layer"],
                 "the site flags this ostracon as text-bearing; the edition is " \
                 "<damage><unclear/></damage> only — the census's readable predicate rules"
  end

  def test_catalog_only_record_is_metadata_only
    document = parse("urn:nabu:elephantine:100009")
    assert_empty document.to_a
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "egy-Egyd", document.language
    assert_equal "mention of tombs of persons with Greek names", document.title
  end

  # --- the -en translation lane -----------------------------------------------

  def test_translation_sibling_is_a_parallel_english_document
    document = parse("urn:nabu:elephantine:100117-en")
    assert_equal "eng", document.language
    assert_equal "translation", document.metadata["kind"]
    expected = (1..8).map { |n| "urn:nabu:elephantine:100117-en:#{n}" }
    assert_equal expected, document.map(&:urn),
                 "the translation <pb n=\"\"/> is empty — line suffixes carry no page part"
    assert_equal "Pachois, son of Harpaesis.", document.to_a[1].text
    document.each { |passage| assert_equal "eng", passage.language }
  end

  def test_translation_duplicate_line_numbers_take_the_house_b2_disambiguator
    document = parse("urn:nabu:elephantine:307762-en")
    urns = document.map(&:urn)
    assert_includes urns, "urn:nabu:elephantine:307762-en:V.1"
    assert_includes urns, "urn:nabu:elephantine:307762-en:V.1:b2",
                    "upstream repeats <pb n=\"V\"/> with restarting line numbers across two abs"
    assert_equal 17, document.size
  end

  def test_translation_of_an_unreadable_record_is_skipped_by_rule
    adapter = conformance_adapter
    refs = adapter.discover(FIXTURES).to_a
    %w[100009 100141].each do |id|
      ref = refs.find { |r| r.id == "urn:nabu:elephantine:#{id}-en" }
      refute_nil ref
      assert_raises(Nabu::DocumentSkipped) { adapter.parse(ref) }
    end
  end

  # --- quarantines -------------------------------------------------------------

  def test_licence_drift_is_a_loud_stop
    doctored_copy("elephantine_erc_db_002881.tei.xml",
                  from: "http://creativecommons.org/licenses/by-sa/3.0/",
                  to: "http://creativecommons.org/licenses/by-nc-sa/3.0/de/") do |adapter, ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/licence/i, error.message)
      assert_match(/by-sa/i, error.message, "the pin the file drifted from is named")
    end
  end

  def test_identity_drift_is_a_loud_stop
    doctored_copy("elephantine_erc_db_002881.tei.xml",
                  from: 'xml:id="elephantine_erc_db_002881"',
                  to: 'xml:id="elephantine_erc_db_999999"') do |adapter, ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/xml:id/, error.message)
    end
  end

  def test_malformed_xml_quarantines_with_a_parse_error
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "elephantine_erc_db_000001.tei.xml"), "<TEI><unclosed></TEI>")
      adapter = Nabu::Adapters::Elephantine.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/malformed XML/, error.message)
    end
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_delegates_to_the_manifest_crawl
    listing = File.read(File.join(FIXTURES, "objects-listing-marriage.html"))
    stub_request(:post, "https://elephantine.smb.museum/objects/index.php")
      .with(body: "showresults=15000")
      .to_return(status: 200, body: listing)
    stub_request(:get, %r{https://elephantine\.smb\.museum/xml/elephantine_erc_db_.+\.tei\.xml})
      .to_return(status: 200, body: "<TEI/>")
    Dir.mktmpdir do |workdir|
      report = Nabu::Adapters::Elephantine.new(delay: 0).fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/23 records/, report.notes)
      assert File.file?(File.join(workdir, "elephantine_erc_db_002881.tei.xml"))
    end
  end

  def test_fetch_wraps_crawl_failure_in_fetch_error
    stub_request(:post, "https://elephantine.smb.museum/objects/index.php").to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Elephantine.new(delay: 0).fetch(workdir) }
    end
  end

  # --- idempotency (load twice, counts unchanged) -------------------------------

  def test_loading_the_fixture_set_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "elephantine", name: "Elephantine",
                                        adapter_class: "Nabu::Adapters::Elephantine",
                                        license_class: "attribution")
    adapter = -> { Nabu::Adapters::Elephantine.new(translations: true) }
    first = Nabu::Store::Loader.new(db: db, source: source)
                               .load_from(adapter.call, workdir: FIXTURES)
    assert_equal 10, first.added, "6 originals + 4 readable translation siblings"
    assert_equal 0, first.errored
    assert_equal 88, db[:passages].count,
                 "editions 12+8+0+8+0+17 = 45; translations 12+6+8+17 = 43 " \
                 "(100007-en's x+1 and x+7ff. lines are [///]/⸢..?..⸣ notation — not citable)"

    second = Nabu::Store::Loader.new(db: db, source: source)
                                .load_from(adapter.call, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 10, second.skipped, "a byte-identical reload skips every document"
    assert_equal 88, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  end

  private

  def parse(urn)
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def doctored_copy(name, from:, to:)
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, name)).sub(from, to)
      refute_equal doctored, File.read(File.join(FIXTURES, name)), "the doctoring must hit"
      File.write(File.join(dir, name), doctored)
      adapter = Nabu::Adapters::Elephantine.new
      yield adapter, adapter.discover(dir).first
    end
  end
end
