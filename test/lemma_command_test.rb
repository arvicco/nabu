# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu lemma FORM` and `nabu language CODE --curve` / `language --mixing`
# (P121-2): the lemma attestation desks. An on-disk catalog + fulltext pair
# (the real Indexer builds passage_lemmas; Store::LemmaRollup builds the
# rollups the desks read), then the rendered output. The desk law is pinned
# from both sides: the commands answer from the rollups, and an absent or
# unbuilt rollup is an honest hint naming the refresh, never a scan.
class LemmaCommandTest < Minitest::Test
  # -- nabu lemma ---------------------------------------------------------------

  def test_lemma_profile_renders_span_curve_sparklines_sources_and_dictionary
    with_rollup_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[lemma hostis --lang lat]) }
      assert_nil status
      assert_match(/lemma hostis \[lat\] — first attested 2nd c\. BCE \(artifact\) · last 2nd c\. CE \(composition\)/,
                   out)
      assert_match(%r{2nd c\. BCE\s+2 / 1\s+—}, out, "gold attestations / documents per century")
      assert_match(%r{1st c\. BCE\s+—\s+1 / 1}, out, "silver kept in its own column")
      assert_match(%r{undated\s+1 / 1\s+—}, out, "undated attestations close the table")
      assert_match(/^  gold   █··▅  \(2nd c\. BCE → 2nd c\. CE, one cell per century\)/, out,
                   "gold sparkline on the shared scale; century 0 never gets a cell")
      assert_match(/^  silver ·▅··  /, out)
      assert_match(/top sources: proiel 4 gold · silvery 1 silver/, out)
      assert_match(/lewis-short: hostis — enemy/, out, "the dictionary hop")
      assert_match(/lemma: 5 attestations · 3 dated centuries \(\d/, out, "summary with elapsed")
    end
  end

  def test_lemma_language_alias_and_unattested_form
    with_rollup_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[lemma nusquam --language lat]) }
      assert_nil status
      assert_match(/lemma nusquam \[lat\]: not attested in the lemma rollup/, out)
    end
  end

  def test_lemma_on_an_unbuilt_rollup_is_an_honest_hint
    with_rollup_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[lemma hostis --lang lat]) }
      assert_equal 1, status
      assert_match(/lemma: the rollup is not built yet — run `bundle exec rake builders:refresh`/, err)
    end
  end

  def test_lemma_on_a_pre_migration_catalog_names_the_rebuild
    with_rollup_corpus(build: false) do |config|
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store::LemmaRollup::TABLES.each { |table| db.drop_table(table) }
      db.disconnect
      _out, err, status = with_config(config) { run_cli(%w[lemma hostis]) }
      assert_equal 1, status
      assert_match(/predates the lemma rollups \(migration 038\)/, err)
    end
  end

  # The standalone silver projection moves passage_lemmas rows — the
  # rollup re-derives in the same command.
  def test_lemma_enrich_index_only_refreshes_the_rollup
    with_rollup_corpus do |config|
      shelf = Nabu::LemmaShelf.new(dir: Nabu::LemmaShelf.dir(config))
      shelf.append_batch!(language: "lat", records: [
                            Nabu::LemmaShelf::Record.new(
                              urn: "urn:t:plain:1", language: "lat", source: "proiel",
                              model: "stanza", model_version: "1.14.0", package: "la:ittb",
                              tokens: [%w[hostes hostis NOUN]],
                              generated_at: "2026-10-12T00:00:00Z"
                            )
                          ])
      out, _err, status = with_config(config) { run_cli(%w[lemma-enrich lat --index-only]) }
      assert_nil status
      assert_match(/lemma rollup re-derived: \d+ rows/, out)
      db = Nabu::Store.connect(config.catalog_path)
      silver = db[:lemma_rollup].where(lemma: "hostis", grade: "silver").sum(:occurrences)
      db.disconnect
      assert_equal 2, silver, "the shelf projection lands as a silver attestation"
    end
  end

  # -- nabu language --curve / --mixing --------------------------------------------

  def test_lang_curve_draws_documents_and_passages_per_century
    with_rollup_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[lang lat --curve]) }
      assert_nil status, "`lang` resolves to the language command"
      assert_match(/lat — documents and passages per century/, out)
      assert_match(/2nd c\. BCE\s+1 docs ·\s+2 passages  █+  \(artifact\)/, out)
      assert_match(/2nd c\. CE\s+1 docs ·\s+1 passages  █+  \(composition\)/, out)
      assert_match(/undated\s+3 docs ·\s+4 passages  █+$/, out)
      assert_match(/curve: 6 docs · 8 passages over 3 dated centuries \(\d/, out)
    end
  end

  def test_lang_mixing_is_the_multilingualism_census
    with_rollup_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[lang --mixing]) }
      assert_nil status
      assert_match(/language mixing — 6 documents by passage-language inventory size/, out)
      assert_match(/1 language\s+5 docs \(83\.3%\)/, out)
      assert_match(/2 languages\s+1 docs \(16\.7%\)/, out)
      assert_match(/top mixed inventories:\n  grc,lat\s+1 docs/, out)
      assert_match(%r{proiel\s+1 mixed · 0 block / 1 interleaved · 3 switches}, out)
      assert_match(/mixing: 1 mixed of 6 documents \(16\.7%\) \(\d/, out)
    end
  end

  def test_lang_curve_on_an_unbuilt_rollup_is_an_honest_hint
    with_rollup_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[language lat --curve]) }
      assert_equal 1, status
      assert_match(/language --curve: the rollup is not built yet — run `bundle exec rake builders:refresh`/, err)
    end
  end

  private

  # The store test's dated corpus, plus a plain undated Latin passage with
  # no lemmas (the silver projection's target) and a Lewis-Short entry.
  def with_rollup_corpus(build: true)
    Dir.mktmpdir("nabu-lemma-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      seed(db)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext, lemma_tiers: { "silvery" => "silver" })
      fulltext.disconnect
      Nabu::Store::LemmaRollup.rebuild!(catalog: db, fulltext_path: config.fulltext_path) if build
      db.disconnect
      yield config
    end
  end

  def seed(db)
    gold = Nabu::Store::Source.create(slug: "proiel", name: "PROIEL", adapter_class: "X", license_class: "open")
    silver = Nabu::Store::Source.create(slug: "silvery", name: "S", adapter_class: "X", license_class: "open")
    bce = document(gold, "urn:t:bce")
    axis(db, bce, -300, -30)
    passage(bce, 1, %w[hostis et])
    passage(bce, 2, %w[hostis])
    ce = document(gold, "urn:t:ce")
    axis(db, ce, 101, 200, date_class: "composition")
    passage(ce, 1, %w[hostis])
    passage(document(gold, "urn:t:undated"), 1, %w[hostis])
    stone = document(silver, "urn:s:stone")
    axis(db, stone, -100, -1)
    passage(stone, 1, %w[hostis])
    mixed = document(gold, "urn:t:mixed")
    passage(mixed, 1, %w[et])
    passage(mixed, 2, %w[καί], language: "grc")
    passage(mixed, 3, %w[et])
    passage(mixed, 4, %w[καί], language: "grc")
    passage(document(gold, "urn:t:plain"), 1, [])
    dict = db[:dictionaries].insert(source_id: gold.id, slug: "lewis-short", title: "LS", language: "lat")
    db[:dictionary_entries].insert(dictionary_id: dict, urn: "urn:nabu:lewis-short:hostis", entry_id: "hostis",
                                   key_raw: "hostis", headword: "hostis", headword_folded: "hostis",
                                   gloss: "enemy", body: "b", content_sha256: "x")
  end

  def document(source, urn)
    Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: "lat",
                                 content_sha256: "x", revision: 1)
  end

  def passage(doc, sequence, lemmas, language: "lat")
    tokens = lemmas.map { |lemma| { "lemma" => lemma, "form" => lemma } }
    text = lemmas.empty? ? "hostes" : lemmas.join(" ")
    Nabu::Store::Passage.create(document_id: doc.id, urn: "#{doc.urn}:#{sequence}", sequence: sequence,
                                language: language, text: text, text_normalized: text,
                                annotations_json: lemmas.empty? ? "{}" : JSON.generate({ "tokens" => tokens }),
                                content_sha256: "x", revision: 1)
  end

  def axis(db, doc, not_before, not_after, date_class: nil)
    db[:document_axes].insert(document_id: doc.id, not_before: not_before, not_after: not_after,
                              date_class: date_class, axis_source: "test")
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
