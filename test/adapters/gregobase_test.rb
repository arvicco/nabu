# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Gregobase — GregoBase, the community-transcribed
  # Gregorian repertory, from its own MySQL export. The fixture is the REAL
  # dump trimmed line-verbatim (test/fixtures/gregobase/README.md): six
  # accepted chants covering every record shape (plain GABC, the
  # element-array form with TeX interleaved, a GABC verses block, a TeX
  # verses block, an inline GABC header, NABC neumes, a non-Latin version)
  # and one pinned specimen per REJECTED row grain — upstream-flagged
  # copyrighted (8093, its melody redacted), a retired duplicate (7774), a
  # withdrawn row (16117) and a row with no GABC (18651).
  class GregobaseTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("gregobase")
    ADAPTER = Nabu::Adapters::Gregobase
    DUMP = "gregobase_online.sql"

    def conformance_adapter = ADAPTER.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "gregobase"

    # -- registry -------------------------------------------------------------

    def test_registry_row_exists_wired_with_manual_sync_policy
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["gregobase"]
      refute_nil entry, "config/sources.yml must register gregobase"
      assert_equal ADAPTER, entry.adapter_class
      assert entry.wired,
             "wired after the verified first sync of 2026-11-04 " \
             "(18,422 docs / 20,810 passages, exactly the dump census)"
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_is_cc0_open
      assert_equal "gregobase", ADAPTER.manifest.id
      assert_equal "open", ADAPTER.manifest.license_class
      assert_includes ADAPTER.manifest.license, "CC0"
      assert_equal "https://github.com/gregorio-project/GregoBase", ADAPTER.manifest.upstream_url
    end

    # -- discover + the rejected row grains ------------------------------------

    def test_discover_yields_the_six_accepted_chants_in_id_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[507 8761 13466 14738 17418 18115].map { |id| "urn:nabu:gregobase:#{id}" }, refs.map(&:id)
      refs.each { |ref| assert ref.path.end_with?(DUMP) }
      assert_equal "Factus est adiutor", refs.find { |r| r.id.end_with?(":14738") }.metadata["title"]
    end

    def test_the_rejected_row_grains_are_counted_by_rule_never_dropped_silently
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 4, skips.skipped_by_rule, "8093 copyrighted, 7774 duplicate, 16117 withdrawn, 18651 no GABC"
      assert_equal 0, skips.unrecognized
      assert_predicate skips, :clean?
      notes = skips.notes.join("\n")
      assert_match(/1 upstream-flagged copyrighted/, notes)
      assert_match(/1 retired duplicate/, notes)
      assert_match(/1 withdrawn/, notes)
      assert_match(/1 without GABC/, notes)
    end

    def test_the_copyright_flag_wins_whatever_the_row_carries
      # The specimen's melody is redacted in the fixture; the rule reads
      # upstream's flag, never the content: clear the flag and it is accepted.
      with_doctored_dump(from: "NULL, NULL, NULL, 1, NULL);", to: "NULL, NULL, NULL, 0, NULL);") do |dir|
        assert_includes conformance_adapter.discover(dir).map(&:id), "urn:nabu:gregobase:8093"
        assert_equal 3, conformance_adapter.discovery_skips(dir).skipped_by_rule
      end
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_dump
      Dir.mktmpdir do |dir|
        assert_empty conformance_adapter.discover(dir).to_a
        assert_equal 0, conformance_adapter.discovery_skips(dir).skipped_by_rule
      end
    end

    # -- parse: the text layer and its passages ---------------------------------

    def test_a_plain_gabc_chant_is_one_passage_of_sung_text
      document = parse_urn("urn:nabu:gregobase:14738")
      assert_equal "lat", document.language
      assert_equal "Factus est adiutor", document.title
      assert_equal 1, document.size
      passage = document.first
      assert_equal "urn:nabu:gregobase:14738:1", passage.urn
      assert_equal "FActus est * adiútor meus Deus meus.", passage.text
      assert_equal "gabc", passage.annotations["layer"]
      assert_includes passage.annotations["gabc"], "FA(f|vi)ctus(ghg|tohh)",
                      "the raw GABC (NABC and all) rides beside the text"
    end

    def test_the_element_array_numbers_scores_like_upstream_and_drops_layout_tex
      document = parse_urn("urn:nabu:gregobase:507")
      assert_equal %w[1 2], document.map { |p| p.urn.split(":").last },
                   "two GABC elements (upstream's Element 1/2); the layout TeX and the \\greannotation drop"
      assert_equal "ALlelúia.", document.first.text
      assert_equal "COnfitémini Dómino, quóniam bonus : quóniam in saéculum misericórdia * ejus.",
                   document.to_a.last.text
      assert_equal 2, document.to_a.last.annotations["element"]
    end

    def test_a_gabc_verses_block_becomes_verse_passages
      document = parse_urn("urn:nabu:gregobase:17418")
      assert_equal(%w[1 verses-1], document.map { |p| p.urn.split(":").last })
      assert_equal "María castis ósculis Lambit Dei vestígia, Fletu rigat, tergit comis, Detérsa nardo pérlinit.",
                   document.first.text
      verses = document.to_a.last
      assert_equal "2. Deo Patri sit glória, Ejusque soli Fílio, Cum Spíritu Paráclito, " \
                   "Nunc, et per omne sǽculum. Amen.", verses.text
      assert_equal "gabc_verses", verses.annotations["layer"]
      assert_includes verses.annotations["gabc"], "De(g)o(hi) Pa(ih)tri(j)"
    end

    def test_a_tex_verses_block_becomes_tex_passages
      document = parse_urn("urn:nabu:gregobase:8761")
      assert_equal(%w[1 tex-verses-1], document.map { |p| p.urn.split(":").last })
      assert_equal "Sancte Joánnes Baptísta, ora pro nobis.", document.first.text
      tex = document.to_a.last
      assert_equal "Sancte Joseph, ora pro nobis.", tex.text
      assert_equal "tex_verses", tex.annotations["layer"]
      assert_equal "Sancte \\textbf{Jo}seph, o\\textit{ra pro} \\textbf{no}bis.", tex.annotations["tex"]
    end

    def test_an_inline_gabc_header_is_mined_and_kept_out_of_the_text
      document = parse_urn("urn:nabu:gregobase:18115")
      assert_equal({ "initial-style" => "1" }, document.metadata["gabc_header"])
      assert document.first.text.start_with?("MIrábile mystérium declarátur hódie:")
      assert document.first.text.end_with?("neque divisiónem. E u o u a e.")
      assert_equal ["Sollemnitas S. Dei Genetricis"], document.metadata["tags"]
    end

    def test_language_follows_upstreams_version_field
      document = parse_urn("urn:nabu:gregobase:13466")
      assert_equal "eng", document.language, "Palmer & Burgess = the English plainchant gradual"
      assert_equal "eng", document.first.language
      assert_equal "ALleluya. * ij. ℣. Verily thou art a King that hidest thyself, O God of Israel, * the Saviour.",
                   document.first.text
    end

    def test_a_notation_only_chant_is_skipped_by_rule
      # A score with no syllable text (a bare tone or melisma) has nothing to
      # read: skipped by rule at parse, never quarantined.
      score = "FA(f|vi)ctus(ghg|tohh) est(h|vihh) *()\\\\r\\\\nad(f|tahg)i\\\\u00fa(g|vihg)tor(f|vihg) " \
              "me(f|vi)us(ef|peShg) De(g|vihi)us(fe|clhh) me(d|ta)us.(d|ta) (::)"
      with_doctored_dump(from: score, to: "(f|vi)(ghg|tohh) (::)") do |dir|
        ref = conformance_adapter.discover(dir).find { |r| r.id == "urn:nabu:gregobase:14738" }
        error = assert_raises(Nabu::DocumentSkipped) { conformance_adapter.parse(ref) }
        assert_match(/no sung text/, error.reason)
      end
    end

    # -- parse: metadata (the mined axes) ----------------------------------------

    def test_metadata_carries_the_record_fields_under_stable_keys
      meta = parse_urn("urn:nabu:gregobase:14738").metadata
      assert_equal "002846", meta["cantus_id"], "the cross-shelf chant-identity key"
      assert_equal 14_738, meta["gregobase_id"]
      assert_equal "https://gregobase.selapa.net/chant.php?id=14738", meta["url"]
      assert_equal "an", meta["office_part"]
      assert_equal "Antiphona", meta["office_part_label"]
      assert_equal "1", meta["mode"]
      assert_equal "g", meta["mode_var"]
      assert_equal "Solesmes", meta["version"]
      assert_equal "Jakub Jelínek", meta["transcriber"]
      assert_equal "Cf. Ps. 62, 8", meta["commentary"]
    end

    def test_sources_resolve_to_their_books_with_page_and_year
      sources = parse_urn("urn:nabu:gregobase:14738").metadata["sources"]
      assert_equal(["Antiphonale monasticum I", "Cod. Sang. 390: Antiphonarium officii (winter volume)"],
                   sources.map { |s| s["title"] })
      hartker = sources.last
      assert_equal({ "title" => "Cod. Sang. 390: Antiphonarium officii (winter volume)", "editor" => "Hartker",
                     "year" => 990, "period" => "around 990-1000", "page" => "151",
                     "description" => "St. Gallen, Stiftsbibliothek", "source_id" => 59 }, hartker)
    end

    def test_a_manuscript_witness_dates_the_chant_by_the_codex
      date = parse_urn("urn:nabu:gregobase:14738").metadata["date"]
      assert_equal 990, date["not_before"]
      assert_equal 1000, date["not_after"]
      assert_nil date["class"], "a witness date is the artifact's own, not an edition's"
      assert_includes date["raw"], "around 990-1000"
    end

    def test_printed_sources_date_the_chant_as_an_edition
      date = parse_urn("urn:nabu:gregobase:507").metadata["date"]
      assert_equal({ "not_before" => 1961, "not_after" => 1961, "class" => "edition",
                     "raw" => "Graduale Romanum (1961); The Liber Usualis (1961)" }, date)
    end

    def test_an_unresolvable_source_keeps_its_id_and_claims_no_date
      with_doctored_dump(from: "(13466, 50, '54', 0, 1);", to: "(13466, 999, '54', 0, 1);") do |dir|
        ref = conformance_adapter.discover(dir).find { |r| r.id == "urn:nabu:gregobase:13466" }
        meta = conformance_adapter.parse(ref).metadata
        assert_nil meta["date"]
        assert_equal [{ "page" => "54", "source_id" => 999 }], meta["sources"]
      end
    end

    def test_the_cantus_id_sentinel_zero_is_dropped
      with_doctored_dump(from: "(14738, '002846',", to: "(14738, '0',") do |dir|
        ref = conformance_adapter.discover(dir).find { |r| r.id == "urn:nabu:gregobase:14738" }
        refute conformance_adapter.parse(ref).metadata.key?("cantus_id")
      end
    end

    # -- the kind axis (shipped config) -------------------------------------------

    def test_every_office_part_folds_through_the_shipped_kind_map
      kinds = Nabu::Kinds.load(
        classes_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_classes.yml"),
        map_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_map.yml")
      )
      assert_equal ["office_part"], kinds.metadata_for("gregobase")
      ADAPTER::OFFICE_PARTS.each_key do |code|
        paths = kinds.normalize("gregobase", code)
        refute_empty paths, "#{code} must fold"
        refute_includes paths, Nabu::Kinds::UNMAPPED, code
      end
      assert_equal ["hymn-prayer/hymn"], kinds.normalize("gregobase", "hy")
      assert_equal ["ritual/liturgy"], kinds.normalize("gregobase", "an")
    end

    # -- load: idempotency -----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "gregobase", name: "GregoBase",
                                          adapter_class: ADAPTER.name, license_class: "open")
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 6, first.added
      assert_equal 0, first.errored
      counts = [catalog[:documents].count, catalog[:passages].count]
      assert_equal [6, 9], counts
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    # -- fetch (local upstream; no network) ---------------------------------------------

    def test_fetch_clones_the_upstream_repo_holding_the_dump
      Dir.mktmpdir do |dir|
        upstream = File.join(dir, "upstream")
        FileUtils.mkdir_p(upstream)
        FileUtils.cp(File.join(FIXTURES, DUMP), upstream)
        Nabu::Shell.run("git", "-C", upstream, "init", "--quiet", "--initial-branch=master")
        Nabu::Shell.run("git", "-C", upstream, "add", ".")
        Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@e.st", "-c", "user.name=t",
                        "commit", "--quiet", "-m", "dump")
        sha = Nabu::Shell.run("git", "-C", upstream, "rev-parse", "HEAD").strip
        workdir = File.join(dir, "work")
        report = ADAPTER.new(repo_url: upstream).fetch(workdir)
        assert_equal sha, report.sha
        assert_equal 6, ADAPTER.new.discover(workdir).count
      end
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    # The real fixture with ONE surgical replacement (real bytes, one
    # deliberate variant).
    def with_doctored_dump(from:, to:)
      Dir.mktmpdir do |dir|
        dump = File.read(File.join(FIXTURES, DUMP))
        assert_includes dump, from, "the doctoring anchor must exist in the fixture"
        File.write(File.join(dir, DUMP), dump.sub(from, to))
        yield dir
      end
    end
  end
end
