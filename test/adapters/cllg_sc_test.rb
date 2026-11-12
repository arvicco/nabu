# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# CLLG Sources Chrétiennes — the Inria CLLG corpus of the Cerf series' Greek
# (and a few Latin) texts. Discovery walks the per-author metadata.xml
# catalog records (urns, titles, descriptions); the edition files parse
# through the cllg-tei family. Fixtures: trimmed real files,
# test/fixtures/cllg-sc/README.md.
class CllgScTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cllg-sc")

  CELSUM = "urn:cts:greekLit:tlg2042.tlg001.sc-cllg-grc1"
  PROVERBS = "urn:cts:greekLit:tlg4110.cllg001.sc-cllg-grc1"
  HOMILY = "urn:cts:greekLit:cllg0010.cllg001.sc-cllg-grc1"
  DEMETRIANUM = "urn:cts:latinLit:stoa0104a.stoa002.cllg-lat1"

  def conformance_adapter
    Nabu::Adapters::CllgSc.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "cllg-sc"
  end

  def adapter
    @adapter ||= Nabu::Adapters::CllgSc.new
  end

  def refs
    @refs ||= adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
  end

  def parsed(urn)
    adapter.parse(refs.fetch(urn))
  end

  # -- manifest --------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::CllgSc.manifest
    assert_equal "cllg-sc", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "https://gitlab.inria.fr/almanach/cllg/sources-chretiennes.git", manifest.upstream_url
    assert_equal "cllg-tei", manifest.parser_family
    assert_match(/CC-BY/, manifest.license)
    assert_match(%r{16/00005}, manifest.license, "the French case-law provenance rides the licence text")
  end

  # -- discovery: every catalogued edition file ---------------------------------

  def test_discover_yields_every_metadata_resource_by_its_urn
    assert_equal [HOMILY, CELSUM, PROVERBS, DEMETRIANUM].sort, refs.keys.sort
    assert_equal File.join(FIXTURES, "data", "tlg2042", "contra_celsum.xml"), refs.fetch(CELSUM).path
  end

  def test_an_edition_file_no_catalog_record_claims_is_skipped_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_predicate skips, :clean?
    assert_equal 1, skips.skipped_by_rule
    assert_match(%r{1 uncatalogued edition file.*tlg4110/lettre_sur_la_foi\.xml}, skips.notes.join("\n"))
  end

  def test_a_zero_match_tree_is_skipped_by_rule_at_parse
    error = assert_raises(Nabu::DocumentSkipped) { parsed(HOMILY) }
    assert_equal "declared citeStructure matches nothing", error.reason
  end

  # -- parse -----------------------------------------------------------------

  def test_contra_celsum_parses_book_dot_section
    document = parsed(CELSUM)
    assert_equal "grc", document.language
    assert_equal "Contre Celse (SC 132, 136, 147, 150)", document.title
    assert_equal(%w[proem.1 proem.2 1.1], document.map { |passage| passage.urn.delete_prefix("#{CELSUM}:") })
    assert document.first.text.start_with?("Ὁ μὲν σωτὴρ καὶ κύριος ἡμῶν Ἰησοῦς Χριστὸς ψευδομαρτυρούμενος")
  end

  def test_the_latin_edition_parses_as_lat
    document = parsed(DEMETRIANUM)
    assert_equal "lat", document.language
    assert_equal(%w[1.1 1.2 2.1 2.2], document.map { |passage| passage.urn.delete_prefix("#{DEMETRIANUM}:") })
  end

  # -- the catalog + header mining (aggressive-mining law) -------------------------

  def test_catalog_metadata_rides_the_document
    metadata = parsed(CELSUM).metadata
    assert_equal "Origène", metadata["author"]
    assert_equal "Contre Celse", metadata["work_title"]
    assert_match(/Borret, 1967-1969/, metadata["description"])
    assert_equal "tlg2042.tlg001", metadata["tlg"]
  end

  def test_every_sc_volume_edition_is_mined_with_its_year
    metadata = parsed(CELSUM).metadata
    assert_equal %w[132 136 147 150], metadata["sc_volumes"]
    assert_equal ["Marcel Borret"], metadata["editors"]
    assert_equal "1967, 1968, 1969", metadata["edition_year"], "the EDITION_FALLBACK years, distinct"
    assert_nil metadata["date"], "no composition claim upstream — the edition year falls back on the timeline"
    edition = metadata["editions"].first
    assert_equal({ "n" => "SC132", "title" => "Contre Celse, Livres I et II", "editors" => ["Marcel Borret"],
                   "date" => "1967", "publisher" => "Les Éditions du Cerf", "place" => "Paris",
                   "series" => "Sources chrétiennes", "volume" => "132",
                   "identifiers" => { "ISBN" => "978-2-204-07872-6" } }, edition)
  end

  def test_the_original_work_century_is_a_composition_date
    metadata = parsed(DEMETRIANUM).metadata
    assert_equal({ "not_before" => 201, "not_after" => 300, "raw" => "ca. 3th century", "class" => "composition" },
                 metadata["date"])
    assert_equal "2003", metadata["edition_year"]
    assert_equal({ "ISBN" => "978-2-204-06854-3", "CPL" => "46" }, metadata["identifiers"])
  end

  def test_cpg_identifier_and_title_genre
    metadata = parsed(PROVERBS).metadata
    assert_equal "Commentaire", metadata["genre"], "the title's genre noun (the cgpg title-keyword precedent)"
    assert_nil parsed(CELSUM).metadata["genre"], "Contre … names no genre noun"
  end

  def test_title_genre_takes_the_earliest_genre_noun
    genre = ->(title) { Nabu::Adapters::CllgSc.title_genre(title) }
    assert_equal "Homélie", genre.call("Contra Anomoeos (Contre les Anoméens, homélie 11)")
    assert_equal "Préface", genre.call("Préface aux hymnes divins")
    assert_equal "Lettre", genre.call("Correspondance (Collection de Patmos, I-LII)")
    assert_equal "Éloge funèbre", genre.call("Éloge funèbre de Mélèce, évêque d'Antioche")
    assert_equal "Vie", genre.call("Vie de sainte Macrine")
    assert_nil genre.call("Sur la prière")
  end

  # Every label the title cut can mint folds onto a ruled head in
  # config/kind_map.yml — except "Dialogue", unmapped by design.
  def test_every_title_genre_label_folds_or_is_declared_unmapped
    kinds = Nabu::Kinds.load(classes_path: File.expand_path("../../config/kind_classes.yml", __dir__),
                             map_path: File.expand_path("../../config/kind_map.yml", __dir__))
    labels = Nabu::Adapters::CllgSc::TITLE_GENRES.map(&:first)
    unmapped = labels.select { |label| kinds.normalize("cllg-sc", label) == [Nabu::Kinds::UNMAPPED] }
    assert_equal ["Dialogue"], unmapped
    assert_equal ["sermon/homily"], kinds.normalize("cllg-sc", "Homélie")
    assert_equal ["exegesis"], kinds.normalize("cllg-sc", parsed(PROVERBS).metadata["genre"])
  end

  # -- store: idempotent load ---------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "cllg-sc", name: "CLLG Sources Chrétiennes",
                                        adapter_class: "Nabu::Adapters::CllgSc", license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 1, first.skipped_by_rule, "the zero-match homily"
    assert_equal 0, first.errored
    passages = db[:passages].count
    assert_equal 3 + 4 + 18, passages, "Contra Celsum 3 + Ad Demetrianum 4 + the 18 proverb items"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal passages, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch (local git only, no network) --------------------------------------

  def test_fetch_clones_through_the_non_destructive_git_path
    Dir.mktmpdir("nabu-cllg-sc-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.cp_r(FIXTURES, upstream)
      Nabu::Shell.run("git", "init", "-q", upstream)
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=test@test", "-c", "user.name=test",
                      "commit", "-q", "-m", "seed")
      sc = adapter
      sc.define_singleton_method(:repo_url) { upstream }
      work = File.join(root, "canonical")
      report = sc.fetch(work)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal refs.keys.sort, sc.discover(work).map(&:id).sort
    end
  end
end
