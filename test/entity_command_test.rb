# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# `nabu entity NAME` and `nabu show --entities`: the readers of the inline
# "entities" passage annotation. An on-disk catalog seeded with the live
# record shapes (Perseus EpiDoc: type/text/key; Coptic Scriptorium:
# type/text/identity), Store::EntityIndex built over it, then the rendered
# output. The desk law is pinned from both sides: the desk answers from
# the index, and an absent or unbuilt index is an honest hint, never a scan.
class EntityCommandTest < Minitest::Test
  HERODOTUS = "urn:cts:greekLit:tlg0016.tlg001.perseus-grc2"

  # -- nabu entity -------------------------------------------------------------

  def test_entity_lists_matched_names_and_their_passages
    with_entity_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[entity κροισ]) }
      assert_nil status
      assert_match(/entity "κροισ": 2 names · 2 passages/, out)
      assert_match(/person\s+Κροῖσος\s+perseus-greek\s+1 passage/, out)
      assert_match(/#{Regexp.escape(HERODOTUS)}:1\s+person Κροῖσος/, out)
      assert_match(/Κροῖσος ἦν Λυδὸς μὲν γένος/, out, "the passage text rides under its urn")
      refute_match(/:2\b/, out, "the Sardis passage does not match")
    end
  end

  def test_entity_type_filter_and_key_lookup
    with_entity_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[entity κροισ --type place]) }
      assert_nil status
      assert_match(/entity "κροισ" \[place\]: no names match/, out)

      key_out, = with_config(config) { run_cli(%w[entity tgn,7002011]) }
      assert_match(/place\s+Σάρδις\s+\[key tgn,7002011 · subtype city\]\s+perseus-greek/, key_out)
    end
  end

  def test_entity_identity_shows_beside_the_surface
    with_entity_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["entity", "macarius of egypt"]) }
      assert_nil status
      assert_match(/person\s+ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ\s+\[identity Macarius of Egypt\]\s+coptic-scriptorium/, out)
    end
  end

  def test_entity_limit_announces_truncation
    with_entity_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[entity κροισ --limit 1]) }
      assert_nil status
      assert_match(/showing 1 of 2 passages — raise --limit/, out)
    end
  end

  def test_entity_census_without_a_name
    with_entity_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[entity]) }
      assert_nil status
      assert_match(/entity index:/, out)
      assert_match(/perseus-greek\s+person\s+2 names\s+2 passages/, out)
      assert_match(/coptic-scriptorium\s+person\s+1 name\s+1 passage/, out)
    end
  end

  def test_entity_on_an_unbuilt_index_is_an_honest_hint
    with_entity_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[entity κροισ]) }
      assert_equal 1, status
      assert_match(/entity: the entity index is not built yet — run `bundle exec rake builders:refresh`/, err)
    end
  end

  def test_entity_on_a_pre_migration_catalog_names_the_migration
    with_entity_corpus(build: false) do |config|
      db = Nabu::Store.connect(config.catalog_path)
      db.drop_table(:passage_entities)
      db.drop_table(:passage_entity_names)
      db.disconnect
      _out, err, status = with_config(config) { run_cli(%w[entity κροισ]) }
      assert_equal 1, status
      assert_match(/predates the entity index \(migration 050\)/, err)
    end
  end

  # -- nabu show --entities ----------------------------------------------------

  def test_show_entities_lists_a_passages_inline_names
    with_entity_corpus(build: false) do |config|
      out, _err, status = with_config(config) { run_cli(%W[show #{HERODOTUS}:1 --entities]) }
      assert_nil status
      assert_match(/entities \(2\):/, out)
      assert_match(/^  person\s+Κροῖσος$/, out)
      assert_match(/^  ethnic\s+Λυδὸς$/, out)
    end
  end

  def test_show_entities_carries_key_identity_and_subtype
    with_entity_corpus(build: false) do |config|
      out, = with_config(config) { run_cli(%W[show #{HERODOTUS}:2 --entities]) }
      assert_match(/^  place\s+Σάρδις\s+\[key tgn,7002011 · subtype city\]$/, out)
      coptic, = with_config(config) { run_cli(%w[show urn:nabu:coptic-scriptorium:ap.1:4 --entities]) }
      assert_match(/^  person\s+ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ\s+\[identity Macarius of Egypt\]$/, coptic)
    end
  end

  def test_show_entities_on_a_document_groups_by_passage
    with_entity_corpus(build: false) do |config|
      out, _err, status = with_config(config) { run_cli(%W[show #{HERODOTUS} --entities]) }
      assert_nil status
      assert_match(/entities \(4 in 3 passages\):/, out)
      assert_match(/^  :2\n    place\s+Σάρδις/, out)
    end
  end

  def test_show_entities_on_a_passage_without_them_says_so
    with_entity_corpus(build: false) do |config|
      out, = with_config(config) { run_cli(%w[show urn:nabu:coptic-scriptorium:ap.1:5 --entities]) }
      assert_match(/no inline entities stored for this passage/, out)
    end
  end

  # The token-grain name lane: an ORACC passage's qpn-tagged tokens (the
  # live stored shape) answer the desk and `show --entities` alike.
  def test_token_grain_names_answer_the_desk_and_show
    with_entity_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[entity idrimi --type RN]) }
      assert_nil status
      assert_match(/RN\s+\{m\}id-ri-mi\s+\[key Idrimi\]\s+oracc\s+1 passage/, out)
      shown, = with_config(config) { run_cli(%w[show urn:nabu:oracc:p1:1 --entities]) }
      assert_match(/entities \(2\):/, shown, "the preposition is no name")
      assert_match(/^  RN\s+\{m\}id-ri-mi\s+\[key Idrimi\]$/, shown)
      assert_match(/^  DN\s+\{d\}IM\s+\[key Addu\]$/, shown)
    end
  end

  def test_show_entities_does_not_compose_with_random
    with_entity_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random --entities]) }
      assert_equal 1, status
      assert_match(%r{--entities does not compose with --random/--parallel}, err)
    end
  end

  private

  def with_entity_corpus(build: true)
    Dir.mktmpdir("nabu-entity-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      seed
      Nabu::Store::EntityIndex.rebuild!(catalog: db, sources: %w[perseus-greek coptic-scriptorium oracc]) if build
      db.disconnect
      yield config
    end
  end

  def seed
    perseus = source("perseus-greek")
    herodotus = document(perseus, HERODOTUS)
    passage(herodotus, 1, "Κροῖσος ἦν Λυδὸς μὲν γένος",
            [{ "type" => "person", "text" => "Κροῖσος" }, { "type" => "ethnic", "text" => "Λυδὸς" }])
    passage(herodotus, 2, "ἐς Σάρδις ἀπικνέεται",
            [{ "type" => "place", "text" => "Σάρδις", "key" => "tgn,7002011", "subtype" => "city" }])
    passage(herodotus, 3, "Κροίσου δὲ ἐπαίνεε", [{ "type" => "person", "text" => "Κροίσου" }])
    coptic = source("coptic-scriptorium")
    apophthegmata = document(coptic, "urn:nabu:coptic-scriptorium:ap.1")
    passage(apophthegmata, 4, "ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ ⲡⲉϫⲁϥ",
            [{ "head" => "#u3", "type" => "person", "text" => "ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ", "identity" => "Macarius of Egypt" }])
    passage(apophthegmata, 5, "ⲡⲉϫⲁϥ ⲛⲁϥ", nil)
    oracc = document(source("oracc"), "urn:nabu:oracc:p1")
    Nabu::Store::Passage.create(
      document_id: oracc.id, urn: "urn:nabu:oracc:p1:1", sequence: 1, language: "akk",
      text: "{m}id-ri-mi a-na {d}IM", text_normalized: "id ri mi a na im", content_sha256: "x", revision: 1,
      annotations_json: JSON.generate("tokens" => [
                                        { "form" => "{m}id-ri-mi", "lemma" => "Idrimi", "pos" => "RN" },
                                        { "form" => "a-na", "lemma" => "ana", "pos" => "PRP" },
                                        { "form" => "{d}IM", "lemma" => "Addu", "pos" => "DN" }
                                      ])
    )
  end

  def source(slug)
    Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "X", license_class: "open")
  end

  def document(source, urn)
    Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: "grc",
                                 content_sha256: urn, revision: 1)
  end

  def passage(document, sequence, text, entities)
    Nabu::Store::Passage.create(
      document_id: document.id, urn: "#{document.urn}:#{sequence}", sequence: sequence, language: "grc",
      text: text, text_normalized: text, content_sha256: "x", revision: 1,
      annotations_json: JSON.generate(entities ? { "entities" => entities } : {})
    )
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
