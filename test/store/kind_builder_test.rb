# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::KindBuilder (P99-2 — №R-63): the derived pass that
  # projects the kind axis into document_facets — reads each ruled
  # source's mapped facet rows (or applies its source_kind declaration),
  # normalizes through Nabu::Kinds, writes facet="kind" rows
  # (value = class path, raw = the upstream value verbatim). Fully
  # derivable by construction: drop-and-reproject, like FacetBuilder.
  class KindBuilderTest < Minitest::Test
    include StoreTestDB

    CLASSES = <<~YAML
      classes:
        funerary: {desc: "d", subs: [epitaph]}
        legal: {desc: "d"}
        historiography: {desc: "d", subs: [annals]}
        unknown: {desc: "d"}
    YAML

    MAP = <<~YAML
      split: ["|"]
      strip: ["?"]
      sources:
        edr:
          facet: genre
          map:
            "sepulcralis": funerary/epitaph
            "ignoratur": unknown
        okhc:
          source_kind: historiography/annals
        sefaria:
          metadata: categories
          map:
            "Talmud": legal
        dta:
          metadata: [subgenre, genre]
          map:
            "Drama": funerary
            "Wissenschaft": legal
        papyri-ddbdp:
          walk: hgv-keywords
          map:
            "Quittung": legal
    YAML

    def setup
      @db = store_test_db
      @kinds = Dir.mktmpdir do |dir|
        File.write(File.join(dir, "c.yml"), CLASSES)
        File.write(File.join(dir, "m.yml"), MAP)
        break Nabu::Kinds.load(classes_path: File.join(dir, "c.yml"),
                               map_path: File.join(dir, "m.yml"))
      end
      seed
    end

    def seed
      @edr = Nabu::Store::Source.create(slug: "edr", name: "EDR", adapter_class: "X",
                                        license_class: "open")
      @okhc = Nabu::Store::Source.create(slug: "okhc", name: "OKHC", adapter_class: "X",
                                         license_class: "open")
      @d1 = doc(@edr, "urn:nabu:edr:1")
      @d2 = doc(@edr, "urn:nabu:edr:2")
      @d3 = doc(@okhc, "urn:nabu:okhc:1")
      @withdrawn = doc(@okhc, "urn:nabu:okhc:gone", withdrawn: true)
      facet(@d1, "genre", "sepulcralis")
      facet(@d1, "genre", "cetera")           # unmapped
      facet(@d2, "genre", "ignoratur")
      facet(@d2, "material", "Marmor")        # a different facet — never read
    end

    def doc(source, urn, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, language: "la", title: "t",
        canonical_path: urn, content_sha256: Digest::SHA256.hexdigest(urn),
        withdrawn: withdrawn
      )
    end

    def facet(document, name, value)
      @db[:document_facets].insert(document_id: document.id, facet: name, value: value)
    end

    def kind_rows
      @db[:document_facets].where(facet: "kind").order(:document_id, :value)
                           .select_map(%i[document_id value raw])
    end

    def rebuild!
      Nabu::Store::KindBuilder.rebuild!(catalog: @db, kinds: @kinds)
    end

    def test_rebuild_projects_mapped_facets_with_raw_provenance
      summary = rebuild!
      assert_includes kind_rows, [@d1.id, "funerary/epitaph", "sepulcralis"]
      assert_includes kind_rows, [@d1.id, "unmapped", "cetera"],
                      "an unmapped value emits the honest bucket, raw preserved"
      assert_includes kind_rows, [@d2.id, "unknown", "ignoratur"]
      refute(kind_rows.any? { |row| row[2] == "Marmor" }, "other facets are never read")
      assert_equal 3, summary.documents
      assert_operator summary.rows, :>=, 4
    end

    def test_source_kind_declaration_covers_every_live_document
      rebuild!
      assert_includes kind_rows, [@d3.id, "historiography/annals", nil]
      refute(kind_rows.any? { |row| row[0] == @withdrawn.id },
             "withdrawn documents contribute no kind rows")
    end

    def test_rebuild_is_idempotent
      rebuild!
      first = kind_rows
      summary = rebuild!
      assert_equal first, kind_rows, "drop-and-reproject: same input, same rows"
      assert_equal 3, summary.documents
    end

    def test_refresh_source_touches_only_that_source
      rebuild!
      @db[:document_facets].where(document_id: @d1.id, facet: "genre",
                                  value: "cetera").delete
      Nabu::Store::KindBuilder.refresh_source!(catalog: @db, kinds: @kinds, slug: "edr")
      refute_includes kind_rows, [@d1.id, "unmapped", "cetera"], "edr re-projected"
      assert_includes kind_rows, [@d3.id, "historiography/annals", nil],
                      "okhc rows survive an edr refresh"
    end

    def test_refresh_of_an_unruled_source_is_a_clean_zero
      rebuild!
      assert_equal 0, Nabu::Store::KindBuilder.refresh_source!(
        catalog: @db, kinds: @kinds, slug: "perseus"
      )
    end

    # P99-3: the precompiled census (migration 032) — per (source, head)
    # distinct docs + a NULL-head per-source total, written in the same
    # projection pass so the census never groups the millions.
    def test_stats_precompile_per_source_head_with_null_total
      rebuild!
      stats = @db[:kind_stats].order(:source_id, :head).select_map(%i[source_id head documents])
      assert_includes stats, [@edr.id, "funerary", 1]
      assert_includes stats, [@edr.id, "unknown", 1]
      assert_includes stats, [@edr.id, "unmapped", 1]
      assert_includes stats, [@edr.id, nil, 2], "the NULL-head row is edr's distinct-doc total"
      assert_includes stats, [@okhc.id, "historiography", 1]
      assert_includes stats, [@okhc.id, nil, 1]
    end

    def test_refresh_source_replaces_only_that_sources_stats
      rebuild!
      Nabu::Store::KindBuilder.refresh_source!(catalog: @db, kinds: @kinds, slug: "edr")
      assert_equal 1, @db[:kind_stats].where(source_id: @okhc.id, head: "historiography").count,
                   "okhc stats survive an edr refresh"
      assert_equal 1, @db[:kind_stats].where(source_id: @edr.id, head: nil).count,
                   "edr's total row re-minted once, not duplicated"
    end

    def test_nil_kinds_is_the_lane_off_posture
      summary = Nabu::Store::KindBuilder.rebuild!(catalog: @db, kinds: nil)
      assert_equal 0, summary.rows
      assert_empty kind_rows
    end

    # P100-3: the hgv-keywords walker reads the HGV sidecar files from
    # the canonical tree (the TimelineBuilder precedent) — the LEADING
    # keywords term is the text type, joined ddb-hybrid → urn; without
    # canonical_dir the walk skips honestly to zero rows.
    def test_hgv_keywords_walk_projects_the_leading_term
      papyri = Nabu::Store::Source.create(slug: "papyri-ddbdp", name: "P", adapter_class: "X",
                                          license_class: "open")
      receipt = doc(papyri, "urn:nabu:ddbdp:p.ryl:2:249")     # fixture 134.xml, "Quittung"
      copy = doc(papyri, "urn:nabu:ddbdp:p.adl::G2")          # fixture 1.xml, "Kopie" — unmapped
      Nabu::Store::KindBuilder.rebuild!(catalog: @db, kinds: @kinds,
                                        canonical_dir: Nabu::TestSupport.fixtures("timeline"))
      assert_includes kind_rows, [receipt.id, "legal", "Quittung"]
      assert_includes kind_rows, [copy.id, "unmapped", "Kopie"],
                      "an unmapped leading term keeps the honest bucket"
      refute(kind_rows.any? { |row| row[2] == "Geld" }, "subject tails never emit")
    end

    def test_walk_without_canonical_dir_skips_honestly
      papyri = Nabu::Store::Source.create(slug: "papyri-ddbdp", name: "P", adapter_class: "X",
                                          license_class: "open")
      doc(papyri, "urn:nabu:ddbdp:p.ryl:2:249")
      Nabu::Store::KindBuilder.rebuild!(catalog: @db, kinds: @kinds)
      refute(kind_rows.any? { |row| row[1] == "legal" && row[2] == "Quittung" },
             "no canonical_dir → the walk contributes nothing, never an error")
    end

    # P100-1: metadata rules read documents.metadata_json directly —
    # declared fields extracted per document, an ARRAY value takes its
    # FIRST element (category paths are hierarchies, not multi-labels),
    # several declared fields each map independently, raw preserved.
    def test_metadata_rules_project_from_metadata_json
      sefaria = Nabu::Store::Source.create(slug: "sefaria", name: "S", adapter_class: "X",
                                           license_class: "open")
      dta = Nabu::Store::Source.create(slug: "dta", name: "D", adapter_class: "X",
                                       license_class: "open")
      talmud = doc(sefaria, "urn:s:1")
      talmud.update(metadata_json: '{"categories":["Talmud","Bavli"],"title":"x"}')
      bare = doc(sefaria, "urn:s:2")
      bare.update(metadata_json: '{"title":"no categories"}')
      play = doc(dta, "urn:d:1")
      play.update(metadata_json: '{"genre":"Wissenschaft","subgenre":"Drama"}')

      rebuild!
      assert_includes kind_rows, [talmud.id, "legal", "Talmud"],
                      "the array's FIRST element is the claim; 'Bavli' never emits"
      refute(kind_rows.any? { |row| row[0] == bare.id },
             "a document without the declared field contributes nothing — not unmapped")
      assert_includes kind_rows, [play.id, "funerary", "Drama"]
      assert_includes kind_rows, [play.id, "legal", "Wissenschaft"],
                      "each declared metadata field maps independently"
    end
  end
end
