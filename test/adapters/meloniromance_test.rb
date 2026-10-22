# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# meloniromance: the lexibank CLDF edition of Meloni, Ravfogel & Goldberg
# (2021)'s Romance cognate sets — Latin etyma with their Romanian, French,
# Italian, Spanish and Portuguese reflexes, all in broad IPA. Brought in
# through the IE-CoR seam: one dictionary shelf, one entry per cognate set,
# member forms as DictionaryReflex rows (so define/etym/the reflex-roots
# closure read it with no new query code). Dictionary-shaped, so it mirrors
# the conformance checks by hand (the iecor/sabellic-loans precedent).
# Fixture: three real sets (1 — all six varieties; 75 — the non-NFC
# Portuguese specimen; 358 — the two-member minimum) + the rejected
# raw/data.tsv grain's specimen; see test/fixtures/meloniromance/README.md.
class MeloniromanceTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("meloniromance")

  def adapter = Nabu::Adapters::Meloniromance.new

  def document = adapter.parse(adapter.discover(FIXTURES).first)

  def entry(id) = document.find { |e| e.entry_id == id } || flunk("set #{id} missing")

  # --- manifest + kind -------------------------------------------------------------

  def test_manifest_records_the_cc_by_grant_and_the_citation
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "meloniromance", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/Meloni, Ravfogel & Goldberg 2021/, manifest.license)
    assert_equal "cldf-csv", manifest.parser_family
    assert_equal "https://github.com/lexibank/meloniromance", manifest.upstream_url
  end

  def test_a_reflex_bearing_dictionary_source
    assert_equal :dictionary, Nabu::Adapters::Meloniromance.content_kind
    assert Nabu::Adapters::Meloniromance.reflex_bearing?
  end

  # --- discover ----------------------------------------------------------------------

  def test_discover_yields_one_ref_for_the_cldf_wordlist
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["meloniromance:cldf"], refs.map(&:id)
    assert_equal ["meloniromance"], refs.map(&:source_id)
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_the_raw_table_grain_is_skipped_by_rule_never_dropped
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal ["pre-CLDF raw table (the same sets, unconverted), not ingested: raw/data.tsv"], skips.notes
  end

  # --- parse ---------------------------------------------------------------------------

  def test_one_latin_headed_entry_per_cognate_set
    doc = document
    assert_kind_of Nabu::DictionaryDocument, doc
    assert_equal "meloniromance", doc.slug
    assert_equal "lat", doc.language
    assert_equal %w[1 75 358], doc.map(&:entry_id)
    assert_equal ["-aːbɪlɛm", "abɪʊŋɡɛrɛ", "albeːskɛrɛ"], doc.map(&:headword)
  end

  def test_romance_members_become_reflex_rows_in_upstream_order
    set = entry("1")
    assert_equal %w[ron fra ita spa por], set.reflexes.map(&:lang_code)
    assert_equal %w[ron fra ita spa por], set.reflexes.map(&:language)
    assert_equal %w[Romanian French Italian Spanish Portuguese], set.reflexes.map(&:lang_name)
    assert_equal ["-abil", "-abl", "-abile", "-aβle", "-avɛl"], set.reflexes.map(&:word)
    assert(set.reflexes.none?(&:borrowed), "upstream's Loan column is empty: inherited, never a loan flag")
    assert(set.reflexes.all? { |r| r.relation.nil? }, "descendant rows state no typed relation (the IE-CoR rule)")
  end

  def test_the_two_member_minimum_keeps_its_single_reflex
    assert_equal([%w[ron albʲ]], entry("358").reflexes.map { |r| [r.language, r.word] })
  end

  def test_non_nfc_upstream_forms_normalize_at_the_boundary
    word = entry("75").reflexes.first.word
    assert_equal "ɐbʒũŋʒiɹ", word, "u + U+0303 composes to ũ"
    assert word.unicode_normalized?(:nfc)
  end

  def test_folds_are_the_house_search_forms
    set = entry("1")
    assert_equal Nabu::Normalize.search_form("-aːbɪlɛm", language: "lat"), set.headword_folded
    set.reflexes.each do |reflex|
      assert_equal Nabu::Normalize.search_form(reflex.word, language: reflex.language), reflex.word_folded
    end
  end

  def test_the_body_states_the_set_the_transcription_and_the_members
    body = entry("1").body
    assert_match(/Meloni et al\. 2021 Romance cognate set 1/, body)
    assert_match(/broad IPA/, body)
    assert_includes body, "Latin -aːbɪlɛm"
    assert_includes body, "Spanish -aβle"
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    first = document.map(&:entry_id)
    assert_equal first.uniq, first
    assert_equal first, document.map(&:entry_id)
  end

  def test_a_set_without_its_latin_form_is_a_parse_error_not_a_guess
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "cldf"), dir)
      %w[forms.csv cognates.csv].each do |table|
        path = File.join(dir, "cldf", table)
        File.write(path, File.readlines(path).reject { |line| line.start_with?("Latin-concept_358") }.join)
      end
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/set 358.*no Latin form/, error.message)
    end
  end

  # --- loader round-trip -----------------------------------------------------------------

  def test_loads_through_the_dictionary_loader_idempotently
    Dir.mktmpdir do |canonical_root|
      db = store_test_db
      source = Nabu::Store::Source.create(
        slug: "meloniromance", name: "meloniromance", adapter_class: "Nabu::Adapters::Meloniromance",
        license: "CC BY 4.0", license_class: "attribution",
        upstream_url: "https://github.com/lexibank/meloniromance", enabled: false
      )
      loader = Nabu::Store::DictionaryLoader.new(
        db: db, source: source, ledger: ledger_test_db,
        language_shelf_dir: File.join(canonical_root, Nabu::LanguageShelf::SLUG)
      )
      report = loader.load_from(adapter, workdir: FIXTURES)
      assert_equal 3, report.added
      assert_equal 0, report.errored
      row = db[:dictionary_entries].where(entry_id: "1").first
      assert_equal "urn:nabu:dict:meloniromance:1", row[:urn]
      assert_equal 7, db[:dictionary_reflexes].count, "5 + 1 + 1 Romance members"
      second = loader.load_from(adapter, workdir: FIXTURES)
      assert_equal 0, second.added + second.updated + second.withdrawn
      assert_equal 7, db[:dictionary_reflexes].count
    end
  end

  # --- fetch -------------------------------------------------------------------------------

  def test_fetch_is_the_sanctioned_git_fetch_of_the_repository
    captured = nil
    subject = adapter
    subject.define_singleton_method(:git_fetch!) { |**kw| captured = kw }
    subject.fetch("/tmp/nowhere")
    assert_equal "https://github.com/lexibank/meloniromance", captured[:repo_url]
  end

  # --- registry ---------------------------------------------------------------------------

  def test_registry_row_is_unwired_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["meloniromance"]
    refute_nil entry, "meloniromance must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Meloniromance, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
  end
end
