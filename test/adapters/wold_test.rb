# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The WOLD adapter (P46-6): the World Loanword Database (Haspelmath &
# Tadmor 2009, lexibank/wold v4.2) as the etym desk's structured
# loanword-flow layer — one dictionary shelf per WOLD vocabulary (the
# starling many-shelves-one-source shape), one entry per lexeme with its
# curated borrowed status, and each borrowing event's donor word minted as
# a borrowed reflex edge (the donor side is where the ancient languages
# live: Latin, Old Norse, Sanskrit, Classical Arabic…). Dictionary-shaped,
# so like Iecor/Starling it mirrors the passage conformance suite by hand
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the loanword-donor round-trip pins.
class WoldTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wold")

  def adapter(pin: nil)
    pin ? Nabu::Adapters::Wold.new(pin: pin) : Nabu::Adapters::Wold.new
  end

  # --- manifest + capabilities -----------------------------------------------------

  def test_manifest_identifies_the_wold_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wold", manifest.id
    assert_match(/CC[- ]BY[- ]4\.0/i, manifest.license)
    assert_match(/Haspelmath/, manifest.license, "the citation rides the license lane")
    assert_equal "attribution", manifest.license_class
    assert_equal "cldf-csv", manifest.parser_family
    assert_match(/zenodo/, manifest.upstream_url)
  end

  def test_content_kind_is_dictionary_and_the_source_promises_reflexes
    assert_equal :dictionary, Nabu::Adapters::Wold.content_kind
    assert Nabu::Adapters::Wold.reflex_bearing?, "donor words mint borrowed reflex edges"
  end

  def test_probe_is_http_zip_against_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::Wold.remote_probe_strategy
    targets = Nabu::Adapters::Wold.http_probe_targets
    assert_equal [Nabu::Adapters::Wold::ZENODO_ZIP_URL], targets.map(&:zip_url)
  end

  # --- discover → parse ------------------------------------------------------------

  def test_discover_yields_one_ref_per_vocabulary_in_upstream_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wold-swahili:cldf", "wold-oldhighgerman:cldf", "wold-english:cldf"],
                 refs.map(&:id), "languages.csv file order"
    assert_equal %w[wold] * 3, refs.map(&:source_id)
    vocabularies = refs.map { |r| r.metadata.fetch("vocabulary") }
    assert_equal %w[Swahili OldHighGerman English], vocabularies
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse(vocabulary)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("vocabulary") == vocabulary }
    adapter.parse(ref)
  end

  def test_parse_english_yields_the_vocabulary_shelf_with_the_contributor_title
    document = parse("English")
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wold-english", document.slug
    assert_equal "eng", document.language, "ISO 639-3 pass-through (the eng-web tag)"
    assert_match(/English vocabulary/, document.title)
    assert_match(/Anthony Grant/, document.title, "the per-vocabulary contributor credit")
    assert_equal %w[English-1-1-1 English-1-51-1 English-5-92-1 English-23-395-1],
                 document.map(&:entry_id), "entry id = the upstream form ID, verbatim"
  end

  def test_vocabularies_without_iso_codes_use_the_censused_tag_map
    assert_equal "goh", parse("OldHighGerman").language,
                 "WOLD leaves OldHighGerman's ISO column blank — the censused map fills goh"
  end

  # --- the loanword-donor round-trip (the packet pin) ------------------------------

  def test_a_clearly_borrowed_word_carries_its_donor_as_a_borrowed_reflex
    wine = parse("English").entries.find { |e| e.entry_id == "English-5-92-1" }
    assert_equal "wine", wine.headword
    assert_equal "the wine", wine.gloss, "gloss = the WOLD meaning label"
    assert_includes wine.body, "borrowed status: 1. clearly borrowed"
    assert_includes wine.body, "loan ← Latin vīnum ‘wine’"
    assert_includes wine.body, "loan ← Greek (w)oînos ‘wine’ (earlier)",
                    "non-immediate events carry their Source_relation"
    donors = wine.reflexes
    assert_equal [%w[lati1261 lat], ["mode1248", nil]],
                 donors.map { |r| [r.lang_code, r.language] },
                 "lang_code = the upstream glottocode verbatim; the donor map keys on the NAME " \
                 "(WOLD's own glottocodes are unreliable — noon1243), unmapped donors stay display-only"
    vinum = donors.first
    assert_equal "vīnum", vinum.word
    assert vinum.borrowed, "a donor edge is a borrowing edge"
    assert_equal "Latin", vinum.lang_name
    assert_equal Nabu::Normalize.search_form("vinum", language: "lat"), vinum.word_folded,
                 "the donor fold lands on the Latin gold-side §9 key — the etym join"
  end

  def test_old_norse_donors_map_by_name_despite_the_upstream_glottocode
    sky = parse("English").entries.find { |e| e.entry_id == "English-1-51-1" }
    donor = sky.reflexes.first
    assert_equal "noon1243", donor.lang_code, "upstream bytes verbatim (Glottolog says Noone!)"
    assert_equal "non", donor.language, "the NAME 'Old Norse' decides the catalog tag"
    assert_equal "ský", donor.word
  end

  def test_a_native_word_still_mints_an_entry_with_its_status
    world = parse("English").entries.find { |e| e.entry_id == "English-1-1-1" }
    assert_equal "world", world.headword
    assert_includes world.body, "borrowed status: 5. no evidence for borrowing"
    assert_includes world.body, "age: Proto-Germanic"
    assert_empty world.reflexes
  end

  def test_concept_line_carries_the_concepticon_id_for_the_spine
    wine = parse("English").entries.find { |e| e.entry_id == "English-5-92-1" }
    assert_includes wine.body, "concept: the wine (Concepticon 1524 WINE)",
                    "the id the cldf-spine resolver resolves (test/cldf_spine_test.rb)"
  end

  def test_a_comma_multiform_donor_with_a_non_word_part_stays_unsplit
    helfant = parse("OldHighGerman").entries.find { |e| e.entry_id == "OldHighGerman-3-77-1" }
    words = helfant.reflexes.map(&:word)
    assert_includes words, "elephantus", "the immediate Latin donor"
    assert_includes words, "elephas, -ntos",
                    "Greek ‘elephas, -ntos’ keeps its inflection tail — splitting would mint ‘-ntos’"
  end

  def test_a_weak_evidence_word_keeps_both_the_status_and_the_event
    ulimwengu = parse("Swahili").entries.find { |e| e.entry_id == "Swahili-1-1-2" }
    assert_includes ulimwengu.body, "borrowed status: 4. very little evidence for borrowing"
    assert_includes ulimwengu.body, "loan ← Arabic lˁmān + ˁālmyān",
                    "the curated event rides even where the status is doubtful — both are upstream truth"
    assert_equal ["lˁmān + ˁālmyān"], ulimwengu.reflexes.map(&:word), "unsplittable — one verbatim edge"
    assert_equal "ara", ulimwengu.reflexes.first.language
  end

  def test_entry_ids_are_stable_across_independent_passes_and_nfc
    snapshot = -> { parse("English").map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    parse("English").each do |entry|
      assert_equal entry.headword.unicode_normalize(:nfc), entry.headword
      assert_equal entry.body.unicode_normalize(:nfc), entry.body
    end
  end

  # --- loader round-trip -----------------------------------------------------------

  def test_loads_through_the_dictionary_loader_idempotently
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "wold", name: "WOLD", adapter_class: "Nabu::Adapters::Wold",
      license: "CC BY 4.0", license_class: "attribution",
      upstream_url: "https://zenodo.org", enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source)
    report = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 9, report.added
    assert_equal 0, report.errored
    wine = db[:dictionary_entries].where(entry_id: "English-5-92-1").first
    assert_equal "urn:nabu:dict:wold-english:English-5-92-1", wine[:urn]
    reflexes = db[:dictionary_reflexes].where(dictionary_entry_id: wine[:id]).all
    assert_equal 2, reflexes.size
    assert(reflexes.all? { |r| r[:borrowed] }, "every donor edge is borrowed=true")
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added + second.updated + second.withdrawn
    assert_equal 9, second.skipped
  end

  # --- fetch (WebMock only, no network) --------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      tree = File.join(dir, "lexibank-wold-test", "cldf")
      FileUtils.mkdir_p(tree)
      Dir.glob(File.join(FIXTURES, "cldf", "*.csv")).each { |csv| FileUtils.cp(csv, tree) }
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "lexibank-wold-test") }
      File.binread(zip)
    end
  end

  def stub_zenodo(body)
    stub_request(:get, Nabu::Adapters::Wold::ZENODO_ZIP_URL)
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Mon, 09 Feb 2026 00:00:00 GMT" })
  end

  def test_fetch_pins_the_release_sha_and_unpacks_the_bundle
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      report = adapter(pin: Digest::SHA256.hexdigest(body)).fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal 3, adapter.discover(workdir).to_a.size
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_release_pin
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256/, error.message)
      refute File.exist?(File.join(workdir, "cldf")), "a refused fetch must leave the tree untouched"
    end
  end

  # --- registry --------------------------------------------------------------------

  def test_registry_row_is_unwired_manual_on_the_etym_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wold"]
    refute_nil entry, "config/sources.yml must register wold"
    assert_equal Nabu::Adapters::Wold, entry.adapter_class
    refute entry.wired, "wired flips only after the owner-fired first sync (CLAUDE.md checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "etym"
  end
end
