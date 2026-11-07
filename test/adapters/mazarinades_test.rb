# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Mazarinades adapter tests: the Antonomaz corpus (github.com/Antonomaz/Corpus)
# on the antonomaz-tei family. Fixture (test/fixtures/mazarinades/README.md):
# upstream's own tree under tree/ — eight accepted pamphlets (Google Books,
# Gallica, Mazarinum and hand-transcribed copies; Moreau-numbered and
# Labadie; French verse and prose, a Picard dialogue, a pb-as-container
# file), upstream's two
# working files inside Mazarinades/, and one specimen of every rejected
# tree (Doublons, Mazarinades_jsons, output, script, top-level furniture);
# malformed/ holds one of upstream's 13 malformed files for the quarantine.
class MazarinadesTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  ROOT = Nabu::TestSupport.fixtures("mazarinades")
  TREE = File.join(ROOT, "tree")
  PREFIX = "urn:nabu:mazarinades:"
  PRINCE = "#{PREFIX}Moreau1483_GBOOKS".freeze
  RENTES = "#{PREFIX}Moreau2135_MAZ".freeze
  PICARDS = "#{PREFIX}Moreau1085-i_MAZ".freeze
  MANUAL = "#{PREFIX}Moreau2542_MANUAL".freeze

  def conformance_adapter = Nabu::Adapters::Mazarinades.new
  def conformance_workdir = TREE
  def conformance_expected_source_id = "mazarinades"

  def adapter = Nabu::Adapters::Mazarinades.new

  def document(urn)
    ref = adapter.discover(TREE).find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end

  # --- manifest + license ---------------------------------------------------------

  def test_manifest_records_the_readme_licence_verbatim
    manifest = adapter.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Les textes sont publiés sous la licence CC BY 4.0"
    assert_equal "antonomaz-tei", manifest.parser_family
    assert_equal "https://github.com/Antonomaz/Corpus", manifest.upstream_url
  end

  def test_the_fixture_carries_the_license_evidence_first_hand
    readme = File.read(File.join(TREE, "README.md"))
    assert_includes readme, "Les textes sont publiés sous la licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)."
    file = File.read(File.join(TREE, "Mazarinades/1401-1500/Moreau1483_GBOOKS.xml"))
    assert_includes file, %(<availability n="cc-by" status="restricted">)
    assert_includes file, %(<licence target="https://creativecommons.org/licenses/by/4.0"/>)
  end

  def test_every_document_carries_its_licence_and_the_availability_oddity
    adapter.discover(TREE).each do |ref|
      meta = adapter.parse(ref).metadata
      assert_equal "https://creativecommons.org/licenses/by/4.0", meta["licence"], ref.id
      assert_equal "restricted", meta.dig("availability", "status"), ref.id
    end
    assert_equal "NaN", document("#{PREFIX}Moreau1021_GBOOKS").metadata.dig("availability", "n")
  end

  # --- discovery -------------------------------------------------------------------

  def test_discover_yields_one_document_per_pamphlet_file
    expected = %W[
      #{PREFIX}Moreau1021_GBOOKS #{PICARDS} #{PRINCE} #{RENTES} #{MANUAL}
      #{PREFIX}Moreau4018_GALL #{PREFIX}Moreau614_GALL #{PREFIX}Labadie332_GALL
    ]
    assert_equal expected, adapter.discover(TREE).map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a, "the pre-fetch state yields nothing" }
  end

  def test_rejected_trees_and_working_files_skip_by_rule
    skips = adapter.discovery_skips(TREE)
    assert_equal 0, skips.unrecognized, skips.notes.join("\n")
    notes = skips.notes.join("\n")
    assert_match(%r{Doublons/Moreau3845-bad_GBOOKS\.xml: a duplicate exemplar}, notes)
    assert_match(%r{Doublons/README\.md: a duplicate exemplar}, notes)
    assert_match(%r{Doublons/Moreau1suppl195_GBOOKS\.textClipping: a duplicate exemplar}, notes)
    assert_match(%r{Mazarinades_jsons/1401-1500/Moreau1483_GBOOKS\.json: a JSON derivative}, notes)
    assert_match(%r{output/Mazarinades_filecount\.txt: upstream's generated reports}, notes)
    assert_match(%r{output/reviewed_files\.csv: the first-page review ledger}, notes)
    assert_match(%r{script/update_tracking\.txt: upstream's processing scripts}, notes)
    assert_match(/Requete_sous_corpus\.md: repository furniture/, notes)
    assert_match(/README\.md: repository furniture/, notes)
    assert_match(%r{Mazarinades/filecount\.txt: a working file}, notes)
    assert_match(%r{Mazarinades/1-100/diff\.txt: a working file}, notes)
    assert_equal 11, skips.skipped_by_rule
  end

  def test_an_unnamed_tree_is_unrecognized_never_silently_dropped
    Dir.mktmpdir do |work|
      FileUtils.cp_r(File.join(TREE, "Mazarinades"), work)
      FileUtils.mkdir_p(File.join(work, "to_do"))
      FileUtils.cp(File.join(TREE, "Mazarinades/1401-1500/Moreau1483_GBOOKS.xml"), File.join(work, "to_do"))
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.unrecognized
      assert_match(%r{to_do/Moreau1483_GBOOKS\.xml: a tree no rule names}, skips.notes.join("\n"))
      assert_equal 8, adapter.discover(work).count
    end
  end

  # --- documents and passages ------------------------------------------------------------

  def test_passage_censuses
    counts = adapter.discover(TREE).to_h { |ref| [ref.id.delete_prefix(PREFIX), adapter.parse(ref).map(&:urn)] }
    assert_equal ["#{PRINCE}:1"], counts["Moreau1483_GBOOKS"]
    assert_equal ["#{RENTES}:v9", "#{RENTES}:v12"], counts["Moreau2135_MAZ"]
    assert_equal ["#{MANUAL}:pre"], counts["Moreau2542_MANUAL"], "a pb-less transcription is one page"
    assert_equal(%w[1 3 4 5 6], counts["Moreau614_GALL"].map { |urn| urn.split(":").last })
  end

  def test_a_known_text_and_its_page_annotations
    page = document(RENTES).find { |p| p.urn == "#{RENTES}:v12" }
    assert page.text.start_with?("ne Ville de Paris, & pour leuer tout le doute que\n")
    assert_equal "fra", page.language
    assert_equal({ "page" => "v12", "vue" => "12", "continued_lines" => [4, 5, 6, 9, 10, 15, 18] },
                 page.annotations.slice("page", "vue", "continued_lines"))
    first = document(RENTES).first
    assert_equal true, first.annotations["manual_correction"]
    assert_equal ["decoration"], first.annotations["figures"]
  end

  def test_document_title_and_bibliography
    doc = document(RENTES)
    assert_equal "Lettre du roy à messieurs les prévôt des marchands et échevins de sa bonne ville de Paris " \
                 "sur l'assurance du payement des rentes, de Saumeur , le seizième de février 1652.", doc.title
    meta = doc.metadata
    assert_equal "Moreau", meta["catalog"]
    assert_equal "2135", meta["catalog_number"]
    assert_equal "Moreau", meta["collection"]
    assert_equal "MAZ", meta["digitization"]
    assert_equal "Louis XIV", meta["author"]
    assert_equal "Pierre Rocolet", meta["printer"]
    assert_equal ["lettre"], meta["genre"]
    assert_equal ["prose"], meta["form"]
    assert_equal 4, meta["pages"]
    assert meta["moreau_entry"].start_with?("2135. Lettre du roy")
    assert_equal [{ "id" => "evt_Moreau_65", "source" => "Moreau",
                    "label" => "Arrêt du parlement pour le payement des rentes de l’Hôtel de Ville",
                    "when" => "1652-02-08" }], meta["events"]
    assert_equal "M11599", meta.dig("holding", "idno")
  end

  def test_supplement_and_labadie_collections
    assert_equal "Labadie", document("#{PREFIX}Labadie332_GALL").metadata["collection"]
    assert_equal "332", document("#{PREFIX}Labadie332_GALL").metadata["catalog_number"]
    meta = Nabu::Adapters::Mazarinades.method(:catalog_metadata)
    assert_equal({ "collection" => "Moreau supplement 1", "catalog" => "Moreau", "catalog_number" => "1suppl218",
                   "digitization" => "GALL" }, meta.call("Moreau_sup1", "Moreau1suppl218_GALL"))
    assert_equal({ "collection" => "Bibliothèque Mazarine", "catalog" => "BM", "catalog_number" => "49258",
                   "digitization" => "MAZ" }, meta.call("Bibliotheque_Mazarine", "BM49258_MAZ"))
    assert_equal "1053pp167-210", meta.call("1001-1100", "Moreau1053pp167-210_GALL")["catalog_number"]
  end

  # --- the mined axes ---------------------------------------------------------------

  def test_dates_from_the_bibliographic_entry
    assert_equal({ "not_before" => 1652, "not_after" => 1652, "raw" => "1652 (Moreau)" },
                 document(PRINCE).metadata["date"])
    rentes = document(RENTES).metadata
    assert_equal({ "not_before" => 1652, "not_after" => 1652, "raw" => "1652 (Mazarine)" }, rentes["date"])
    assert_equal 2, rentes["dates"].size, "every typed date rides metadata, Carrier's dating included"
    assert_equal({ "not_before" => 1653, "not_after" => 1653, "raw" => "1653 (Labadie)" },
                 document("#{PREFIX}Labadie332_GALL").metadata["date"])
  end

  def test_date_envelope_rules
    envelope = Nabu::Adapters::Mazarinades.method(:date_envelope)
    assert_nil envelope.call([{ "source" => "Moreau", "when" => "Sans date", "text" => "Sans date" }])
    assert_equal({ "not_before" => 1649, "not_after" => 1649, "raw" => "pendant le blocus (Carrier)" },
                 envelope.call([{ "source" => "Carrier", "when" => "1649", "not_before" => "1649-01",
                                  "not_after" => "1649-03", "text" => "pendant le blocus" }]))
    assert_equal({ "not_before" => 1652, "not_after" => 1652, "raw" => "après le 19 août 1652 (Carrier)" },
                 envelope.call([{ "source" => "Carrier", "when" => "1652", "not_before" => "1652-08-19",
                                  "text" => "après le 19 août 1652" }]))
  end

  def test_places_from_the_imprint
    assert_equal({ "ancient" => "Paris", "geonames" => "geonames:2988507" }, document(PRINCE).metadata["place"])
    assert_equal({ "ancient" => "Rouen", "geonames" => "geonames:2982652" }, document(MANUAL).metadata["place"])
    picards = document(PICARDS).metadata
    refute picards.key?("place"), "Sans lieu names no place"
    assert_equal({ "name" => "Sans lieu", "source" => "Mazarine" }, picards["pub_place"])
    place = Nabu::Adapters::Mazarinades.method(:place_claim)
    assert_equal({ "ancient" => "Anvers" }, place.call({ "name" => "Anvers", "ref" => "geonames:2988507" }),
                 "Paris's GeoNames id on another town is upstream's template default — the ref drops")
    assert_equal({ "ancient" => "Amsterdam (Paris)", "geonames" => "geonames:2988507" },
                 place.call({ "name" => "Amsterdam (Paris)", "ref" => "geonames:2988507" }),
                 "a false imprint naming Paris keeps the ref")
    assert_nil place.call({ "name" => "Sans lieu", "ref" => "geonames:0000000" })
  end

  def test_the_place_and_date_reach_the_timeline_lanes
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["mazarinades"]
  end

  def test_genre_folds_onto_the_kind_axis
    root = File.expand_path("../../config", __dir__)
    kinds = Nabu::Kinds.load(classes_path: File.join(root, "kind_classes.yml"),
                             map_path: File.join(root, "kind_map.yml"))
    assert_equal ["letter"], kinds.normalize("mazarinades", "lettre")
    assert_equal ["literary/poetry"], kinds.normalize("mazarinades", "burlesque")
    assert_equal ["legal/court"], kinds.normalize("mazarinades", "arrêt")
    assert_equal ["literary/wisdom/dialogue"], kinds.normalize("mazarinades", "dialogue")
    assert_equal [], kinds.normalize("mazarinades", "pamphlet"), "a format, not a genre (deliberate)"
  end

  # The oratory head (ruled 2026-11-07) takes the speech-form cluster the
  # first fold had to leave unmapped. None of these labels sits in the
  # fixture's five pieces (their genres: lettre, dialogue, poésie, sonnet,
  # satirique, …), so the pins read the rule over the census labels.
  ORATORY_LABELS = ["discours adressé", "dicours adressé", "discours", "discours prononcé", "harangue", "hanrangue",
                    "manifeste", "maifeste", "rhétorique délibérative", "rhérotique délibérative",
                    "rhétorique judiciaire", "rhétorique épidictique", "éloge", "panégyrique", "blâme",
                    "remerciement", "consolation", "apologie", "justification", "défense", "réfutation",
                    "réponse", "avis", "pro et contra", "prosopopée", "prosopoée", "prospopée"].freeze

  def test_the_speech_form_cluster_folds_onto_oratory
    root = File.expand_path("../../config", __dir__)
    kinds = Nabu::Kinds.load(classes_path: File.join(root, "kind_classes.yml"),
                             map_path: File.join(root, "kind_map.yml"))
    ORATORY_LABELS.each { |label| assert_equal ["oratory"], kinds.normalize("mazarinades", label), label }
    assert_equal %w[letter oratory], kinds.normalize("mazarinades", "lettre | discours adressé").sort,
                 "a multi-label piece keeps its letter form beside the speech form"
    # judged ambiguous, left in the counted unmapped bucket: the laments, the
    # satirical mode, the parody catechisms, the two "doctrinal" discourses
    %w[satirique lamentation plainte regrets soupirs catéchisme].push("discours doctrinal").each do |label|
      assert_equal ["unmapped"], kinds.normalize("mazarinades", label), label
    end
  end

  # --- language, lect, text nature -----------------------------------------------------

  def test_languages_from_the_label
    assert_equal "fra", document(PRINCE).language
    picards = document(PICARDS)
    assert_equal "pcd", picards.language
    assert_equal "Document en picard", picards.metadata["language_label"]
    code = Nabu::Adapters::Mazarinades.method(:language_code)
    assert_equal "lat", code.call({ "ident" => "fra", "label" => "Document en latin" }), "the label wins"
    assert_equal "oci", code.call({ "ident" => "other", "label" => "Document en gascon" })
    assert_equal "nrf", code.call({ "ident" => "other", "label" => "Document en normand" })
    assert_equal "fra", code.call({ "ident" => "other", "label" => "Patois francilien" })
    assert_equal "fra", code.call({ "ident" => "other", "label" => "Document en pseudo-patois (normand)" })
    assert_equal "spa", code.call({ "ident" => "other", "label" => "Document en espagnol" })
    assert_equal "deu", code.call({ "ident" => "ger", "label" => "Document en allemand" })
    assert_nil code.call({ "ident" => "lat", "label" => "Passages en latin" }), "a partial claim, not the document's"
  end

  def test_french_resolves_to_classical_french_by_override
    overrides = YAML.safe_load_file(File.expand_path("../../config/lect_overrides.yml", __dir__))
    assert_equal({ "lect" => "fr:cls", "tier" => "certain" }, overrides.dig("sources", "mazarinades", "fra"))
  end

  def test_text_nature_follows_the_project_statement
    meta = document(PRINCE).metadata
    assert_equal "machine-ocr", meta["text_nature"]
    assert_includes meta["text_origin"], "OCRisation réalisé avec Kraken"
    manual = document(MANUAL).metadata
    refute manual.key?("text_nature"), "a hand transcription carries no OCR label"
    assert_includes manual["text_origin"], "transcription manuelle"
  end

  def test_the_first_page_review_ledger_rides_the_document
    assert_equal({ "reviewed" => true, "corrected_before" => true, "remark" => "sudden jump from 1 to 3 in numbering" },
                 document("#{PREFIX}Moreau1021_GBOOKS").metadata["first_page_review"])
    refute document(PRINCE).metadata.key?("first_page_review"), "an unreviewed row is no claim"
  end

  # --- quarantine ----------------------------------------------------------------------

  def test_a_malformed_file_is_discovered_and_quarantines_on_parse
    Dir.mktmpdir do |work|
      FileUtils.cp_r(File.join(TREE, "Mazarinades"), work)
      FileUtils.cp_r(File.join(ROOT, "malformed", "Mazarinades"), work)
      ref = adapter.discover(work).find { |r| r.id == "#{PREFIX}Moreau1902_MANUAL" } || flunk("must be discovered")
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- store: idempotent double-load ------------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "mazarinades", name: "Mazarinades",
                                        adapter_class: "Nabu::Adapters::Mazarinades", license_class: "attribution")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: TREE, full: true)
    assert_equal 8, first.added
    assert_equal 0, first.errored
    passages = catalog[:passages].count
    second = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: TREE, full: true)
    assert_equal 0, second.errored
    assert_equal 8, second.skipped, "a byte-identical reload skips every document"
    assert_equal passages, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- registry + fetch --------------------------------------------------------

  def test_registry_resolves_mazarinades
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["mazarinades"]
    refute_nil entry, "mazarinades must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Mazarinades, entry.adapter_class
    assert_equal Nabu::Adapters::Mazarinades.manifest, entry.manifest
    assert entry.wired, "first real sync verified (3,067 docs / 40,883 passages)"
  end

  def test_fetch_clones_the_cone_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-mazarinades-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      Dir.children(TREE).each { |entry| FileUtils.cp_r(File.join(TREE, entry), upstream) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      mazarinades = adapter
      mazarinades.define_singleton_method(:repo_url) { upstream }
      workdir = File.join(root, "canonical")
      report = mazarinades.fetch(workdir)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal 8, mazarinades.discover(workdir).count
      %w[Doublons Mazarinades_jsons script output/Mazarinades_filecount.txt Requete_sous_corpus.md].each do |path|
        refute File.exist?(File.join(workdir, path)), "#{path} stays outside the cone"
      end
      assert File.file?(File.join(workdir, "README.md")), "the licence evidence rides the cone"
      assert File.file?(File.join(workdir, "output/reviewed_files.csv")), "the review ledger rides the cone"
      skips = mazarinades.discovery_skips(workdir)
      assert_equal 4, skips.skipped_by_rule, "live: README, the review ledger and the two working files"
    end
  end
end
