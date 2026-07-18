# frozen_string_literal: true

require "test_helper"
require "digest"
require "tmpdir"

# LarthEtp adapter tests (P29-0): the ETP_POS.csv vocabulary (Larth repo,
# Wallace-project ETP lineage) as the second Etruscan dictionary row —
# flat-csv family, Python-tuple translation parsing with the honest
# uncertainty marks, grammatical-category bodies. Dictionary sources skip
# the passage conformance suite (the wiktionary-recon precedent); fixture
# rows are byte-verbatim upstream (test/fixtures/larth-etp/README.md).
class LarthEtpTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("larth-etp")

  def adapter
    Nabu::Adapters::LarthEtp.new
  end

  # --- manifest / capabilities ------------------------------------------------

  def test_manifest_pins_the_larth_repo_and_the_flat_csv_family
    manifest = Nabu::Adapters::LarthEtp.manifest
    assert_equal "larth-etp", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/Vico/, manifest.license, "the required attribution names the authors")
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::LarthEtp.content_kind
  end

  # --- discover / parse -------------------------------------------------------

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_equal "larth-etp:ETP_POS.csv", refs.first.id
    adapter.parse(refs.first)
  end

  def entries_by_id
    parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_parse_yields_one_entry_per_vocabulary_row
    document = parsed
    assert_equal "larth-etp", document.slug
    assert_equal "ett", document.language
    assert_equal 9, document.count
  end

  def test_certain_translation_becomes_the_gloss
    avil = entries_by_id.fetch("649")
    assert_equal "avil", avil.headword
    assert_equal "year", avil.gloss
    assert_match(/grammatical: nom acc/, avil.body)
    assert_match(/pos: NOUN/, avil.body)
  end

  def test_uncertain_translations_carry_the_honest_question_mark
    acil = entries_by_id.fetch("644")
    assert_equal "work", acil.gloss, "the certain translation wins the gloss"
    assert_match(/product \(\?\)/, acil.body, "the upstream False flag renders as (?)")
  end

  def test_homograph_rows_stay_separate_entries
    ids = entries_by_id
    assert_equal %w[acil acil], [ids.fetch("643").headword, ids.fetch("644").headword],
                 "the upstream row index is the entry key — homograph rows never merge"
  end

  def test_empty_translation_tuples_yield_a_nil_gloss_and_an_honest_body
    pi = entries_by_id.fetch("9")
    assert_nil pi.gloss
    assert_match(/grammatical: enclitic particle/, pi.body)
  end

  def test_suffix_inferred_and_abbreviation_flags_ride_the_body
    ids = entries_by_id
    assert_match(/suffix entry/, ids.fetch("0").body, "Is suffix rows say so")
    assert_match(/inferred/, ids.fetch("461").body, "Is inferred rows say so")
    assert_match(/abbreviation of aule/, ids.fetch("121").body)
    assert_equal "aule", ids.fetch("121").gloss
  end

  def test_headwords_fold_with_the_ett_search_form
    sla = entries_by_id.fetch("461")
    assert_equal "σ'la", sla.headword
    assert_equal Nabu::Normalize.search_form("σ'la", language: "ett"), sla.headword_folded
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_lands_the_csv_and_verifies_the_pin
    body = File.binread(File.join(FIXTURES, "ETP_POS.csv"))
    stub_request(:get, Nabu::Adapters::LarthEtp::CSV_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::LarthEtp.new(csv_sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, "ETP_POS.csv"))
      refute_nil report.sha
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    body = File.binread(File.join(FIXTURES, "ETP_POS.csv"))
    stub_request(:get, Nabu::Adapters::LarthEtp::CSV_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) do
        Nabu::Adapters::LarthEtp.new(csv_sha256: "0" * 64).fetch(dir)
      end
      assert_match(/re-pin/, error.message)
      refute File.exist?(File.join(dir, "ETP_POS.csv"))
    end
  end
end
