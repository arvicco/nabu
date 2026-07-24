# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Glaux (P44-1): GLAUx — "the Greek Language Automated"
# (Keersmaekers) — ~20M tokens of Ancient Greek automatically annotated for
# morphology, syntax, lemmas, animacy and word senses (AGDT guidelines). The
# analysis-side complement to the held Perseus/First1K editions. Fixture: two
# whole real works from github.com/alekkeersmaekers/glaux (2026-07-24) plus a
# trimmed real metadata.txt carrying the license census's four honest cases.
#
# THE SILVER TIER: every sentence carries analysis="auto" (machine output), so
# sources.yml registers `lemma_tier: silver` and every count renders labeled.
#
# THE D44-a CENSUS: dominant class attribution (CC BY-SA); a 72/1,421 (5.1%)
# restrictive slice — NC source texts OR PROIEL/Gorman NC manual annotation —
# carries a per-document license_override: nc so filters never over-share.
class GlauxTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  EPIGRAM_URN = "urn:nabu:glaux:0003-002"
  WORK_URN = "urn:nabu:glaux:0004-002"
  # struct_id is GLAUx's global sentence key — the passage urn's tail.
  EPIGRAM_S1 = "urn:nabu:glaux:0003-002:27421"

  def conformance_adapter = Nabu::Adapters::Glaux.new

  def conformance_workdir = Nabu::TestSupport.fixtures("glaux")

  def conformance_expected_source_id = "glaux"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_xml_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [EPIGRAM_URN, WORK_URN], refs.map(&:id),
                 "one document per xml/<stem>.xml, urn urn:nabu:glaux:<stem>, sorted"
    assert(refs.all? { |ref| ref.source_id == "glaux" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  # -- parse (the epigram, a complete small work) -----------------------------

  def test_parses_the_epigram_at_sentence_grain_with_the_struct_id_urn
    document = adapter.parse(ref_for(EPIGRAM_URN))
    assert_equal "grc", document.language
    assert_equal 4, document.count, "the epigram has 4 sentences"
    first = document.first
    assert_equal EPIGRAM_S1, first.urn, "passage urn = <doc>:<struct_id>, not the 1..n ordinal"
    assert_equal 0, first.sequence
  end

  def test_text_reassembles_forms_space_separated_with_punctuation_glued_left
    first = adapter.parse(ref_for(EPIGRAM_URN)).first
    assert_equal "μνῆμα μὲν Ἑλλὰς ἅπασ’ Εὐριπίδου·", first.text,
                 "word forms space-joined; the ano teleia (postag u) glues left, no space before"
  end

  def test_lemma_and_morph_annotations_ride_the_token_lane
    tokens = adapter.parse(ref_for(EPIGRAM_URN)).first.annotations.fetch("tokens")
    mnema = tokens.find { |t| t["form"] == "μνῆμα" } || flunk("μνῆμα token missing")
    assert_equal "μνῆμα", mnema["lemma"], "the LEMMA rides into annotations (feeds search --lemma)"
    assert_equal "n-s---nn-", mnema["postag"], "the AGDT 9-place postag rides verbatim on the token"
    assert_equal "concrete", mnema["animacy"], "the animacy semantic layer rides"
    assert_equal "grave.n.02", mnema["sense"], "the WordNet sense layer rides"
    assert_equal "SBJ", mnema["relation"]
  end

  def test_analysis_attribute_rides_as_the_tier_signal
    annotations = adapter.parse(ref_for(EPIGRAM_URN)).first.annotations
    assert_equal "auto", annotations["analysis"],
                 "the per-sentence analysis signal is recorded (silver honesty; future gold split)"
  end

  def test_citation_rides_from_div_book_and_div_chapter
    annotations = adapter.parse(ref_for(EPIGRAM_URN)).first.annotations
    assert_equal "7", annotations["book"]
    assert_equal "7.45", annotations["chapter"]
    assert_equal "7.45", annotations["citation"], "the most specific div is the citation"
  end

  # -- the artifacts: elliptic reconstruction + punctuation --------------------

  def test_elliptic_tokens_ride_the_tree_but_never_the_text_or_lemma_lane
    first = adapter.parse(ref_for(EPIGRAM_URN)).first
    elliptic = first.annotations.fetch("tokens").find { |t| t["artificial"] == "elliptic" }
    refute_nil elliptic, "the elliptic PRED node is kept — the dependency tree needs it"
    assert_equal "E", elliptic["form"]
    refute elliptic.key?("lemma"),
           "an elliptic reconstruction carries no lemma — the silver index mints no bogus 'e'"
    refute_includes first.text, "E", "the artificial token contributes nothing to the surface"
  end

  def test_punctuation_tokens_carry_no_lemma
    tokens = adapter.parse(ref_for(EPIGRAM_URN)).first.annotations.fetch("tokens")
    punct = tokens.find { |t| t["form"] == "·" } || flunk("· token missing")
    assert_equal "AuxK", punct["relation"]
    refute punct.key?("lemma"), "punctuation is not a dictionary form — no lemma row"
  end

  # -- NFD → NFC at the boundary (regression on real offending bytes) ----------

  # GLAUx is Unicode-NFD upstream: μνῆμα arrives as μ ν η U+0342(perispomeni)
  # μ α. The adapter NFC-normalizes at the boundary → μ ν U+1FC6 μ α. grc is
  # NOT on the NFC-exempt list, so both text AND lemma collapse.
  def test_nfd_source_is_nfc_normalized_at_the_boundary
    first = adapter.parse(ref_for(EPIGRAM_URN)).first
    refute_includes first.text, "͂", "no bare combining perispomeni survives"
    assert_includes first.text, "ῆ", "η+perispomeni collapses to the precomposed ῆ"
    assert_equal first.text, first.text.unicode_normalize(:nfc), "the whole passage is NFC"
    lemma = first.annotations.fetch("tokens").first["lemma"]
    assert_equal lemma, lemma.unicode_normalize(:nfc), "lemmas are NFC too"
  end

  def test_the_larger_work_parses_whole
    document = adapter.parse(ref_for(WORK_URN))
    assert_equal 84, document.count, "0004-002 carries 84 sentences"
    document.each do |passage|
      refute_empty passage.text
      assert_equal passage.text, passage.text.unicode_normalize(:nfc)
    end
  end

  # -- the D44-a license census / per-document override ------------------------

  def test_license_class_for_is_the_census_resolution
    glaux = Nabu::Adapters::Glaux
    assert_equal "nc", glaux.license_class_for(source_license: "CC BY-NC-SA 4.0", annotation: "NA"),
                 "an NC source text needs nc"
    assert_equal "nc", glaux.license_class_for(source_license: "CC BY-SA 4.0", annotation: "PROIEL"),
                 "a BY-SA text with PROIEL (CC BY-NC-SA 3.0) manual annotation needs nc"
    assert_equal "nc", glaux.license_class_for(
      source_license: "CC BY-SA 4.0",
      annotation: "Vanessa Gorman's Ancient Greek Prose Dependency Treebanks"
    ), "a BY-SA text with Gorman (CC BY-NC-SA 4.0) manual annotation needs nc"
    assert_nil glaux.license_class_for(source_license: "CC BY-SA 4.0", annotation: "NA"),
               "a plain BY-SA text inherits the source's attribution class (no override)"
  end

  def test_license_index_resolves_every_metadata_row
    index = adapter.license_index(workdir)
    assert_nil index["0003-002"], "BY-SA, no manual annotation → inherit attribution"
    assert_nil index["0004-002"]
    assert_equal "nc", index["0068-001"], "CC BY-NC-SA 4.0 source text"
    assert_equal "nc", index["0016-001"], "PROIEL-annotated (NC annotation)"
    assert_equal "nc", index["0028-001"], "Gorman-annotated (NC annotation)"
  end

  def test_by_sa_documents_carry_no_override_and_inherit_attribution
    ref = ref_for(EPIGRAM_URN)
    refute ref.metadata.key?("license_class"),
           "a BY-SA doc rides no per-document class — it inherits the source attribution"
    assert_nil adapter.parse(ref).license_override,
               "the Document's license_override stays nil for the attribution majority"
  end

  def test_document_metadata_journals_the_verbatim_source_license
    metadata = adapter.parse(ref_for(EPIGRAM_URN)).metadata
    assert_equal "CC BY-SA 4.0", metadata["source_license"], "the per-text license rides verbatim"
    assert_equal "Perseus", metadata["source"]
  end

  # -- store: idempotent load + the silver tier end to end ---------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 2, first.added
    assert_equal 0, first.errored
    assert_equal 88, db[:passages].count, "4 epigram + 84 work sentences"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 2, second.skipped, "a byte-identical reload skips every document"
    assert_equal 88, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # THE TIER PIN: GLAUx is registered `lemma_tier: silver` — its lemma rows
  # land as tier "silver" and never count as gold anywhere.
  def test_lemma_rows_index_as_silver_tier
    db, fulltext = indexed_store
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
    refute_equal 0, rows.count, "the fixture carries lemmatized tokens"
    assert_equal ["silver"], rows.select_map(:tier).uniq, "every GLAUx lemma row is silver"
    assert_equal ["grc"], rows.select_map(:language).uniq
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  def test_lemma_search_labels_silver_hits
    db, fulltext = indexed_store
    search = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext)
    results = search.run("μνῆμα")
    assert_equal [EPIGRAM_S1], results.map(&:urn), "the automatic lemma layer answers dictionary search"
    assert_equal ["silver"], results.map(&:tier), "the hit is labeled silver, never a bare number"
    assert_empty search.run("μνῆμα", gold_only: true), "--gold-only excludes the automatic layer"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch (local git only, no network) --------------------------------------

  def test_fetch_sparse_clones_only_the_xml_cone
    Dir.mktmpdir("nabu-glaux-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      glaux = adapter
      glaux.define_singleton_method(:repo_url) { upstream }
      report = glaux.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "xml", "0003-002.xml")), "the annotation cone materializes"
      assert File.file?(File.join(work, "metadata.txt")), "the license census file is in the cone"
      refute File.exist?(File.join(work, "glaux-nlp")),
             "outside-cone paths (the nlp code tree) must not materialize"
      refute_empty glaux.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "glaux", name: "GLAUx", adapter_class: "Nabu::Adapters::Glaux",
      license_class: "attribution"
    )
  end

  def indexed_store
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                  lemma_tiers: { "glaux" => "silver" })
    [db, fulltext]
  end

  # A local upstream repo with the real cone (fixture bytes) plus outside-cone
  # ballast the sparse fetch must not materialize.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    FileUtils.cp_r(File.join(workdir, "xml"), upstream)
    FileUtils.cp(File.join(workdir, "metadata.txt"), File.join(upstream, "metadata.txt"))
    File.write(File.join(upstream, "README.md"), "repo readme (in the cone)")
    FileUtils.mkdir_p(File.join(upstream, "glaux-nlp"))
    File.write(File.join(upstream, "glaux-nlp", "train.py"), "outside the cone")
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
