# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

# Nabu::Adapters::LotsawaHouse: Tibetan Buddhist texts (the Tibetan source
# pages) and their translations from lotsawahouse.org, crawled page by page
# (Nabu::LotsawaFetch). Fixtures are REAL pages retrieved 2026-10-21 — see
# test/fixtures/lotsawa-house/README.md.
class LotsawaHouseTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("lotsawa-house")
  House = Nabu::Adapters::LotsawaHouse
  URN = "urn:nabu:lotsawa-house:"

  def conformance_adapter = House.new(translations: true)
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "lotsawa-house"

  def adapter = conformance_adapter

  def parse(lang, path)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "#{URN}#{lang}:#{path}" }
    refute_nil ref, "fixture #{lang}:#{path} must be discovered"
    adapter.parse(ref)
  end

  # --- manifest / registry ----------------------------------------------------

  def test_manifest_quotes_the_terms_of_service_verbatim
    manifest = House.manifest
    assert_equal "nc", manifest.license_class
    assert_match(/All texts on Lotsawa House are covered by the Creative Commons Attribution-NonCommercial 4\.0/,
                 manifest.license)
    assert_match(/crawl each page for indexing/, manifest.license)
  end

  def test_registry_resolves_lotsawa_house_unwired_with_translations
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["lotsawa-house"]
    refute_nil entry
    assert_equal House, entry.adapter_class
    assert entry.wired, "wired since the verified first sync (2026-10-21)"
    assert entry.translations, "the translation pages ride (the site's own reason to exist)"
    assert_equal House.manifest, entry.manifest
  end

  # --- discovery ----------------------------------------------------------------

  def test_discover_yields_the_tibetan_pages_first_then_translations
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[
      bo:tibetan-masters/mipham/acala-sadhana
      bo:tibetan-masters/mipham/instruction-on-point-of-mind
      bo:words-of-the-buddha/amitayus-dharani
      en:tibetan-masters/mipham/acala-sadhana
      en:tibetan-masters/mipham/instruction-on-point-of-mind
      en:words-of-the-buddha/amitayus-dharani
      fr:tibetan-masters/alak-zenkar/patrul-biography
      nl:indian-masters/atisha/prayer-to-tara
      zh:indian-masters/tilopa/ganges-mahamudra-instruction
    ].map { |id| "#{URN}#{id}" }, ids
  end

  def test_without_translations_only_the_tibetan_pages_are_documents
    ids = House.new.discover(FIXTURES).map(&:id)
    assert_equal 3, ids.size
    assert(ids.all? { |id| id.start_with?("#{URN}bo:") })
  end

  # The rejected catalog grain: listing pages persist under catalog/ and
  # are skipped by rule (the fetch/ tree is the crawl test's own corpus).
  def test_discovery_skips_count_the_catalog_listing_pages
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_match(%r{catalog listing page.*catalog/en/tibetan-masters/mipham\.html}, skips.notes.join("\n"))
    assert skips.clean?
  end

  # --- the Tibetan source page ----------------------------------------------------

  def test_a_tibetan_page_is_a_classical_tibetan_document
    document = parse("bo", "tibetan-masters/mipham/instruction-on-point-of-mind")
    assert_equal "xct", document.language
    assert_equal "སེམས་དོན་གདམས་ངག", document.title
    assert_equal ["xct"], document.map(&:language).uniq
    assert_equal "༄༅། །སེམས་དོན་གདམས་ངག་བཞུགས།", document.first.text
    verse = document.passages[1]
    assert verse.text.start_with?("མགོན་མཚུངས་མེད་འཇམ་དབྱངས་བླ་མར་འདུད། །\nགྲོགས་ཟོལ་མེད་"),
           "a <br>-broken verse keeps its line breaks"
    metadata = document.metadata
    assert_equal "tibetan-masters", metadata["collection"]
    assert_equal "mipham", metadata["author_slug"]
    assert_equal "P252", metadata["bdrc_person"]
    assert_equal %w[dzogchen advice uncommon-dzogchen-instructions], metadata["topics"]
    assert_equal({ "values" => %w[dzogchen advice uncommon-dzogchen-instructions] }, metadata.dig("facets", "topic"))
    refute metadata.key?("translation_of")
    refute metadata["restricted"]
  end

  # --- the English translation (Markdown page) ------------------------------------

  def test_an_english_translation_points_at_its_tibetan_source
    document = parse("en", "tibetan-masters/mipham/instruction-on-point-of-mind")
    assert_equal "eng", document.language
    assert_equal "Instruction on Ultimate Point of Mind", document.title
    metadata = document.metadata
    assert_equal "translation", metadata["kind"]
    assert_equal "#{URN}bo:tibetan-masters/mipham/instruction-on-point-of-mind", metadata["translation_of"]
    assert_equal ["Adam Pearcey"], metadata["translators"]
    assert_equal 2026, metadata["translation_year"]
    assert_equal "1.0–20261019", metadata["version"]
    assert_equal "Mipham Rinpoche", metadata["author"]
    assert_equal %w[en bo], metadata["languages"]
    assert(metadata["bibliography"].any? { |line| line.start_with?("Tibetan Edition: 'ju mi pham") },
           "the h4 label prefixes its citation")
  end

  def test_footnote_markers_leave_the_text_and_notes_become_passages
    document = parse("en", "tibetan-masters/mipham/instruction-on-point-of-mind")
    heading = document.first
    assert_equal "An Instruction on the Ultimate Point of Mind", heading.text
    assert_equal ["1"], heading.annotations["notes"]
    notes = document.select { |passage| passage.annotations["block"] == "note" }
    assert_equal(%w[1 2 3], notes.map { |passage| passage.annotations["note"] })
    assert_equal "Corresponding to 22 March 1890.", notes.last.text, "the return arrow is cut"
    refute(document.any? { |passage| passage.text.include?("Translated by") }, "credits are metadata, not text")
    refute(document.any? { |passage| passage.text.start_with?("Version") })
  end

  # --- the trilingual liturgy page ------------------------------------------------

  def test_liturgy_lines_split_by_script_with_phonetics_on_the_tibetan_line
    document = parse("en", "tibetan-masters/mipham/acala-sadhana")
    assert document.metadata["restricted"], "the site's restricted-practice flag rides metadata"
    assert_equal({ "value" => "tibetan-masters" }, document.metadata.dig("facets", "collection"))
    verse = document.find { |passage| passage.text == "སྟོང་པའི་ངང་ལས་པད་ཉི་བདུད་བཞིའི་སྟེང་། །" }
    refute_nil verse
    assert_equal "xct", verse.language
    assert_equal "tongpé ngang lé pé nyi dü zhi teng", verse.annotations["phonetics"]
    english = document.passages[document.passages.index(verse) + 1]
    assert_equal "From the state of emptiness, upon a sun and moon and the four māras,", english.text
    assert_equal "eng", english.language
    mantra = document.find { |passage| passage.annotations["block"] == "p.EnglishMantra" }
    assert_equal "san", mantra.language
    assert(document.metadata["bibliography"].any? { |line| line.include?("mi g.yo ba'i sgrub thabs") },
           "the Source block is the edition citation")
    assert_equal "1.2-20211217", document.metadata["version"]
  end

  def test_a_dutch_liturgy_keeps_its_own_language_under_english_class_names
    document = parse("nl", "indian-masters/atisha/prayer-to-tara")
    assert_equal "nld", document.language
    line = document.find { |passage| passage.text.start_with?("Oṃ! Hulde aan de vrouwe") }
    assert_equal "nld", line.language, "upstream's EnglishText class carries Dutch here"
    assert_equal "indian-masters", document.metadata["collection"]
  end

  def test_a_chinese_translation_keeps_the_colophon_as_a_credit
    document = parse("zh", "indian-masters/tilopa/ganges-mahamudra-instruction")
    assert_equal "cmn", document.language
    assert_equal "恆河大手印", document.title
    assert_equal "恆河大手印", document.first.text
    assert(document.metadata["credits"].first.start_with?("二OO九年夏至行者普舟恭譯"))
    refute(document.any? { |passage| passage.text.include?("普舟恭譯") })
  end

  def test_a_french_prose_page_keeps_blockquote_paragraphs
    document = parse("fr", "tibetan-masters/alak-zenkar/patrul-biography")
    assert_equal "fra", document.language
    assert(document.any? { |passage| passage.text.start_with?("Si le sage les analyse") })
    assert_equal ["Mélanie Slomka"], document.metadata["translators"]
    assert_equal "1.3–20220826", document.metadata["version"]
  end

  def test_a_words_of_the_buddha_page_has_no_author
    document = parse("bo", "words-of-the-buddha/amitayus-dharani")
    assert_equal "words-of-the-buddha", document.metadata["collection"]
    refute document.metadata.key?("author_slug")
  end

  # --- store ----------------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "lotsawa-house", name: "Lotsawa House",
                                        adapter_class: "Nabu::Adapters::LotsawaHouse", license_class: "nc")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 9, first.added
    assert_equal 0, first.errored
    count = db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 9, second.skipped
    assert_equal count, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # --- fetch wiring ---------------------------------------------------------------

  def test_fetch_scope_follows_the_translations_posture
    calls = []
    fake = lambda do |**kwargs|
      calls << kwargs[:languages]
      Nabu::LotsawaFetch::Result.new(sha: "0" * 64, atticked: [], fetched: 0, cached: 0, records: 0,
                                     listings: 0, missing: [], languages: kwargs[:languages])
    end
    original = Nabu::LotsawaFetch.method(:sync!)
    Nabu::LotsawaFetch.define_singleton_method(:sync!) { |**kwargs| fake.call(**kwargs) }
    Dir.mktmpdir do |dir|
      House.new.fetch(dir)
      House.new(translations: true).fetch(dir)
    end
    assert_equal [%w[bo], Nabu::LotsawaFetch::LANGUAGES], calls
  ensure
    Nabu::LotsawaFetch.define_singleton_method(:sync!, original) if original
  end
end
