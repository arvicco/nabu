# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The DCS lookup lane: the held DCS tree's lookup/ directory carries the
# corpus's own lexicon (dictionary.csv — the LemmaIds every gold token
# cites, with meanings) and its WordNet-shaped sense bank (word-senses.csv
# + sembank-relations.csv + the sembank-attestations.xml sense→lemma
# bridge). Both ride the secondary dictionary lane (Adapter.dictionary_lane)
# as two shelves — dcs-lexicon and dcs-senses — beside MW. Runs against the
# REAL trimmed lookup fixtures (test/fixtures/dcs/README.md has the recipe),
# which include upstream's broken-record pairs and a sense set whose
# relation edges and attestation concepts cross-reference each other.
class DcsLexiconLaneTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("dcs")
  LOOKUP = File.join("dcs", "data", "conllu", "lookup")

  def lane
    @lane ||= Nabu::Adapters::DcsLexiconLane.new
  end

  def document(slug, workdir: FIXTURES)
    ref = lane.discover(workdir).find { |r| r.metadata["dictionary"] == slug } || flunk("no #{slug} ref")
    lane.parse(ref)
  end

  def lexicon = @lexicon ||= document("dcs-lexicon")
  def senses = @senses ||= document("dcs-senses")

  def entry(document, entry_id)
    document.entries.find { |e| e.entry_id == entry_id } || flunk("expected entry #{entry_id}")
  end

  # --- the seam ----------------------------------------------------------------

  def test_dcs_declares_the_lane
    assert_kind_of Nabu::Adapters::DcsLexiconLane, Nabu::Adapters::Dcs.dictionary_lane
    assert_equal Nabu::Adapters::Dcs::LANGUAGE, Nabu::Adapters::DcsLexiconLane::LANGUAGE,
                 "the shelves speak the corpus's language tag"
  end

  def test_discover_yields_one_ref_per_dictionary_of_the_dcs_source
    refs = lane.discover(FIXTURES).to_a
    assert_equal %w[dcs-lexicon dcs-senses], refs.map(&:id)
    refs.each { |ref| assert_equal "dcs", ref.source_id }
    assert_equal "dictionary.csv", File.basename(refs.first.path)
    assert_equal "word-senses.csv", File.basename(refs.last.path)
  end

  def test_absent_lookup_dir_discovers_nothing
    Dir.mktmpdir("nabu-dcs-lookup") do |dir|
      assert_empty lane.discover(dir).to_a
    end
  end

  # --- dcs-lexicon ---------------------------------------------------------------

  def test_lexicon_document_shape
    assert_equal "dcs-lexicon", lexicon.slug
    assert_equal "san", lexicon.language
    assert_equal 11, lexicon.size, "12 records, one headword-less row skipped by rule"
  end

  def test_lexicon_entry_keeps_lemma_id_headword_gloss_and_grammar
    bhuta = entry(lexicon, "25207")
    assert_equal "bhūta", bhuta.headword
    assert_equal "bhuta", bhuta.headword_folded
    assert bhuta.gloss.start_with?("that which is or exists; any living being;"), "meanings verbatim"
    assert_includes bhuta.body, "bhūta (mn)"
    assert_includes bhuta.body, bhuta.gloss
  end

  def test_lexicon_preverbs_ride_the_body
    accar = entry(lexicon, "157203")
    assert_includes accar.body, "acchācar (1.P.)"
    assert_includes accar.body, "preverbs: acchā"
    assert_equal "to attain; to go towards", accar.gloss
  end

  def test_lexicon_empty_meanings_still_an_entry_without_an_invented_gloss
    agam = entry(lexicon, "157202")
    assert_nil agam.gloss
    assert_equal "acchāgam (1.P.)\npreverbs: acchā", agam.body
  end

  def test_lexicon_headwordless_row_is_skipped_and_censused
    refute(lexicon.entries.any? { |e| e.entry_id == "3562" }, "a row with no word mints no entry")
    assert_equal 1, lane.census.fetch("dcs-lexicon").fetch(:headwordless)
  end

  # Upstream record 39892 carries a newline INSIDE its word field
  # ("aiḍavi\na"): the physical line has 2 fields and its successor 4. The
  # deterministic rejoin restores the 5-field record; the verbatim field
  # (newline and all) is key_raw, the display headword spaces it.
  def test_lexicon_broken_record_is_rejoined
    aidavi = entry(lexicon, "39892")
    assert_equal "aiḍavi\na", aidavi.key_raw
    assert_equal "aiḍavi a", aidavi.headword
    assert_equal "a descendant of Iḍaviḍā", aidavi.gloss
    assert_includes aidavi.body, "aiḍavi a (m)"
    assert_equal 1, lane.census.fetch("dcs-lexicon").fetch(:rejoined)
    # its neighbours parse untouched
    assert_equal "a species of sheep", entry(lexicon, "39891").gloss
    assert_equal "aiṇa", entry(lexicon, "39893").headword
  end

  def test_lexicon_duplicate_id_is_a_parse_error
    Dir.mktmpdir("nabu-dcs-lookup") do |dir|
      lookup = copy_lookup(dir)
      path = File.join(lookup, "dictionary.csv")
      lines = File.readlines(path)
      File.write(path, (lines + [lines.find { |l| l.start_with?("25207\t") }]).join)

      ref = lane.discover(dir).find { |r| r.id == "dcs-lexicon" }
      error = assert_raises(Nabu::ParseError) { lane.parse(ref) }
      assert_match(/duplicate lemma id "25207"/, error.message)
    end
  end

  # --- dcs-senses ------------------------------------------------------------------

  def test_senses_document_shape
    assert_equal "dcs-senses", senses.slug
    assert_equal "san", senses.language, "the tls-concepts precedent: the shelf speaks its members' language"
    assert_equal 16, senses.size
  end

  def test_sense_entry_carries_name_gloss_and_wordnet_fields
    person = entry(senses, "574")
    assert_equal "person", person.headword
    assert_equal "a human being; \"there was too much for one person to do\"", person.gloss
    assert_includes person.body, "WordNet 2.1: 00007"
    assert_includes person.body, "supersense: Tops (03)"
    entity = entry(senses, "568")
    refute_includes entity.body, "WordNet", "`_` placeholders never render"
  end

  def test_senses_broken_record_is_rejoined
    druti = entry(senses, "127090")
    assert_equal "bāhyadruti", druti.headword
    assert_equal "1. one of the Saṃskāras of mercury 2. amalgamation of a molten metal with mercury", druti.gloss
    assert_includes druti.body, "1. one of the Saṃskāras of mercury\n2. amalgamation"
    assert_equal 1, lane.census.fetch("dcs-senses").fetch(:rejoined)
  end

  def test_relation_edges_become_id_keyed_crossrefs_within_the_sense_shelf
    being = entry(senses, "569").crossrefs.reject { |c| c.kind == "lexicalization" }
    assert_equal([["~", "574"], ["~", "575"], ["~", "576"], ["%p", "572"]],
                 being.map { |c| [c.kind, c.target_id] })
    assert(being.all? { |c| c.to_dictionary == "dcs-senses" })
    assert_equal "hyponym person", being.first.label
    assert_equal "person", being.first.target
    assert_equal "part meronym cell", being.last.label
    assert_equal "575", being[1].target, "an unheld target displays its id"
    holonym = entry(senses, "572").crossrefs.first
    assert_equal ["#p", "part holonym being"], [holonym.kind, holonym.label]
  end

  def test_duplicate_edges_collapse_and_junk_codes_and_unheld_sources_are_censused
    antonyms = entry(senses, "5675").crossrefs
    assert_equal([["!", "5676", "antonym non-engagement"]], antonyms.map { |c| [c.kind, c.target_id, c.label] })
    assert_empty entry(senses, "126807").crossrefs, "the junk code 77D15 mints no row"
    census = lane.census.fetch("dcs-senses")
    assert_equal 11, census.fetch(:relations)
    assert_equal 4, census.fetch(:duplicate_edges)
    assert_equal 1, census.fetch(:junk_codes)
    assert_equal 2, census.fetch(:unheld_from)
  end

  def test_attestation_bridge_points_senses_at_lexicon_lemmas
    being = entry(senses, "569").crossrefs.select { |c| c.kind == "lexicalization" }
    assert_equal([%w[25207 bhūta], %w[150748 prajā]], being.map { |c| [c.target_id, c.target] })
    assert(being.all? { |c| c.to_dictionary == "dcs-lexicon" })
    assert_equal "bhūta (158 attestations)", being.first.label, "76 + 63 + 19 in the trimmed fixture"
    assert_equal "bhūta (1 attestation)", entry(senses, "568").crossrefs.last.label
    census = lane.census.fetch("dcs-senses")
    assert_equal 6, census.fetch(:lexicalizations)
    assert_equal 1, census.fetch(:unheld_concepts), "concept 147806 is not in the trimmed sense list"
  end

  def test_senses_parse_without_sidecars_mints_no_crossrefs
    Dir.mktmpdir("nabu-dcs-lookup") do |dir|
      lookup = copy_lookup(dir)
      FileUtils.rm(File.join(lookup, "sembank-relations.csv"))
      FileUtils.rm(File.join(lookup, "sembank-attestations.xml"))

      document = lane.parse(lane.discover(dir).find { |r| r.id == "dcs-senses" })
      assert_equal 16, document.size
      assert(document.entries.all? { |e| e.crossrefs.empty? })
    end
  end

  # --- loader round-trip, resolution, define ----------------------------------

  def test_double_load_is_idempotent_and_crossrefs_resolve_across_both_shelves
    db, loader = loader_setup
    first = loader.load_from(lane, workdir: FIXTURES)
    assert_equal 27, first.added
    assert_equal 0, first.errored
    assert_equal %w[dcs-lexicon dcs-senses], db[:dictionaries].order(:slug).select_map(:slug)
    assert_equal "urn:nabu:dict:dcs-lexicon:25207",
                 db[:dictionary_entries].where(entry_id: "25207").get(:urn)
    assert_equal 17, db[:dictionary_crossrefs].count
    assert_equal 15, db[:dictionary_crossrefs].exclude(to_entry_id: nil).count,
                 "every edge resolves except the two pointing at unheld senses 575/576"
    bhuta_row = db[:dictionary_entries].where(urn: "urn:nabu:dict:dcs-lexicon:25207").get(:id)
    assert_equal 2, db[:dictionary_crossrefs].where(to_entry_id: bhuta_row).count, "entity + being → bhūta"

    crossrefs = db[:dictionary_crossrefs].order(:id).all
    second = loader.load_from(lane, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 27, second.skipped
    assert_equal 0, second.withdrawn
    assert_equal 27, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq, "a re-load must revise nothing"
    assert_equal crossrefs, db[:dictionary_crossrefs].order(:id).all
  end

  def test_define_finds_a_lexicon_entry_by_folded_headword
    db, loader = loader_setup
    loader.load_from(lane, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db)

    hits = define.run("bhuta").select { |r| r.dictionary_slug == "dcs-lexicon" }
    assert_equal ["urn:nabu:dict:dcs-lexicon:25207"], hits.map(&:urn)
    assert_equal "bhūta", hits.first.headword
    assert_equal "dcs", hits.first.source_slug
    assert_equal "attribution", hits.first.license_class

    being = define.by_urn("urn:nabu:dict:dcs-senses:569")
    assert_includes being.crossrefs.map(&:resolved_urn), "urn:nabu:dict:dcs-lexicon:25207"
  end

  private

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "dcs", name: "DCS", adapter_class: "Nabu::Adapters::Dcs",
      license: "CC BY 4.0", license_class: "attribution",
      upstream_url: Nabu::Adapters::Dcs::REPO_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source, ledger: ledger_test_db)]
  end

  def copy_lookup(dir)
    lookup = File.join(dir, LOOKUP)
    FileUtils.mkdir_p(File.dirname(lookup))
    FileUtils.cp_r(File.join(FIXTURES, LOOKUP), lookup)
    lookup
  end
end
