# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::PnaPersons: the PNA network dataset's persons projected into the
# "pna" person-index slice, their person-text links resolved through the
# publication crosswalk onto HELD oracc/cdli documents. Fixtures: eight
# real persons and all their links, trimmed from the Zenodo v3 files
# (test/fixtures/pna/README.md); the zips are re-packed from the trimmed
# members at test time, the upstream layout kept.
class PnaPersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("pna")

  # The held catalog rows the crosswalk resolves against — real urns and
  # designations from the box's oracc and cdli shelves.
  HELD = {
    "oracc" => [
      ["urn:nabu:oracc:saao-saa06:P335335", "SAA 06 010"],
      ["urn:nabu:oracc:saao-saa12:P337170", "SAA 12 063"],
      ["urn:nabu:oracc:saao-saa12:P337170-en", "SAA 12 063"],
      ["urn:nabu:oracc:atae-stat2:P336861", "StAT 2 053"],
      ["urn:nabu:oracc:atae-saab0509:P528281", "SAAB 05 058"]
    ],
    "cdli" => [
      ["urn:nabu:cdli:p237981", "ABL 0458"],
      ["urn:nabu:cdli:p237249", "ABL 0791"],
      ["urn:nabu:cdli:p335326", "ADD 0382"],
      ["urn:nabu:cdli:p335335", "ADD 0391"]
    ]
  }.freeze

  def setup
    @catalog = store_test_db
    @workdir = Dir.mktmpdir
    PnaFixtureZips.pack!(FIXTURES, @workdir)
  end

  def teardown
    FileUtils.remove_entry(@workdir)
  end

  def seed_held!
    HELD.each do |slug, rows|
      source_id = @catalog[:sources].insert(slug: slug, name: slug, adapter_class: "X", license_class: "open")
      rows.each do |urn, title|
        @catalog[:documents].insert(source_id: source_id, urn: urn, title: title, content_sha256: "x",
                                    withdrawn: false)
      end
    end
  end

  def crosswalk
    seed_held!
    Nabu::PnaPersons::Crosswalk.from_catalog(@catalog, concordance: Nabu::PnaPersons.concordance(@workdir))
  end

  def persons(walk = Nabu::PnaPersons::Crosswalk.empty)
    @persons ||= Nabu::PnaPersons.each_person(@workdir, crosswalk: walk).to_a
  end

  def person(id) = persons.find { |p| p.person_id == id }

  def key(name) = Nabu::Pleiades.name_key(name)

  def test_every_person_keyed_by_the_disambiguated_label
    assert_equal ["'Idru_1", "Hundāru (Ahundāra)_2", "Aššūr-zāqip_4", "Ki[...]_2", "Ṣirānû or Ṣērānû_1",
                  "Mullissu-šāzizinni_1", "Abbūtā_1", "Ahu-ṭāba_1"], persons.map(&:person_id)
    hundaru = person("Hundāru (Ahundāra)_2")
    assert_equal "Hundāru (Ahundāra)", hundaru.name, "the label with PNA's homonym number dropped"
    assert_nil hundaru.name_han
    assert_nil hundaru.refs
    assert person("Mullissu-šāzizinni_1").female
    refute hundaru.female
  end

  def test_upstream_attributes_ride_and_placeholders_never_do
    assert_equal({ "name_language" => "Elamite", "gender" => "masc", "era" => "668–631 Assurbanipal",
                   "era_start" => -668, "era_end" => -631, "profession" => "Non-Assyrian ruler" },
                 person("Hundāru (Ahundāra)_2").attributes)
    abbuta = person("Abbūtā_1").attributes
    assert_equal "Ialunean", abbuta["origin"]
    assert_equal "Kalhu", abbuta["place"]
    assert_equal "Ethnicity", abbuta["profession"]
    zaqip = person("Aššūr-zāqip_4").attributes
    refute zaqip.key?("era"), "N/A is upstream's no-period placeholder"
    refute zaqip.key?("era_start"), "N/A rows carry the 01/01/2000 placeholder date — never a year"
    refute zaqip.key?("profession"), "'Unknown or not applicable' is no profession"
    assert_equal "Assur", zaqip["place"]
  end

  def test_name_keys_fold_alternatives_and_skip_fragments
    hundaru = person("Hundāru (Ahundāra)_2").name_keys
    assert_includes hundaru, key("Hundāru")
    assert_includes hundaru, key("Ahundāra")
    assert_includes hundaru, key("Hundaru"), "a diacritic-free key so a plain-ASCII query meets the name"
    sirani = person("Ṣirānû or Ṣērānû_1").name_keys
    assert_includes sirani, key("Ṣirānû")
    assert_includes sirani, key("Ṣērānû")
    assert_includes sirani, key("Siranu")
    assert_includes person("'Idru_1").name_keys, key("'Idru")
    assert_empty person("Ki[...]_2").name_keys, "a broken name keys nothing (still resolvable by ref)"
  end

  def test_links_ride_in_upstream_order_unresolved_without_a_crosswalk
    texts = person("Hundāru (Ahundāra)_2").texts
    assert_equal ["AAA 20", "ABL 458", "ABL 791"], texts.map(&:publication)
    assert(texts.all? { |t| t.urn.nil? })
  end

  def test_the_crosswalk_resolves_publications_onto_held_documents
    walk = crosswalk
    assert_equal "urn:nabu:oracc:saao-saa12:P337170", walk.resolve("SAA 12 63"),
                 "PNA's concordance names the Oracc id; the held doc carries it"
    assert_equal "urn:nabu:oracc:saao-saa06:P335335", walk.resolve("SAA 6 10"),
                 "the concordance's first row is lacost (not held) — the held saao copy of the same id wins, " \
                 "never the cdli record sharing the P-number"
    assert_equal "urn:nabu:oracc:atae-stat2:P336861", walk.resolve("StAT 2 53"),
                 "a designation match under the zero-pad fold (StAT 2 053)"
    assert_equal "urn:nabu:oracc:atae-saab0509:P528281", walk.resolve("SAAB 5 58")
    assert_equal "urn:nabu:cdli:p237981", walk.resolve("ABL 458"), "cdli when oracc holds nothing"
    assert_nil walk.resolve("AAA 20"), "nothing held: the publication stays a bare citation"
    assert_nil walk.resolve("GPA 121")
  end

  def test_resolved_links_ride_on_the_person
    texts = persons(crosswalk).find { |p| p.person_id == "Ahu-ṭāba_1" }.texts
    assert_equal([["ADD 382", "urn:nabu:cdli:p335326"], ["SAA 6 10", "urn:nabu:oracc:saao-saa06:P335335"]],
                 texts.map { |t| [t.publication, t.urn] })
  end

  def test_producer_derives_the_slice_with_texts_and_attributes
    seed_held!
    census = Nabu::PnaPersons::Producer.new(catalog: @catalog).run("pna", workdir: @workdir)
    assert_equal 8, census.persons
    assert_equal 11, census.links
    assert_equal 9, census.resolved, "every link but AAA 20 and GPA 121 meets a held document"
    resolver = Nabu::Store::PersonIndex.resolver(@catalog, authority: "pna")
    card = resolver.person("Ahu-ṭāba_1")
    assert_equal "Ahu-ṭāba", card.name
    assert_equal "Owners of property", card.attributes["profession"]
    assert_equal ["ADD 382", "SAA 6 10"], card.texts.map(&:publication)
    assert_equal ["Hundāru (Ahundāra)_2"], resolver.named("Ahundara").map(&:person_id)
  end

  def test_producer_reads_the_oracc_and_cdli_shelves
    assert_equal %w[oracc cdli], Nabu::PnaPersons::Producer.new(catalog: @catalog).reads_sources
  end

  def test_producer_is_a_no_op_without_the_archives
    Dir.mktmpdir do |empty|
      assert_nil Nabu::PnaPersons::Producer.new(catalog: @catalog).run("pna", workdir: empty)
    end
  end

  def test_rederive_is_idempotent
    seed_held!
    producer = Nabu::PnaPersons::Producer.new(catalog: @catalog)
    producer.run("pna", workdir: @workdir)
    before = [@catalog[:person_index].count, @catalog[:person_index_texts].count,
              @catalog[:person_index_names].count]
    producer.run("pna", workdir: @workdir)
    assert_equal before, [@catalog[:person_index].count, @catalog[:person_index_texts].count,
                          @catalog[:person_index_names].count]
  end

  def test_census_counts_the_skipped_co_occurrence_edges
    read = ->(rel) { File.binread(File.join(@workdir, rel)) if File.file?(File.join(@workdir, rel)) }
    counts = Nabu::PnaPersons.census(read).to_h { |c| [c.label, c.count] }
    assert_equal 8, counts["persons"]
    assert_equal 11, counts["person-text links"]
    assert_equal 9, counts["texts"]
    assert_equal 3, counts["co-occurrence edges (skipped by rule)"]
  end
end
