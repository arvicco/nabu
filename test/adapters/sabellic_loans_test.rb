# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The sabellic-loans adapter (P29-2 rider): the en.wiktionary-curated
# Sabellic → Latin loan shelves (the P17-3 `borrowed` pattern). Dictionary-
# shaped, so it mirrors the conformance checks the passage suite cannot
# cover (manifest validity, discover→parse round-trip, id uniqueness and
# stability, NFC, license class) and adds: the borrowed-flag semantics
# (explicit borrowing true, derived-only false), the etymon headwords with
# lemma fallback, the vendored-copy fetch round-trip, and the language-notes
# rider. The parsed data IS the shipped curation (config/sabellic_loans.yml).
class SabellicLoansTest < Minitest::Test
  CONFIG = File.expand_path("../../config/sabellic_loans.yml", __dir__)

  def adapter = Nabu::Adapters::SabellicLoans.new

  # A workdir holding the curated file, as fetch materializes it.
  def with_workdir
    Dir.mktmpdir do |dir|
      FileUtils.cp(CONFIG, File.join(dir, Nabu::Adapters::SabellicLoans::FILENAME))
      yield dir
    end
  end

  # --- manifest + content kind ------------------------------------------------

  def test_manifest_identifies_the_curation_and_its_grant
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "sabellic-loans", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA/, manifest.license)
    assert_match(/retrieved 2026-07-18/, manifest.license, "the curation date travels in the grant text")
    assert_equal "curated-yaml", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::SabellicLoans.content_kind
  end

  # --- discover → parse round-trip --------------------------------------------

  def test_discover_yields_one_ref_per_shelf_and_nothing_before_a_first_fetch
    with_workdir do |dir|
      refs = adapter.discover(dir).to_a
      assert_equal %w[sabellic-osc sabellic-xum sabellic-sbv],
                   refs.map { |ref| ref.metadata.fetch("dictionary") }.to_a
      assert(refs.all? { |ref| ref.source_id == "sabellic-loans" })
    end
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_mints_the_three_shelves_at_the_curated_counts
    with_workdir do |dir|
      documents = adapter.discover(dir).map { |ref| adapter.parse(ref) }
      assert_equal %w[osc xum sbv], documents.map(&:language)
      assert_equal [48, 11, 26], documents.map(&:count),
                   "the category census at retrieval: Oscan 48 · Umbrian 11 · Sabine 26"
    end
  end

  def test_borrowed_flag_reads_true_for_explicit_borrowings_false_for_derived_only
    with_workdir do |dir|
      osc = adapter.parse(adapter.discover(dir).first)
      rufus = osc.find { |entry| entry.entry_id == "rufus" }
      assert_equal "𐌓𐌖𐌚𐌓𐌉𐌉𐌔", rufus.headword, "the Old Italic etymon from the entry's own template"
      assert_equal ["lat"], rufus.reflexes.map(&:language)
      assert rufus.reflexes.first.borrowed, "category 'borrowed from Oscan' → borrowed true"
      assert_equal "rufus", rufus.reflexes.first.word

      mephitis = osc.find { |entry| entry.entry_id == "mephitis" }
      assert_equal "𐌌𐌄𐌚𐌉𐌞", mephitis.headword
      refute mephitis.reflexes.first.borrowed, "derived-only → borrowed false (the P17-3 no-marker semantics)"
    end
  end

  def test_an_etymon_less_lemma_falls_back_to_the_latin_headword
    with_workdir do |dir|
      osc = adapter.parse(adapter.discover(dir).first)
      tofus = osc.find { |entry| entry.entry_id == "tofus" }
      assert_equal "tofus", tofus.headword, "en.wiktionary names no Oscan form; the body says so"
      assert_match(/no .* form is cited/i, tofus.body)
      assert rufus_body = osc.find { |entry| entry.entry_id == "rufus" }.body
      assert_match(/retrieved 2026-07-18/, rufus_body, "provenance + date in every body")
    end
  end

  def test_entry_ids_are_unique_and_stable_across_independent_parses
    with_workdir do |dir|
      first = adapter.discover(dir).map { |ref| adapter.parse(ref).map(&:entry_id) }
      second = adapter.discover(dir).map { |ref| adapter.parse(ref).map(&:entry_id) }
      assert_equal first, second
      first.each { |ids| assert_equal ids.uniq, ids }
    end
  end

  def test_entries_are_nfc_with_folded_lookup_keys
    with_workdir do |dir|
      adapter.discover(dir).each do |ref|
        adapter.parse(ref).each do |entry|
          assert entry.headword.unicode_normalized?(:nfc)
          refute_empty entry.headword_folded
          entry.reflexes.each do |reflex|
            assert_equal Nabu::Normalize.search_form(reflex.word, language: "lat"), reflex.word_folded
          end
        end
      end
    end
  end

  # --- fetch (the vendored copy) ----------------------------------------------

  def test_fetch_materializes_the_curated_file_and_pins_it
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      target = File.join(dir, Nabu::Adapters::SabellicLoans::FILENAME)
      assert File.file?(target)
      assert_equal File.read(CONFIG), File.read(target), "byte-identical vendored copy"
      assert_equal ["local:#{Nabu::Adapters::SabellicLoans::FILENAME}"], report.repos.keys
      # Idempotent second pass.
      report = adapter.fetch(dir)
      assert_equal 3, adapter.discover(dir).count
      refute_nil report.sha
    end
  end

  # --- the language-notes rider ------------------------------------------------

  def test_language_notes_witness_the_three_sabellic_codes
    notes = Nabu::Adapters::SabellicLoans.language_notes
    assert_equal %w[osc xum sbv], notes.map(&:first)
    notes.each do |(_code, kind, body)|
      assert_equal "witness:sabellic-loans", kind
      assert_match(/en\.wiktionary/, body)
    end
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_is_disabled_local
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sabellic-loans"]
    refute_nil entry, "sabellic-loans must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::SabellicLoans, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync is eyeballed"
    assert_equal "local", entry.sync_policy, "no upstream, no network — the curation is the artifact"
  end
end
