# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# LexiconItant adapter tests: DigItAnt's Lexicon ItAnt — the OntoLex-Lemon
# lexicon of the languages of ancient Italy (CC BY-NC-SA → class nc).
# Dictionary-shaped, so it mirrors the passage conformance checks for the
# dictionary shape (manifest, discover→parse round-trip, id uniqueness and
# stability, NFC, license class — the CalfaLexiconTest mold) and adds the
# DictionaryLoader contract, the grain census (the auxiliary lexicons and
# the standalone SKOS file skipped by rule) and source-specific pins.
#
# The fixture is a block trim of the real lexicon_1_0.ttl: four of the
# sixteen accepted lexicons (osc 5 entries, umc 1, xfa 2, xve 1) beside
# the rejected lat/grc/PIE/PIT lexicon nodes and their cited words.
class LexiconItantTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("lexicon-itant")
  MEDDISS = "urn:nabu:dict:itant-lexicon-osc:meddíss_noun_osc_entry"

  def adapter = Nabu::Adapters::LexiconItant.new

  # --- manifest + content kind ----------------------------------------------

  def test_manifest_records_the_nc_grant_verbatim
    manifest = adapter.manifest
    assert_equal "lexicon-itant", manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_includes manifest.license, "Lexicon_ItAnt  is licensed under CC-BY-NC-SA"
    assert_equal "https://github.com/DigItAnt/Lexicon_ItAnt", manifest.upstream_url
    assert_equal "lila-ttl", manifest.parser_family
    assert_equal :dictionary, Nabu::Adapters::LexiconItant.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_one_ref_per_accepted_lexicon_in_table_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[itant-lexicon-osc:lexicon_1_0.ttl itant-lexicon-umc:lexicon_1_0.ttl
                    itant-lexicon-xfa:lexicon_1_0.ttl itant-lexicon-xve:lexicon_1_0.ttl], refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "lexicon-itant" })
    assert_equal(%w[osc umc xfa xve], refs.map { |ref| ref.metadata.fetch("language") })
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_dictionary_per_language
    documents = parsed
    assert_equal %w[itant-lexicon-osc itant-lexicon-umc itant-lexicon-xfa itant-lexicon-xve], documents.map(&:slug)
    assert_equal %w[osc umc xfa xve], documents.map(&:language)
    assert_equal [5, 1, 2, 1], documents.map(&:size)
    assert_equal "Lexicon ItAnt — Venetic (DigItAnt)", documents.last.title
  end

  def test_entry_ids_are_unique_per_dictionary_and_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(FIXTURES).flat_map do |ref|
        adapter.parse(ref).map { |entry| [ref.metadata.fetch("dictionary"), entry.entry_id] }
      end
    end
    first = snapshot.call
    assert_equal first.uniq.sort, first.sort
    assert_equal first, snapshot.call
  end

  def test_content_is_stable_across_independent_parses
    hashes = lambda do
      Nabu::Adapters::LexiconItant.new.then do |fresh|
        fresh.discover(FIXTURES).flat_map do |ref|
          fresh.parse(ref).map { |entry| Nabu::Store::ContentHash.dictionary_entry(entry) }
        end
      end
    end
    assert_equal hashes.call, hashes.call
  end

  def test_entry_output_is_nfc
    entries.each do |entry|
      [entry.headword, entry.body, entry.headword_folded, entry.entry_id].each do |text|
        assert text.unicode_normalized?(:nfc), entry.entry_id
      end
    end
  end

  # --- the entry shape ------------------------------------------------------

  def test_meddiss_carries_gloss_forms_etymology_cognates_and_references
    entry = entry("meddíss_noun_osc_entry")
    assert_equal "meddíss", entry.headword
    assert_equal "meddiss", entry.headword_folded
    assert_equal "magistrate", entry.gloss
    body = entry.body
    assert_match(/\Anoun · stem cons\.\n1\. magistrate\n/, body)
    assert_includes body, "form μεδδειξ — nominativeCase masculine plural"
    assert_includes body, "form m(eddís) — nominativeCase masculine singular — hasAttestation: ItAnt_Oscan_20"
    assert_includes body, "etymology: inheritance from PIE *med-es"
    assert_includes body, "cognates: umc medix\n", "the trim keeps one of the four cognates (ims/pgn/xvo dangle)"
    assert_equal 1, body.scan("Untermann J., Wörterbuch des Oskisch-Umbrischen (2000)").size,
                 "two bibliography nodes citing one book render once"
    assert_equal({ "pos" => "noun", "semantic_field" => ["Social Relations"] }, entry.annotations)
  end

  def test_etymology_links_mint_typed_reflexes_with_registry_languages
    reflexes = entry("meddíss_noun_osc_entry").reflexes
    assert_equal([%w[PIE ine-pro *med-es inherited], %w[PIE ine-pro *dik- inherited],
                  %w[umc umc medix cognate]],
                 reflexes.map { |r| [r.lang_code, r.language, r.word, r.relation] })
    assert_equal "med-es", reflexes.first.word_folded, "the asterisk drops from the fold"
    assert_equal([%w[PIT itc-pro inherited]],
                 entry("deívaí_noun_osc_entry").reflexes.first(1).map { |r| [r.lang_code, r.language, r.relation] })
  end

  def test_borrowings_flag_the_donor_word_from_the_rejected_lexicons
    senate = entry("senateís_noun_osc_entry").reflexes
    rows = senate.map { |r| [r.language, r.word, r.relation, r.borrowed] }
    assert_equal [["lat", "senātus", "borrowed", true]], rows
    apolo = entry("LexO_2023-04-2713_34_08_678")
    assert_equal "apolo", apolo.headword
    assert_equal([["grc", "Ἀπόλλων", true]], apolo.reflexes.map { |r| [r.language, r.word, r.borrowed] })
    assert_includes apolo.body, "etymology: borrowing from grc Ἀπόλλων"
  end

  def test_editorial_marks_stay_in_the_headword_and_leave_the_fold
    entry = entry("seemuneís_properNoun_osc_entry")
    assert_equal "seemuṇẹị́[s".unicode_normalize(:nfc), entry.headword
    assert_equal "seemuneis", entry.headword_folded
  end

  def test_html_notes_and_character_references_read_as_text
    body = entry("deívaí_noun_osc_entry").body
    assert_includes body, "comment: deívaí genetaí hasAttestation: ItAnt_Oscan_1 A, l. 15"
    refute_match(/&#\d+;|<div>/, body)
    mego = entry("LexO_2023-08-0413_33_51_854")
    refute_match(/&#\d+;/, mego.body)
    assert_equal "me", mego.gloss
    cognates = mego.reflexes.select { |r| r.relation == "cognate" }
    assert_equal([%w[xfa med cognate]], cognates.map { |r| [r.lang_code, r.word, r.relation] })
  end

  # --- the grain census -------------------------------------------------------

  def test_auxiliary_lexicons_and_the_skos_file_skip_by_rule_with_notes
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 5, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(/semanticFields_Buck_ItAnt_skos\.ttl: the standalone Buck semantic-field scheme/, notes)
    %w[lat grc PIE PIT].each { |language| assert_match(/lexicon #{language} \(\d+ members\)/, notes) }
    refute(adapter.discover(FIXTURES).any? { |ref| ref.id.start_with?("itant-lexicon-lat") })
  end

  def test_an_unknown_file_or_lexicon_language_is_unrecognized_never_silent
    Dir.mktmpdir do |work|
      FileUtils.cp(Dir[File.join(FIXTURES, "*.ttl")], work)
      File.write(File.join(work, "extra.ttl"), "")
      text = File.read(File.join(work, "lexicon_1_0.ttl"))
      File.write(File.join(work, "lexicon_1_0.ttl"),
                 text.sub("lime:language \"xve\"", "lime:language \"xyz\""))
      skips = adapter.discovery_skips(work)
      assert_equal 2, skips.unrecognized
      assert_match(/extra\.ttl: not a recognized/, skips.notes.join("\n"))
      assert_match(/lexicon xyz \(85 members\): not a recognized language/, skips.notes.join("\n"))
    end
  end

  def test_an_older_lexicon_version_is_superseded_by_rule
    Dir.mktmpdir do |work|
      FileUtils.cp(Dir[File.join(FIXTURES, "*.ttl")], work)
      FileUtils.cp(File.join(work, "lexicon_1_0.ttl"), File.join(work, "lexicon_1_1.ttl"))
      assert(adapter.discover(work).all? { |ref| ref.path.end_with?("lexicon_1_1.ttl") })
      assert_match(/lexicon_1_0\.ttl: superseded by lexicon_1_1\.ttl/, adapter.discovery_skips(work).notes.join("\n"))
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------

  def test_loads_idempotently_and_define_finds_the_headword
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "lexicon-itant", name: "Lexicon ItAnt",
                                        adapter_class: "Nabu::Adapters::LexiconItant", license_class: "nc")
    first = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, first.errored
    assert_equal 9, db[:dictionary_entries].count
    second = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 9, db[:dictionary_entries].count, "a byte-identical reload upserts, never duplicates"
    assert_includes db[:dictionary_entries].select_map(:urn), MEDDISS
    hits = Nabu::Query::Define.new(catalog: db, lila: nil, form_lemma: nil, verb_lemma: nil, lects: nil)
                              .run("meddiss", limit: nil).map(&:urn)
    assert_includes hits, MEDDISS
  ensure
    db&.disconnect
  end

  # --- registry + fetch -------------------------------------------------------

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["lexicon-itant"]
    refute_nil entry, "config/sources.yml must register lexicon-itant"
    assert_equal Nabu::Adapters::LexiconItant, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
  end

  def test_fetch_clones_the_repo_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-lexicon-itant-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp(Dir[File.join(FIXTURES, "*.ttl")], upstream)
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      lexicon = adapter
      lexicon.define_singleton_method(:repo_url) { upstream }
      report = lexicon.fetch(File.join(root, "canonical"))
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal 4, lexicon.discover(File.join(root, "canonical")).count
    end
  end

  private

  def parsed
    lexicon = adapter
    lexicon.discover(FIXTURES).map { |ref| lexicon.parse(ref) }
  end

  def entries = parsed.flat_map(&:entries)

  def entry(id)
    entries.find { |candidate| candidate.entry_id == id.unicode_normalize(:nfc) } or flunk "no entry #{id}"
  end
end
