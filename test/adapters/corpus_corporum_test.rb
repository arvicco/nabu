# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::CorpusCorporum (P80-1/80-2): Corpus Córporum — mlat.uzh.ch
# (Univ. of Zurich, dir. Philipp Roelli), v1 scope the Patrologia Latina
# corpus (idno 38: 5,277 texts / 85.5M words at the 2026-08-19 census).
# Fixtures: three whole real PL texts (download.php?idno=10454/10468/10821,
# 2026-08-19) — small opuscula chosen via the catalog's word counts.
#
# THE LICENSE (80-1, the ETCSL class-3 mold): source-level nc — the homepage
# License section verbatim ("Creative Commons Share-Alike … reused freely
# (but non-commercially) as long as the source is indicated"); most texts PD
# or use-granted, download offered "for non-commercial use". Per-text
# teiHeaders carry NO availability/licence element (censused on the
# fixtures + idno 3) — the sefaria-mold per-text gate therefore defaults to
# the source class (license_override nil) and maps an explicit grant only
# when one ever appears in a header.
#
# THE COMPOSE VERDICT: the bytes REFUTE every existing TEI family — PL wraps
# the ENTIRE reading text in <body><note><div1> (the Migne monitum quirk), so
# the blanket drop-<note> rule shared by epidoc/croala-tei/openmgh-tei parses
# every PL document to ZERO passages. The bespoke `corpus-corporum-tei`
# family (croala-tei sibling) distinguishes STRUCTURAL notes (transparent)
# from INLINE notes inside a reading unit (apparatus — dropped), and handles
# the numbered div1/div2 ladder plus Migne column <pb n="0637A"/> milestones.
class CorpusCorporumTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  HISTORIA = "urn:nabu:corpus-corporum:10454"  # Petrus Bibliothecarius, 71 blocks
  EPISTOLA = "urn:nabu:corpus-corporum:10468"  # Wido monachus, 2 blocks
  FRACTIO  = "urn:nabu:corpus-corporum:10821"  # Abbaudus abbas, 12 blocks

  def conformance_adapter = Nabu::Adapters::CorpusCorporum.new

  def conformance_workdir = Nabu::TestSupport.fixtures("corpus-corporum")

  def conformance_expected_source_id = "corpus-corporum"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [HISTORIA, EPISTOLA, FRACTIO], refs.map(&:id),
                 "one document per texts/<idno>.xml, urn urn:nabu:corpus-corporum:<idno>, sorted"
    assert(refs.all? { |ref| ref.source_id == "corpus-corporum" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  def test_discover_never_yields_catalog_files_or_the_refusal_fixture
    ids = adapter.discover(workdir).map(&:id)
    assert_equal 3, ids.size, "catalog/*.xml and refusal.txt are not documents"
  end

  # -- the PL structural-note quirk (the reason this family exists) -----------

  def test_reading_text_inside_the_body_note_wrapper_is_captured
    document = adapter.parse(ref_for(EPISTOLA))
    assert_equal "lat", document.language
    assert_equal 2, document.count,
                 "body > note > div1 > 2 <p> — the structural <note> wrapper is transparent, " \
                 "never dropped (a blanket drop-note rule parses every PL document to zero)"
    assert_equal ["#{EPISTOLA}:d1.p1", "#{EPISTOLA}:d1.p2"], document.map(&:urn)
    assert_includes document.to_a[1].text, "Fraternae mortis crimen incurrit",
                    "the letter's own text survives the wrapper"
  end

  def test_inline_notes_inside_a_reading_unit_are_apparatus_and_drop
    document = adapter.parse(ref_for(EPISTOLA))
    refute(document.any? { |p| p.text.include?("FULGENT. De fide ad Petr.") },
           "the seven <note> citations inside the letter's <p> are apparatus — dropped")
  end

  def test_head_subtrees_never_enter_the_reading_text
    document = adapter.parse(ref_for(FRACTIO))
    assert_equal 12, document.count
    refute(document.any? { |p| p.text.include?("MONITUM") },
           "the Migne <head> caption is apparatus — dropped from every passage")
  end

  def test_the_chronicle_parses_at_prose_block_grain
    document = adapter.parse(ref_for(HISTORIA))
    assert_equal 71, document.count, "71 <p> blocks in the single div1"
    assert_equal "#{HISTORIA}:d1.p1", document.first.urn
    assert_includes document.first.text, "Historiam hanc, Chesnio"
  end

  # -- Migne column provenance ------------------------------------------------

  def test_passages_carry_the_migne_column_annotation
    document = adapter.parse(ref_for(EPISTOLA))
    assert_equal "0637A", document.to_a[1].annotations["column"],
                 "the first <pb n> milestone inside the unit is the Migne column cite"
    assert_equal "structural-ordinal", document.first.annotations["addressing"]
  end

  # -- teiHeader provenance (the 80-1 per-text license gate's capture) --------

  def test_header_provenance_rides_document_metadata
    document = adapter.parse(ref_for(HISTORIA))
    metadata = document.metadata
    assert_equal "Abbrevatia historia Francorum", document.title
    assert_equal "Petrus Bibliothecarius", metadata["author"]
    assert_equal "fl. 892", metadata["author_date"]
    assert_equal "http://viaf.org/viaf/75436192", metadata["author_ref"]
    assert_equal "Jacques-Paul Migne", metadata["editor"]
    assert_equal "early modern edition, no apparatus", metadata["edition"]
    assert_equal "J. P. Migne", metadata["publisher"]
    assert_equal "Parisiis", metadata["pub_place"]
    assert_equal "1853", metadata["pub_date"]
    assert_equal "Patrologia Latina, vol. 151", metadata["series"]
    assert_equal "PetBib.AbHiFr", metadata["series_idno"]
    assert_equal "lat", metadata["language_ident"]
  end

  # -- the dating envelope (P81-1) --------------------------------------------
  #
  # Three lanes, walked in confidence order: the checkpoint's per-work
  # work_composition year, the checkpoint's author life band (born/died),
  # and the teiHeader's author floruit/life string. The fixture state file
  # is the real product of the new walk over the real 2026-08-19 catalog
  # responses (test/fixtures/corpus-corporum/README.md).

  def test_the_checkpoints_work_composition_year_rules_the_envelope
    metadata = adapter.parse(ref_for(HISTORIA)).metadata
    assert_equal({ "not_before" => 892, "not_after" => 892, "raw" => "work composition 892" },
                 metadata["date"])
    assert_equal "fl. 892", metadata["author_date"], "the header lane still rides verbatim"
  end

  def test_the_author_life_band_serves_when_a_work_carries_no_composition_year
    with_doctored_state(drop_composition: true) do |dir|
      metadata = adapter.parse(adapter.discover(dir).find { |r| r.id == EPISTOLA }).metadata
      assert_equal({ "not_before" => 992, "not_after" => 1050, "raw" => "author 992–1050" },
                   metadata["date"])
    end
  end

  def test_the_header_author_date_serves_when_no_checkpoint_exists
    # Today's LIVE canonical state: the pre-P81 checkpoint carries no years
    # (and is schema-invalidated) — the teiHeader floruit still bounds.
    with_doctored_state(remove: true) do |dir|
      metadata = adapter.parse(adapter.discover(dir).find { |r| r.id == EPISTOLA }).metadata
      assert_equal({ "not_before" => 1000, "not_after" => 1000, "raw" => "fl. 1000" },
                   metadata["date"])
    end
  end

  def test_the_author_date_ladder_reads_the_censused_header_forms
    bounds = Nabu::Adapters::CorpusCorporum.method(:author_date_bounds)
    # Real live-catalog values (censused 2026-08-21): Augustine's life
    # band, Cyprian's bare death year, the c.-qualified pair, floruits.
    assert_equal({ "not_before" => 354, "not_after" => 430, "raw" => "354-430" }, bounds.call("354-430"))
    assert_equal({ "not_before" => nil, "not_after" => 258, "raw" => "-258" }, bounds.call("-258"))
    assert_equal({ "not_before" => 470, "not_after" => 544, "raw" => "c.470–c.544" },
                 bounds.call("c.470–c.544"))
    assert_equal({ "not_before" => 1150, "not_after" => 1150, "raw" => "fl. 1150" }, bounds.call("fl. 1150"))
    assert_equal 450, bounds.call("fl.450")["not_before"], "the unspaced floruit variant"
    assert_nil bounds.call("sine-data"), "upstream's own no-data marker mints nothing"
    assert_nil bounds.call("1067-1055"), "a descending pair is not a clean claim"
    assert_nil bounds.call(nil)
  end

  def test_corpus_corporum_is_registered_for_the_structured_metadata_dates_shape
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["corpus-corporum"]
  end

  # Copy the fixture tree into a tmpdir and doctor the CHECKPOINT (our own
  # derived state, never the upstream fixtures): drop the work_composition
  # years, or remove the state file entirely.
  def with_doctored_state(drop_composition: false, remove: false)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(workdir, "texts"), dir)
      state_path = File.join(dir, Nabu::CorpusCorporumFetch::STATE_FILE)
      FileUtils.cp(File.join(workdir, Nabu::CorpusCorporumFetch::STATE_FILE), state_path)
      if drop_composition
        state = JSON.parse(File.read(state_path))
        state["catalog"].each_value { |row| row["texts"].each { |t| t.delete("work_composition") } }
        File.write(state_path, JSON.pretty_generate(state))
      end
      FileUtils.rm_f(state_path) if remove
      yield dir
    end
  end

  def test_license_silent_headers_inherit_the_source_nc_class
    adapter.discover(workdir).each do |ref|
      document = adapter.parse(ref)
      assert_nil document.license_override,
                 "#{ref.id}: teiHeader carries no availability/licence (censused) — " \
                 "the source-level nc class governs, no per-text override"
      refute document.metadata.key?("availability")
    end
  end

  # The sefaria-mold mapping for the day a header DOES carry a grant: only an
  # explicit machine-recognizable statement maps; anything else stays nil and
  # the conservative source-level nc governs.
  def test_license_override_mapping_is_explicit_and_conservative
    map = Nabu::Adapters::CorpusCorporum.method(:license_override_for)
    assert_nil map.call(nil)
    assert_equal "open", map.call("This text is in the Public Domain")
    assert_equal "attribution", map.call("Creative Commons Attribution 4.0 International (CC BY 4.0)")
    assert_equal "nc", map.call("Creative Commons Attribution-NonCommercial-ShareAlike")
    assert_equal "nc", map.call("published under Creative Commons Share-Alike, non-commercial use")
    assert_nil map.call("use was granted us by the owners"), "an unmapped grant string stays conservative"
  end

  # -- damage: the refusal body -----------------------------------------------

  def test_a_refusal_body_on_disk_quarantines_as_parse_error
    Dir.mktmpdir("nabu-cc-refusal") do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(workdir, "refusal.txt"), File.join(texts, "999.xml"))
      refs = adapter.discover(dir).to_a
      assert_equal 1, refs.size
      assert_raises(Nabu::ParseError) { adapter.parse(refs.first) }
    end
  end

  # -- manifest + probe -------------------------------------------------------

  def test_manifest_records_the_nc_wording_verbatim
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "reused freely (but non-commercially) as long as the source is indicated"
    assert_includes manifest.license, "non-commercial use"
  end

  def test_remote_probe_is_a_liveness_only_head_of_the_catalog
    assert_equal :http_zip, Nabu::Adapters::CorpusCorporum.remote_probe_strategy
    targets = Nabu::Adapters::CorpusCorporum.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert target.liveness_only, "a crawl fetch with a state file the probe cannot diff URL-by-URL — " \
                                 "liveness is the honest verdict"
    assert_equal "https://mlat.uzh.ch/php_modules/navigate.php?path=/", target.zip_url
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 85, db[:passages].count, "71 + 2 + 12 prose blocks"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 85, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "corpus-corporum", name: "Corpus Corporum", adapter_class: "Nabu::Adapters::CorpusCorporum",
      license_class: "nc"
    )
  end
end
