# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The render-conformance suite (P35-6, dev-loop §6b rule 2 — the durable
# residue of the recalibration pass): every truncating surface announces
# what it hid, and every empty result under active filters explains itself.
# Silence that looks like completeness is a defect, not a default.
#
# Data-driven: one seeded corpus, one CASES table — a future surface joins
# by adding a row (argv + the announcement its render must carry). The rows
# pin TODAY's honesty vocabulary: the inner-window hint (all four search
# surfaces), the fuzzy scope line, the script-miss hint, define's P34-r2
# render-cap tail, list's shared enumeration tail, the H9 unreadable-
# annotations notes, and show --tokens' honest absences.
class RenderConformanceTest < Minitest::Test
  CASES = {
    # (--license, not --lang: P42-3 moved plain-search --lang into the MATCH,
    # where it cannot starve; license stays catalog-side and still must announce.)
    "search: a filter-emptied page announces the exhausted inner window" =>
      [%w[search arma --license nc --limit 1],
       /page may be incomplete under these filters — raise --limit/],
    "search --near: the same announcement" =>
      [%w[search arma --near cano --lang grc --limit 1], /page may be incomplete under these filters/],
    "search --lemma: the same announcement" =>
      [%w[search --lemma λέγω --license nc --limit 1], /page may be incomplete under these filters/],
    "search --fuzzy: the same announcement" =>
      [%w[search --fuzzy arma --lang grc --limit 1], /page may be incomplete under these filters/],
    "search --fuzzy: every render names its documentary scope" =>
      [%w[search --fuzzy zzzz], /fuzzy index covers:/],
    "search: a cross-script zero hit hints instead of missing silently" =>
      [%w[search ⰲⱏⱄⱅⰰ], /Glagolitic/],
    "define: the render cap announces its tail (P34-r2)" =>
      [%w[define μῆνις --limit 2], /… \d+ more entr(y|ies) match.*--long shows all/],
    "list SLUG --documents: the shared enumeration tail" =>
      [%w[list open --documents --limit 1], /… \d+ more — raise --limit \(0 = all\)/],
    "show: unreadable stored annotations say so (H9)" =>
      [%w[show urn:w:bad:1], /unreadable \(invalid JSON\) — skipped/],
    "show --tokens: an unannotated passage says so" =>
      [%w[show urn:w:grc:1 --tokens], /no token annotations stored for this passage/],
    "export: a dropped annotation lane is announced on its line (H9)" =>
      [%w[export --format jsonl], /annotations_error/]
  }.freeze

  def test_every_surface_announces_its_truncations_and_explains_its_empties
    with_conformance_corpus do |config|
      CASES.each do |name, (argv, announcement)|
        out = run_cli(config, argv)
        assert_match announcement, out,
                     "#{name}: expected the render of `nabu #{argv.join(' ')}` to announce itself"
      end
    end
  end

  private

  # In-process CLI run (the cli_test house pattern), returning stdout.
  def run_cli(config, argv)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    out, = capture_io do
      Nabu::CLI.start(argv)
    rescue SystemExit
      nil
    end
    out
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  # One corpus serving every row: the window-exhaustion shape (ten short lat
  # rows outrank one long grc row; an nc λέγω attestation beyond the lemma
  # window), a corrupt-annotations passage (H9), and four same-headword
  # dictionaries (the define render-cap tail). Fuzzy scope covers everything.
  def with_conformance_corpus
    Dir.mktmpdir("nabu-conformance") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed(catalog)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext, fuzzy_slugs: %w[open nc])
      fulltext.disconnect
      catalog.disconnect
      yield config
    end
  end

  def seed(catalog)
    open_id = catalog[:sources].insert(slug: "open", name: "Open", adapter_class: "TestAdapter",
                                       license_class: "open", enabled: true)
    nc_id = catalog[:sources].insert(slug: "nc", name: "NC", adapter_class: "TestAdapter",
                                     license_class: "nc", enabled: true)
    lat = document(catalog, open_id, "urn:w:lat", "lat")
    10.times do |i|
      passage(catalog, lat, "urn:w:lat:#{i}", "arma virumque cano", i, "lat",
              tokens: [{ "lemma" => "λέγω", "form" => "λέγειν" }])
    end
    grc = document(catalog, open_id, "urn:w:grc", "grc")
    passage(catalog, grc, "urn:w:grc:1",
            "arma sits before cano yet far down the rank because this passage carries many more words",
            0, "grc")
    nc_doc = document(catalog, nc_id, "urn:w:nc", "grc")
    passage(catalog, nc_doc, "urn:w:nc:1", "εἶπας", 0, "grc",
            tokens: [{ "lemma" => "λέγω", "form" => "εἶπας" }])
    bad = document(catalog, open_id, "urn:w:bad", "grc")
    passage(catalog, bad, "urn:w:bad:1", "σῆμα κακόν", 0, "grc", raw_annotations: "{broken")
    seed_shelves(catalog, open_id)
  end

  # Four dictionaries all defining the same headword — `define --limit 2`
  # must announce the two hidden entries (the P34-r2 lesson).
  def seed_shelves(catalog, source_id)
    4.times do |i|
      dict_id = catalog[:dictionaries].insert(source_id: source_id, slug: "dict#{i}",
                                              title: "Dictionary #{i}", language: "grc")
      catalog[:dictionary_entries].insert(
        dictionary_id: dict_id, urn: "urn:nabu:dict:dict#{i}:n1", entry_id: "n1",
        key_raw: "μῆνις", headword: "μῆνις",
        headword_folded: Nabu::Normalize.search_form("μῆνις", language: "grc"),
        gloss: "wrath", body: "μῆνις body #{i}", content_sha256: "x", revision: 1, withdrawn: false
      )
    end
  end

  def document(catalog, source_id, urn, language)
    catalog[:documents].insert(
      source_id: source_id, urn: urn, title: urn, language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
  end

  def passage(catalog, doc_id, urn, text, sequence, language, tokens: nil, raw_annotations: nil)
    annotations = raw_annotations || JSON.generate({ "tokens" => tokens || [] })
    catalog[:passages].insert(
      document_id: doc_id, urn: urn, sequence: sequence, language: language,
      text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
      content_sha256: "x", revision: 1, withdrawn: false, annotations_json: annotations
    )
  end
end
