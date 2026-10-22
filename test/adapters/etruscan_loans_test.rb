# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The etruscan-loans adapter: the en.wiktionary-curated Etruscan → Latin
# loan shelf (the sabellic-loans recipe; the P17-3 `borrowed` pattern from
# a non-Indo-European donor). Dictionary-shaped, so it mirrors the
# conformance checks the passage suite cannot cover (manifest validity,
# discover→parse round-trip, id uniqueness and stability, NFC, license
# class) and adds the borrowed-flag semantics, the etymon headwords with
# the Latin fallback, the declared no-etymon residue, the vendored-copy
# fetch round-trip and the language-notes rider. The parsed data IS the
# shipped curation (config/etruscan_loans.yml); its reader is tested in
# test/wiktionary_loan_curation_test.rb.
class EtruscanLoansTest < Minitest::Test
  CONFIG = File.expand_path("../../config/etruscan_loans.yml", __dir__)

  def adapter = Nabu::Adapters::EtruscanLoans.new

  def with_workdir
    Dir.mktmpdir do |dir|
      FileUtils.cp(CONFIG, File.join(dir, Nabu::Adapters::EtruscanLoans::FILENAME))
      yield dir
    end
  end

  def shelf
    with_workdir { |dir| return adapter.parse(adapter.discover(dir).first) }
  end

  def entry(id) = shelf.find { |e| e.entry_id == id } || flunk("#{id} missing")

  # --- manifest + content kind -------------------------------------------------

  def test_manifest_identifies_the_curation_and_its_grant
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "etruscan-loans", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA/, manifest.license)
    assert_match(/retrieved 2026-10-22/, manifest.license, "the curation date travels in the grant text")
    assert_equal "curated-yaml", manifest.parser_family
  end

  def test_content_kind_is_dictionary_and_no_git_upstream
    assert_equal :dictionary, Nabu::Adapters::EtruscanLoans.content_kind
    assert_empty Nabu::Adapters::EtruscanLoans.upstream_repo_urls
  end

  # --- discover → parse ----------------------------------------------------------

  def test_discover_yields_one_ref_and_nothing_before_a_first_fetch
    with_workdir do |dir|
      refs = adapter.discover(dir).to_a
      assert_equal(["etruscan-ett"], refs.map { |ref| ref.metadata.fetch("dictionary") })
      assert_equal ["etruscan-loans"], refs.map(&:source_id)
    end
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_mints_the_curated_census
    doc = shelf
    assert_equal "ett", doc.language
    assert_equal 199, doc.count, "every Latin lemma of the derived superset (69 borrowed + 130 derived-only)"
    assert_equal(69, doc.count { |e| e.reflexes.first.borrowed })
    assert_equal 76, doc.count { |e| e.headword != e.entry_id }, "rows citing an Etruscan form head with it"
  end

  def test_borrowed_flag_reads_true_for_explicit_borrowings_false_for_derived_only
    roma = entry("Roma")
    assert_equal "𐌓𐌖𐌌𐌀", roma.headword
    assert_equal([%w[la lat]], roma.reflexes.map { |r| [r.lang_code, r.language] })
    assert roma.reflexes.first.borrowed
    persona = entry("persona")
    assert_equal "𐌘𐌄𐌓𐌔𐌖", persona.headword
    refute persona.reflexes.first.borrowed, "derived-only → borrowed false (the P17-3 no-marker semantics)"
  end

  def test_the_no_etymon_residue_falls_back_to_the_latin_headword_and_says_why
    as = entry("as")
    assert_equal "as", as.headword
    assert_match(/names Etruscan as the source but cites no Etruscan form/, as.body)
    titulo = entry("titulo")
    assert_equal "titulo", titulo.headword
    assert_match(/carries no Etruscan etymology template/, titulo.body)
    assert_match(/retrieved 2026-10-22/, entry("Roma").body, "provenance + date in every body")
  end

  def test_a_split_page_rows_under_its_lemma
    assert_equal "a", entry("a").entry_id
    assert_match(%r{a/languages A to L}, entry("a").body)
  end

  def test_entry_ids_are_unique_and_stable_across_independent_parses
    first = shelf.map(&:entry_id)
    assert_equal first.uniq, first
    assert_equal first, shelf.map(&:entry_id)
  end

  def test_entries_are_nfc_with_folded_lookup_keys
    shelf.each do |e|
      assert e.headword.unicode_normalized?(:nfc)
      refute_empty e.headword_folded
      e.reflexes.each do |reflex|
        assert_equal Nabu::Normalize.search_form(reflex.word, language: "lat"), reflex.word_folded
      end
    end
  end

  # --- fetch (the vendored copy) --------------------------------------------------

  def test_fetch_materializes_the_curated_file_and_pins_it
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      target = File.join(dir, Nabu::Adapters::EtruscanLoans::FILENAME)
      assert FileUtils.compare_file(CONFIG, target), "byte-identical vendored copy"
      assert_equal ["local:#{Nabu::Adapters::EtruscanLoans::FILENAME}"], report.repos.keys
      report = adapter.fetch(dir)
      assert_equal 1, adapter.discover(dir).count
      refute_nil report.sha
    end
  end

  # --- the language-notes rider ---------------------------------------------------

  def test_language_notes_witness_etruscan
    notes = Nabu::Adapters::EtruscanLoans.language_notes
    assert_equal ["ett"], notes.map(&:first)
    assert_equal "witness:etruscan-loans", notes.first[1]
    assert_match(/en\.wiktionary/, notes.first[2])
  end

  # --- registry -----------------------------------------------------------------

  def test_registry_row_is_unwired_frozen
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["etruscan-loans"]
    refute_nil entry
    assert_equal Nabu::Adapters::EtruscanLoans, entry.adapter_class
    assert entry.wired, "wired flipped at the first sync: 199 entries, 69 loan-flagged"
    assert_equal "frozen", entry.sync_policy, "the vendored curation IS the immutable artifact"
  end
end
