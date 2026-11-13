# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# CLLG Freed Corpus — the TLG E canon as citeStructure TEI (Inria CLLG).
# Discovery walks the per-author metadata.xml catalog records and peeks each
# edition header for a declared citation tree; parse runs the cllg-tei
# family. Fixtures: trimmed real files, test/fixtures/cllg-freed/README.md.
class CllgFreedTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cllg-freed")

  ILIAD = "urn:cts:greekLit:tlg0012.tlg001.cllg-grc1"
  REPUBLIC = "urn:cts:greekLit:tlg0059.tlg030.cllg-grc1"
  CHRONICLE = "urn:cts:greekLit:tlg2738.tlg002.cllg-grc1"
  MNASEAS = "urn:cts:greekLit:tlg1514.tlg002.cllg-grc1"
  AESCHYLUS = "urn:cts:greekLit:tlg0085.tlg011.cllg-grc1"
  PSEUDO_CHRYSOSTOM = "urn:cts:greekLit:tlg2062.tlg473.cllg-grc1"
  AELIAN = "urn:cts:greekLit:tlg0545.tlg005.cllg-grc1"
  ATHANASIUS_SERAPION = "urn:cts:greekLit:tlg2035.tlg043.cllg-grc1"
  CITED = [ILIAD, REPUBLIC, CHRONICLE, MNASEAS, AESCHYLUS, PSEUDO_CHRYSOSTOM].freeze

  def conformance_adapter
    Nabu::Adapters::CllgFreed.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "cllg-freed"
  end

  def adapter
    @adapter ||= Nabu::Adapters::CllgFreed.new
  end

  def refs
    @refs ||= adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
  end

  def parsed(urn)
    adapter.parse(refs.fetch(urn))
  end

  # -- manifest ----------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::CllgFreed.manifest
    assert_equal "cllg-freed", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "https://gitlab.inria.fr/almanach/cllg/freed-corpus.git", manifest.upstream_url
    assert_equal "cllg-tei", manifest.parser_family
    assert_match(/CC0 1\.0/, manifest.license)
    assert_match(/CC-BY 4\.0/, manifest.license)
  end

  # -- discovery: every catalogued file that declares a citation tree ---------------

  def test_discover_yields_the_cited_editions_including_the_spuria_tree
    assert_equal CITED.sort, refs.keys.sort
    assert refs.fetch(PSEUDO_CHRYSOSTOM).path.include?("/spurious-and-dubia/cllg-spuria0001/")
  end

  # The 331 class: a file whose header declares no citeStructure at all.
  # Upstream's site counts them as "Without citeStructure" — a skip by rule,
  # counted and named, never a quarantine.
  def test_a_file_declaring_no_citation_tree_is_skipped_by_rule_at_discovery
    refute refs.key?(AELIAN)
    skips = adapter.discovery_skips(FIXTURES)
    assert_predicate skips, :clean?
    assert_equal 2, skips.skipped_by_rule, "1 uncited + 1 SC-overlap specimen"
    assert_match(%r{1 edition file declaring no citeStructure.*data/tlg0545/tlg005/tlg0545\.tlg005\.cllg-grc1\.xml},
                 skips.notes.join("\n"))
  end

  # The 4 class: an edition urn the CLLG Sources Chrétiennes corpus mints
  # too (same cllg-grc1 version id over a different text state). Freed
  # defers by rule — deterministically, whatever the sync or rebuild order —
  # so the catalog always holds the SC record and never flips winners.
  def test_an_edition_the_sc_corpus_also_mints_defers_to_sc_by_rule
    refute refs.key?(ATHANASIUS_SERAPION), "the SC-overlap specimen must not be discovered"
    skips = adapter.discovery_skips(FIXTURES)
    assert_predicate skips, :clean?
    assert_match(/1 edition also served by cllg-sc under the same version urn.*tlg2035\.tlg043\.cllg-grc1/,
                 skips.notes.join("\n"))
  end

  # The overlap is a closed census fact (full urn intersection of the two
  # repos, 2026-11-12): exactly these four, pinned so a registry drift on
  # either side surfaces as a test failure, not a load-order surprise.
  def test_the_sc_overlap_list_is_the_censused_intersection
    assert_equal %w[
      urn:cts:greekLit:tlg2017.tlg042.cllg-grc1
      urn:cts:greekLit:tlg2017.tlg079.cllg-grc1
      urn:cts:greekLit:tlg2035.tlg001.cllg-grc1
      urn:cts:greekLit:tlg2035.tlg043.cllg-grc1
    ].sort, Nabu::Adapters::CllgFreed::SC_OVERLAP.sort
  end

  # -- parse --------------------------------------------------------------------

  def test_every_document_is_greek_and_cites_its_default_tree
    iliad = parsed(ILIAD)
    assert_equal "grc", iliad.language
    assert_equal "Ilias", iliad.title
    assert_equal(%w[1.1 1.2 1.3 2.1 2.2], iliad.map { |passage| passage.urn.delete_prefix("#{ILIAD}:") })
    assert_equal(%w[327a 327b 327c], parsed(REPUBLIC).map { |passage| passage.urn.delete_prefix("#{REPUBLIC}:") })
  end

  # Aeschylus fr. 451s**,50 (Radt, a papyrus): line 2 is a lacuna alone and
  # line 3 a lone metrical sign (U+035C) — neither leaves searchable text, so
  # neither is a passage.
  def test_units_without_searchable_text_are_not_passages
    lines = parsed(AESCHYLUS).map { |passage| passage.urn.delete_prefix("#{AESCHYLUS}:") }
    assert_equal ["451s**,50.1", "451s**,50.4", "451s**,50.5"], lines
  end

  # -- the TLG canon mining (aggressive-mining law) -----------------------------------

  def test_the_tlg_canon_date_is_a_composition_envelope
    metadata = parsed(ILIAD).metadata
    assert_equal "c. 8 B.C.", metadata["tlg_date"]
    assert_equal({ "not_before" => -800, "not_after" => -701, "raw" => "c. 8 B.C.", "class" => "composition" },
                 metadata["date"])
    assert_equal "1931", metadata["edition_year"], "the edition year rides for the fallback"
    assert_equal ["Allen, T.W."], metadata["editors"]
    assert_equal "tlg0012.tlg001", metadata["tlg"]
    assert_match(/Ed\. Allen, T\.W\. Oxford: Clarendon Press, 1931/, metadata["description"])
  end

  def test_the_author_epithets_are_the_genre
    metadata = parsed(ILIAD).metadata
    assert_equal "Homerus Epic. Homer", metadata["author"]
    assert_equal ["Epic."], metadata["epithets"]
    assert_equal "Epic.", metadata["genre"]
    assert_equal "Scr. Eccl.", parsed(PSEUDO_CHRYSOSTOM).metadata["genre"]
    assert_nil parsed(CHRONICLE).metadata["genre"], "Chronographiae Anonymae carries no epithet"
  end

  def test_epithet_extraction_is_closed_and_skips_collection_sigla
    epithets = ->(label) { Nabu::Adapters::CllgFreed.epithets(label) }
    assert_equal ["Hist.", "Phil."], epithets.call("Chaeremon Hist. et Phil.")
    assert_equal ["Poeta", "Scr. Rerum Nat."], epithets.call("Manuel Philes Poeta et Scr. Rerum Nat.")
    assert_equal ["Gramm.", "Poeta"], epithets.call("Joannes Gramm. et Poeta")
    assert_empty epithets.call("Comica Adespota (Suppl. Com.)")
    assert_empty epithets.call("Pausaniae I Et Xerxis Epistulae")
  end

  def test_spuria_carry_their_attribution
    metadata = parsed(PSEUDO_CHRYSOSTOM).metadata
    assert metadata["dubia"]
    assert_equal "urn:cts:greekLit:tlg2062", metadata["spuria_of"]
    assert_equal "Pseudo-Chrysostomus", metadata["author_label"]
    assert_equal "Joannes Chrysostomus Scr. Eccl. John Chrysostom", metadata["author"]
  end

  def test_tlg_canon_dates_parse_the_century_notation
    date = ->(raw) { Nabu::Adapters::CllgFreed::TlgDate.parse(raw)&.slice("not_before", "not_after") }
    assert_equal({ "not_before" => 301, "not_after" => 500 }, date.call("c. A.D. 4-5"))
    assert_equal({ "not_before" => -500, "not_after" => -301 }, date.call("c. 5-4 B.C."))
    assert_equal({ "not_before" => -100, "not_after" => 100 }, date.call("c. 1 B.C.-A.D. 1"))
    assert_equal({ "not_before" => -300, "not_after" => 300 }, date.call("c. 3 B.C./A.D. 3"))
    assert_equal({ "not_before" => 101, "not_after" => 400 }, date.call("c. A.D. 2?/4"))
    assert_equal({ "not_before" => 101 }, date.call("c. p. A.D. 2"), "post: one open bound")
    assert_equal({ "not_after" => 200 }, date.call("c. a. A.D. 2"), "ante: one open bound")
    assert_equal({ "not_before" => -600, "not_after" => 300 }, date.call("c. p. 6 B.C. a. A.D. 3"))
    assert_nil date.call("Varia")
    assert_nil date.call("Incertum")
  end

  def test_every_epithet_folds_or_is_counted_unmapped
    kinds = Nabu::Kinds.load(classes_path: File.expand_path("../../config/kind_classes.yml", __dir__),
                             map_path: File.expand_path("../../config/kind_map.yml", __dir__))
    assert_equal ["literary/narrative/epic"], kinds.normalize("cllg-freed", "Epic.")
    assert_equal ["literary/drama"], kinds.normalize("cllg-freed", parsed(AESCHYLUS).metadata["genre"])
    assert_equal ["philosophy"], kinds.normalize("cllg-freed", "Phil."),
                 "the philosophy head ruled 2026-11-13 (unmapped before it)"
    assert_equal %w[historiography philosophy], kinds.normalize("cllg-freed", "Hist.|Phil.")
    assert_equal [Nabu::Kinds::UNMAPPED], kinds.normalize("cllg-freed", "Biogr."),
                 "the unmapped-by-design tail still counts honestly"
  end

  # -- store: idempotent load -----------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "cllg-freed", name: "CLLG Freed Corpus",
                                        adapter_class: "Nabu::Adapters::CllgFreed", license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 6, first.added
    assert_equal 0, first.errored
    passages = db[:passages].count
    assert_equal 5 + 3 + 3 + 4 + 3 + 2, passages

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 6, second.skipped, "a byte-identical reload skips every document"
    assert_equal passages, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch: the sparse cone (local git only, no network) ----------------------------

  def test_fetch_materializes_only_the_sparse_cone
    Dir.mktmpdir("nabu-cllg-freed-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.cp_r(FIXTURES, upstream)
      FileUtils.mkdir_p(File.join(upstream, "scripts", "out", "paren_clf"))
      File.write(File.join(upstream, "scripts", "out", "paren_clf", "weights.bin"), "classifier ballast")
      Nabu::Shell.run("git", "init", "-q", upstream)
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=test@test", "-c", "user.name=test",
                      "commit", "-q", "-m", "seed")
      freed = adapter
      freed.define_singleton_method(:repo_url) { upstream }
      work = File.join(root, "canonical")
      report = freed.fetch(work)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "cllg-freed.xml")), "the root catalog is in the cone"
      refute File.exist?(File.join(work, "scripts")), "the classifier ballast never materializes"
      assert_equal CITED.sort, freed.discover(work).map(&:id).sort
    end
  end
end
