# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::BetamasaheftWorks (P46-2): Beta maṣāḥǝft Works — the
# Ethiopic (Gǝʿǝz) literature shelf of the Hiob-Ludolf-Zentrum, Hamburg.
# Fixture: four real text-bearing records (one trimmed, three whole), one
# catalog-only record, and the repo-root packaging file — see
# test/fixtures/betamasaheft-works/README.md.
#
# THE D46-a LICENSE (owner-ratified 2026-07-26): the per-document in-file
# <licence> grant governs — CC BY-SA 4.0 on 6,545 of 6,548 files → class
# attribution; the website's blanket CC BY-NC-SA does NOT. A file without an
# in-file grant is never ingested (skip-by-rule), and a non-BY-SA grant
# would surface as an UNRECOGNIZED census line, loudly.
#
# THE SELECTION RULE: most of the corpus is catalog records with zero (or
# non-Ethiopic) edition content. Text-bearing = an edition div whose region
# carries Ethiopic script; everything else skips silently by rule — the
# corpus norm, never quarantine noise.
class BetamasaheftWorksTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  MMDZ = "urn:nabu:betamasaheft-works:LIT0017MMDZ"
  MARKGO = "urn:nabu:betamasaheft-works:LIT1882MarkGo"
  RUTH = "urn:nabu:betamasaheft-works:LIT2229RuthBo"
  MARK = "urn:nabu:betamasaheft-works:LIT2711Mark"

  def conformance_adapter = Nabu::Adapters::BetamasaheftWorks.new

  def conformance_workdir = Nabu::TestSupport.fixtures("betamasaheft-works")

  def conformance_expected_source_id = "betamasaheft-works"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover: the text-bearing selection rule ------------------------------

  def test_discover_yields_only_text_bearing_licensed_records_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [MMDZ, MARKGO, RUTH, MARK], refs.map(&:id),
                 "text-bearing records only: the catalog-only LIT2006Mazmur and the " \
                 "licence-less repo.xml never become refs"
    assert(refs.all? { |ref| ref.source_id == "betamasaheft-works" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  def test_discovery_skips_census_counts_the_quiet_skips
    skips = adapter.discovery_skips(workdir)
    assert_equal 2, skips.skipped_by_rule,
                 "LIT2006Mazmur (catalog-only) + repo.xml (no in-file licence) skip by rule"
    assert_equal 0, skips.unrecognized, "every skip is accounted for — nothing unrecognized"
  end

  # -- the license gate (D46-a) -----------------------------------------------

  def test_manifest_class_is_attribution_per_the_in_file_by_sa_grant
    manifest = adapter.manifest
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/BY-NC-SA/, manifest.license,
                 "the website-vs-in-file discrepancy is recorded honestly in the manifest")
  end

  def test_documents_carry_the_in_file_licence_statement_and_ride_the_source_class
    document = adapter.parse(ref_for(RUTH))
    assert_nil document.license_override, "BY-SA == the source class — no override minted"
    assert_match(/Attribution-ShareAlike 4\.0/, document.metadata["licence_statement"])
    assert_equal "http://creativecommons.org/licenses/by-sa/4.0/",
                 document.metadata["licence_target"]
  end

  def test_per_document_attribution_is_mined_from_the_header
    metadata = adapter.parse(ref_for(RUTH)).metadata
    assert_match(/Ran HaCohen/, metadata["attribution"],
                 "the Octateuch transcriber is credited in-file (editionStmt) and carried per-document")
    assert_match(/Ran HaCohen/, metadata["licence_statement"],
                 "the licence paragraph names the transcription copyright too")
    assert_match(/PEMM/, adapter.parse(ref_for(MMDZ)).metadata["attribution"],
                 "the Princeton PEMM data credit rides the same editionStmt lane")
  end

  # -- the chapter/verse shape (Mark) -----------------------------------------

  def test_mark_parses_at_verse_grain_with_upstream_l_n_citations
    document = adapter.parse(ref_for(MARK))
    assert_equal "gez", document.language
    assert_equal "Gospel of Mark", document.title
    assert_equal 85, document.count, "73 numbered verses + 12 unnumbered rubric lines (chapters 1-2)"
    numbered = document.select { |p| p.annotations.key?("n") }
    assert_equal 73, numbered.size,
                 "the canonical chapter 1-2 verse counts (45 + 28) — the trimmed-sample pin"

    verse = document.find { |p| p.urn == "#{MARK}:1.1" } || flunk("no 1.1")
    assert_equal "ቀዳሚሁ፡ ለወንጌለ፡ እግዚእነ፡ ኢየሱስ፡ ክርስቶስ። ወልደ፡ እግዚአብሔር፡ ሕያው።", verse.text,
                 "the empty <ref> verse pointer folds away; the verse text is verbatim"
    assert_equal "1", verse.annotations["n"]
    assert_equal "chapter", verse.annotations["subtype"]
    assert_includes document.map(&:urn), "#{MARK}:2.28", "chapter 2 ends at the canonical verse 28"
  end

  def test_unnumbered_rubric_lines_are_reading_text_with_positional_tokens
    document = adapter.parse(ref_for(MARK))
    rubric = document.first
    assert_equal "#{MARK}:1.l1", rubric.urn,
                 "an unnumbered <l> gets a positional l<k> token, never a fake verse number"
    assert_equal "በእንተ፡ ስብከተ፡ ዮሐንስ", rubric.text
    refute rubric.annotations.key?("n")
  end

  def test_chapter_labels_never_enter_the_reading_text
    document = adapter.parse(ref_for(MARK))
    refute(document.any? { |p| p.text.include?("ምዕራፍ") },
           "the <label>ምዕራፍ 1</label> chapter heading is apparatus — dropped")
  end

  # -- the whole-book shape (Ruth) + word-divider handling --------------------

  def test_ruth_parses_85_verses_across_four_chapters
    document = adapter.parse(ref_for(RUTH))
    assert_equal "Book of Ruth", document.title
    assert_equal 85, document.count
    assert_equal "#{RUTH}:1.1", document.first.urn
    assert_equal "#{RUTH}:4.22", document.to_a.last.urn
    first = document.first
    assert first.text.start_with?("ወኮነ ፡ በመዋዕለ ፡ ይኴንኑ ፡ መሳፍንት"),
           "Ruth writes SPACED word dividers (word ፡ word) — reproduced verbatim, not 'cleaned'"
    assert first.text.end_with?("።"), "the sentence mark ። closes the verse"
    refute(document.any? { |p| p.text.match?(/\A\d+\z/) },
           "the in-body chapter <title> elements (' 1') are apparatus — dropped")
  end

  # -- the incipit/explicit record shape (MarkGo) -----------------------------

  def test_incipit_explicit_records_parse_with_positional_div_paths
    document = adapter.parse(ref_for(MARKGO))
    assert_equal "gez", document.language, "an edition div without @xml:lang defaults to gez"
    assert_equal "Gospel of Mark (Collection)", document.title
    assert_equal 14, document.count,
                 "biography + Eusebian sections + tituli + headline + gospel + postscript excerpts"
    assert_equal ["#{MARKGO}:BiographyMark.d1.ab1", "#{MARKGO}:BiographyMark.d2.ab1"],
                 document.map(&:urn).first(2),
                 "div path components: @n first, else @xml:id (BiographyMark), else positional d<k>"
    assert_includes document.map(&:urn), "#{MARKGO}:d4.MarkGospel.d1.ab1",
                    "a div with neither @n nor @xml:id reads positionally (d4, the gospel chapter div)"
    assert_includes document.map(&:urn), "#{MARKGO}:TituliMark.d1.1",
                    "the tituli incipit keeps its upstream <l n=\"1\"> verse token"
    assert_equal %w[incipit explicit], document.map { |p| p.annotations["subtype"] }.first(2)
    assert document.first.text.start_with?("በስመ፡ እግዚአብሔር፡ ሕያው፡"),
           "the incipit <ab> is reading text; <listBibl>/<note> apparatus is dropped"
  end

  # -- the mislabeled-language shape (MMDZ) -----------------------------------

  def test_ethiopic_content_under_an_en_labeled_edition_ingests_as_gez
    document = adapter.parse(ref_for(MMDZ))
    assert_equal "gez", document.language,
                 "upstream labels this edition xml:lang=\"en\" but the <ab> is Gǝʿǝz — " \
                 "the Ethiopic-content rule wins over the sloppy record attribute"
    assert_equal 1, document.count
    assert_equal "#{MMDZ}:d1.ab1", document.first.urn
    assert document.first.text.start_with?("ተአምር፡ ዘገብረት፡ ሎቱ፡ እግዝእትነ፡ ማርያም፡"),
           "the commented-out English translation div never parses"
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 185, db[:passages].count, "85 Mark + 85 Ruth + 14 MarkGo + 1 MMDZ"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 185, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_sparse_clones_the_xml_cone
    Dir.mktmpdir("nabu-bm-works-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      works = adapter
      works.define_singleton_method(:repo_url) { upstream }
      report = works.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "2001-3000", "LIT2229RuthBo.xml")), "the TEI cone materializes"
      refute File.exist?(File.join(work, "icon.png")), "outside-cone binaries must not materialize"
      refute_empty works.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "betamasaheft-works", name: "Beta maṣāḥǝft Works",
      adapter_class: "Nabu::Adapters::BetamasaheftWorks", license_class: "attribution"
    )
  end

  # A local upstream repo mirroring the real layout (range dir + root
  # packaging file) plus outside-cone ballast the sparse fetch must skip.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "2001-3000"))
    FileUtils.cp(File.join(workdir, "2001-3000", "LIT2229RuthBo.xml"),
                 File.join(upstream, "2001-3000", "LIT2229RuthBo.xml"))
    FileUtils.cp(File.join(workdir, "repo.xml"), File.join(upstream, "repo.xml"))
    File.binwrite(File.join(upstream, "icon.png"), "\x89PNG outside the cone")
    Nabu::Shell.run("git", "init", "-q", upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
