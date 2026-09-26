# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The ORACC glossary lane (P104-4, Q81 — the №R-69a secondary-lane pilot):
# per-project gloss-<lang>.json → one dictionary per (project, language),
# streamed (the instances/summaries mass after the entries array is never
# read). Runs against the REAL checked-in gloss fixtures: rimanum's whole
# gloss-sux.json and the truncated saao/saa01 gloss-qpn.json with its real
# NESTED zip root (see test/fixtures/oracc/README.md for both recipes).
class OraccGlossaryLaneTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("oracc")

  def lane
    Nabu::Adapters::OraccGlossaryLane.new
  end

  # --- the seam declaration ------------------------------------------------

  def test_oracc_declares_the_lane_and_the_base_default_is_nil
    assert_kind_of Nabu::Adapters::OraccGlossaryLane, Nabu::Adapters::Oracc.dictionary_lane
    assert_nil Nabu::Adapter.dictionary_lane, "the base capability must default to no lane"
  end

  # --- discovery ------------------------------------------------------------

  def test_discover_finds_gloss_files_at_both_unpack_depths
    refs = lane.discover(FIXTURES).to_a
    assert_equal %w[oracc-gloss:rimanum:sux oracc-gloss:saao-saa01:qpn], refs.map(&:id),
                 "one ref per gloss file — top-level rimanum AND the nested saao-saa01/saa01 root"
    refs.each { |ref| assert_equal "oracc", ref.source_id }
    qpn = refs.last
    assert_equal "saao-saa01", qpn.metadata["project"]
    assert_equal "saao/saa01", qpn.metadata["project_path"]
    assert_equal "qpn", qpn.metadata["lang"]
  end

  def test_absent_cone_discovers_nothing
    Dir.mktmpdir("nabu-gloss") do |dir|
      assert_empty lane.discover(dir).to_a, "no gloss files = no dictionaries, no error"
    end
  end

  # --- parse correctness (rimanum gloss-sux, 25 real entries) ---------------

  def test_parse_yields_one_dictionary_per_project_and_language
    document = lane.parse(sux_ref)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "oracc-rimanum-sux", document.slug
    assert_equal "sux", document.language
    assert_equal "ORACC glossary — rimanum (sux)", document.title
    assert_equal 25, document.size
  end

  def test_parse_mints_entries_from_the_glossarys_own_fields
    entry = lane.parse(sux_ref).entries.find { |e| e.entry_id == "x000000010" } ||
            flunk("expected the glossary's own entry id x000000010 (adam)")
    assert_equal "adam", entry.headword
    assert_equal "adam[habitation]N", entry.key_raw
    assert_equal "habitation", entry.gloss
    assert_equal "sux", entry.language
    assert_equal Nabu::Normalize.search_form("adam", language: "sux"), entry.headword_folded
    assert_includes entry.body, "adam — habitation (N)"
    assert_includes entry.body, "forms:"
  end

  def test_parse_keeps_sumerian_headword_characters_nfc
    hursag = lane.parse(sux_ref).entries.find { |e| e.headword == "hursaŋ" } ||
             flunk("expected the real hursaŋ entry")
    assert hursag.headword.unicode_normalized?(:nfc)
    assert_equal "mountain", hursag.gloss
  end

  def test_parse_resolves_the_nested_zip_root
    document = lane.parse(qpn_ref)
    assert_equal "oracc-saao-saa01-qpn", document.slug
    assert_equal 6, document.size
    adad = document.entries.find { |e| e.entry_id == "x000004280" } || flunk("expected Adad (x000004280)")
    assert_equal "Adad", adad.headword
  end

  # --- streaming honesty -----------------------------------------------------

  # The scanner must STOP at the entries array's close: a file whose
  # instances/summaries tail is not even JSON parses fine, because those
  # bytes are never read (the 625 MB live worst case is 95% tail).
  def test_parse_never_reads_past_the_entries_array
    Dir.mktmpdir("nabu-gloss") do |dir|
      original = File.read(File.join(FIXTURES, "rimanum", "gloss-sux.json"), encoding: Encoding::UTF_8)
      poisoned = original.sub(/"instances":.*\z/m, "\"instances\": %%NOT-JSON%%")
      refute_equal original, poisoned, "the fixture must carry an instances tail to poison"
      FileUtils.mkdir_p(File.join(dir, "rimanum"))
      File.write(File.join(dir, "rimanum", "gloss-sux.json"), poisoned)

      refs = lane.discover(dir).to_a
      assert_equal 25, lane.parse(refs.fetch(0)).size,
                   "a poisoned post-entries tail must be invisible to the streamed parse"
    end
  end

  def test_truncated_glossary_quarantines_as_parse_error
    Dir.mktmpdir("nabu-gloss") do |dir|
      bytes = File.binread(File.join(FIXTURES, "rimanum", "gloss-sux.json"))
      FileUtils.mkdir_p(File.join(dir, "rimanum"))
      File.binwrite(File.join(dir, "rimanum", "gloss-sux.json"), bytes[0, 900])

      ref = lane.discover(dir).to_a.fetch(0)
      error = assert_raises(Nabu::ParseError) { lane.parse(ref) }
      assert_match(/oracc glossary oracc-gloss:rimanum:sux/, error.message)
    end
  end

  def test_lang_divergence_between_filename_and_payload_quarantines
    Dir.mktmpdir("nabu-gloss") do |dir|
      FileUtils.mkdir_p(File.join(dir, "rimanum"))
      # The real sux payload under an akk filename: mislabeling, not damage —
      # it must stop the file, never shelve entries under the wrong language.
      FileUtils.cp(File.join(FIXTURES, "rimanum", "gloss-sux.json"),
                   File.join(dir, "rimanum", "gloss-akk.json"))

      ref = lane.discover(dir).to_a.fetch(0)
      error = assert_raises(Nabu::ParseError) { lane.parse(ref) }
      assert_match(/filename says "akk".*lang field says "sux"/, error.message)
    end
  end

  # --- loader round-trip: idempotency ---------------------------------------

  def test_double_load_through_the_dictionary_loader_is_idempotent
    db = store_test_db
    ledger = ledger_test_db
    source = Nabu::Store::Source.create(
      slug: "oracc", name: "ORACC", adapter_class: "Nabu::Adapters::Oracc",
      license: "CC0", license_class: "open",
      upstream_url: "https://oracc.museum.upenn.edu", enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source, ledger: ledger)

    first = loader.load_from(lane, workdir: FIXTURES)
    assert_equal 31, first.added # 25 sux + 6 qpn entries
    assert_equal 0, first.errored
    assert_equal %w[oracc-rimanum-sux oracc-saao-saa01-qpn], db[:dictionaries].select_map(:slug).sort
    assert_equal "urn:nabu:dict:oracc-rimanum-sux:x000000010",
                 db[:dictionary_entries].where(entry_id: "x000000010").get(:urn)

    second = loader.load_from(lane, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 31, second.skipped
    assert_equal 0, second.withdrawn
    assert_equal 31, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq, "a re-load must revise nothing"
  end

  private

  def sux_ref
    lane.discover(FIXTURES).find { |ref| ref.id == "oracc-gloss:rimanum:sux" }
  end

  def qpn_ref
    lane.discover(FIXTURES).find { |ref| ref.id == "oracc-gloss:saao-saa01:qpn" }
  end
end
