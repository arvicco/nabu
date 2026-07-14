# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The de Vaan EDL skeleton adapter (P18-6): one source, TWO staged etymon
# shelves (edl-ine-pro + edl-itc-pro) from one Turtle file — the Leiden-school
# cross-witness beside kaikki's itc-pro (provenance-distinct entries, the
# MW-beside-kaikki precedent). Mirrors the dictionary-shape conformance
# checks and adds: the two-refs-one-file discovery, the staged reflex chain
# (PIE→PIt proto-to-proto + PIt→lat + the 27 direct PIE→lat edges), the
# U+2011 non-breaking-hyphen fold pin, the blank-node canonicalForm parse,
# the loader contract, the language-notes rider, and the etym acceptance
# render (the full lat → PIt → PIE ascent, beside a second itc-pro witness).
class EdlTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("edl")
  RAW_URL = "https://raw.githubusercontent.com/CIRCSE/EtymologicalDictionaryLatin/master/data/BrillEDL.ttl"

  def adapter = Nabu::Adapters::Edl.new

  # --- manifest + content kind ---------------------------------------------------

  def test_manifest_identifies_the_edl_source
    manifest = adapter.manifest
    assert_equal "edl", manifest.id
    assert_equal "nc", manifest.license_class, "CC BY-NC-SA 4.0 — the GRETIL/MW class"
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(/The dictionary entries are not represented/, manifest.license,
                 "the README skeleton statement travels verbatim")
    assert_equal RAW_URL, manifest.upstream_url
    assert_equal "lila-ttl", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Edl.content_kind
  end

  # --- discover → parse: two shelves from one file ---------------------------------

  def test_discover_yields_one_ref_per_shelf_and_nothing_before_a_fetch
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["edl-ine-pro:BrillEDL.ttl", "edl-itc-pro:BrillEDL.ttl"], refs.map(&:id)
    assert_equal %w[edl edl], refs.map(&:source_id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_splits_etymons_by_stage
    ine, itc = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    assert_equal "edl-ine-pro", ine.slug
    assert_equal "ine-pro", ine.language
    assert_equal %w[pie0787 pie1043 pie1418], ine.map(&:entry_id), "file order, upstream ids"
    assert_equal "edl-itc-pro", itc.slug
    assert_equal "itc-pro", itc.language
    assert_equal %w[pit1043], itc.map(&:entry_id)
  end

  def test_headwords_keep_the_upstream_nonbreaking_hyphen_but_fold_it_ascii
    ine = adapter.parse(adapter.discover(FIXTURES).first)
    rodo = ine.entries.find { |entry| entry.entry_id == "pie1043" }
    assert_equal "*Hreh₃d‑e/o‑", rodo.key_raw
    assert_equal "Hreh₃d‑e/o‑", rodo.headword, "asterisk stripped, U+2011 kept for display"
    assert_equal "hreh₃d-e/o-", rodo.headword_folded,
                 "folded through §9 ine with U+2011 → ASCII hyphen, so typed lookups reach it"
    assert_nil rodo.gloss, "the skeleton carries no entry content — Brill copyright"
    assert_includes rodo.body, "*Hreh₃d‑e/o‑;*ureh₃d‑e/o‑", "variant reconstructions from rdfs:comment"
    assert_includes rodo.body, "Etymology for: rōdō (la1405)"
  end

  # --- the staged reflex chain ------------------------------------------------------

  def test_pie_etymons_mint_proto_to_proto_and_direct_latin_reflexes
    ine = adapter.parse(adapter.discover(FIXTURES).first)
    entries = ine.entries.to_h { |entry| [entry.entry_id, entry] }

    pit_edge = entries["pie1043"].reflexes
    assert_equal 1, pit_edge.size
    reflex = pit_edge.first
    assert_equal "PIt", reflex.lang_code, "upstream lime:language verbatim"
    assert_equal "itc-pro", reflex.language
    assert_equal "*(w)rōde/o‑", reflex.word, "proto-to-proto reflexes keep the asterisk (kaikki precedent)"
    assert_equal "(w)rode/o-", reflex.word_folded

    direct = entries["pie1418"].reflexes
    assert_equal [%w[la lat cōlum colum]],
                 direct.map { |r| [r.lang_code, r.language, r.word, r.word_folded] },
                 "one of the 27 direct PIE→Latin edges — no PIt stage"

    assert_empty entries["pie0787"].reflexes, "no link in the slice — an honest empty"
  end

  def test_pit_etymons_mint_latin_reflexes
    itc = adapter.discover(FIXTURES).to_a.last.then { |ref| adapter.parse(ref) }
    reflexes = itc.entries.first.reflexes
    assert_equal 1, reflexes.size
    assert_equal "rōdō", reflexes.first.word
    assert_equal "rodo", reflexes.first.word_folded, "macrons fall to the §9 mark strip"
    refute reflexes.first.borrowed, "every EDL link is etyLinkType inheritance (censused)"
  end

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    snapshot = lambda do
      adapter.discover(FIXTURES).flat_map { |ref| adapter.parse(ref).map(&:entry_id) }
    end
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    adapter.discover(FIXTURES).each do |ref|
      adapter.parse(ref).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  # --- fetch (WebMock only) --------------------------------------------------------

  def test_fetch_downloads_the_ttl_and_discovers_both_shelves
    stub_request(:get, RAW_URL).to_return(status: 200, body: File.read(File.join(FIXTURES, "BrillEDL.ttl")))
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 2, adapter.discover(workdir).count
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, RAW_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_the_raw_file_once
    assert_equal :http_zip, Nabu::Adapters::Edl.remote_probe_strategy
    targets = Nabu::Adapters::Edl.http_probe_targets
    assert_equal [RAW_URL], targets.map(&:zip_url), "one file, one probe — not one per shelf"
    assert_nil targets.first.metadata_url
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup(ledger: nil)
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "edl", name: "de Vaan EDL", adapter_class: "Nabu::Adapters::Edl",
      license: "CC BY-NC-SA 4.0", license_class: "nc",
      upstream_url: RAW_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source, ledger: ledger)]
  end

  def test_loading_twice_is_idempotent_across_both_shelves
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 4, second.skipped
    assert_equal 2, db[:dictionaries].count, "two shelves under the one edl source"
    assert_equal "urn:nabu:dict:edl-ine-pro:pie1043",
                 db[:dictionary_entries].where(entry_id: "pie1043").get(:urn)
    assert_equal 3, db[:dictionary_reflexes].count
  end

  # --- language-notes rider ---------------------------------------------------------

  def test_load_accretes_the_stage_witness_notes_idempotently
    ledger = ledger_test_db
    _db, loader = loader_setup(ledger: ledger)
    loader.load_from(adapter, workdir: FIXTURES)
    rows = ledger[:language_notes].where(kind: "witness:edl").order(:id).all
    assert_equal %w[itc-pro lat], rows.map { |row| row[:lang_code] }.sort
    assert_equal ["edl"], rows.map { |row| row[:source] }.uniq
    assert_match(/Proto-Italic/, rows.find { |row| row[:lang_code] == "itc-pro" }[:body])
    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 2, ledger[:language_notes].where(kind: "witness:edl").count
  end

  # --- acceptance render: the full lat → PIt → PIE ascent ---------------------------

  def test_etym_walks_rodo_up_the_leiden_chain
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Etym.new(catalog: db).run("rodo")
    assert_equal 1, results.size
    pit = results.first
    assert_equal "edl-itc-pro", pit.dictionary_slug
    assert_equal "*(w)rōde/o‑", pit.headword
    assert_equal "rōdō", pit.matched_reflex.word
    assert_equal ["*Hreh₃d‑e/o‑"], pit.ancestors.map(&:headword),
                 "the PIE shelf names the PIt etymon — the shelf-visited ascent, zero new query code"
    assert_equal ["edl-ine-pro"], pit.ancestors.map(&:dictionary_slug)
  end

  # The P18-3-audited stance: a second itc-pro shelf naming the same Latin
  # lemma is TWO honest witnesses, never a dupe — etym lists both entries.
  def test_etym_lists_edl_beside_a_kaikki_style_itc_witness
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    kaikki = Nabu::Store::Source.create(
      slug: "wiktionary-recon", name: "kaikki", adapter_class: "Nabu::Adapters::WiktionaryRecon",
      license: "CC-BY-SA + GFDL", license_class: "attribution", enabled: true
    )
    shelf = Nabu::Store::Dictionary.create(
      source_id: kaikki.id, slug: "wiktionary-itc-pro",
      title: "Wiktionary — Proto-Italic (kaikki.org extract)", language: "itc-pro"
    )
    entry = Nabu::Store::DictionaryEntry.create(
      dictionary_id: shelf.id, urn: "urn:nabu:dict:wiktionary-itc-pro:rōdō:verb",
      entry_id: "rōdō:verb", key_raw: "rōdō", headword: "rōdō", headword_folded: "rodo",
      gloss: "to gnaw", body: "to gnaw", content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::DictionaryReflex.create(
      dictionary_entry_id: entry.id, seq: 0, lang_code: "la", language: "lat",
      word: "rōdō", word_folded: "rodo", borrowed: false
    )
    results = Nabu::Query::Etym.new(catalog: db).run("rodo")
    assert_equal %w[edl-itc-pro wiktionary-itc-pro], results.map(&:dictionary_slug).sort,
                 "provenance-distinct witnesses side by side"
  end

  # --- registry ---------------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["edl"]
    refute_nil entry, "config/sources.yml must register edl"
    assert_equal Nabu::Adapters::Edl, entry.adapter_class
    refute entry.enabled
    assert_equal "manual", entry.sync_policy
  end
end
