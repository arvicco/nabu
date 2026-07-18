# frozen_string_literal: true

require "test_helper"

# Nabu::Languages (P18-4, rehomed by P19-1): the merged read over the derived
# dossier records (catalog, migration 014), the derived name census (catalog,
# migration 011), and the TRANSITIONAL ledger notes (ledger migration 004 —
# the per-(code, kind) fallback until the owner-fired dossier export lands).
# Every handle is optional and every table guarded — the degradation cases
# are tested, not assumed.
class LanguagesTest < Minitest::Test
  include StoreTestDB

  def setup
    @catalog = store_test_db
    @ledger = ledger_test_db
  end

  def languages
    Nabu::Languages.new(catalog: @catalog, ledger: @ledger)
  end

  def dictionary(slug: "d1")
    source = Nabu::Store::Source.first(slug: "src") ||
             Nabu::Store::Source.create(slug: "src", name: "S", adapter_class: "X", license_class: "open")
    Nabu::Store::Dictionary.create(source_id: source.id, slug: slug, title: slug, language: "sla-pro")
  end

  def census!(dictionary_id, rows)
    rows.each do |(code, name, occurrences)|
      @catalog[:language_names].insert(dictionary_id: dictionary_id, lang_code: code,
                                       name: name, occurrences: occurrences)
    end
  end

  def note!(code, kind, body, source: "test")
    @ledger[:language_notes].insert(lang_code: code, kind: kind, body: body,
                                    source: source, created_at: Time.now)
  end

  def record!(code, kind, body, source: "dossier")
    @catalog[:language_records].insert(lang_code: code, kind: kind, body: body, source: source)
  end

  # -- the census read: filter, then mode over summed counts ------------------------

  # -- ISO 639-2 B/T code equivalence (owner report 2026-07-18: aes minted
  # German as "ger", tla-hf as "deu" — both legit 639-2, one language;
  # queries must accept either spelling, fold-both-sides style) ------------

  def test_code_variants_expands_the_bibliographic_terminological_pair
    assert_equal %w[deu ger], Nabu::Languages.code_variants("ger").sort
    assert_equal %w[deu ger], Nabu::Languages.code_variants("deu").sort
    assert_equal %w[fra fre], Nabu::Languages.code_variants("fre").sort
    assert_equal %w[cym wel], Nabu::Languages.code_variants("cym").sort
  end

  def test_code_variants_accepts_the_common_two_letter_spellings
    assert_equal %w[deu ger], Nabu::Languages.code_variants("de").sort
    assert_equal %w[fra fre], Nabu::Languages.code_variants("fr").sort
    assert_equal ["eng"], Nabu::Languages.code_variants("en")
  end

  def test_code_variants_passes_unknown_codes_through_untouched
    assert_equal ["egy"], Nabu::Languages.code_variants("egy")
    assert_equal ["xlp"], Nabu::Languages.code_variants("xlp")
    assert_equal [], Nabu::Languages.code_variants(nil)
  end

  def test_census_name_takes_the_mode_across_dictionaries
    one = dictionary(slug: "d1")
    two = dictionary(slug: "d2")
    census!(one.id, [["gkm", "Byzantine Greek", 3], ["gkm", "Medieval Greek", 2]])
    census!(two.id, [["gkm", "Medieval Greek", 4]])
    assert_equal "Medieval Greek", languages.name("gkm"), "3 vs 6 — summed across shelves"
  end

  def test_census_name_filters_script_wrappers_unknown_and_fragments
    d = dictionary
    census!(d.id, [["cu", "Old Cyrillic script", 1532], ["cu", "Glagolitic script", 1070],
                   ["cu", "Old Church Slavonic", 919], ["cu", "unknown", 8],
                   ["cu", "→ Baltic German", 20], ["cu", "(in compounds", 6]])
    assert_equal "Old Church Slavonic", languages.name("cu"),
                 "wrapper/placeholder/fragment names never win the mode"
  end

  def test_census_name_is_nil_when_only_implausible_names_exist
    d = dictionary
    census!(d.id, [["kdr", "Cyrillic script", 1], ["unk", "unknown", 12]])
    assert_nil languages.name("kdr")
    assert_nil languages.name("unk")
  end

  def test_plausible_name_rules
    refute Nabu::Languages.plausible_name?("unknown")
    refute Nabu::Languages.plausible_name?("Latin script")
    refute Nabu::Languages.plausible_name?("(Scots")
    refute Nabu::Languages.plausible_name?("")
    assert Nabu::Languages.plausible_name?("Old Ruthenian")
    assert Nabu::Languages.plausible_name?("Föhr-Amrum North Frisian")
  end

  # -- records (P19-1): the dossier index is the first read layer --------------------

  def test_dossier_record_beats_census_and_transitional_note
    d = dictionary
    census!(d.id, [["rue", "Carpathian Rusyn", 100]])
    note!("rue", "name", "Rusyn (ledger, pre-migration)")
    record!("rue", "name", "Rusyn")
    assert_equal "Rusyn", languages.name("rue"), "the dossier record wins"
    assert_equal "Rusyn (ledger, pre-migration)",
                 Nabu::Languages.new(catalog: old_catalog, ledger: @ledger).name("rue"),
                 "a catalog predating migration 014 still reads the transitional note"
  end

  def test_context_and_family_read_records_with_note_fallback_per_kind
    record!("gkm", "context", "Byzantine Greek, ca. 600–1453.")
    note!("gkm", "family", "Hellenic < Indo-European")
    assert_equal "Byzantine Greek, ca. 600–1453.", languages.context("gkm")
    assert_equal "Hellenic < Indo-European", languages.family("gkm"),
                 "a kind with no record falls back to the ledger note — per (code, kind), not per code"
    assert languages.curated?("gkm")
    refute languages.curated?("zzz")
  end

  def test_transitional_notes_answer_alone_and_latest_wins
    note!("rue", "name", "Rusyn (first)")
    note!("rue", "name", "Rusyn")
    assert_equal "Rusyn", languages.name("rue"), "the appended supersession wins in the fallback"
    assert languages.curated?("rue")
  end

  def test_family_fallback_reads_the_prefix_code_lanes
    record!("zle", "name", "East Slavic")
    note!("zle", "context", "The Rus' branch and its historical stages.")
    fallback = languages.family_fallback("zle-xyz")
    assert_equal "zle", fallback.code
    assert_equal "East Slavic", fallback.name
    assert_equal "The Rus' branch and its historical stages.", fallback.context
    assert_nil languages.family_fallback("zle"), "an unhyphenated code has no prefix"
    assert_nil languages.family_fallback("qq-x"), "an unknown prefix yields no hint — no guessing"
  end

  # P18-5: kinds beyond name/family/context (programmatic accretions and
  # dossier front-matter extras) surface as extra notes, records winning per
  # kind, shipped kinds excluded (they have their own readers).
  def test_extra_notes_merge_records_over_notes_per_kind
    note!("chu", "iecor", "IE-CoR variety: OCS (ledger, pre-migration)", source: "iecor")
    record!("chu", "iecor", "IE-CoR variety: OCS (dossier)", source: "iecor")
    record!("chu", "period", "9th–11th c.")
    note!("chu", "context", "Curated context stays out of the extras.")
    assert_equal({ "iecor" => "IE-CoR variety: OCS (dossier)", "period" => "9th–11th c." },
                 languages.extra_notes("chu"))
    assert_equal({}, languages.extra_notes("zzz"))
    assert_equal({}, Nabu::Languages.new.extra_notes("chu"), "degrades without handles")
  end

  def test_witnesses_merge_per_source_lane_and_never_shadow_context
    record!("itc-pro", "context", "Curated Proto-Italic prose.")
    record!("itc-pro", "witness:edl", "Leiden-school PIt stage (dossier).", source: "edl")
    note!("itc-pro", "witness:iecor", "Another source's lane (ledger).", source: "iecor")
    view = languages
    assert_equal "Curated Proto-Italic prose.", view.context("itc-pro")
    assert_equal({ "edl" => "Leiden-school PIt stage (dossier).",
                   "iecor" => "Another source's lane (ledger)." },
                 view.witnesses("itc-pro"))
    assert_empty view.witnesses("lat")
  end

  # -- degradation: missing handles/tables read as no data --------------------------

  def test_degrades_honestly_without_handles_or_tables
    bare = Nabu::Languages.new
    assert_nil bare.name("chu")
    assert_nil bare.context("chu")
    assert_nil bare.family_fallback("zle-ort")
    refute bare.curated?("chu")
    # a ledger predating ledger migration 004 (language_notes absent)
    old_ledger = Sequel.sqlite
    assert_nil Nabu::Languages.new(ledger: old_ledger).context("chu")
    # a catalog predating migration 014 (language_records absent)
    assert_nil Nabu::Languages.new(catalog: old_catalog).context("chu")
  end

  private

  # A catalog with neither the census nor the records table.
  def old_catalog
    Sequel.sqlite
  end
end
