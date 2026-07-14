# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Languages (P18-4): the merged read over the derived name census
# (catalog, migration 011) and the accumulated curated notes (ledger,
# ledger migration 004), plus the idempotent seed path from
# config/languages.yml. Every handle is optional and every table guarded —
# the degradation cases are tested, not assumed.
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

  # -- the census read: filter, then mode over summed counts ------------------------

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

  # -- notes: latest per (code, kind) wins; curated name beats the census -----------

  def test_curated_name_beats_the_census_and_latest_note_wins
    d = dictionary
    census!(d.id, [["rue", "Carpathian Rusyn", 100]])
    note!("rue", "name", "Rusyn (first)")
    note!("rue", "name", "Rusyn")
    assert_equal "Rusyn", languages.name("rue"), "the appended supersession wins"
    assert_equal "Carpathian Rusyn", Nabu::Languages.new(catalog: @catalog).name("rue"),
                 "no ledger — the census still answers"
  end

  def test_context_and_family_read_their_kinds
    note!("gkm", "context", "Byzantine Greek, ca. 600–1453.")
    note!("gkm", "family", "Hellenic < Indo-European")
    assert_equal "Byzantine Greek, ca. 600–1453.", languages.context("gkm")
    assert_equal "Hellenic < Indo-European", languages.family("gkm")
    assert languages.curated?("gkm")
    refute languages.curated?("zzz")
  end

  def test_family_fallback_reads_the_prefix_code_notes
    note!("zle", "name", "East Slavic")
    note!("zle", "context", "The Rus' branch and its historical stages.")
    fallback = languages.family_fallback("zle-xyz")
    assert_equal "zle", fallback.code
    assert_equal "East Slavic", fallback.name
    assert_equal "The Rus' branch and its historical stages.", fallback.context
    assert_nil languages.family_fallback("zle"), "an unhyphenated code has no prefix"
    assert_nil languages.family_fallback("qq-x"), "an unknown prefix yields no hint — no guessing"
  end

  # P18-5: kinds beyond name/family/context (the programmatic accretions —
  # "iecor" today) surface as extra notes, latest per kind, shipped kinds
  # excluded (they have their own readers).
  def test_extra_notes_surface_latest_per_kind_beyond_the_shipped_kinds
    note!("chu", "iecor", "IE-CoR variety: Old Church Slavonic (superseded)", source: "iecor")
    note!("chu", "iecor", "IE-CoR variety: Old Church Slavonic (latest)", source: "iecor")
    note!("chu", "context", "Curated context stays out of the extras.")
    assert_equal({ "iecor" => "IE-CoR variety: Old Church Slavonic (latest)" },
                 languages.extra_notes("chu"))
    assert_equal({}, languages.extra_notes("zzz"))
    assert_equal({}, Nabu::Languages.new.extra_notes("chu"), "degrades without a ledger")
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
  end

  # -- the seed path -----------------------------------------------------------------

  def seed_yaml(dir, body)
    path = File.join(dir, "languages.yml")
    File.write(path, body)
    path
  end

  def test_seed_is_idempotent_and_supersedes_by_append
    Dir.mktmpdir do |dir|
      path = seed_yaml(dir, <<~YAML)
        languages:
          gkm:
            name: Medieval Greek
            context: Byzantine Greek.
        families:
          zle:
            name: East Slavic
      YAML
      report = Nabu::Languages.seed!(ledger: @ledger, path: path)
      assert_equal 3, report.appended
      assert_equal 0, report.unchanged

      report = Nabu::Languages.seed!(ledger: @ledger, path: path)
      assert_equal 0, report.appended, "re-seeding an unchanged file writes nothing"
      assert_equal 3, report.unchanged
      assert_equal 3, @ledger[:language_notes].count

      path = seed_yaml(dir, <<~YAML)
        languages:
          gkm:
            name: Medieval Greek
            context: Byzantine Greek, ca. 600–1453.
        families:
          zle:
            name: East Slavic
      YAML
      report = Nabu::Languages.seed!(ledger: @ledger, path: path)
      assert_equal 1, report.appended, "only the changed body appends"
      assert_equal 2, report.unchanged
      assert_equal 4, @ledger[:language_notes].count, "supersession appends — nothing is updated or deleted"
      assert_equal "Byzantine Greek, ca. 600–1453.", languages.context("gkm")
      assert_equal Nabu::Languages::SEED_SOURCE,
                   @ledger[:language_notes].order(Sequel.desc(:id)).get(:source)
    end
  end

  def test_seed_refuses_a_code_in_both_sections
    Dir.mktmpdir do |dir|
      path = seed_yaml(dir, <<~YAML)
        languages:
          grc:
            name: Ancient Greek
        families:
          grc:
            name: Ancient Greek (dialects)
      YAML
      error = assert_raises(Nabu::Error) { Nabu::Languages.seed!(ledger: @ledger, path: path) }
      assert_match(%r{grc/name}, error.message)
      assert_equal 0, @ledger[:language_notes].count, "a refused seed writes nothing"
    end
  end

  # The SHIPPED seed file: parses, and covers the held languages and the
  # owner's pain codes (anchors only — prose may move).
  def test_shipped_seed_file_covers_held_languages_and_the_etymology_tail
    Nabu::Languages.seed!(ledger: @ledger)
    view = languages
    assert_equal "Old Church Slavonic", view.name("chu")
    assert_match(/OCS canon/, view.context("chu"))
    assert_match(/Grand Duchy of Lithuania/, view.context("zle-ort"), "the owner's pain code is curated")
    assert_match(/Novgorod/, view.context("zle-ono"))
    assert_equal "Medieval Greek", view.name("gkm")
    %w[sla-pro ine-pro gem-pro ine-bsl-pro gmw-pro itc-pro iir-pro].each do |shelf|
      assert view.context(shelf), "every reconstruction shelf carries a note (#{shelf})"
    end
    %w[zle zlw zls gmw gmq ine iir itc grk roa].each do |family|
      assert view.context(family), "family-level note missing for #{family}"
    end
    assert_equal "West Slavic", view.family_fallback("zlw-osk").name
  end

  # -- accretion + witnesses (P18-6: the loader/agent write path made real) ---------

  def test_accrete_appends_with_provenance_and_the_latest_body_rule
    notes = [["ine-pro", "witness:liv", "305 PIE verbal roots."]]
    assert_equal 1, Nabu::Languages.accrete!(ledger: @ledger, notes: notes, source: "liv")
    assert_equal 0, Nabu::Languages.accrete!(ledger: @ledger, notes: notes, source: "liv"),
                 "re-accreting an unchanged body writes nothing — the seed! rule"
    assert_equal 1, Nabu::Languages.accrete!(ledger: @ledger, source: "liv",
                                             notes: [["ine-pro", "witness:liv", "revised wording."]]),
                 "a changed body appends a superseding note"
    assert_equal 2, @ledger[:language_notes].count, "append-only — nothing updated or deleted"
    assert_equal %w[liv], @ledger[:language_notes].select_map(:source).uniq
  end

  def test_witness_lanes_never_shadow_the_seed_context_and_read_per_source
    note!("itc-pro", "context", "Curated Proto-Italic prose.", source: Nabu::Languages::SEED_SOURCE)
    Nabu::Languages.accrete!(ledger: @ledger, source: "edl",
                             notes: [["itc-pro", "witness:edl", "Leiden-school PIt stage."]])
    Nabu::Languages.accrete!(ledger: @ledger, source: "iecor",
                             notes: [["itc-pro", "witness:iecor", "Another source's lane."]])
    view = languages
    assert_equal "Curated Proto-Italic prose.", view.context("itc-pro"),
                 "source-laned kinds never supersede the curated context"
    assert_equal({ "edl" => "Leiden-school PIt stage.", "iecor" => "Another source's lane." },
                 view.witnesses("itc-pro"))
    assert_empty view.witnesses("lat")
  end

  def test_accrete_and_witnesses_degrade_on_a_ledger_predating_the_notes_table
    old_ledger = Sequel.sqlite
    assert_equal 0, Nabu::Languages.accrete!(ledger: old_ledger, source: "liv",
                                             notes: [["ine-pro", "witness:liv", "x"]])
    assert_empty Nabu::Languages.new(ledger: old_ledger).witnesses("ine-pro")
  end
end
