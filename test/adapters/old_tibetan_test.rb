# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::OldTibetan (P48-3): tibetan-nlp/old-tibetan-corpus — the
# Old Tibetan Annals (OTA, OTDO Pt_1288) and Old Tibetan Chronicle (OTC,
# Pt_1287), Unicode-converted, gold-segmented and POS-tagged with
# verb-argument dependencies (Faggionato/Garrett/Meelen, hand-corrected in
# BRAT), plus Dotson 2009's aligned English translation of the Annals as
# `# text_en` — the `-en` parallel sibling (the elephantine mold). A thin
# composition of the shared ConlluParser (10 clean columns, mandatory
# sent_id + text — censused, the digiliblt counter-case does not apply).
#
# LANGUAGE RULING (P48-3, pinned below): both texts are `otb` (ISO 639-3
# Old Tibetan — Dunhuang-era orthography with the reversed gi-gu), never
# `xct` (the soas-tibetan classical lane) nor `bo` (kaikki's modern
# dictionary shelf).
#
# THE SILVER LEMMA TIER: the LEMMA column is the ot2ct-normalized Classical
# Tibetan citation form (`√`-marked: ནས་√cv) — a pipeline product; the
# upstream README's hand-correction claim covers segmentation, POS and the
# dependency layer, NOT the lemmas. Registry `lemma_tier: silver`, every
# hit labeled (the cdli/ebl defensive-honesty precedent).
class OldTibetanTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("old-tibetan")

  ANNALS_URN = "urn:nabu:old-tibetan:otannals"
  ANNALS_EN_URN = "urn:nabu:old-tibetan:otannals-en"
  CHRONICLE_URN = "urn:nabu:old-tibetan:otchronicle"
  CHRONICLE_EN_URN = "urn:nabu:old-tibetan:otchronicle-en"

  # The registry posture: translations: true (the -en siblings ride).
  def conformance_adapter = Nabu::Adapters::OldTibetan.new(translations: true)

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "old-tibetan"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_originals_and_en_siblings_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [ANNALS_URN, ANNALS_EN_URN, CHRONICLE_URN, CHRONICLE_EN_URN],
                 refs.map(&:id)
    assert_equal "translation", refs[1].metadata["kind"]
    assert_nil refs[0].metadata["kind"]
  end

  def test_without_the_translations_flag_only_originals_are_discovered
    refs = Nabu::Adapters::OldTibetan.new.discover(workdir).to_a
    assert_equal [ANNALS_URN, CHRONICLE_URN], refs.map(&:id)
  end

  def test_the_legacy_archive_exports_are_a_censused_discovery_skip
    refute_includes adapter.discover(workdir).to_a.map(&:path),
                    File.join(workdir, "archive", "otannals-normalized.conllu"),
                    "archive/*.conllu would double-load the texts in the wrong orthography"
    assert_equal 1, adapter.discovery_skips(workdir).skipped_by_rule
  end

  # -- parse: the otb originals -----------------------------------------------

  def test_the_annals_parse_as_otb_with_stripped_citations
    document = adapter.parse(ref_for(ANNALS_URN))
    assert_equal "otb", document.language,
                 "Old Tibetan is otb — not xct (classical), not bo (modern)"
    assert_equal "Old Tibetan Annals", document.title
    assert_equal 5, document.count, "trimmed fixture: the real first 5 of 546 blocks"
    first = document.first
    assert_equal "#{ANNALS_URN}:000:T55", first.urn,
                 "the citation hook strips the redundant otannals: sent_id prefix " \
                 "(the damaskini mold)"
    assert first.text.start_with?("[---]་འཁུས་ནས།"),
           "lacunose Dunhuang text rides verbatim, brackets and all"
  end

  def test_gold_pos_and_silver_lemmas_ride_the_tokens
    tokens = adapter.parse(ref_for(ANNALS_URN)).first.annotations["tokens"]
    treacherous = tokens.find { |token| token["form"] == "འཁུས་" }
    assert_equal "VERB", treacherous["upos"]
    assert_equal "འཁུ་", treacherous["lemma"], "the ot2ct-normalized citation form"
    assert_equal "Tense=Past", treacherous["feats"]
    marked = tokens.find { |token| token["form"] == "ནས" }
    assert_equal "ནས་√cv", marked["lemma"], "√-marked lemmas ride verbatim (canonical)"
  end

  def test_the_verb_argument_dependency_layer_survives
    tokens = adapter.parse(ref_for(ANNALS_URN)).first.annotations["tokens"]
    lvc = tokens.find { |token| token["deprel"] == "arg2:lvc" }
    assert_equal "གློ་བ་", lvc["form"]
    assert_equal "14", lvc["head"], "the hand-annotated verb-argument edge"
  end

  def test_the_mwt_range_line_rides_as_form_only
    tokens = adapter.parse(ref_for(ANNALS_URN)).first.annotations["tokens"]
    mwt = tokens.find { |token| token["id"] == "26-27" }
    assert_equal "བཀུམོ", mwt["form"],
                 "the orthographic fusion; its members carry the analysis"
    refute mwt.key?("lemma")
  end

  def test_the_english_lane_stays_out_of_the_original_annotations
    document = adapter.parse(ref_for(ANNALS_URN))
    refute_match(/treacherous/, JSON.generate(document.first.annotations),
                 "text_en belongs to the -en sibling, never the otb passage")
  end

  def test_the_chronicle_parses_as_otb_including_the_punctuation_opening
    document = adapter.parse(ref_for(CHRONICLE_URN))
    assert_equal "otb", document.language
    assert_equal "Old Tibetan Chronicle", document.title
    assert_equal 3, document.count
    assert_equal "#{CHRONICLE_URN}:001:T1", document.first.urn
    assert_equal "༆།༔།", document.first.text
  end

  # -- parse: the -en Dotson sibling ------------------------------------------

  def test_the_annals_en_sibling_pairs_citations_with_the_original
    document = adapter.parse(ref_for(ANNALS_EN_URN))
    assert_equal "eng", document.language
    assert_equal "translation", document.metadata["kind"]
    assert_equal "Brandon Dotson", document.metadata["translator"]
    assert_equal 5, document.count, "every fixture Annals block carries text_en"
    original = adapter.parse(ref_for(ANNALS_URN))
    assert_equal original.map { |passage| passage.urn.delete_prefix(ANNALS_URN) },
                 document.map { |passage| passage.urn.delete_prefix(ANNALS_EN_URN) },
                 "identical citation suffixes — what show --parallel aligns on"
    assert_match(/became treacherous/, document.first.text, "Dotson 2009, real bytes")
  end

  def test_the_chronicle_en_sibling_skips_by_rule
    error = assert_raises(Nabu::DocumentSkipped) { adapter.parse(ref_for(CHRONICLE_EN_URN)) }
    assert_match(/text_en/, error.message)
  end

  # -- store: idempotent load + the silver tier end to end --------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added, "otannals + otannals-en + otchronicle (chronicle-en skips)"
    assert_equal 0, first.errored
    assert_equal 13, db[:passages].count, "5 otb + 5 eng + 3 otb"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped
    assert_equal 13, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  def test_lemma_rows_index_as_silver_tier_in_otb
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                  lemma_tiers: { "old-tibetan" => "silver" })
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
    refute_equal 0, rows.count
    assert_equal ["silver"], rows.select_map(:tier).uniq,
                 "pipeline-normalized lemmas never count as gold"
    assert_equal ["otb"], rows.select_map(:language).uniq,
                 "the eng sibling carries no tokens — no lemma rows leak from it"
    assert_includes rows.select_map(:lemma_raw), "འཁུ་"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch: whole-repo git clone (local git, no network) --------------------

  def test_fetch_clones_the_repo_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-old-tibetan-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      old_tibetan = adapter
      old_tibetan.define_singleton_method(:repo_url) { upstream }
      report = old_tibetan.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal [ANNALS_URN, ANNALS_EN_URN, CHRONICLE_URN, CHRONICLE_EN_URN],
                   old_tibetan.discover(work).to_a.map(&:id)
    end
  end

  # -- registry round-trip ----------------------------------------------------

  def test_registry_resolves_old_tibetan_with_the_full_posture
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["old-tibetan"]
    refute_nil entry, "old-tibetan must be registered in config/sources.yml"
    assert_equal "Nabu::Adapters::OldTibetan", entry.adapter_class_name
    refute entry.wired, "wired: false until the owner-fired first sync"
    assert_equal "manual", entry.sync_policy
    assert entry.translations, "the Dotson -en sibling is the registry posture"
    assert_equal ["-en"], entry.siblings
    assert_equal "silver", entry.lemma_tier
    assert_includes entry.axes, "tibetan"
    assert_equal "attribution", entry.manifest.license_class
    assert_match(/MIT/, entry.manifest.license,
                 "the GitHub MIT grant is the recorded license basis (the Zenodo twin " \
                 "says only 'Other (Open)')")
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "old-tibetan", name: "Old Tibetan Corpus",
      adapter_class: "Nabu::Adapters::OldTibetan", license_class: "attribution"
    )
  end

  # A local upstream shaped like tibetan-nlp/old-tibetan-corpus: conllu/ +
  # the archive/ legacy lane + LICENSE/README.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "conllu"))
    FileUtils.cp_r(Dir.glob(File.join(workdir, "conllu", "*")), File.join(upstream, "conllu"))
    FileUtils.mkdir_p(File.join(upstream, "archive"))
    FileUtils.cp_r(Dir.glob(File.join(workdir, "archive", "*")), File.join(upstream, "archive"))
    File.write(File.join(upstream, "LICENSE"), "MIT License\n\nCopyright (c) 2018 Tibetan NLP\n")
    File.write(File.join(upstream, "README.md"), "# Old Tibetan Corpus\n")
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
