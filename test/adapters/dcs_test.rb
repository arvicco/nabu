# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::Adapters::Dcs (P26-0): the Digital Corpus of Sanskrit — 15,900
# gold-annotated CoNLL-U chapter files / 270 texts in OliverHellwig/sanskrit
# under dcs/data/conllu/ (844 MB; CC BY 4.0 verbatim in both data readmes).
# One document per chapter file (the corpus's own unit), one passage per
# sentence, urns minted from upstream's permanent numeric ids
# (urn:nabu:dcs:<textId>:<chapterId>:<sent_id>).
#
# THE GOLD GATE: lookup/chapter-info.xml machine-declares
# <layer type="gold">lexicon</layer> for every chapter ("The analysis of each
# string has been verified by one annotator") — the adapter's gold claim rides
# that declaration, never prose: an undeclared or non-gold chapter quarantines,
# and the automatic .conllu_parsed siblings are never even discovered.
#
# DEDUP PIN (no dedup wanted): UD's sanskrit-vedic treebank is the same
# Hellwig Vedic material at a different grain (UD conversion there, native DCS
# chapters here) — two honest witnesses, the MW-beside-kaikki precedent; the
# UD dedup guard exists for RE-EXPORTS of already-synced sources, which this
# is not. Pinned here so nobody "fixes" the overlap later (see backlog P26-0).
class DcsTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  AU_URN = "urn:nabu:dcs:421:8816"
  SU_AMSA_URN = "urn:nabu:dcs:5:3363"
  SU_KANTHA_URN = "urn:nabu:dcs:5:3656"

  def conformance_adapter
    Nabu::Adapters::Dcs.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("dcs")
  end

  def conformance_expected_source_id
    "dcs"
  end

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_chapter_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [AU_URN, SU_AMSA_URN, SU_KANTHA_URN], refs.map(&:id),
                 "one document per chapter file, urn urn:nabu:dcs:<textId>:<chapterId>, sorted"
  end

  def test_discover_never_yields_the_automatic_conllu_parsed_siblings
    refs = adapter.discover(workdir).to_a
    assert refs.none? { |ref| ref.path.end_with?(".conllu_parsed") },
           "the .conllu_parsed automatic layers (7,227 upstream) must never be discovered"
    assert_equal 3, refs.size, "the fixture's parsed sibling adds no ref"
  end

  # -- parse ------------------------------------------------------------------

  def test_parses_a_vedic_treebank_chapter_with_gold_annotations
    document = adapter.parse(ref_for(AU_URN))
    assert_equal "san", document.language
    assert_equal "Aitareyopaniṣad — AU, 1, 1", document.title
    assert_equal 35, document.count, "the fixture chapter has 35 sentence blocks"
    first = document.first
    assert_equal "#{AU_URN}:556276_1", first.urn, "passage citation = the upstream sent_id"
    assert_equal "ātmā vai idam ekaḥ eva agre āsīt na anyat kiṃcana miṣat", first.text
    lemmas = first.annotations.fetch("tokens").map { |token| token["lemma"] }
    assert_includes lemmas, "ātman", "the gold LEMMA column rides into annotations"
    heads = first.annotations.fetch("tokens").filter_map { |t| t["head"] }
    refute_empty heads, "Vedic-Treebank chapters carry the dependency tree (HEAD filled, not `_`)"
    assert_includes heads, "0", "the root token points at 0"
  end

  def test_document_metadata_carries_the_chapter_info_layers
    document = adapter.parse(ref_for(AU_URN))
    metadata = document.metadata
    assert_equal "Aitareyopaniṣad", metadata.fetch("text")
    assert_equal "AU, 1, 1", metadata.fetch("chapter")
    assert_equal "421", metadata.fetch("text_id")
    assert_equal "8816", metadata.fetch("chapter_id")
    assert_equal %w[morpho-syntax lexicon syntax], metadata.fetch("gold_layers"),
                 "the machine-read gold declaration is journaled on the document"
    assert_equal "prose", metadata.dig("details", "register"), "the Vedic details block rides along"
    assert_equal "RV", metadata.dig("details", "veda")
    assert_equal({ "value" => "prose", "raw" => "prose" }, metadata.dig("facets", "register"))
  end

  def test_parses_a_plain_gold_chapter_with_mwt_compounds_and_numeric_sent_ids
    document = adapter.parse(ref_for(SU_KANTHA_URN))
    assert_equal 6, document.count, "the trimmed fixture keeps 6 blocks"
    assert_equal "#{SU_KANTHA_URN}:10902", document.first.urn, "plain numeric sent_ids stay verbatim"
    refute_includes document.metadata.fetch("gold_layers"), "syntax",
                    "a chapter outside the Vedic Treebank claims no gold syntax"
    compound = document.flat_map { |p| p.annotations.fetch("tokens") }
                       .find { |token| token["id"] == "5-6" && token["form"] == "kaṇṭhagrīvaṃ" }
    refute_nil compound, "MWT compound ranges (kaṇṭhagrīvaṃ = kaṇṭha + grīva) survive the parse"
  end

  # -- the gold gate ----------------------------------------------------------

  def test_a_chapter_absent_from_chapter_info_quarantines
    with_edited_workdir(drop_entry: "Aitareyopaniṣad-0000") do |dir|
      refs = adapter.discover(dir).to_a
      ref = refs.find { |r| r.path.include?("Aitareyopaniṣad") } || flunk("undeclared ref missing")
      assert_match(/undeclared/, ref.id, "an undeclared chapter cannot mint the id urn")
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/chapter-info\.xml/, error.message)
      assert_match(/gold/, error.message)
    end
  end

  def test_a_chapter_without_the_gold_lexicon_layer_quarantines
    with_edited_workdir(degold: "Aitareyopaniṣad-0000") do |dir|
      ref = adapter.discover(dir).to_a.find { |r| r.id == AU_URN } || flunk("AU ref missing")
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/gold.*lexicon/, error.message)
      assert_match(/machine-readable/, error.message)
    end
  end

  # -- store: idempotent double-load + the tier/join pins ----------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    loader = Nabu::Store::Loader.new(db: db, source: source)
    first = loader.load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 45, db[:passages].count, "35 + 4 + 6 sentence blocks"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 3, db[:documents].count
    assert_equal 45, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # DCS is a GOLD source (absent from any lemma_tiers map — the P26-0
  # absent-is-gold contract), so its lemma rows land tier "gold" and count as
  # attested_count, never silver.
  def test_lemma_rows_index_as_gold_tier
    db, fulltext = indexed_store
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "kantha")
    assert_equal 2, rows.count, "kaṇṭha is attested in 2 fixture passages"
    assert_equal ["gold"], rows.select_map(:tier).uniq
    assert_equal ["san"], rows.select_map(:language).uniq
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # THE FOLD-JOIN PIN (scout-verified 7/7, 2026-07-16/17): a DCS gold lemma
  # lights the attested count of a Sanskrit reflex edge through the EXISTING
  # ReflexViews path — no new fold rules. The reflex row here is minted with
  # the same Normalize.search_form call the starling piet parser uses for its
  # IND stems (kaṇṭha, śīghrá), pinning fold("kaṇṭha")="kantha" and
  # fold("śīghrá")="sighra" — IAST joins IAST across shelves.
  def test_dcs_lemmas_light_reflex_attested_counts_through_reflex_views
    db, fulltext = indexed_store
    assert_equal "kantha", Nabu::Normalize.search_form("kaṇṭha", language: "san")
    assert_equal "sighra", Nabu::Normalize.search_form("śīghrá", language: "san")

    entry_id = seed_reflex_entry(db, [%w[kaṇṭha san], %w[śīghrá san]])
    views = Nabu::Query::ReflexViews.new(catalog: db, fulltext: fulltext).for_entry(entry_id)
    kantha = views.find { |v| v.word == "kaṇṭha" } || flunk("kaṇṭha view missing")
    assert_equal 2, kantha.attested_count, "2 gold DCS passages attest kaṇṭha"
    assert_nil kantha.silver_count, "gold rows never masquerade as silver"
    sighra = views.find { |v| v.word == "śīghrá" } || flunk("śīghrá view missing")
    assert_equal 1, sighra.attested_count, "the accented piet stem joins via the same fold"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # THE MW HEADWORD JOIN (the other half of the scout's 7/7): DCS lemma aṃśa
  # folds to "amsa", exactly the fold of MW's SLP1 key1 aMSa after the
  # Slp1→IAST transcode — so a DCS lemma hit carries the MW gloss through the
  # existing P11-4 gloss bridge, end to end on real fixtures of both sources.
  def test_dcs_lemma_hit_carries_the_mw_gloss_through_the_fold_join
    db, fulltext = indexed_store
    mw_source = Nabu::Store::Source.create(
      slug: "mw", name: "Monier-Williams", adapter_class: "Nabu::Adapters::Mw", license_class: "nc"
    )
    Nabu::Store::DictionaryLoader.new(db: db, source: mw_source)
                                 .load_from(Nabu::Adapters::Mw.new, workdir: Nabu::TestSupport.fixtures("mw"))

    results = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext).run("aṃśa")
    assert_equal ["#{SU_AMSA_URN}:2612"], results.map(&:urn), "the aṃśa block is the one hit"
    assert_equal "gold", results.first.tier
    refute_nil results.first.gloss, "the MW entry glosses the DCS hit — the fold join is live"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch (local git only, no network) --------------------------------------

  def test_fetch_sparse_clones_only_the_conllu_cone
    Dir.mktmpdir("nabu-dcs-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      dcs = adapter
      dcs.define_singleton_method(:repo_url) { upstream }
      report = dcs.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "dcs", "data", "conllu", "readme.md"))
      assert File.file?(File.join(work, "dcs", "data", "readme.md")),
             "the parent readme (second license grant) is in the cone"
      refute File.exist?(File.join(work, "papers")),
             "outside-cone paths (papers, other data dirs) must not materialize"
      refute_empty dcs.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "dcs", name: "DCS", adapter_class: "Nabu::Adapters::Dcs", license_class: "attribution"
    )
  end

  def indexed_store
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
    [db, fulltext]
  end

  # A reconstruction-shaped entry with san reflex edges, folded EXACTLY as the
  # starling piet parser folds its IND stems (Normalize.search_form, language
  # san) — the existing crosswalk row shape, no new machinery.
  def seed_reflex_entry(db, words)
    recon = Nabu::Store::Source.create(
      slug: "recon", name: "Recon", adapter_class: "TestAdapter", license_class: "attribution"
    )
    dictionary = Nabu::Store::Dictionary.create(
      source_id: recon.id, slug: "recon-piet", title: "PIE etymology", language: "ine-pro"
    )
    entry = Nabu::Store::DictionaryEntry.create(
      dictionary_id: dictionary.id, urn: "urn:nabu:dict:recon-piet:test", entry_id: "test",
      key_raw: "*test-", headword: "*test-", headword_folded: "test", body: "b",
      content_sha256: "x"
    )
    words.each_with_index do |(word, language), seq|
      db[:dictionary_reflexes].insert(
        dictionary_entry_id: entry.id, seq: seq, lang_code: language, language: language,
        word: word, word_folded: Nabu::Normalize.search_form(word, language: language)
      )
    end
    entry.id
  end

  # Copy the fixture into a tmpdir and surgically edit chapter-info.xml —
  # real upstream data throughout; only the DECLARATION changes, which is
  # exactly what the gate must react to.
  def with_edited_workdir(drop_entry: nil, degold: nil)
    Dir.mktmpdir("nabu-dcs") do |dir|
      FileUtils.cp_r(File.join(workdir, "."), dir)
      info_path = File.join(dir, "dcs", "data", "conllu", "lookup", "chapter-info.xml")
      xml = File.read(info_path)
      if drop_entry
        xml = xml.gsub(%r{<chapter>(?:(?!</chapter>).)*#{Regexp.escape(drop_entry)}(?:(?!</chapter>).)*</chapter>}m, "")
      end
      if degold
        entry = xml[%r{<chapter>(?:(?!</chapter>).)*#{Regexp.escape(degold)}(?:(?!</chapter>).)*</chapter>}m]
        xml = xml.sub(entry, entry.gsub('<layer type="gold">lexicon</layer>', ""))
      end
      File.write(info_path, xml)
      yield dir
    end
  end

  # A local upstream repo with the real layout: the conllu cone (fixture
  # bytes) plus outside-cone ballast the sparse fetch must not materialize.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    FileUtils.cp_r(File.join(workdir, "dcs"), upstream)
    FileUtils.mkdir_p(File.join(upstream, "papers"))
    File.write(File.join(upstream, "papers", "big.pdf"), "outside the cone")
    File.write(File.join(upstream, "README.md"), "repo root readme (outside the cone)")
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
