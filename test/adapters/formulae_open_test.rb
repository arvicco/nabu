# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# formulae-open — the public-domain charter editions of the Hamburg
# Formulae – Litterae – Chartae project (Akademie der Wissenschaften in
# Hamburg). CapiTainS v3 (__capitains__.xml catalogs), one charter per TEI
# file, cited by charta div; the EpidocParser family reads the bodies. What
# the adapter adds: the per-document licence law, the rejected E-Lexicon
# grain, and the charter axes (dateline dating, issuing place, the edition
# lineage). Fixtures: real files, test/fixtures/formulae-open/README.md.
class FormulaeOpenTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("formulae-open")

  STGALLEN = "urn:cts:formulae:stgallen.wartmann0001.lat001"            # dated 700, issued at Cannstadt
  FREISING_A = "urn:cts:formulae:freising.bitterauf1019.lat001"         # Nr. 1019a, the abbr/expan formula
  FREISING_B = "urn:cts:formulae:freising.bitterauf1019.lat002"         # Nr. 1019b — a second document
  HERSFELD = "urn:cts:formulae:hersfeld.weirich0037.lat001"             # four charta divs
  ANJOU = "urn:cts:formulae:anjou_archives.marchegay_carbaio_0006.lat001" # undated; three-level tree
  VENDOME = "urn:cts:formulae:marmoutier_vendomois.trémault0011.lat001" # a non-ASCII path
  EUDES = "urn:cts:formulae:eudes.lex0034.lat001"                       # CC BY-NC-ND 4.0
  ACCEPTED = [STGALLEN, FREISING_A, FREISING_B, HERSFELD, ANJOU, VENDOME, EUDES].freeze

  BY = "https://creativecommons.org/licenses/by/4.0/"
  BY_NC_ND = "https://creativecommons.org/licenses/by-nc-nd/4.0/"

  def conformance_adapter
    Nabu::Adapters::FormulaeOpen.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "formulae-open"
  end

  def adapter
    @adapter ||= Nabu::Adapters::FormulaeOpen.new
  end

  def refs
    @refs ||= adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
  end

  def parsed(urn)
    adapter.parse(refs.fetch(urn))
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::FormulaeOpen.manifest

    assert_equal "formulae-open", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/Formulae-Litterae-Chartae/formulae-open", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
    assert_equal manifest, adapter.manifest
  end

  # --- discovery: every licensed Latin charter, the rejected grains by rule ----

  def test_discover_takes_every_latin_charter_edition_in_urn_order
    assert_equal ACCEPTED.sort, adapter.discover(FIXTURES).map(&:id)
    assert(refs.values.all? { |ref| ref.metadata["language"] == "lat" })
  end

  def test_urns_are_nfc_even_where_the_path_is_not_ascii
    assert_includes refs.keys, VENDOME
    assert_equal Nabu::Normalize.nfc(VENDOME), refs.fetch(VENDOME).id
  end

  def test_discovery_skips_count_every_rejected_grain_by_rule
    skips = adapter.discovery_skips(FIXTURES)

    assert_predicate skips, :clean?
    assert_equal 3, skips.skipped_by_rule
    notes = skips.notes.join("\n")

    assert_match(/1 E-Lexicon entry \(elexicon.*\): elexicon\.riga\.deu001/, notes)
    assert_match(/1 unlicensed file \(no <licence> in the header\): luzern\.schiess0004\.lat001/, notes)
    assert_match(/1 regest-only record \(.*no Latin text.*\): hersfeld\.weirich0004\.lat001/, notes)
  end

  def test_a_regest_only_record_is_skipped_not_quarantined
    refute_includes refs.keys, "urn:cts:formulae:hersfeld.weirich0004.lat001"
    record = File.read(File.join(FIXTURES, "data/hersfeld/weirich0004/hersfeld.weirich0004.lat001.xml"))

    assert_includes record, %(<div type="textpart" subtype="charta" n="1"/>)
    assert_includes record, "Bischof Lullus von Mainz übergibt das Kloster Hersfeld König Karl."
  end

  def test_the_elexicon_is_rejected_even_though_its_entries_are_licensed
    refute(refs.keys.any? { |urn| urn.include?("elexicon") })
    riga = File.join(FIXTURES, "data/elexicon/riga/elexicon.riga.deu001.xml")

    assert_includes File.read(riga), BY # the grain rule, not the licence law, rejects it
  end

  # --- the per-document licence law ---------------------------------------------

  def test_each_document_carries_its_own_licence
    assert_equal BY, refs[STGALLEN].metadata["license"]
    assert_equal BY_NC_ND, refs[EUDES].metadata["license"]
  end

  def test_attribution_rides_the_source_class_and_nc_nd_overrides_to_nc
    assert_nil parsed(STGALLEN).license_override
    assert_nil parsed(FREISING_A).license_override
    assert_equal "nc", parsed(EUDES).license_override
  end

  def test_licence_classes_cover_every_target_upstream_ships
    law = Nabu::Adapters::FormulaeOpen::LICENCE_CLASSES

    assert_equal({ BY => "attribution", BY_NC_ND => "nc" }, law)
  end

  def test_an_unknown_licence_stops_discovery_loudly
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "data"), dir)
      path = File.join(dir, "data/stgallen/wartmann0001/stgallen.wartmann0001.lat001.xml")
      File.write(path, File.read(path).sub("licenses/by/4.0/", "licenses/by-sa/4.0/"))

      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::FormulaeOpen.new.discover(dir).to_a }
      assert_includes error.message, "by-sa/4.0"
    end
  end

  # --- parsing ------------------------------------------------------------------

  def test_one_charter_one_passage_cited_by_its_charta_div
    doc = parsed(STGALLEN)

    assert_equal ["#{STGALLEN}:1"], doc.passages.map(&:urn)
    assert_equal "lat", doc.language
    assert_equal "Urkundenbuch der Abtei Sanct Gallen (Ed. Wartmann) Nr. 1", doc.title
    assert doc.passages.first.text.start_with?("Gotefridus Alemanniae dux tradit Biberburgum vicum ad Neccarum.")
  end

  def test_a_multi_part_charter_keeps_every_charta_div
    doc = parsed(HERSFELD)

    assert_equal %w[1 2 3 4].map { |n| "#{HERSFELD}:#{n}" }, doc.passages.map(&:urn)
    assert doc.passages.first.text.start_with?("[1] Haec est decimatio, quae pertinet ad sanctum Wigberhtum")
  end

  def test_two_editions_of_one_work_are_two_documents
    assert_equal "Die Traditionen des Hochstifts Freising (Ed. Bitterauf), Nr. 1019a", parsed(FREISING_A).title
    assert_equal "Die Traditionen des Hochstifts Freising (Ed. Bitterauf), Nr. 1019b", parsed(FREISING_B).title
  end

  def test_the_printed_abbreviation_stays_and_the_supplied_expansion_leaves
    text = parsed(FREISING_A).passages.first.text

    assert_includes text, "Unde —possideat aevis temporibus (= 748)"
    refute_includes text, "duas commutationes inter se fieri rogaverunt"
  end

  def test_the_manuscript_rubric_stays_in_the_charter_text
    assert parsed(FREISING_A).passages.first.text.start_with?("COMMUTATIO INTER UUALDONEM EPISCOPUM")
  end

  # --- the charter axes ---------------------------------------------------------

  def test_dateline_when_is_a_one_year_envelope
    assert_equal({ "not_before" => 700, "not_after" => 700, "raw" => "700" }, parsed(STGALLEN).metadata["date"])
  end

  def test_dateline_bounds_and_their_printed_wording
    assert_equal({ "not_before" => 880, "not_after" => 899, "raw" => "[880-899]" },
                 parsed(HERSFELD).metadata["date"])
    assert_equal({ "not_before" => 1072, "not_after" => 1072, "raw" => "1072" }, parsed(VENDOME).metadata["date"])
  end

  def test_the_envelope_spans_every_dated_child_and_skips_the_empty_one
    assert_equal({ "not_before" => 995, "not_after" => 1037, "raw" => "Sans date" }, parsed(EUDES).metadata["date"])
  end

  def test_an_empty_dateline_mints_no_date_but_keeps_the_edition_year
    metadata = parsed(ANJOU).metadata

    assert_nil metadata["date"]
    assert_equal "1853", metadata["source_date"]
  end

  def test_the_issuing_place_is_the_editions_ausstellungsort
    assert_equal "Cannstadt", parsed(STGALLEN).metadata["place"]
    assert_nil parsed(HERSFELD).metadata["place"]
  end

  def test_kind_rides_upstreams_own_text_type
    assert_equal "charta", parsed(STGALLEN).metadata["genre"]
  end

  def test_regest_collection_and_the_printed_edition
    metadata = parsed(STGALLEN).metadata

    assert_equal "Herzog Gottfried von Alamannien gibt den Ort Biberburg am Neckar an Sanct Gallen.",
                 metadata["regest"]
    assert_equal "stgallen", metadata["collection"]
    assert_equal "Urkundenbuch der Abtei Sanct Gallen, ed. von H. Wartmann (1863)", metadata["collection_title"]
    assert_equal "stgallen", metadata["cts_textgroup"]
    assert_equal "stgallen.wartmann0001", metadata["cts_work"]
    assert_equal ["Wartmann, Hermann"], metadata["editors"]
    assert_equal "Urkundenbuch der Abtei Sanct Gallen", metadata["edition"]
    assert_equal "1863", metadata["source_date"]
    assert_equal "http://d-nb.info/810983249", metadata["source_uri"]
  end

  def test_the_dating_lane_reads_the_structured_dateline
    shapes = Nabu::Store::TimelineBuilder::MetadataDates

    assert_equal :structured, shapes::SHAPES.fetch("formulae-open")
    assert_equal [880, 899, "[880-899]", nil, nil], shapes.structured(parsed(HERSFELD).metadata)
  end
end
