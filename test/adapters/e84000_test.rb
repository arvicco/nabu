# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::E84000 (P48-2): 84000's English translations of the Tibetan
# canon (github.com/84000/data-tei) — the Kangyur's translation layer. 396
# published Kangyur TEI + 3 Tengyur publications; 560 + 3,366 placeholder
# stubs skip by rule (sibling placeholders/ dirs, censused). Document slugs
# are the texts' own Toh numbers (urn:nabu:e84000:toh846a) — the FROZEN
# crosswalk key to the derge-kangyur shelf (P48-6 alignment); passages mirror
# 84000's own published citation grain: one `milestone unit="chunk"` per
# numbered paragraph, s.1 / ac.1 / i.3 / 1.5 / c.1 labels (verified against
# the live Reading Room).
#
# LICENSE: CC BY-NC-ND 3.0, stated in the repo README → class nc (the TraCES
# BY-NC-ND precedent; MCP default-excluded). CAVEAT pinned below: the linked
# Terms_of_Use.md layers "data partnership" registration language for bulk
# external use — the README grant is the operative license (P47-s2,
# owner-acknowledged).
class E84000Test < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  TOH846A = "urn:nabu:e84000:toh846a"
  TOH539E = "urn:nabu:e84000:toh539e"
  TOH761 = "urn:nabu:e84000:toh761"
  TOH3156 = "urn:nabu:e84000:toh3156"

  def conformance_adapter = Nabu::Adapters::E84000.new

  def conformance_workdir = Nabu::TestSupport.fixtures("e84000")

  def conformance_expected_source_id = "e84000"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover: toh slugs from both cones, stubs and duplicates never ---------

  def test_discover_yields_toh_slugs_from_both_publication_cones
    refs = adapter.discover(workdir).to_a
    assert_equal [TOH3156, TOH539E, TOH761, TOH846A], refs.map(&:id),
                 "one ref per published text, slugged by its first Toh number, sorted; " \
                 "placeholders and the duplicate loser never become refs"
    assert(refs.all? { |ref| ref.source_id == "e84000" })
    assert_equal "tengyur", ref_for(TOH3156).metadata["collection"]
    assert_equal "kangyur", ref_for(TOH846A).metadata["collection"]
  end

  def test_discovery_skips_census_counts_stubs_and_duplicate_losers
    skips = adapter.discovery_skips(workdir)
    assert_equal 2, skips.skipped_by_rule,
                 "1 placeholder stub + 1 duplicate-pair loser skip by rule, censused"
    assert_equal 0, skips.unrecognized
  end

  def test_duplicate_pair_resolves_to_the_highest_edition_version
    ref = ref_for(TOH761)
    assert_equal "096-010_toh761-the_dharani_of_the_iron_beak.xml", ref.metadata["file"],
                 "upstream keeps two copies of the same publication (same UT id); " \
                 "the higher edition version wins deterministically"
    assert_equal "v 1.0.2 2025", adapter.parse(ref).metadata["edition"]
  end

  def test_part_publications_keep_their_part_suffix_but_expose_the_base_toh
    # Toh 1 and Toh 44 are published chapter-wise upstream (toh1-1 … toh44-45,
    # upstream's own bibl keys); the slug keeps the part, the base Toh number
    # rides toh_base for the P48-6 crosswalk join.
    assert_equal "toh1", Nabu::Adapters::E84000.toh_base("toh1-1")
    assert_equal "toh44", Nabu::Adapters::E84000.toh_base("toh44-45")
    assert_equal "toh846a", Nabu::Adapters::E84000.toh_base("toh846a"),
                 "letter suffixes are part of the Toh number itself, never stripped"
  end

  # -- the published citation grain (s. / ac. / i. / 1.N / c.) -----------------

  def test_toh846a_mirrors_the_reading_room_section_paragraph_grain
    document = adapter.parse(ref_for(TOH846A))
    assert_equal "en", document.language
    assert_equal "The Threefold Ritual", document.title
    expected = %w[s.1 ac.1 i.1 i.2 i.3 1.1 1.2 1.3 1.4 1.5]
    assert_equal expected.map { |ref| "#{TOH846A}:#{ref}" }, document.map(&:urn),
                 "one passage per chunk milestone, labeled exactly as the Reading Room numbers them"
  end

  def test_body_chunks_carry_the_reading_text
    document = adapter.parse(ref_for(TOH846A))
    first = document.find { |p| p.urn.end_with?(":1.1") }
    assert first.text.start_with?("Brahmā, great king Śakra, gods and nāgas,"),
           "verse lines join into their chunk; the empty folio ref contributes nothing"
    assert_equal "chunk", first.annotations["unit"]
    assert_equal "section", first.annotations["division"]
    assert_equal "UT22084-100-002-7", first.annotations["chunk_id"],
                 "the milestone xml:id (84000's global anchor) rides as provenance"
  end

  def test_endnote_subtrees_drop_from_the_reading_text
    document = adapter.parse(ref_for(TOH846A))
    i3 = document.find { |p| p.urn.end_with?(":i.3") }
    assert_includes i3.text, "modified Tohoku number Toh 846a"
    refute_includes i3.text, "several other Kangyur databases",
                    "the inline <note place=\"end\"> subtree is apparatus, never reading text"
  end

  def test_mantras_stay_in_the_reading_text
    document = adapter.parse(ref_for(TOH539E))
    first = document.find { |p| p.urn.end_with?(":1.1") }
    assert_equal "Homage to the Three Jewels. oṃ smara smara| vismanaskara mahājava hūṃ|",
                 first.text, "the Sanskrit <mantra> is part of the translation"
    trailer = document.find { |p| p.urn.end_with?(":1.3") }
    assert_equal "This completes “The Dhāraṇī of the Polished Gem.”", trailer.text,
                 "a trailer opened by its own milestone is its own chunk"
  end

  def test_tengyur_publication_parses_through_prefixed_divs_to_the_colophon
    document = adapter.parse(ref_for(TOH3156))
    expected = %w[s.1 ac.1 ac.2 i.1 i.2 i.3 i.4 i.5 i.6 i.7 1.1 1.2 1.3 1.4 c.1]
    assert_equal expected.map { |ref| "#{TOH3156}:#{ref}" }, document.map(&:urn),
                 "<tei:div>-prefixed markup (a real upstream variant) parses identically"
    colophon = document.find { |p| p.urn.end_with?(":c.1") }
    assert_equal "This was translated by the monk Tsultrim Gyaltsen.", colophon.text
    assert_equal "colophon", colophon.annotations["division"]
  end

  # -- metadata: the crosswalk keys and the Tibetan identity -------------------

  def test_multi_toh_texts_record_every_toh_number_first_mints_the_slug
    document = adapter.parse(ref_for(TOH539E))
    assert_equal TOH539E, document.urn
    assert_equal %w[toh539e toh774 toh1074], document.metadata["toh"],
                 "all three Degé witnesses of the one publication, upstream bibl order"
  end

  def test_document_metadata_carries_ut_id_titles_and_translators
    metadata = adapter.parse(ref_for(TOH846A)).metadata
    assert_equal ["toh846a"], metadata["toh"]
    assert_equal ["toh846a"], metadata["toh_base"]
    assert_equal "UT22084-100-002", metadata["ut_id"]
    assert_equal "རྒྱུད་གསུམ་པ།", metadata["title_bo"]
    assert_equal "rgyud gsum pa", metadata["title_wylie"]
    assert_equal ["Adam Krug"], metadata["translators"]
    assert_match(/Dharmachakra Translation Committee/, metadata["translator_main"])
    assert_equal "2020-02-17", metadata["publication_date"]
    assert_match(/Degé Kangyur, vol\. 100/, metadata["bibl_scope"])
  end

  def test_sanskrit_title_rides_metadata_when_present
    metadata = adapter.parse(ref_for(TOH3156)).metadata
    assert_equal "seng ge sgra’i gzungs", metadata["title_wylie"]
    assert_equal "Siṃha­nāda­dhāraṇī", metadata["title_sanskrit"],
                 "verbatim, soft hyphens included — canonical means canonical"
    assert_equal ["Catherine Dalton"], metadata["translators"],
                 "the 84000 team (titleStmt) only"
    assert_equal "Tsultrim Gyaltsen", metadata["translator_tib"],
                 "the HISTORICAL translator (sourceDesc author role=translatorTib — the same " \
                 "monk the colophon names) is a separate field, never mixed into the team list"
  end

  # -- license -----------------------------------------------------------------

  def test_manifest_class_is_nc_with_the_terms_of_use_caveat_pinned
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-ND.*3\.0/, manifest.license, "the README grant, verbatim basis")
    assert_match(/Terms_of_Use/, manifest.license,
                 "the caveat is part of the license record: the fuller Terms_of_Use.md layers " \
                 "data-partnership registration language; the README grant is operative")
  end

  # -- store: idempotent load --------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 38, db[:passages].count, "10 toh846a + 10 toh539e + 3 toh761(trim) + 15 toh3156"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped
    assert_equal 38, db[:passages].count
  ensure
    db&.disconnect
  end

  # -- fetch (local git only, no network) --------------------------------------

  def test_fetch_sparse_clones_the_translations_cone
    Dir.mktmpdir("nabu-e84000-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      e84000 = adapter
      e84000.define_singleton_method(:repo_url) { upstream }
      report = e84000.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "translations/kangyur/translations",
                                  "100-002_toh846a-the_threefold_ritual.xml")),
             "the translations cone materializes"
      refute File.exist?(File.join(work, "knowledgebase")),
             "outside-cone dirs (knowledgebase, schema, sections) must not materialize"
      refute_empty e84000.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  # --- the translation crosswalk rider (P48-6) --------------------------------

  def test_declares_the_translation_crosswalk_reference_producer
    assert Nabu::Adapters::E84000.reference_edges?,
           "each publication's toh_base keys mint kind=translation edges after each sync"
    producer = Nabu::Adapters::E84000.reference_producer(catalog: nil, journal: nil)
    assert_instance_of Nabu::E84000Translations, producer
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "e84000", name: "84000 English Kangyur translations",
      adapter_class: "Nabu::Adapters::E84000", license_class: "nc"
    )
  end

  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "knowledgebase"))
    FileUtils.cp_r(File.join(workdir, "translations"), upstream)
    File.write(File.join(upstream, "knowledgebase", "stub.xml"), "<kb/>\n")
    Nabu::Shell.run("git", "init", "-q", upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
