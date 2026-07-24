# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Croala (P44-9): CroALa — Croatiae auctores Latini
# (Jovanović, ed.) — the TEI P5 edition of Croatian Latin authors, 976 CE
# onward, on the classical desk's medieval-Latin edge. Fixture: three whole
# real documents from github.com/nevenjovanovic/croatiae-auctores-latini-textus
# (2026-07-24) covering the minimal prose shape, a medieval charter whose text
# lives in opener/closer, and a multi-div verse collection.
#
# THE D44-b LICENSE: the in-repo LICENSE.md is CC BY 4.0 verbatim → class
# attribution; the recorded site-vs-GitHub fork resolves to the in-file grant.
#
# THE COMPOSE VERDICT: the bytes REFUTE reuse — CroALa keeps reading text in
# <opener>/<closer> (dropped by SARIT and every reading-TEI family) and carries
# a sparse every-fifth-line @n that would corrupt an @n-first citation ladder.
# So a small bespoke `croala-tei` parser addresses positionally instead.
class CroalaTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  INSCR = "urn:nabu:croala:albert-i-inscr"
  DONATIO = "urn:nabu:croala:adam-radauanus-traditio"
  CARMINA = "urn:nabu:croala:andreis-f-carm-h46"

  def conformance_adapter = Nabu::Adapters::Croala.new

  def conformance_workdir = Nabu::TestSupport.fixtures("croala")

  def conformance_expected_source_id = "croala"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_xml_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [DONATIO, CARMINA, INSCR].sort, refs.map(&:id),
                 "one document per txts/<stem>.xml, urn urn:nabu:croala:<stem>, sorted"
    assert(refs.all? { |ref| ref.source_id == "croala" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  # -- the minimal prose shape (the <lb/> → space rule) -----------------------

  def test_prose_inscription_is_one_passage_with_lb_folded_to_space
    document = adapter.parse(ref_for(INSCR))
    assert_equal "lat", document.language
    assert_equal 1, document.count, "one div, one <p> → one passage"
    passage = document.first
    assert_equal "#{INSCR}:d1.p1", passage.urn,
                 "citation = <div-path>.<unit>: an unnumbered div is d1, its first prose block p1"
    assert_equal "HAEC QVIBUS IANCI? CVI FORTVNA FAVEBIT", passage.text,
                 "the inline <lb/> folds to a single space, whitespace collapses"
    assert_equal 0, passage.sequence
    assert_equal "structural-ordinal", passage.annotations["addressing"]
    assert_equal "prosa-inscriptio", passage.annotations["div_type"]
  end

  # -- the charter: opener + closer ARE reading text (the compose-killer) ------

  def test_charter_captures_opener_body_and_closer_as_ordered_prose_blocks
    document = adapter.parse(ref_for(DONATIO))
    assert_equal 4, document.count, "opener + two <p> + closer, in reading order"
    assert_equal ["#{DONATIO}:d1.p1", "#{DONATIO}:d1.p2", "#{DONATIO}:d1.p3", "#{DONATIO}:d1.p4"],
                 document.map(&:urn)
    assert_equal %w[opener p p closer], document.map { |p| p.annotations["unit"] },
                 "opener and closer carry the charter's dating clause and scribal subscription"
  end

  def test_charter_opener_text_is_reproduced_verbatim_with_supplied_kept
    opener = adapter.parse(ref_for(DONATIO)).first
    assert opener.text.start_with?("† Anno ab incarnatione domini nostri Iesu Christi millesimo LXX"),
           "the opener's dating clause is real reading text, not apparatus"
    closer = adapter.parse(ref_for(DONATIO)).to_a.last
    assert_equal "Ego Adam, presbiter et monachus, ueritate comperta rogatus manu mea scripsi.",
                 closer.text,
                 "the <signed> subscription rides in the closer; <supplied>ueritate</supplied> is kept in place"
  end

  # -- the timeline feed (976 CE onward reaching the date dimension) ----------

  def test_medieval_creation_date_metadata_feeds_the_timeline
    metadata = adapter.parse(ref_for(DONATIO)).metadata
    assert_equal "1070-09-01", metadata["date_not_before"], "the machine date the timeline consumes"
    assert_equal "1070-09-01", metadata["date"], "the display date"
    assert_equal "Nin", metadata["place"]
    assert_equal "Adam, redovnik", metadata["author"]
  end

  def test_title_is_mined_from_the_teiheader
    assert_equal "Donatio Radauani (1070), versio electronica",
                 adapter.parse(ref_for(DONATIO)).title
  end

  # -- verse: line grain, multiple sibling divs, the sparse @n ----------------

  def test_verse_is_line_grain_across_positional_sibling_divs
    document = adapter.parse(ref_for(CARMINA))
    assert_equal 229, document.count, "every non-empty <l> is a passage"
    first = document.first
    assert_equal "#{CARMINA}:d1.l1", first.urn, "first line of the first poem"
    assert_equal "O pater, o rerum Deus, infinita potestas,", first.text
    assert_equal "hexameter", first.annotations["met"], "the div's @met rides the passage"
    assert_includes document.map(&:urn), "#{CARMINA}:d2.l1",
                    "the second sibling poem is d2, not a collision with d1"
    assert_equal "#{CARMINA}:d7.l30", document.to_a.last.urn, "seven poems in the file"
  end

  def test_sparse_line_marker_rides_as_annotation_and_coincides_with_the_ordinal
    document = adapter.parse(ref_for(CARMINA))
    marked = document.find { |p| p.urn == "#{CARMINA}:d1.l5" }
    assert_equal "5", marked.annotations["n"],
                 "the source's every-fifth-line <l n=\"5\"> rides as the 'n' annotation"
    assert_equal "structural-ordinal", marked.annotations["addressing"],
                 "the citation stays positional (d1.l5) — the sparse @n is never the address"
    bare = document.find { |p| p.urn == "#{CARMINA}:d1.l1" }
    refute bare.annotations.key?("n"), "an unmarked line carries no 'n' annotation"
  end

  # -- text discipline: <head> and <note> are dropped -------------------------

  def test_head_and_note_subtrees_never_enter_the_reading_text
    document = adapter.parse(ref_for(CARMINA))
    refute(document.any? { |p| p.text.include?("Precatio Tranquilli ad Deum") },
           "the poem <head> title is apparatus — dropped from every passage")
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 234, db[:passages].count, "1 inscription + 4 charter + 229 verse lines"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 234, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_sparse_clones_only_the_txts_cone
    Dir.mktmpdir("nabu-croala-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      croala = adapter
      croala.define_singleton_method(:repo_url) { upstream }
      report = croala.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "txts", "albert-i-inscr.xml")), "the TEI cone materializes"
      assert File.file?(File.join(work, "LICENSE.md")), "the in-file grant (D44-b) is in the cone"
      refute File.exist?(File.join(work, "schemas")),
             "outside-cone paths (schemas/, scripts/) must not materialize"
      refute_empty croala.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "croala", name: "CroALa", adapter_class: "Nabu::Adapters::Croala",
      license_class: "attribution"
    )
  end

  # A local upstream repo with the real cone (fixture bytes) plus outside-cone
  # ballast the sparse fetch must not materialize.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    FileUtils.cp_r(File.join(workdir, "txts"), upstream)
    FileUtils.cp(File.join(workdir, "LICENSE.md"), File.join(upstream, "LICENSE.md"))
    File.write(File.join(upstream, "README.md"), "collection note (in the cone)")
    FileUtils.mkdir_p(File.join(upstream, "schemas"))
    File.write(File.join(upstream, "schemas", "croala.rng"), "outside the cone")
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
