# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Nabu::Adapters::Etcsl (P31-5): the Electronic Text Corpus of Sumerian
# Literature, Revised edition (Oxford, October 2006) — 394 composite
# transliterations (Sumerian, hand-lemmatized: every <w> carries an
# editorial lemma/citation form, word class and English gloss) + 381 paired
# English prose translations, one frozen 4,910,212-byte zip on the Oxford
# Text Archive's current CLARIN-UK home (LLDS record hdl 20.500.14106/2518).
#
# SECOND-WITNESS STANCE (MW-beside-kaikki): the epsd2/literary ORACC project
# (sibling packet P31-0) edits the same compositions; ETCSL documents mint
# as their OWN source's documents — deliberately unmerged provenance-distinct
# editions meeting at the "etcsl:<num>" reference-edge key space (every
# document asserts its own composition number plus its body xref targets).
#
# TRANSLATIONS are -en sibling documents (the riig registry-opt-in pattern):
# one urn:nabu:etcsl:<num>-en document per c/t pair whose translation file
# carries prose; the pairing is upstream's own file structure (c.<num>.xml /
# t.<num>.xml) plus per-line corresp pointers, which ride the passages as
# annotations.
#
# LICENSE: CC BY-NC-SA 3.0 → class "nc". The grant lives on the LLDS record
# ONLY (the artifact carries no license statement) — the manifest quotes the
# record verbatim.
class EtcslTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  LUGALBANDA = "urn:nabu:etcsl:1.8.2.1"
  ADAB = "urn:nabu:etcsl:2.5.2.3"
  CATALOGUE = "urn:nabu:etcsl:0.2.01"

  def conformance_adapter
    Nabu::Adapters::Etcsl.new(translations: true)
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("etcsl")
  end

  def conformance_expected_source_id
    "etcsl"
  end

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- manifest / probe -------------------------------------------------------

  def test_manifest_quotes_the_record_grant_verbatim_and_classes_nc
    manifest = Nabu::Adapters::Etcsl.manifest
    assert_equal "nc", manifest.license_class
    assert_match(/Attribution-NonCommercial-ShareAlike 3\.0 Unported \(CC BY-NC-SA 3\.0\)/,
                 manifest.license, "the LLDS record's exact grant wording")
    assert_match(/artifact.*carries no license statement/i, manifest.license,
                 "honest provenance: the grant is record-level only")
    assert_equal "etcsl-tei", manifest.parser_family
  end

  def test_probe_is_http_zip_against_the_llds_bitstream
    assert_equal :http_zip, Nabu::Adapters::Etcsl.remote_probe_strategy
    targets = Nabu::Adapters::Etcsl.http_probe_targets
    assert_equal 1, targets.size
    assert_equal Nabu::Adapters::Etcsl::ZIP_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url, "no machine license endpoint — the grant is record-page HTML"
  end

  def test_reference_edges_run_under_the_etcsl_producer
    assert Nabu::Adapters::Etcsl.reference_edges?
  end

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_composites_plus_en_siblings_sorted
    assert_equal [CATALOGUE, LUGALBANDA, "#{LUGALBANDA}-en", ADAB, "#{ADAB}-en"],
                 adapter.discover(workdir).to_a.map(&:id),
                 "one ref per c file, plus -en for each paired t file with prose; " \
                 "the catalogue has no t file and mints no sibling"
  end

  def test_translations_off_yields_only_composites_and_censuses_the_skip
    plain = Nabu::Adapters::Etcsl.new
    assert_equal [CATALOGUE, LUGALBANDA, ADAB], plain.discover(workdir).to_a.map(&:id)
    skips = plain.discovery_skips(workdir)
    assert_equal 2, skips.skipped_by_rule, "the two t files are skipped by rule when opted out"
    assert_predicate skips, :clean?
  end

  def test_translations_on_censuses_no_skips_for_paired_prose
    skips = adapter.discovery_skips(workdir)
    assert_equal 0, skips.skipped_by_rule, "both t files mint siblings — nothing skipped"
    assert_predicate skips, :clean?
  end

  # -- composite parse --------------------------------------------------------

  def test_parses_lugalbanda_with_segments_lemma_tokens_and_concordance
    document = parse(LUGALBANDA)
    assert_equal "sux", document.language
    assert_equal "Lugalbanda in the mountain cave -- a composite transliteration", document.title
    assert_equal "composite", document.metadata["kind"]
    assert_equal "1.8.2.1", document.metadata["etcsl_no"]
    # The body xref targets (the OB catalogue citations in line A.1's
    # editorial note) as FULL urns — in-catalog targets resolve in `links`
    # (the isicily→EDH precedent; owner repro 2026-07-19: compact keys
    # rendered "(not in catalog)" on documents that ARE in the catalog).
    # The self-assertion lives in metadata["etcsl_no"], never as a
    # self-loop edge; epsd2 concordance producers target these same urns.
    assert_equal %w[urn:nabu:etcsl:0.2.01 urn:nabu:etcsl:0.2.02 urn:nabu:etcsl:0.2.04],
                 document.metadata["related"]

    passages = document.passages
    assert_equal 17, passages.size, "10 div1-A lines + 7 div1-B lines (trim)"
    first = passages.first
    assert_equal "#{LUGALBANDA}:A.1", first.urn
    assert_equal "ud ul an ki-ta ba9-ra2-a-ba", first.text,
                 "line text is the w forms in document order; the English editorial " \
                 "note (with its xrefs) never leaks in"
    assert_equal "p1", first.annotations["corresp"], "the upstream pointer to the paired translation paragraph"
    tokens = first.annotations["tokens"]
    assert_equal 5, tokens.size
    assert_equal({ "form" => "ud", "lemma" => "ud", "pos" => "N", "label" => "day(light)" },
                 tokens.first, "the hand-assigned lemma layer rides every token")
    assert_equal "#{LUGALBANDA}:B.1", passages[10].urn, "div1 B lines cite by their own segment"
  end

  def test_decodes_the_etcsl_entity_layer_honestly
    document = parse(LUGALBANDA)
    damaged = document.passages[1] # A.2
    assert_equal "… ul-e suh10 kece2-da …", damaged.text,
                 "&X; is upstream's illegibility ellipsis; damage/supplied milestones " \
                 "never break a word (ul-e, kece2-da); ETCSL ASCII (c=š, j=ĝ) stays verbatim"
    lemmas = damaged.annotations["tokens"].map { |t| t["lemma"] }
    assert_equal %w[ul suh10 kece2], lemmas, "illegible &X;/X placeholder tokens carry no lemma claim"
  end

  def test_parses_the_adab_lg_shape_with_trailer_and_determinatives
    document = parse(ADAB)
    assert_equal "An adab for Šu-ilīšu (Šu-ilīšu C) -- a composite transliteration".unicode_normalize(:nfc),
                 document.title, "ETCSL char entities decode per the .ent comments (&C; → Š, &imacr; → ī)"
    cites = document.passages.map { |p| p.urn.split(":").last }
    assert_equal %w[A.1 A.2 A.3 A.4], cites, "lg lines and the trailer line all cite by upstream l ids"
    assert_equal "a-da-ab {d}…", document.passages.last.text,
                 "the trailer rubric line; determinative entities render in ORACC-style braces"
  end

  def test_parses_the_catalogue_without_sibling_and_with_its_crossrefs
    document = parse(CATALOGUE)
    assert_equal 62, document.passages.size
    assert_equal "lugal-me-en cag4-ta", document.passages.first.text
    assert_includes document.metadata["related"], "urn:nabu:etcsl:1.8.2.1",
                    "the catalogue's incipit xrefs mint the concordance edges"
    assert_equal 46, document.metadata["related"].size, "46 unique xref targets, no self-loop"
  end

  # -- translation siblings ---------------------------------------------------

  def test_parses_the_lugalbanda_translation_as_en_sibling
    document = parse("#{LUGALBANDA}-en")
    assert_equal "eng", document.language
    assert_equal "Lugalbanda in the mountain cave -- an English prose translation", document.title
    assert_equal "translation", document.metadata["kind"]

    passages = document.passages
    assert_equal 3, passages.size, "p1-p3 carry prose; div1 B's gap-only p35 is skipped honestly"
    first = passages.first
    assert_equal "#{LUGALBANDA}-en:p1", first.urn
    assert first.text.start_with?("When in ancient days heaven was separated from earth,")
    assert_equal "1-19", first.annotations["lines"], "the upstream line-range of the paragraph"
    assert_equal "A.1", first.annotations["corresp"], "the anchor line in the composite"
    refute_match(/i\.e\./, passages[2].text, "footnote apparatus (note elements) never leaks into prose")
  end

  def test_translation_entities_decode_in_english_prose
    document = parse("#{ADAB}-en")
    assert_equal ["…… august divine powers ……. May …… prolong …… for Šu-ilīšu.".unicode_normalize(:nfc),
                  "Its uru.", "An adab of ……."],
                 document.passages.map(&:text)
  end

  # -- store round-trip -------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 5, first.added
    assert_equal 0, first.errored
    assert_equal 89, db[:passages].count, "62 + 17 + 4 composite lines, 3 + 3 translation paragraphs"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 5, second.skipped, "a byte-identical reload skips every document"
    assert_equal 89, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  end

  # THE TIER PIN: ETCSL's lemmatization is scholarly hand-curation (upstream
  # readme: "each word form … has been assigned to a lexeme which is
  # specified by a citation form, word class information and basic English
  # translation") — the registry default GOLD tier, asserted end to end.
  def test_lemma_rows_index_as_gold_tier
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext, lemma_tiers: {})
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
    refute_equal 0, rows.count, "the fixtures carry lemmatized tokens"
    assert_equal ["gold"], rows.select_map(:tier).uniq
    assert_equal ["sux"], rows.select_map(:language).uniq, "only composite lines feed the lemma index"
    assert rows.where(lemma_raw: "kece2").any?, "the A.2 damage-split lemma is findable"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_pins_the_zip_sha_and_unpacks_the_single_root_tree
    body = zip_body
    stub_zip(body)
    Dir.mktmpdir do |work|
      report = Nabu::Adapters::Etcsl.new(pin: Digest::SHA256.hexdigest(body)).fetch(work)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert File.file?(File.join(work, "transliterations", "c.1.8.2.1.xml")),
             "the zip's single top-level etcsl/ dir maps onto the workdir (ZipFetch tree_root)"
      assert_equal 5, adapter.discover(work).to_a.size
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_pin
    stub_zip(zip_body)
    Dir.mktmpdir do |work|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(work) }
      assert_match(/sha256/, error.message)
      assert_match(/#{Nabu::Adapters::Etcsl::ZIP_SHA256[0, 12]}/, error.message)
      refute File.exist?(File.join(work, "transliterations")), "a refused fetch leaves the tree untouched"
    end
  end

  def test_fetch_wraps_http_failures_as_fetch_errors
    stub_request(:get, Nabu::Adapters::Etcsl::ZIP_URL).to_return(status: 503)
    Dir.mktmpdir do |work|
      assert_raises(Nabu::FetchError) { adapter.fetch(work) }
    end
  end

  private

  def parse(urn)
    ref = adapter.discover(workdir).to_a.find { |r| r.id == urn } || flunk("no ref #{urn}")
    adapter.parse(ref)
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "etcsl", name: "ETCSL", adapter_class: "Nabu::Adapters::Etcsl",
      license_class: "nc"
    )
  end

  # A real zip of the fixture tree under the upstream's single top-level
  # etcsl/ dir (the shape ZipFetch's tree_root collapses).
  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      root = File.join(dir, "etcsl")
      FileUtils.mkdir_p(root)
      %w[transliterations translations].each do |sub|
        FileUtils.cp_r(File.join(workdir, sub), File.join(root, sub))
      end
      zip = File.join(dir, "etcsl.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-qr", zip, "etcsl") }
      File.binread(zip)
    end
  end

  def stub_zip(body)
    stub_request(:get, Nabu::Adapters::Etcsl::ZIP_URL)
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Thu, 02 Nov 2017 15:12:00 GMT" })
  end
end
