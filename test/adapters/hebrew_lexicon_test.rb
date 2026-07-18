# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nokogiri"

# The hebrew-lexicon adapter (P30-1): the augmented-Strong define shelf +
# the BDB outline. Dictionary-shaped, so it cannot include the
# passage-shaped AdapterConformance suite; like AedTest/LexicaTest it
# mirrors those checks for the dictionary shape (manifest validity,
# discover→parse round-trip, id uniqueness/stability, byte-honest text,
# license class) and adds the DictionaryLoader contract (idempotency, urn
# shape) plus THE JOIN CONTRACT: entry ids are augmented-Strong ids — what
# an OSHB lemma yields after HebrewLexicon.normalize_lemma — pinned against
# the REAL lemma bytes of the OSHB fixtures (test/fixtures/oshb), verse by
# verse, so urn:nabu:dict:hebrew-lexicon:<id> resolves an OSHB token
# end-to-end.
class HebrewLexiconTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("hebrew-lexicon")
  OSHB_FIXTURES = Nabu::TestSupport.fixtures("oshb")

  # The four OSHB fixture verses whose complete normalized-lemma inventory
  # the fixture AugIndex carries (fixture README): the creation verse, the
  # Beth-el "1008+" verse, the Aramaic Jegar-sahadutha verse, the Aramaic
  # verse of Jeremiah.
  JOIN_VERSES = { "Gen" => %w[Gen.1.1 Gen.31.13 Gen.31.47], "Jer" => %w[Jer.10.11] }.freeze

  def adapter = Nabu::Adapters::HebrewLexicon.new

  # --- manifest + content kind ----------------------------------------------------

  def test_manifest_identifies_the_hebrew_lexicon_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "hebrew-lexicon", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/These files are released under the Creative Commons/, manifest.license,
                 "the readme.md grant is quoted verbatim")
    assert_match(/credit the Open Scriptures Hebrew Bible Project/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/openscriptures/HebrewLexicon", manifest.upstream_url
    assert_equal "oshb-lexicon", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::HebrewLexicon.content_kind
  end

  # --- the normalization rule (the OSHB side of the contract) ---------------------

  def test_normalize_lemma_pins_the_one_mechanical_rule
    normalize = Nabu::Adapters::HebrewLexicon.method(:normalize_lemma)
    # Real OSHB fixture lemma spellings (see the join test below for the
    # full verse-level inventory):
    assert_equal "7225", normalize.call("b/7225")
    assert_equal "1254a", normalize.call("1254 a")
    assert_equal "6213a", normalize.call("c/6213 a")
    assert_equal "1008", normalize.call("1008+")
    assert_equal "l", normalize.call("l")
    assert_equal "430", normalize.call("430")
    # The spec's composed exemplar (prefix + augmented letter):
    assert_equal "1254a", normalize.call("b/1254 a")
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_per_dictionary
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[bdb:BrownDriverBriggs.xml hebrew-lexicon:AugIndex.xml], refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "hebrew-lexicon" })
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse_shelf(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata["dictionary"] == slug }
    adapter.parse(ref)
  end

  def test_parse_yields_the_strongs_shelf
    document = parse_shelf("hebrew-lexicon")
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "hebrew-lexicon", document.slug
    assert_equal "hbo", document.language
    assert_equal 43, document.size
    assert_equal({ "hbo" => 28, "arc" => 15 }, document.entries.group_by(&:language).transform_values(&:size),
                 "per-entry hbo/arc rides the domain entries (H/A number spaces share the shelf)")
  end

  def test_parse_yields_the_bdb_outline_shelf
    document = parse_shelf("bdb")
    assert_equal "bdb", document.slug
    assert_equal "hbo", document.language
    assert_equal 19, document.size
  end

  def test_a_missing_sibling_file_quarantines_the_strongs_shelf
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "AugIndex.xml"), dir)
      FileUtils.cp(File.join(FIXTURES, "LexicalIndex.xml"), dir)
      ref = adapter.discover(dir).find { |r| r.metadata["dictionary"] == "hebrew-lexicon" }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/missing sibling file HebrewStrong\.xml/, error.message)
    end
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { parse_shelf("hebrew-lexicon").map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_text_is_byte_honest_utf8
    %w[hebrew-lexicon bdb].each do |slug|
      non_nfc = 0
      parse_shelf(slug).each do |entry|
        assert entry.headword.valid_encoding?
        assert entry.body.valid_encoding?
        assert entry.headword_folded.unicode_normalized?(:nfc), "the folded lookup key stays NFC"
        non_nfc += 1 unless entry.headword.unicode_normalized?(:nfc)
      end
      assert_operator non_nfc, :>, 0,
                      "#{slug}: the fixture carries non-NFC Masoretic headwords and they must stay byte-verbatim"
    end
  end

  # --- DictionaryLoader contract (idempotency / urn) ------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "hebrew-lexicon", name: "OSHB Hebrew Lexicon",
      adapter_class: "Nabu::Adapters::HebrewLexicon",
      license: Nabu::Adapters::HebrewLexicon::MANIFEST.license, license_class: "attribution",
      upstream_url: Nabu::Adapters::HebrewLexicon::MANIFEST.upstream_url, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 62, first.added, "43 strongs + 19 bdb entries"
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 62, second.skipped
    assert_equal 62, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    bara = db[:dictionary_entries].where(entry_id: "1254a").first
    assert_equal "urn:nabu:dict:hebrew-lexicon:1254a", bara[:urn]
    outline = db[:dictionary_entries].where(entry_id: "b.cw.aa").first
    assert_equal "urn:nabu:dict:bdb:b.cw.aa", outline[:urn]
    assert_equal 1, db[:dictionary_citations].where(dictionary_entry_id: outline[:id]).count
  end

  # --- THE JOIN CONTRACT (P30-1's point) ------------------------------------------

  def test_every_oshb_fixture_token_of_the_join_verses_resolves_end_to_end
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db)

    checked = 0
    JOIN_VERSES.each do |book, verses|
      xml = Nokogiri::XML(File.read(File.join(OSHB_FIXTURES, "wlc", "#{book}.xml")), &:strict)
      xml.remove_namespaces!
      verses.each do |osis_id|
        words = xml.xpath(%(//verse[@osisID="#{osis_id}"]//w))
        refute_empty words, "#{osis_id} must exist in the OSHB fixture"
        words.each do |w|
          id = Nabu::Adapters::HebrewLexicon.normalize_lemma(w["lemma"])
          result = define.by_urn("urn:nabu:dict:hebrew-lexicon:#{id}")
          refute_nil result, "OSHB lemma #{w['lemma'].inspect} (#{osis_id}) → #{id.inspect} must resolve"
          checked += 1
        end
      end
    end
    assert_operator checked, :>=, 40, "the four verses carry a real token load"
  end

  def test_an_oshb_lemma_resolves_to_the_full_entry
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)

    # Gen 1:1 בָּרָא carries lemma "1254 a" (real fixture bytes, pinned above).
    urn = "urn:nabu:dict:hebrew-lexicon:#{Nabu::Adapters::HebrewLexicon.normalize_lemma('1254 a')}"
    result = Nabu::Query::Define.new(catalog: db).by_urn(urn)
    assert_equal "shape", result.gloss
    assert_equal "bxy", result.key_raw
    assert_match(/^usage: choose, create \(creator\)/, result.body)
    assert_equal "attribution", result.license_class
  end

  # --- define: the two shelves meet on the folded skeleton ------------------------

  def define_on_loaded_shelf
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    Nabu::Query::Define.new(catalog: db)
  end

  def test_define_bara_finds_both_shelves
    results = define_on_loaded_shelf.run("ברא", limit: 10)
    assert_equal %w[urn:nabu:dict:bdb:b.cw.aa urn:nabu:dict:hebrew-lexicon:1254a], results.map(&:urn).sort,
                 "the Strong entry and the BDB outline sit side by side (LSJ+LS precedent)"
  end

  def test_define_reaches_pointed_headwords_from_bare_consonants
    # אֱלֹהִים typed bare: the niqqud falls to the generic mark strip on the
    # shelf side, so the consonantal query lands.
    results = define_on_loaded_shelf.run("אלהים", limit: 10)
    assert_includes results.map(&:urn), "urn:nabu:dict:hebrew-lexicon:430"
  end

  def test_define_finds_an_aramaic_entry
    results = define_on_loaded_shelf.run("יגר", limit: 10)
    result = results.find { |r| r.urn == "urn:nabu:dict:hebrew-lexicon:3026a" }
    refute_nil result
    assert_equal "heap", result.gloss
  end

  def test_bdb_print_pages_stay_unresolved_deep_links
    result = define_on_loaded_shelf.run("ברא", limit: 10)
                                   .find { |r| r.urn == "urn:nabu:dict:bdb:b.cw.aa" }
    assert_equal ["BDB p. 135"], result.citations.map(&:label)
    assert_nil result.citations.first.resolved_urn,
               "a print page resolves to nothing until the BDB 1906 scan is in the library"
  end

  # --- registry -------------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["hebrew-lexicon"]
    refute_nil entry, "config/sources.yml must register hebrew-lexicon"
    assert_equal Nabu::Adapters::HebrewLexicon, entry.adapter_class
    refute entry.enabled, "hebrew-lexicon stays disabled until the owner-fired first real sync (checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::HebrewLexicon.manifest, entry.manifest
  end
end
