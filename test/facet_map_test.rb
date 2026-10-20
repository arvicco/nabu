# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::FacetMap (P104-1, under the aggressive-mining policy, 2026-09-26): the
# metadata-field → facet projection config — per-source declarations of
# which documents.metadata_json fields project into document_facets rows,
# so a source whose axis-shaped fields already ride the catalog gets its
# facets as a pure projection (no canonical re-parse). The kind_map
# discipline: config is the rule surface, validated at load.
class FacetMapTest < Minitest::Test
  def build(doc)
    Nabu::FacetMap.new(doc)
  end

  def test_loads_fields_per_source
    map = build("sources" => { "okhc" => { "fields" => { "corpus" => "collection" } } })
    assert_equal %w[okhc], map.sources
    assert_equal({ "corpus" => "collection" }, map.fields_for("okhc"))
  end

  def test_unruled_source_has_no_fields
    map = build("sources" => {})
    assert_nil map.fields_for("nope")
    assert_empty map.sources
  end

  def test_source_without_fields_is_a_config_error
    error = assert_raises(Nabu::FacetMap::ConfigError) { build("sources" => { "okhc" => {} }) }
    assert_match(/okhc/, error.message)
  end

  def test_blank_facet_name_is_a_config_error
    assert_raises(Nabu::FacetMap::ConfigError) do
      build("sources" => { "okhc" => { "fields" => { "corpus" => "" } } })
    end
  end

  # The passage grain: a source may declare passage_fields (passage
  # annotations_json keys → passage facet names) beside — or instead of —
  # its document fields. The two lanes read separately: #sources stays the
  # document-field lane FacetBuilder walks.
  def test_loads_passage_fields_beside_document_fields
    map = build("sources" => {
                  "sillok" => { "passage_fields" => { "subject_classes" => "subject" } },
                  "okhc" => { "fields" => { "corpus" => "collection" },
                              "passage_fields" => { "topics" => "topic" } }
                })
    assert_equal %w[okhc], map.sources
    assert_nil map.fields_for("sillok")
    assert_equal %w[sillok okhc], map.passage_sources
    assert_equal({ "subject_classes" => "subject" }, map.passage_fields_for("sillok"))
    assert_equal({ "topics" => "topic" }, map.passage_fields_for("okhc"))
    assert_nil map.passage_fields_for("nope")
  end

  def test_blank_passage_facet_name_is_a_config_error
    error = assert_raises(Nabu::FacetMap::ConfigError) do
      build("sources" => { "sillok" => { "passage_fields" => { "subject_classes" => " " } } })
    end
    assert_match(/sillok/, error.message)
  end

  def test_empty_passage_fields_is_a_config_error
    assert_raises(Nabu::FacetMap::ConfigError) do
      build("sources" => { "sillok" => { "passage_fields" => {} } })
    end
  end

  # The dictionary-entry grain: entry_fields name dictionary_entries
  # annotations keys → entry facet names, a third sibling lane on the same
  # per-source entry (a source may carry it alone).
  def test_loads_entry_fields_as_their_own_lane
    map = build("sources" => {
                  "edrdg" => { "entry_fields" => { "field" => "domain" } },
                  "okhc" => { "fields" => { "corpus" => "collection" } }
                })
    assert_equal %w[okhc], map.sources
    assert_empty map.passage_sources
    assert_equal %w[edrdg], map.entry_sources
    assert_equal({ "field" => "domain" }, map.entry_fields_for("edrdg"))
    assert_nil map.entry_fields_for("okhc")
  end

  def test_blank_or_empty_entry_fields_are_config_errors
    assert_raises(Nabu::FacetMap::ConfigError) do
      build("sources" => { "edrdg" => { "entry_fields" => { "field" => "" } } })
    end
    assert_raises(Nabu::FacetMap::ConfigError) { build("sources" => { "edrdg" => { "entry_fields" => {} } }) }
  end

  def test_shipped_config_rules_the_dictionary_entry_labels
    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    assert_equal({ "field" => "domain", "misc" => "usage", "dial" => "dialect",
                   "lsource" => "loan_source", "wasei" => "wasei_source" },
                 map.entry_fields_for("edrdg"))
    assert_equal({ "semantic_field" => "semantic_field", "semantic_category" => "word_class",
                   "borrowed" => "borrowed_status" },
                 map.entry_fields_for("wold"))
    assert_equal({ "concept" => "concept" }, map.entry_fields_for("tls"))
  end

  def test_shipped_config_projects_sillok_subjects_and_itkc_genres_at_passage_grain
    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    assert_equal "subject", map.passage_fields_for("sillok")["subject_classes"]
    assert_equal({ "genre_classes" => "genre" }, map.passage_fields_for("itkc"))
  end

  # The NIKH index markup: each source rules exactly the entity kinds its
  # deposit carries (NikhXmlParser::ENTITY_KINDS keys), one facet each.
  def test_shipped_config_rules_the_nikh_index_markup_per_source
    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    entity = ->(slug) { map.passage_fields_for(slug).except("subject_classes") }
    assert_equal({ "persons" => "person", "places" => "place", "books" => "book", "eras" => "era",
                   "offices" => "office" }, entity["sillok"])
    assert_equal({ "persons" => "person", "places" => "place", "books" => "book" }, entity["sjw"])
    family = { "persons" => "person", "offices" => "office", "places" => "place", "orgs" => "org", "books" => "book" }
    assert_equal family, entity["goryeosa"]
    assert_equal family, entity["goryeosa-jeoryo"]
    assert_equal({ "persons" => "person" }, entity["bibyeonsa"])
    kinds = Nabu::Adapters::NikhXmlParser::ENTITY_KINDS.values
    %w[sillok sjw goryeosa goryeosa-jeoryo bibyeonsa].each do |slug|
      assert_empty entity[slug].keys - kinds, "#{slug} rules only mined kinds"
    end
  end

  def test_load_default_reads_the_config_file_and_absent_file_is_nil
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, "config")
      FileUtils.mkdir_p(config_dir)
      config = Struct.new(:config_dir).new(config_dir)
      assert_nil Nabu::FacetMap.load_default(config: config)

      File.write(File.join(config_dir, "facet_map.yml"),
                 "sources:\n  seal:\n    fields:\n      genre: genre\n")
      map = Nabu::FacetMap.load_default(config: config)
      assert_equal({ "genre" => "genre" }, map.fields_for("seal"))
    end
  end

  # The shipped config/facet_map.yml must load and target only real
  # sources (the kind_map hygiene stance).
  # P105-5b: every local-library doc carries a multi-language
  # manifest but only the first code becomes documents.language — the
  # trailing claims (ett under eng facsimiles, xum…) must stay visible
  # through the facet lane.
  def test_shipped_config_projects_library_manifest_languages
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    assert_equal({ "languages" => "language" }, Nabu::FacetMap.load(path).fields_for("local-library"))
  end

  # UD: the README Genre tags at document grain; egyptian-pc's king and
  # genre and coptic-bohairic's author at sentence grain.
  def test_shipped_config_projects_the_ud_genre_line_and_sentence_comments
    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    assert_equal({ "genres" => "genre" }, map.fields_for("ud"))
    assert_equal({ "king" => "ruler", "genre" => "genre", "author" => "author" }, map.passage_fields_for("ud"))
  end

  # P118-R4 S2 (the held-but-dark audit's facet_map wave): axis-shaped
  # fields already stored verbatim on ~450k documents that fed no facet.
  def test_shipped_config_projects_the_dark_audit_facet_wave
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    map = Nabu::FacetMap.load(path)
    expected = {
      "cdli" => { "material" => "material", "object_type" => "object_type", "museum_no" => "museum",
                  "subgenre" => "subgenre", "excavation_no" => "excavation", "accession_no" => "accession" },
      "rundata" => { "material_type" => "material", "material" => "material",
                     "objectInfo" => "object_type", "style" => "style" },
      "glaux" => { "dialect" => "dialect", "author" => "author", "work" => "work" },
      "kdsp" => { "canonicity" => "canonicity", "period_slot" => "period", "author" => "author" },
      "ref" => { "medium" => "medium", "text-type" => "text_type", "genre" => "genre" },
      "rem" => { "topic" => "topic", "text_type" => "text_type" },
      "edr" => { "repository" => "museum" },
      "edh" => { "repository" => "museum" },
      "oncoj" => { "corpus" => "collection" }
    }
    expected.each { |slug, fields| assert_equal fields, map.fields_for(slug), slug }
  end

  # The mining-law sweep: DAMOS's per-item writing support (clay ×5,888,
  # ivory, stone) projects as the material facet — the cdli/rundata
  # facet name, never a kind.
  def test_shipped_config_projects_the_damos_material
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    assert_equal({ "material" => "material" }, Nabu::FacetMap.load(path).fields_for("damos"))
  end

  # ociana: the per-record script (the lect stage-flip key) and the
  # recording survey, both stored verbatim on every document.
  def test_shipped_config_projects_ociana_script_and_survey
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    assert_equal({ "script" => "script", "survey" => "collection" },
                 Nabu::FacetMap.load(path).fields_for("ociana"))
  end

  # The Arabic/Syriac crosswalk wave: OpenITI's TSV classification tags,
  # DiCCAS's tagged catastrophe vocabulary + mentioned places + book
  # authors, and the Syriac corpus's author and parent-work lanes — all
  # parse-time metadata the facet lane projects verbatim.
  def test_shipped_config_projects_the_arabic_and_syriac_crosswalk_fields
    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    assert_equal({ "genre_tags" => "genre_tag" }, map.fields_for("openiti"))
    assert_equal({ "disaster_types" => "disaster", "disaster_classes" => "disaster_class",
                   "places_mentioned" => "place_mentioned", "author" => "author" },
                 map.fields_for("diccas"))
    assert_equal({ "author" => "author", "author_ref" => "author_ref", "parent_works" => "work" },
                 map.fields_for("syriac-corpus"))
  end

  # oracc's catalogue extras: persons by role (ancient_author → the shared
  # author facet; ruler → the ruler facet CDLI already emits), the
  # context columns, and the letters' sending place.
  def test_shipped_config_projects_the_oracc_catalogue_persons_and_context
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    fields = Nabu::FacetMap.load(path).fields_for("oracc")
    expected = { "ruler" => "ruler", "ancient_author" => "author", "ancient_recipient" => "recipient",
                 "eponym" => "eponym", "dossier_list" => "dossier", "seal_owner" => "seal_owner",
                 "ancient_buyer" => "buyer", "ancient_seller" => "seller", "ancient_creditor" => "creditor",
                 "ancient_debtor" => "debtor", "subgenre" => "subgenre", "supergenre" => "supergenre",
                 "archive" => "archive", "dynastic_seat" => "dynastic_seat", "series" => "series",
                 "sender_loc" => "sender_place" }
    assert_equal expected, fields
  end

  # The author/work wave: sources whose adapters already store an author
  # (and sometimes a work title or an authority id) in metadata_json,
  # which surfaced in no facet — field names confirmed against the
  # adapters and the stored metadata. Ids project only where the value
  # names its own authority (GND/VIAF URLs, viaf:/wikidata: prefixes, the
  # Corpus Corporum work keys); bare source-local integers do not.
  def test_shipped_config_projects_the_author_work_wave
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    map = Nabu::FacetMap.load(path)
    expected = {
      "tamilex" => { "poet" => "author" },
      "madurai" => { "authors" => "author", "genres" => "genre" },
      "shabados" => { "authors" => "author" },
      "bu-ajami" => { "author_or_owner" => "author" },
      "africa-pd" => { "author" => "author" },
      "eebo-tcp" => { "author" => "author", "subjects" => "subject" },
      "dta" => { "author" => "author", "author_gnd" => "author_id" },
      "corpus-corporum" => { "author" => "author", "author_ref" => "author_id",
                             "series_idno" => "work_id" },
      "cantigas" => { "author" => "author" },
      "diorisis" => { "author" => "author", "work" => "work" },
      "sl-wikisource" => { "author" => "author" },
      "hr-wikisource" => { "author" => "author" },
      "sr-wikisource" => { "author" => "author" },
      "mk-wikisource" => { "author" => "author" },
      "bg-wikisource" => { "recension" => "recension", "author" => "author" },
      "imp" => { "author" => "author" },
      "croala" => { "author" => "author", "author_refs" => "author_id" },
      "digiliblt" => { "author" => "author", "work" => "work" },
      "bfm" => { "author" => "author" },
      "elektire" => { "author" => "author" },
      "eltec-srp" => { "author" => "author", "author_refs" => "author_id",
                       "title_refs" => "work_id" },
      "gretil" => { "author" => "author", "genre" => "genre" },
      "sarit" => { "author" => "author" },
      "pl-wikisource" => { "author" => "author", "work" => "work" },
      "cs-wikisource" => { "author" => "author", "work" => "work" },
      "uk-wikisource" => { "author" => "author", "work" => "work" },
      "ru-wikisource" => { "author" => "author", "work" => "work" },
      "menota" => { "work" => "work" },
      "perseus-greek" => { "author" => "author", "work" => "work", "cts_textgroup" => "author_id",
                           "cts_work" => "work_id" },
      "perseus-latin" => { "author" => "author", "work" => "work", "cts_textgroup" => "author_id",
                           "cts_work" => "work_id" },
      "first1k-greek" => { "author" => "author", "work" => "work", "cts_textgroup" => "author_id",
                           "cts_work" => "work_id" }
    }
    expected.each { |slug, fields| assert_equal fields, map.fields_for(slug), slug }
  end

  # The CJK persons tail: person/place/series fields the CJK adapters
  # now mine at parse time (bylines, header slots, catalog joins).
  def test_shipped_config_projects_the_cjk_persons_tail
    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    expected = {
      "cbeta" => { "byline_authors" => "author" },
      "ja-wikisource" => { "author" => "author" },
      "itkc" => { "author" => "author", "subject_class" => "subject", "sabu_class" => "classification" },
      "honkoku" => { "ndl_catalog.author_names" => "author", "ndl_catalog.subjects" => "subject" },
      "obi-burmese" => { "subject" => "subject" },
      "korba" => { "translator" => "translator" },
      "dharma-javanese-texts" => { "author" => "author" }
    }
    expected.each { |slug, fields| assert_equal fields, map.fields_for(slug), slug }
  end

  def test_shipped_config_loads
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    map = Nabu::FacetMap.load(path)
    refute_nil map
    slugs = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")).keys
    (map.sources + map.passage_sources).each do |slug|
      assert_includes slugs, slug, "facet_map.yml names #{slug}, which is not a registered source"
    end
  end
end
