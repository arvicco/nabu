# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::PassageFacetBuilder: the passage-grain facet lane —
  # config/facet_map.yml passage_fields projected from the loaded
  # passages' annotations_json into the dictionary-encoded
  # passage_facet_values / passage_facets pair. Values verbatim, arrays
  # one row per element, {"value", "ref"} objects carry their authority
  # ref, absence mints nothing; wholesale per source, idempotent,
  # withdrawn passages and documents excluded.
  class PassageFacetBuilderTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @sillok = make_source("sillok")
      @itkc = make_source("itkc")
      @sequence = 0
    end

    def make_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T", license_class: "attribution")
    end

    def make_document(source, urn, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: "lzh",
        content_sha256: urn, revision: 1, withdrawn: withdrawn
      )
    end

    # Brace-less string-keyed annotations arrive through **fields.
    def make_passage(document, annotations = nil, withdrawn: false, **fields)
      annotations ||= fields
      @sequence += 1
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "#{document.urn}:#{@sequence}", sequence: @sequence,
        language: "lzh", text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
        withdrawn: withdrawn, annotations_json: JSON.generate(annotations)
      )
    end

    MAP = Nabu::FacetMap.new("sources" => {
                               "sillok" => { "passage_fields" => { "subject_classes" => "subject" } },
                               "itkc" => { "passage_fields" => { "genre_classes" => "genre" } }
                             })

    # The live stored shape (catalog read 2026-10-18): an array of
    # verbatim upper-lower labels on the article passage.
    def test_projects_array_labels_one_pair_per_label
      doc = make_document(@sillok, "urn:nabu:sillok:wza_100")
      passage = make_passage(doc, "title" => "철종 대왕이 승하하다",
                                  "subject_classes" => ["왕실-의식(儀式)", "왕실-국왕(國王)", "인물(人物)"])
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      assert_equal 1, summary.passages
      assert_equal 3, summary.rows
      assert_equal 3, summary.values
      rows = pairs_for(passage.id)
      assert_equal([["subject", "왕실-국왕(國王)", nil], ["subject", "왕실-의식(儀式)", nil],
                    ["subject", "인물(人物)", nil]], rows)
    end

    def test_values_are_a_shared_per_source_dictionary
      doc = make_document(@sillok, "urn:nabu:sillok:wza_101")
      make_passage(doc, "subject_classes" => ["인물(人物)", "왕실-의식(儀式)"])
      make_passage(doc, "subject_classes" => ["인물(人物)"])
      itkc_doc = make_document(@itkc, "urn:nabu:itkc:gp-0001")
      make_passage(itkc_doc, "genre_classes" => %w[雜著類 其他類])
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      assert_equal 3, summary.passages
      assert_equal 5, summary.rows
      assert_equal 4, summary.values, "the repeated label folds to one dictionary row"
      assert_equal 2, @db[:passage_facet_values].where(source_id: @sillok.id).count
      assert_equal 2, @db[:passage_facet_values].where(source_id: @itkc.id, facet: "genre").count
    end

    # The entity shape the follow-on emitters use: {"value", "ref"}
    # objects — a name and its authority ref; a scalar string projects too.
    def test_entity_objects_carry_their_ref_and_scalars_project
      map = Nabu::FacetMap.new("sources" => {
                                 "sillok" => { "passage_fields" => { "persons" => "person", "place" => "place" } }
                               })
      doc = make_document(@sillok, "urn:nabu:sillok:wza_102")
      passage = make_passage(doc, "persons" => [{ "value" => "李昰應", "ref" => "kh:PER_0001" },
                                                { "value" => "趙大妃" }],
                                  "place" => "漢城")
      Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: map)

      assert_equal([["person", "李昰應", "kh:PER_0001"], ["person", "趙大妃", nil], ["place", "漢城", nil]],
                   pairs_for(passage.id))
    end

    def test_skips_absent_blank_duplicate_and_malformed_values
      doc = make_document(@sillok, "urn:nabu:sillok:wza_103")
      bare = make_passage(doc, "title" => "no subjects")
      messy = make_passage(doc, "subject_classes" => ["인물(人物)", "인물(人物)", "", " ", nil, 7, { "ref" => "x" }])
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      assert_empty pairs_for(bare.id)
      assert_equal [["subject", "7", nil], ["subject", "인물(人物)", nil]], pairs_for(messy.id),
                   "numbers stringify; a ref-only object has no value and mints nothing"
      assert_equal 2, summary.rows
    end

    def test_withdrawn_passages_and_documents_are_excluded
      live = make_document(@sillok, "urn:nabu:sillok:wza_104")
      make_passage(live, { "subject_classes" => ["인물(人物)"] }, withdrawn: true)
      gone = make_document(@sillok, "urn:nabu:sillok:wza_105", withdrawn: true)
      make_passage(gone, "subject_classes" => ["인물(人物)"])
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      assert_equal 0, summary.rows
      assert_equal 0, @db[:passage_facet_values].count, "no value without a live pair"
    end

    def test_unruled_sources_and_fields_contribute_nothing
      other = make_source("sjw")
      make_passage(make_document(other, "urn:nabu:sjw:1"), "subject_classes" => ["인물(人物)"])
      make_passage(make_document(@sillok, "urn:nabu:sillok:wza_106"), "weather" => ["雨"])
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      assert_equal 0, summary.rows
    end

    def test_nil_facet_map_is_lane_off_and_clears_the_tables
      make_passage(make_document(@sillok, "urn:nabu:sillok:wza_107"), "subject_classes" => ["인물(人物)"])
      Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: nil)
      assert_equal 0, summary.rows
      assert_equal 0, @db[:passage_facets].count
      assert_equal 0, @db[:passage_facet_values].count
    end

    def test_rebuild_is_idempotent
      doc = make_document(@sillok, "urn:nabu:sillok:wza_108")
      make_passage(doc, "subject_classes" => ["인물(人物)", "왕실-의식(儀式)"])
      Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      before = [@db[:passage_facets].count, @db[:passage_facet_values].count]
      Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)
      assert_equal before, [@db[:passage_facets].count, @db[:passage_facet_values].count]
    end

    # The per-source seam: one source's slice drops and re-projects; the
    # other source's rows are untouched; a source ruled OUT of the config
    # drops its slice on refresh.
    def test_refresh_source_is_wholesale_per_source
      sillok_doc = make_document(@sillok, "urn:nabu:sillok:wza_109")
      make_passage(sillok_doc, "subject_classes" => ["인물(人物)"])
      make_passage(make_document(@itkc, "urn:nabu:itkc:gp-0002"), "genre_classes" => ["詩類"])
      Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: MAP)

      make_passage(sillok_doc, "subject_classes" => ["왕실-의식(儀式)"])
      rows = Nabu::Store::PassageFacetBuilder.refresh_source!(catalog: @db, slug: "sillok", facet_map: MAP)
      assert_equal 2, rows
      assert_equal 3, @db[:passage_facets].count
      assert_equal 2, @db[:passage_facet_values].where(source_id: @sillok.id).count
      assert_equal 1, @db[:passage_facet_values].where(source_id: @itkc.id).count, "itkc untouched"

      rows = Nabu::Store::PassageFacetBuilder.refresh_source!(
        catalog: @db, slug: "sillok", facet_map: Nabu::FacetMap.new("sources" => {})
      )
      assert_equal 0, rows
      assert_equal 0, @db[:passage_facet_values].where(source_id: @sillok.id).count
      assert_equal 1, @db[:passage_facets].count
    end

    def test_refresh_of_an_unknown_source_is_a_no_op
      assert_equal 0, Nabu::Store::PassageFacetBuilder.refresh_source!(catalog: @db, slug: "nope", facet_map: MAP)
    end

    # Fixture-verified: the real sillok + itkc samples, loaded through
    # their adapters, project every stored label under the shipped config.
    def test_shipped_config_projects_the_real_sillok_and_itkc_fixtures
      { "sillok" => [Nabu::Adapters::Sillok, @sillok], "itkc" => [Nabu::Adapters::Itkc, @itkc] }
        .each do |slug, (klass, source)|
        Nabu::Store::Loader.new(db: @db, source: source)
                           .load_from(klass.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
      map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
      summary = Nabu::Store::PassageFacetBuilder.rebuild!(catalog: @db, facet_map: map)

      expected = { "sillok" => "subject_classes", "itkc" => "genre_classes" }.sum do |slug, field|
        stored_labels(slug, field).size
      end
      assert_equal expected, summary.rows
      assert_equal [13, 24, 10], [summary.passages, summary.rows, summary.values],
                   "the fixture census: 13 labelled article passages, 24 pairs, 5 + 5 labels"
      assert_equal %w[genre subject], @db[:passage_facet_values].distinct.select_map(:facet).sort
    end

    private

    def stored_labels(slug, field)
      source_id = @db[:sources].where(slug: slug).get(:id)
      @db[:passages].join(:documents, id: :document_id)
                    .where(Sequel[:documents][:source_id] => source_id)
                    .select_map(Sequel[:passages][:annotations_json])
                    .flat_map { |json| Array(JSON.parse(json)[field]).uniq }
    end

    def pairs_for(passage_id)
      @db[:passage_facets].join(:passage_facet_values, id: :value_id)
                          .where(passage_id: passage_id)
                          .select_map(%i[facet value ref]).sort_by { |row| row.map(&:to_s) }
    end
  end
end
