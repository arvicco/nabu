# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "webmock/minitest"

# Nabu::Adapters::Openmgh (P45-2): openMGH — the Monumenta Germaniae
# Historica critical editions as per-volume TEI-XML zips
# (data.mgh.de/openmgh/<bsbid>.zip; 153 volumes on the index at scout time
# 2026-07-25, re-censused unchanged 2026-08-02 for the P56-3 second wave).
# Fixtures: three whole volumes (Einhard's Vita Karoli, MGH SS rer. Germ.
# 25, Latin; Der Trierer Silvester, MGH Dt. Chron. 1,2, Middle High German;
# Eugippius' Vita sancti Severini, MGH Auct. ant. 1,2 — the P56-3
# second-wave shape check) plus documented trims of two Diplomata volumes
# (teiCorpus of per-charter TEI blocks): MGH DD Rudolf. and MGH DD F. II.
# Band 3 (bsb00002026 — the bare-header/self-closing-<date/> shape that
# quarantined the owner's first second-wave sync, 2026-08-02).
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
  EUGIPPIUS = "urn:nabu:openmgh:bsb00000786"
  FRIDERICI = "urn:nabu:openmgh:bsb00002026"

  def conformance_adapter = Nabu::Adapters::Openmgh.new

  def conformance_workdir = Nabu::TestSupport.fixtures("openmgh")

  def conformance_expected_source_id = "openmgh"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_volume_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [RUDOLFINGER, EINHARD, SILVESTER, EUGIPPIUS, FRIDERICI], refs.map(&:id),
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

  # -- the second wave (P56-3): an Auct. ant. volume, same Scriptores dialect -

  def test_second_wave_auct_ant_volume_parses_through_the_wave_one_machinery
    document = adapter.parse(ref_for(EUGIPPIUS))
    assert_equal "lat", document.language
    assert_equal "MGH Auct. ant. 1,2: Eugippii Vita sancti Severini", document.title
    assert_equal 32, document.count, "2 works × their printed pages — no new shape, no parser change"
    first = document.first
    assert_equal "#{EUGIPPIUS}:w1.pXIX", first.urn
    assert first.text.start_with?("HYMNUS SANCTI SEVERINI ABBATIS. Canticum laudis domino canentes"),
           "the milestone-stream chunker reads Auct. ant. bytes exactly like SS rer. Germ."
    assert_equal "Hymnus s. Severini", first.annotations["work"]
    assert_equal "#{EUGIPPIUS}:w2.p30", document.to_a.last.urn, "the Vita runs to printed page 30"
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

  # P56 hotfix rider (owner's first second-wave sync, 2026-08-02): the three
  # DD F. II. volumes — bsb00066349 (DD 171-426), bsb00002026 (DD 427-657),
  # bsb00002027 (DD 658-929), Die Urkunden Friedrichs II. — quarantined "no
  # citable passages found". Their headers are BARE (empty corpus <title>, no
  # idnos/editor) and every charter bibl carries a SELF-CLOSING <date/>: the
  # Reader emits no end event for an empty element, so the header capture
  # never closed and the entire tenor drained into the date buffer instead of
  # the passage stream. DD Rudolf. never trips this — its dates are filled.
  def test_a_self_closing_charter_date_does_not_swallow_the_tenor
    document = adapter.parse(ref_for(FRIDERICI))
    assert_equal "lat", document.language
    assert_equal 3, document.count, "charters 427-429, one tenor passage each"
    assert_equal ["#{FRIDERICI}:c427", "#{FRIDERICI}:c428", "#{FRIDERICI}:c429"],
                 document.map(&:urn)
    first = document.first
    assert first.text.start_with?("In nomine sancte et individue trinitatis. " \
                                  "Fridericus divina favente clementia Romanorum rex " \
                                  "semper augustus et rex Sicilie."),
           "the tenor is reading text again — including the Ro-/manorum w-pair join"
    assert_includes first.text, "frater Hermanne magister sacre domus hospitalis Teutonicorum"
    assert_nil first.annotations["date"], "an empty <date/> yields no date annotation"
    assert_equal "427", first.annotations["n"]
    assert_nil document.title, "the DD F. II. corpus header is bare — empty <title>"
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
    assert_equal 5, first.added
    assert_equal 0, first.errored
    assert_equal 127, db[:passages].count,
                 "55 Einhard + 34 Silvester + 3 Rudolfinger + 32 Eugippius + 3 Friderici charters"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 5, second.skipped, "a byte-identical reload skips every document"
    assert_equal 127, db[:passages].count
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

  # -- the two waves (D45-d + P56-3) and the series language table ------------

  def test_first_wave_stays_byte_frozen_as_the_ss_rer_germ_series
    assert_equal 57, Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES.size,
                 "D45-d: the complete SS rer. Germ. series (in usum scholarum) — a frozen historical record"
    assert_includes Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES, "bsb00000728", "Einhard is in the wave"
    refute_includes Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES, "bsb00000361",
                    "Diplomata volumes are the second wave"
  end

  def test_second_wave_completes_the_censused_index_without_touching_wave_one
    first = Nabu::Adapters::Openmgh::FIRST_WAVE_VOLUMES
    second = Nabu::Adapters::Openmgh::SECOND_WAVE_VOLUMES
    assert_equal 96, second.size, "P56-3 census (2026-08-02): the 96 non-SS-rer.-Germ. index volumes"
    assert_empty first & second, "the waves are disjoint — wave-1 urns stay byte-frozen"
    assert_equal 153, Nabu::Adapters::Openmgh::ALL_VOLUMES.size,
                 "the full openMGH index: 57 + 96, every id censused from the live listing"
    assert_equal (first + second).sort, Nabu::Adapters::Openmgh::ALL_VOLUMES
    assert_includes second, "bsb00000361", "DD Rudolf. joins in wave 2"
    assert_includes second, "bsb00000786", "Auct. ant. 1,2 (the wave-2 fixture) is censused"
    assert_includes second, "bsb00000858", "SS rer. Lang. — the 1-volume section the wave-1 scout note missed"
  end

  def test_fetch_and_probe_scope_default_to_the_full_censused_index
    targets = Nabu::Adapters::Openmgh.http_probe_targets
    assert_equal Nabu::Adapters::Openmgh::ALL_VOLUMES, targets.map(&:label),
                 "the remote probe sweeps every censused volume, not just wave 1"
    assert_equal "https://data.mgh.de/openmgh/bsb00000786.zip",
                 targets.find { |t| t.label == "bsb00000786" }.zip_url
  end

  def test_language_table_maps_dt_chron_to_gmh_and_defaults_to_latin
    assert_equal "gmh", Nabu::Adapters::Openmgh.volume_language("bsb00000776"), "Dt. Chron. 1,2"
    assert_equal "gmh", Nabu::Adapters::Openmgh.volume_language("bsb00000779"), "Ottokars Reimchronik"
    assert_equal "lat", Nabu::Adapters::Openmgh.volume_language("bsb00000728"), "everything else is Latin"
    assert_equal "lat", Nabu::Adapters::Openmgh.volume_language("bsb00000614"),
                 "Dt. MA is a German-NAMED series of LATIN texts (Briefe Heinrichs IV.)"
  end

  # P56-3 byte census (2026-08-02): two German-language WORKS hide inside
  # Latin series, and two German-TITLED chronicles are Latin — each call
  # verified from the volume's own body text, never the title.
  def test_language_exceptions_in_the_second_wave_are_byte_censused
    assert_equal "gmh", Nabu::Adapters::Openmgh.volume_language("bsb00000691"),
                 "Jakob Unrest, Österr. Chronik (N. S. 11): 'Als man vor in der Osterreichischen coronikn list…'"
    assert_equal "gmh", Nabu::Adapters::Openmgh.volume_language("bsb00000655"),
                 "Reformation Kaiser Siegmunds (Staatsschriften 6): 'Almechtiger got, schöpffer himels und ertrichs…'"
    assert_equal "lat", Nabu::Adapters::Openmgh.volume_language("bsb00000695"),
                 "Kölner Weltchronik (N. S. 15) is a LATIN chronicle under a German title"
    assert_equal "lat", Nabu::Adapters::Openmgh.volume_language("bsb00000697"),
                 "Weltchronik des Mönchs Albert (N. S. 17) likewise: 'Nicolaus tercius… fuit electus in papam'"
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
