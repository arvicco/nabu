# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu char 棄` (P37-4): the character card — the join across held shelves,
# matching Jisho synchronically where a shelf backs the glyph and exceeding
# it diachronically, with the "absent, never —" rule. Builds a catalog from
# the CJK fixtures (Unihan + BabelStone IDS + KRADFILE + TLS + a seeded
# corpus passage) and asserts the rendered sections.
class CharCommandTest < Minitest::Test
  def test_char_of_the_acceptance_glyph_renders_the_whole_card
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 棄]) }
      assert_nil status

      # header — Unihan kTotalStrokes + kRSUnicode → radical 75 木 tree
      assert_match(/棄\s+U\+68C4.*12 strokes.*radical 75 木 tree/, out)
      # decomposition — BabelStone IDS + the printed follow-up "click"
      assert_match(/decomposition \(BabelStone IDS\):/, out)
      assert_match(/⿳亠厶⿻廿木/, out)
      assert_match(/木 — nabu char 木 · nabu search --char-component 木/, out)
      # components — KRADFILE flat index
      assert_match(/components \(KRADFILE index\): 一 木 亠 凵 厶/, out)
      # variants — Unihan trad→simp
      assert_match(/simplified: 弃 \(U\+5F03\)/, out)
      # sinoxenic readings — Unihan
      assert_match(/Mandarin: qì/, out)
      assert_match(/Korean: KI/, out)
      assert_match(/Vietnamese: khí/, out)
      # the diachronic column — TLS senses + attestation counts
      assert_match(/TLS \(Thesaurus Linguae Sericae\):/, out)
      assert_match(/attestation/, out)
      # corpus attestation from the seeded passage
      assert_match(/corpus attestation: lzh 1/, out)
      # search affordances
      assert_match(/search: nabu search 棄.*--char-component 棄.*--radical 75/, out)
    end
  end

  def test_absent_fields_are_omitted_not_dashed
    with_char_catalog do |config|
      out, = with_config(config) { run_cli(%w[char 棄]) }
      # kanjidic2 / baxter-sagart / tshet-uinh / hdic do not back 棄 in the
      # fixture rig — those sections are absent, never rendered "—".
      refute_match(/—$/, out, "no bare em-dash placeholder anywhere")
      refute_match(/readings \(ja, KANJIDIC2\)/, out, "ja readings absent (kanjidic2 lacks 棄)")
      refute_match(/Old Chinese/, out, "OC absent (baxter-sagart lacks 棄)")
    end
  end

  def test_char_notes_the_japanese_reform_cross_reference_and_covers_jpn_corpus
    with_char_catalog do |config|
      # 國 is a kyūjitai — the card names its shinjitai 国, and the corpus
      # column now carries the jpn holding.
      out, = with_config(config) { run_cli(%w[char 國]) }
      assert_match(/shinjitai \(Japanese new form\): 国 \(U\+56FD\)/, out)
      assert_match(/corpus attestation:.*jpn 1/, out)

      # and the reverse: 国 names its kyūjitai 國 (the hani-fold display precedent).
      back, = with_config(config) { run_cli(%w[char 国]) }
      assert_match(/kyūjitai \(Japanese old form\): 國 \(U\+570B\)/, back)
    end
  end

  def test_char_of_a_non_reform_glyph_has_no_jpn_cross_reference_and_zero_jpn_is_graceful
    with_char_catalog do |config|
      out, = with_config(config) { run_cli(%w[char 棄]) }
      refute_match(/shinjitai|kyūjitai/, out, "棄 is not a reform pair — no jpn cross-reference")
      # 棄 has no jpn attestation in the fixture: the column shows lzh only,
      # never an empty/placeholder jpn entry.
      assert_match(/corpus attestation: lzh 1/, out)
      refute_match(/jpn/, out)
    end
  end

  def test_bare_char_errors_helpfully
    with_char_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[char]) }
      assert_equal 1, status
      assert_match(/give a character/, err)
    end
  end

  def test_multi_char_input_errors_naming_the_single_char_grain
    with_char_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[char 棄権]) }
      assert_equal 1, status
      assert_match(/single character/, err)
      assert_match(/--char-component 棄/, err, "points at the containment search instead")
    end
  end

  # --- the structure-search modes (search --radical/--strokes/--char-component) ---

  def test_radical_filter_finds_passages_carrying_a_radical_75_character
    with_search_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --radical 75]) }
      assert_nil status
      assert_match(/urn:nabu:test:qi.*棄/m, out, "the 棄 passage (radical 75 木)")
      refute_match(/urn:nabu:test:tian/, out, "天 is radical 37, excluded")
      assert_match(/character filter: \[radical 75\]/, out, "the footer names the filter distinctly")
    end
  end

  def test_strokes_range_filter
    with_search_catalog do |config|
      out, = with_config(config) { run_cli(%w[search --strokes 1-4]) }
      assert_match(/urn:nabu:test:tian/, out, "天(4)/一(1)/人(2) are in range")
      refute_match(/urn:nabu:test:qi\b/, out, "棄(12) is out of range")
      assert_match(/character filter: \[1-4 strokes\]/, out)
    end
  end

  def test_char_component_union_transitive_containment
    with_search_catalog do |config|
      out, = with_config(config) { run_cli(%w[search --char-component 木]) }
      # 棄 (KRADFILE lists 木; IDS ⿻廿木) and 林 (⿰木木) both contain 木.
      assert_match(/urn:nabu:test:qi\b/, out)
      assert_match(/urn:nabu:test:lin/, out)
      refute_match(/urn:nabu:test:tian/, out, "天 contains no 木")
      assert_match(/character filter: \[contains 木\]/, out)
    end
  end

  def test_char_filters_and_together
    with_search_catalog do |config|
      # radical 75 = {棄}; strokes 1 = {一}; the intersection is empty → an
      # honest zero-character resolution, not a silent empty page.
      out, = with_config(config) { run_cli(%w[search --radical 75 --strokes 1]) }
      assert_match(/no characters match \[radical 75 AND 1 strokes\]/, out)
    end
  end

  def test_char_filter_composes_with_a_text_query
    with_search_catalog do |config|
      # The FTS token for a Han run is the whole run (unicode61); the exact
      # run is the searchable form. The char filter then ANDs on top.
      out, = with_config(config) { run_cli(%w[search 林木森森 --char-component 木]) }
      assert_match(/urn:nabu:test:lin/, out, "林木森森 matches the text query AND contains 木")
      refute_match(/urn:nabu:test:qi\b/, out, "棄 contains 木 but does not match the text query")
      assert_match(/text query "林木森森"/, out)
    end
  end

  def test_char_filters_reject_word_level_combination
    with_search_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --radical 75 --lemma foo]) }
      assert_equal 1, status
      assert_match(/character-level structure search/, err)
    end
  end

  def test_radical_out_of_range_errors
    with_search_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --radical 999]) }
      assert_equal 1, status
      assert_match(/KangXi radical number 1-214/, err)
    end
  end

  private

  def with_search_catalog
    Dir.mktmpdir("nabu-char-search") do |root|
      config = char_config(root)
      db, fulltext = open_dbs(config)
      load_dictionary(db, "unihan", "Nabu::Adapters::Unihan", Nabu::Adapters::Unihan.new, "unihan")
      load_dictionary(db, "babelstone-ids", "Nabu::Adapters::BabelstoneIds",
                      Nabu::Adapters::BabelstoneIds.new, "babelstone-ids")
      load_dictionary(db, "kradfile", "Nabu::Adapters::Kradfile", Nabu::Adapters::Kradfile.new, "kradfile")
      source = Nabu::Store::Source.create(
        slug: "test", name: "test", adapter_class: "Nabu::Adapters::Kanripo", license_class: "open"
      )
      { "qi" => "棄而違之。", "lin" => "林木森森。", "tian" => "天下一人。" }.each do |slug, text|
        seed_passage(source, slug, text)
      end
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      db.disconnect
      fulltext.disconnect
      yield config
    end
  end

  def seed_passage(source, slug, text)
    document = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:nabu:test:#{slug}", title: slug, language: "lzh",
      content_sha256: slug, revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: document.id, urn: "urn:nabu:test:#{slug}:1", sequence: 0,
      language: "lzh", text: text, text_normalized: text, content_sha256: slug, revision: 1
    )
  end

  def char_config(root)
    config = Nabu::Config.new(
      canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
      sources_path: File.join(root, "sources.yml"), config_path: "(test)"
    )
    FileUtils.mkdir_p(config.db_dir)
    config
  end

  def open_dbs(config)
    db = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(db)
    Nabu::Store.setup!(db)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    [db, fulltext]
  end

  def with_char_catalog
    Dir.mktmpdir("nabu-char") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)

      load_dictionary(db, "unihan", "Nabu::Adapters::Unihan", Nabu::Adapters::Unihan.new, "unihan")
      load_dictionary(db, "babelstone-ids", "Nabu::Adapters::BabelstoneIds",
                      Nabu::Adapters::BabelstoneIds.new, "babelstone-ids")
      load_dictionary(db, "kradfile", "Nabu::Adapters::Kradfile", Nabu::Adapters::Kradfile.new, "kradfile")
      load_dictionary(db, "tls", "Nabu::Adapters::Tls", Nabu::Adapters::Tls.new, "tls")

      kanripo = Nabu::Store::Source.create(
        slug: "kanripo", name: "Kanseki Repository", adapter_class: "Nabu::Adapters::Kanripo",
        license_class: "attribution"
      )
      document = Nabu::Store::Document.create(
        source_id: kanripo.id, urn: "urn:nabu:kanripo:KR1h0004", title: "論語", language: "lzh",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "urn:nabu:kanripo:KR1h0004:005:22a", sequence: 0,
        language: "lzh", text: "棄而違之。", text_normalized: "棄而違之。", content_sha256: "x", revision: 1
      )
      # A jpn holding carrying both reform spellings — so the card's corpus
      # column covers jpn (P38-4) and both 國 and 国 attest.
      aozora = Nabu::Store::Source.create(
        slug: "aozora", name: "Aozora Bunko", adapter_class: "Nabu::Adapters::Aozora",
        license_class: "open"
      )
      jpn_doc = Nabu::Store::Document.create(
        source_id: aozora.id, urn: "urn:nabu:aozora:000001", title: "見本", language: "jpn",
        content_sha256: "y", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: jpn_doc.id, urn: "urn:nabu:aozora:000001:1", sequence: 0,
        language: "jpn", text: "國語と国語。", text_normalized: "國語と國語。", content_sha256: "y", revision: 1
      )
      db.disconnect
      yield config
    end
  end

  def load_dictionary(db, slug, adapter_class, adapter, fixture)
    source = Nabu::Store::Source.create(
      slug: slug, name: slug, adapter_class: adapter_class, license_class: "open"
    )
    Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                 .load_from(adapter, workdir: Nabu::TestSupport.fixtures(fixture))
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
