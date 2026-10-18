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

  # P118-R4 S2 (the held-but-dark audit's facet_map wave): axis-shaped
  # fields already stored verbatim on ~450k documents that fed no facet.
  def test_shipped_config_projects_the_dark_audit_facet_wave
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    map = Nabu::FacetMap.load(path)
    expected = {
      "cdli" => { "material" => "material", "object_type" => "object_type", "museum_no" => "museum",
                  "subgenre" => "subgenre" },
      "rundata" => { "material_type" => "material", "material" => "material",
                     "objectInfo" => "object_type", "style" => "style" },
      "glaux" => { "dialect" => "dialect", "author" => "author", "work" => "work" },
      "kdsp" => { "canonicity" => "canonicity", "period_slot" => "period", "author" => "author" },
      "ref" => { "medium" => "medium", "text-type" => "text_type" },
      "rem" => { "topic" => "topic", "text_type" => "text_type" },
      "edr" => { "repository" => "museum" },
      "edh" => { "repository" => "museum" },
      "oncoj" => { "corpus" => "collection" }
    }
    expected.each { |slug, fields| assert_equal fields, map.fields_for(slug), slug }
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
      "eebo-tcp" => { "author" => "author" },
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
      "croala" => { "author" => "author" },
      "digiliblt" => { "author" => "author", "work" => "work" },
      "bfm" => { "author" => "author" },
      "elektire" => { "author" => "author" },
      "eltec-srp" => { "author" => "author", "author_refs" => "author_id",
                       "title_refs" => "work_id" },
      "gretil" => { "author" => "author", "genre" => "genre" },
      "sarit" => { "author" => "author" }
    }
    expected.each { |slug, fields| assert_equal fields, map.fields_for(slug), slug }
  end

  def test_shipped_config_loads
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    map = Nabu::FacetMap.load(path)
    refute_nil map
    slugs = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")).keys
    map.sources.each do |slug|
      assert_includes slugs, slug, "facet_map.yml names #{slug}, which is not a registered source"
    end
  end
end
