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

  private

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
