# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "webmock/minitest"

# Nabu::Adapters::Openmgh (P45-2): openMGH — the Monumenta Germaniae
# Historica critical editions as per-volume TEI-XML zips
# (data.mgh.de/openmgh/<bsbid>.zip; 153 volumes on the index at scout time,
# 2026-07-25). Fixtures: two whole volumes (Einhard's Vita Karoli, MGH SS
# rer. Germ. 25, Latin; Der Trierer Silvester, MGH Dt. Chron. 1,2, Middle
# High German) plus a documented trim of the Diplomata volume MGH DD
# Rudolf. (teiCorpus of per-charter TEI blocks).
#
# THE LICENSE (read from the live page AND every volume's own
# <availability><licence>, 2026-07-25): CC BY 4.0 on the annotations, the
# medieval texts "free from copyright"; cite MGH + Bayerische
# Staatsbibliothek → class attribution.
#
# THE COMPOSE VERDICT: a NEW `openmgh-tei` family. The bytes refute every
# existing family — the body is a bare milestone stream (one <ab> per div,
# zero <p>/<l>/<s> reading elements, so croala/sarit unit iterators find
# NOTHING), hyphenated words ship as <w> pairs that must re-join across
# <lb> AND <pb> (cora-tei would mint both halves as separate tokens), and
# the Diplomata volumes are <teiCorpus> roots (per-charter inner <TEI>)
# no existing family enters.
class OpenmghTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  EINHARD = "urn:nabu:openmgh:bsb00000728"
  SILVESTER = "urn:nabu:openmgh:bsb00000776"
  RUDOLFINGER = "urn:nabu:openmgh:bsb00000361"

  def conformance_adapter = Nabu::Adapters::Openmgh.new

  def conformance_workdir = Nabu::TestSupport.fixtures("openmgh")

  def conformance_expected_source_id = "openmgh"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_volume_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [RUDOLFINGER, EINHARD, SILVESTER], refs.map(&:id),
                 "one document per <bsbid>/<bsbid>.xml, urn urn:nabu:openmgh:<bsbid>, sorted"
    assert(refs.all? { |ref| ref.source_id == "openmgh" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  # -- the Scriptores dialect: work-page passages -----------------------------

  def test_einhard_volume_chunks_into_work_page_passages
    document = adapter.parse(ref_for(EINHARD))
    assert_equal "lat", document.language
    assert_equal 55, document.count, "4 works × their printed pages (2 + 1 + 41 + 11)"
    first = document.first
    assert_equal "#{EINHARD}:w1.pXXVIII", first.urn,
                 "citation = w<work-ordinal>.p<printed page @n> — roman front-matter pages verbatim"
    assert first.text.start_with?("WALAHFRIDI PROLOGUS. Gloriosissimi imperatoris Karoli vitam et gesta"),
           "the page's lines join on spaces"
    assert_equal 0, first.sequence
    assert_equal "work-page", first.annotations["addressing"]
    assert_equal "Walahfridi Prologus", first.annotations["work"]
    assert_equal "XXVIII", first.annotations["page"]
    assert_equal "#{EINHARD}:w4.p52", document.to_a.last.urn, "the appendix runs to page 52"
  end

  def test_hyphenated_w_pairs_rejoin_across_line_breaks
    first = adapter.parse(ref_for(EINHARD)).first
    assert_includes first.text, "descripsisse cognoscitur",
                    "<w>descrip-</w><lb/><w>sisse</w> joins to one word, hyphen dropped"
    refute_includes first.text, "descrip-", "no broken half survives"
  end

  def test_a_word_straddling_a_page_break_lands_whole_on_its_starting_page
    document = adapter.parse(ref_for(EINHARD))
    first = document.first
    assert first.text.end_with?("diligitur"),
           "<w>dili-</w><pb/><w>gitur</w>: the page flush defers until the word completes"
    second = document.to_a[1]
    assert_equal "#{EINHARD}:w1.pXXIX", second.urn
    assert second.text.start_with?(". rarescit in plurimis."),
           "page XXIX resumes after the joined word"
  end

  def test_a_work_without_its_own_pb_rides_the_open_page
    document = adapter.parse(ref_for(EINHARD))
    gerward = document.find { |p| p.urn == "#{EINHARD}:w2.pXXIX" }
    refute_nil gerward, "Gerwardi versus has zero <pb> — it sits on the page work 1 left open"
    assert gerward.text.start_with?("GERWARDI VERSUS.")
    assert_equal "Gerwardi versus", gerward.annotations["work"]
  end

  def test_title_and_edition_metadata_are_mined_from_the_volume_header
    document = adapter.parse(ref_for(EINHARD))
    assert_equal "MGH SS rer. Germ. 25: Einhardi Vita Karoli Magni", document.title
    assert_equal "Holder-Egger, Oswald", document.metadata["editor"]
    assert_equal "bsb00000728", document.metadata["idno_bsb"]
    assert_equal "MGH SS rer. Germ. 25", document.metadata["idno_mgh"]
    assert_equal "1911", document.metadata["printed_date"], "the print edition's year — NOT the text's date"
    assert_equal "Hannover", document.metadata["printed_place"]
  end

  # -- the German series: per-volume language table ---------------------------

  def test_dt_chron_volume_is_middle_high_german_with_sanitized_page_tokens
    document = adapter.parse(ref_for(SILVESTER))
    assert_equal "gmh", document.language,
                 "Dt. Chron. volumes are Middle High German (no xml:lang upstream — the adapter's series table)"
    assert_equal 34, document.count
    first = document.first
    assert_equal "#{SILVESTER}:w1.p46", first.urn,
                 "the parenthesized page n=\"(46)\" sanitizes to the citation token p46"
    assert_equal "(46)", first.annotations["page"], "the printed @n rides the annotation verbatim"
    assert_includes first.text, "Nv̊ tůnt mir eine stille", "combining marks survive NFC"
  end

  # -- the Diplomata dialect: teiCorpus, one passage per charter --------------

  def test_diplomata_corpus_yields_one_passage_per_charter_with_medieval_dates
    document = adapter.parse(ref_for(RUDOLFINGER))
    assert_equal "lat", document.language
    assert_equal 3, document.count,
                 "charters 1-3 carry text; charter 13 (a deperditum, no <ab>) emits nothing"
    assert_equal ["#{RUDOLFINGER}:c1", "#{RUDOLFINGER}:c2", "#{RUDOLFINGER}:c3"],
                 document.map(&:urn), "citation = c<charternum> (the edition's own charter number)"
    first = document.first
    assert first.text.start_with?("Priscorum legum auctoritates sancserunt"),
           "the tenor is one passage; pages/lines join on spaces"
    assert_includes first.text, "aecclaesiasticas", "w-pair joins work inside charters too"
    assert_equal "charter-number", first.annotations["addressing"]
    assert_equal "tenor", first.annotations["unit"]
    assert_equal "1", first.annotations["n"]
    assert_equal "878 März 25.", first.annotations["date"],
                 "the charter's medieval date, verbatim from its own header"
    assert_equal "MGH D Rudolf. 1", first.annotations["charter"]
    assert_equal "Saint-Prex (885) August 13.", document.to_a[1].annotations["date"]
  end

  def test_diplomata_corpus_header_feeds_document_title_and_metadata
    document = adapter.parse(ref_for(RUDOLFINGER))
    assert_equal "MGH DD Rudolf.: Die Urkunden der burgundischen Rudolfinger", document.title
    assert_equal "Schieffer, Theodor", document.metadata["editor"]
    assert_equal "MGH DD Rudolf.", document.metadata["idno_mgh"]
    assert_equal "1977", document.metadata["printed_date"]
    assert_equal "München", document.metadata["printed_place"]
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 92, db[:passages].count, "55 Einhard + 34 Silvester + 3 charters"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 92, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_downloads_each_allowlisted_volume_zip_into_its_own_subdir
    stub_volume_zip("bsb00000728")
    stub_volume_zip("bsb00000776")
    Dir.mktmpdir do |work|
      pilot = Nabu::Adapters::Openmgh.new(classes: %w[bsb00000728 bsb00000776])
      report = pilot.fetch(work)
      assert_instance_of Nabu::FetchReport, report
      assert File.file?(File.join(work, "bsb00000728", "bsb00000728.xml")),
             "each zip's single XML lands under <workdir>/<bsbid>/"
      assert File.file?(File.join(work, "bsb00000776", "bsb00000776.xml"))
      assert_equal 2, pilot.discover(work).to_a.size, "the fetched tree is discoverable"
      assert_includes report.notes, "bsb00000728"
    end
  end

  def test_fetch_wraps_http_failures_as_fetch_errors
    stub_request(:get, "https://data.mgh.de/openmgh/bsb0000nope.zip").to_return(status: 404)
    Dir.mktmpdir do |work|
      pilot = Nabu::Adapters::Openmgh.new(classes: %w[bsb0000nope])
      assert_raises(Nabu::FetchError) { pilot.fetch(work) }
      refute File.exist?(File.join(work, "bsb0000nope")), "a refused fetch leaves no tree behind"
    end
  end

  # -- the first wave (D45-d) and the series language table -------------------

  def test_default_volume_allowlist_is_the_ss_rer_germ_first_wave
    assert_equal 57, Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES.size,
                 "D45-d proposal: the complete SS rer. Germ. series (in usum scholarum)"
    assert_includes Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES, "bsb00000728", "Einhard is in the wave"
    refute_includes Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES, "bsb00000361",
                    "Diplomata volumes are a later wave"
  end

  def test_language_table_maps_dt_chron_to_gmh_and_defaults_to_latin
    assert_equal "gmh", Nabu::Adapters::Openmgh.volume_language("bsb00000776"), "Dt. Chron. 1,2"
    assert_equal "gmh", Nabu::Adapters::Openmgh.volume_language("bsb00000779"), "Ottokars Reimchronik"
    assert_equal "lat", Nabu::Adapters::Openmgh.volume_language("bsb00000728"), "everything else is Latin"
    assert_equal "lat", Nabu::Adapters::Openmgh.volume_language("bsb00000614"),
                 "Dt. MA is a German-NAMED series of LATIN texts (Briefe Heinrichs IV.)"
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "openmgh", name: "openMGH", adapter_class: "Nabu::Adapters::Openmgh",
      license_class: "attribution"
    )
  end

  # A real single-member volume zip, built from the fixture bytes.
  def stub_volume_zip(bsbid)
    body = Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(workdir, bsbid, "#{bsbid}.xml"), dir)
      zip = File.join(dir, "#{bsbid}.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, "#{bsbid}.xml") }
      File.binread(zip)
    end
    stub_request(:get, "https://data.mgh.de/openmgh/#{bsbid}.zip")
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Mon, 28 Nov 2016 15:56:06 GMT" })
  end
end
