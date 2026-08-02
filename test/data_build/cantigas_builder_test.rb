# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The roa-opt/cantigas builder (P56-2) — the thirteenth nabu-data feature and
# the first FULL-CORPUS re-publication: the complete Cantigas Medievais
# Galego-Portuguesas (Littera edition, cantigas.fcsh.unl.pt) projected from
# the catalog into four tables — lines.csv (verse grain, urn+sha anchored),
# cantigas.csv (the cantiga registry), authors.csv (the distinct troubadour
# registry) and manuscripts.csv (the corpus-wide cancioneiro concordance
# parsed from the edition's sigla lines) — under the №45-2 written grant,
# the project's own citation format riding every file.
#
# The catalog side is SYNTHETIC BY CONVENTION (the actib-anchors precedent),
# constructed with real-shaped rows: metadata/annotation shapes and the
# manuscript sigla come verbatim from the 2026-08-02 live-catalog census
# (29 witness shapes over 4,341 tokens — "B 575/576", "(C 12)", "B 1146 bis",
# "V 29=38", bare "P", two-letter "TO 30" are all real census members).
class DataBuildCantigasBuilderTest < Minitest::Test
  include StoreTestDB

  LINES_COLUMNS = %w[ID URN Passage_SHA256 Cantiga_ID Line Stanza Number_Gap Primary_Text].freeze
  CANTIGAS_COLUMNS = %w[ID Cdcant URN Incipit Author_ID Genre Form Rubric].freeze
  AUTHORS_COLUMNS = %w[ID Name Cdaut].freeze
  MANUSCRIPTS_COLUMNS = %w[ID Cantiga_ID Cancioneiro Number Parenthesized].freeze

  URN_PREFIX = "urn:nabu:cantigas:"

  # -- rig -------------------------------------------------------------------

  def sources_yml
    <<~YAML
      cantigas:
        adapter: Nabu::Adapters::Cantigas
        wired: true
        sync_policy: manual
    YAML
  end

  def with_build_env
    Dir.mktmpdir("nabu-cantigas-data") do |root|
      canonical = File.join(root, "canonical")
      cone = File.join(canonical, "cantigas")
      FileUtils.mkdir_p(cone)
      FileUtils.cp(File.join(Nabu::TestSupport::FIXTURES_ROOT, "cantigas", "cantiga-600.html"), cone)
      sources = File.join(root, "sources.yml")
      File.write(sources, sources_yml)
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = store_test_db
      seed_catalog!(canonical)
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog, canonical
    end
  end

  # Four real-shaped documents. cdcant values chosen so NUMERIC order (97,
  # 600, 1000, 1241) differs from string order ("1000" < "1241" < "600" <
  # "97") — the ordering discipline is load-bearing.
  def seed_catalog!(canonical)
    source = Nabu::Store::Source.create(slug: "cantigas", name: "cantigas",
                                        adapter_class: "Nabu::Adapters::Cantigas",
                                        license_class: "attribution")

    seed_document!(source, 97,
                   metadata: { "author" => "Paai Soarez de Taveiroos", "author_id" => 88,
                               "genre" => "Amor",
                               "form" => ["Cantiga de refrão", "3 estrofes de 6 versos"],
                               "manuscripts" => ["A 38, B 149"] },
                   lines: [[1, 1, "No mundo nom me sei parelha,"], [2, 1, "mentre me for como me vai,"],
                           [3, 1, "ca ja moiro por vós e — ai!"], [4, 2, "mia senhor branca e vermelha,"],
                           [5, 2, "queredes que vos retraia"], [6, 2, "quando vos eu vi em saia!"]])
    seed_document!(source, 600,
                   metadata: { "author" => "Dom Sancho I", "author_id" => 93,
                               "genre" => "Amigo", "form" => ["Cantiga de refrão"],
                               "manuscripts" => ["B 575/576, V 179"],
                               "rubric" => "Esta cantiga fez el-rei Dom Sancho",
                               "empty_lines" => [20] },
                   lines: [[1, 1, "Ai eu coitada, como vivo em gram cuidado"], [2, 1, "por meu amigo"],
                           [3, 1, "que hei alongado! Muito me tarda"], [4, 2, "o meu amigo na Guarda!"],
                           [5, 2, "Ai eu coitada, como vivo em gram desejo"]])
    # The P56-1 refrain gap: the edition's numbering runs ahead by 2 at the
    # stanza boundary, so stanza 2 opens at edition line 6 and its first
    # line carries {"number_gap" => 2}; the document totals number_gaps: 2.
    seed_document!(source, 1000,
                   metadata: { "author" => "Paai Soarez de Taveiroos", "author_id" => 88,
                               "genre" => "Escárnio e maldizer",
                               "manuscripts" => ["TO 30, B 1146 bis", "(C 12)", "P"],
                               "number_gaps" => 2 },
                   lines: [[1, 1, "Ai, senhor fremosa, por Deus"], [2, 1, "e por quam boa vos El fez,"],
                           [3, 1, "doede-vos algũa vez"],
                           [6, 2, "de mim e destes olhos meus", { "number_gap" => 2 }],
                           [7, 2, "que vos virom por mal de si,"], [8, 2, "quando vos virom, e por mi!"]])
    # cdcant 1241 (real page, live census 2026-08-02): unattributed AND its
    # Fontes manuscritas line is the literal "Não disponível" marker — the
    # edition's explicit statement that no manuscript source is available,
    # not a witness siglum. It must yield zero concordance rows.
    seed_document!(source, 1241,
                   metadata: { "unattributed" => true, "genre" => "Género incerto",
                               "manuscripts" => ["Não disponível"] },
                   lines: [[1, 1, "Dom Foão, que eu sei que há preço de livão,"],
                           [2, 1, "vedes que fez ena guerra — daquesto som certão:"],
                           [3, 1, "sol que viu os genetes, come boi que fer tavão,"]])

    identity = Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, "cantigas"))
    source.update(last_ingest_identity: identity)
  end

  def seed_document!(source, cdcant, metadata:, lines:)
    urn = "#{URN_PREFIX}#{cdcant}"
    doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: lines.first[2],
                                       language: "roa-opt", metadata_json: JSON.generate(metadata),
                                       content_sha256: Digest::SHA256.hexdigest(urn),
                                       revision: 1, withdrawn: false)
    lines.each_with_index do |(line, stanza, text, extra), sequence|
      annotations = { "line" => line, "stanza" => stanza }.merge(extra || {})
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{urn}:#{line}", sequence: sequence, language: "roa-opt",
        text: text, text_normalized: text, annotations_json: JSON.generate(annotations),
        content_sha256: Digest::SHA256.hexdigest(text), revision: 1, withdrawn: false
      )
    end
  end

  def feature
    Nabu::DataBuild.feature("roa-opt/cantigas")
  end

  def build!(root, runner, into: File.join(root, "nabu-data"))
    summary = runner.run(feature: feature, into: into)
    [summary, summary.out_dir]
  end

  def read_csv(dir, name)
    CSV.read(File.join(dir, name), headers: true)
  end

  def read_manifest(dir)
    JSON.parse(File.read(File.join(dir, "datapackage.json")))
  end

  # -- the registry flip (the thirteenth feature) ----------------------------

  def test_the_feature_is_available_with_the_builder_wired
    assert feature.available?, "P56-2 lands roa-opt/cantigas :available"
    assert_equal Nabu::DataBuild::CantigasBuilder, feature.builder
    assert_equal "gold", feature.tier, "a faithful structured projection of the granted edition"
    assert_equal "urn+sha", feature.anchoring
    assert_equal "CC-BY-4.0", feature.license
    assert_equal ["cantigas"], feature.inputs
    assert_equal ["cantigas"], feature.canonical_cones
    assert_equal "roa-opt-cantigas", feature.package_name
  end

  # -- lines.csv -------------------------------------------------------------

  def test_lines_carry_every_passage_in_numeric_cdcant_order
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "lines.csv")

      assert_equal LINES_COLUMNS, table.headers
      assert_equal 20, table.size, "one row per verse passage"
      assert_equal %w[97 600 1000 1241],
                   table.map { |row| row["Cantiga_ID"].delete_prefix("c-") }.uniq,
                   "documents ride in NUMERIC cdcant order (string order would say 1000 first)"

      first = table.first
      assert_equal "l-97-1", first["ID"]
      assert_equal "#{URN_PREFIX}97:1", first["URN"]
      assert_equal "c-97", first["Cantiga_ID"]
      assert_equal %w[1 1], first.values_at("Line", "Stanza")
      assert_equal "No mundo nom me sei parelha,", first["Primary_Text"]

      shas = catalog[:passages].select_hash(:urn, :content_sha256)
      table.each do |row|
        assert_equal shas.fetch(row["URN"]), row["Passage_SHA256"],
                     "#{row['URN']}: Passage_SHA256 must be the catalog passage's content sha"
      end
    end
  end

  def test_the_number_gap_column_is_empty_except_where_the_annotation_fires
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "lines.csv")

      gapped = table.reject { |row| row["Number_Gap"].to_s.empty? }
      assert_equal 1, gapped.size, "exactly the one passage carrying the P56-1 annotation"
      assert_equal ["#{URN_PREFIX}1000:6", "2", "6", "2"],
                   gapped.first.values_at("URN", "Number_Gap", "Line", "Stanza"),
                   "the gap rides the stanza's first line, with the EDITION's line number"
    end
  end

  # -- cantigas.csv ----------------------------------------------------------

  def test_the_cantiga_registry_row_shape
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "cantigas.csv")

      assert_equal CANTIGAS_COLUMNS, table.headers
      assert_equal(%w[c-97 c-600 c-1000 c-1241], table.map { |row| row["ID"] })

      row = table.find { |entry| entry["ID"] == "c-600" }
      assert_equal "600", row["Cdcant"]
      assert_equal "#{URN_PREFIX}600", row["URN"]
      assert_equal "Ai eu coitada, como vivo em gram cuidado", row["Incipit"]
      assert_equal "a-93", row["Author_ID"], "Author_ID references authors.csv IDs"
      assert_equal "Amigo", row["Genre"]
      assert_equal "Cantiga de refrão", row["Form"]
      assert_equal "Esta cantiga fez el-rei Dom Sancho", row["Rubric"]

      multi_form = table.find { |entry| entry["ID"] == "c-97" }
      assert_equal "Cantiga de refrão; 3 estrofes de 6 versos", multi_form["Form"],
                   "the sidebar's formal-description lines join with '; '"
      assert_equal "", multi_form["Rubric"].to_s, "absent rubric is an empty cell"
    end
  end

  def test_the_unattributed_page_gets_an_empty_author_id
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      row = read_csv(out_dir, "cantigas.csv").find { |entry| entry["ID"] == "c-1241" }
      assert_equal "", row["Author_ID"].to_s,
                   "cdcant 1241 (the one censused unattributed page shape) mints no author"
    end
  end

  # -- authors.csv -----------------------------------------------------------

  def test_the_author_registry_is_distinct_and_in_cdaut_order
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "authors.csv")

      assert_equal AUTHORS_COLUMNS, table.headers
      assert_equal 2, table.size, "two docs share cdaut 88 — the registry is distinct"
      assert_equal [%w[a-88 88], %w[a-93 93]],
                   table.map { |row| row.values_at("ID", "Cdaut") },
                   "authors ride in numeric cdaut order"
      assert_equal "Paai Soarez de Taveiroos", table.first["Name"]
    end
  end

  # -- manuscripts.csv (the sigla census) ------------------------------------

  def test_manuscript_witnesses_split_on_commas_one_row_each
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "manuscripts.csv")

      assert_equal MANUSCRIPTS_COLUMNS, table.headers
      assert_equal 8, table.size

      witnesses = table.select { |row| row["Cantiga_ID"] == "c-97" }
                       .map { |row| row.values_at("Cancioneiro", "Number") }
      assert_equal [%w[A 38], %w[B 149]], witnesses, "one row per comma-separated witness"
    end
  end

  def test_a_slash_run_stays_one_witness
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      rows = read_csv(out_dir, "manuscripts.csv").select { |row| row["Cantiga_ID"] == "c-600" }
      assert_equal [["B", "575/576", "false"], %w[V 179 false]],
                   rows.map { |row| row.values_at("Cancioneiro", "Number", "Parenthesized") },
                   "B 575/576 is ONE witness spanning both numbers, never two rows"
    end
  end

  def test_the_census_sigla_shapes_parse_honestly
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      rows = read_csv(out_dir, "manuscripts.csv").select { |row| row["Cantiga_ID"] == "c-1000" }
                                                 .map { |row| row.values_at("Cancioneiro", "Number", "Parenthesized") }
      expected = [%w[TO 30 false],             # two-letter siglum
                  ["B", "1146 bis", "false"],  # spaced bis suffix, verbatim
                  %w[C 12 true],               # parenthesized index entry
                  ["P", "", "false"]]          # bare siglum, empty Number
      assert_equal expected, rows, "the census shapes parse as found — nothing normalized away"
    end
  end

  def test_the_no_witness_marker_yields_no_rows
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      rows = read_csv(out_dir, "manuscripts.csv").select { |row| row["Cantiga_ID"] == "c-1241" }
      assert_empty rows, "\"Não disponível\" is the edition's no-witness marker (cdcant 1241, " \
                         "live census) — a statement of absence, never a siglum row"
    end
  end

  def test_an_unparseable_witness_refuses_loudly
    error = assert_raises(Nabu::DataBuild::Error) do
      Nabu::DataBuild::CantigasBuilder.parse_witness("b 12")
    end
    assert_match(/b 12/, error.message, "the refusal names the token — never guessed")

    assert_raises(Nabu::DataBuild::Error) { Nabu::DataBuild::CantigasBuilder.parse_witness("(B 12") }
  end

  # -- the in-band eval (the citation-fidelity census) -----------------------

  def test_the_manifest_publishes_the_citation_fidelity_census
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      eval_block = read_manifest(out_dir).dig("nabu", "eval")

      refute_nil eval_block, "the citation-fidelity census IS the eval"
      assert_equal 4, eval_block.fetch("documents")
      assert_equal 20, eval_block.fetch("lines")
      assert_equal 2, eval_block.fetch("printed_number_confirmed"),
                   "lines 97:5 and 600:5 sit on the edition's printed every-5th ordinals"
      assert_equal 1, eval_block.fetch("number_gap_lines")
      assert_equal 2, eval_block.fetch("number_gap_total")
      assert_equal 1, eval_block.fetch("empty_lines")
      assert_equal 1, eval_block.fetch("unattributed")
      assert_includes eval_block.fetch("against"), "every 5th"
    end
  end

  # -- the furniture ---------------------------------------------------------

  def test_ids_obey_the_cldf_discipline_and_primary_keys_are_honest
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      %w[lines.csv cantigas.csv authors.csv manuscripts.csv].each do |name|
        ids = read_csv(out_dir, name).map { |row| row["ID"] }
        assert_equal ids.size, ids.uniq.size, "#{name}: IDs are unique"
        assert(ids.all? { |id| id.match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) },
               "#{name}: every ID matches the CLDF identifier regex (URNs are never IDs)")
      end

      manifest = read_manifest(out_dir)
      %w[lines cantigas authors manuscripts].each do |name|
        resource = manifest["resources"].find { |entry| entry["name"] == name }
        refute_nil resource, "the manifest declares the #{name} resource"
        assert_equal ["ID"], resource.dig("schema", "primaryKey")
      end
    end
  end

  def test_the_readme_opens_with_a_plain_language_overview
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      readme = File.read(File.join(out_dir, "README.md"))

      assert_includes readme, "## Why this dataset exists — in plain terms"
      assert_match(/cancioneiros?/, readme, "the overview names the songbooks")
      assert_match(/browser-only|no TEI, no export/, readme,
                   "the overview states the problem: a superb database with no machine-readable form")
      assert_match(/free for all/, readme, "the overview quotes the written grant")
      assert_operator readme.index("## Why this dataset exists — in plain terms"), :<,
                      readme.index("## Maintenance"),
                      "the plain-language overview comes BEFORE the technical sections"
    end
  end

  def test_the_readme_carries_the_citation_format_verbatim_and_the_1066_gap
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      readme = File.read(File.join(out_dir, "README.md"))

      assert_includes readme, Nabu::Adapters::Cantigas::CITATION,
                      "the project's own citation format rides the README verbatim (№45-2)"
      assert_includes readme, "1066",
                      "the one no-text cantiga is stated honestly — the corpus gap is data"
      assert_match(/read_csv\("lines\.csv"/, readme, "the loading snippet is present")
    end
  end

  def test_the_manifest_sources_carry_the_littera_grant
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      manifest = read_manifest(out_dir)

      source = manifest["sources"].first
      assert_includes source["title"], "Cantigas Medievais"
      assert_includes source.dig("licenses", 0, "name"), "free for all",
                      "the №45-2 grant text rides the manifest sources[] from the adapter manifest"
      recipe = manifest.dig("nabu", "derivation", "recipe")
      ["one row per verse line", "575/576", "Parenthesized", "cdcant order"].each do |claim|
        assert_includes recipe, claim, "the recipe states the derivation precisely"
      end
    end
  end

  # -- determinism -----------------------------------------------------------

  def test_building_twice_is_byte_identical
    with_build_env do |root, runner, _catalog|
      _summary, first_dir = build!(root, runner, into: File.join(root, "first"))
      _summary, second_dir = build!(root, runner, into: File.join(root, "second"))
      files = Dir.glob("**/*", base: first_dir).sort
      assert_equal files, Dir.glob("**/*", base: second_dir).sort
      files.each do |name|
        next if File.directory?(File.join(first_dir, name))

        assert_equal File.binread(File.join(first_dir, name)), File.binread(File.join(second_dir, name)),
                     "#{name} must be byte-identical across rebuilds"
      end
    end
  end

  # -- refusals --------------------------------------------------------------

  def test_the_builder_refuses_without_a_catalog
    Dir.mktmpdir("nabu-cantigas-data") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::CantigasBuilder.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end

  def test_the_builder_refuses_a_catalog_without_cantigas_rows
    Dir.mktmpdir("nabu-cantigas-data") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::CantigasBuilder.new.build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/cantigas/, error.message)
      assert_match(/sync/, error.message)
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end
end
