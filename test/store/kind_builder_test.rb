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
  end
end
