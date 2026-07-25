# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "webmock/minitest"

# Nabu::Adapters::Bfm (P45-4): BFM — Base de français médiéval (BFM2022,
# ENS de Lyon / IHRIM), 219 TEI P5 texts of medieval French (842–15th c.)
# distributed as one NAKALA data(set) per text (collection
# doi:10.34847/nkl.93ee3ts1). Fixtures: three whole real files + one
# documented trim (AlexisRaM: teiHeader + strophes 1, 2 and 10), snapshotted
# 2026-07-25 from the sha1-addressed NAKALA file API, covering the corpus's
# four body shapes:
#
#   nabaret.xml          plain (untokenized) verse — <ab type="gv"> + <lb n>
#   RegleSBenCotton.xml  plain prose — <p> per chapter div, folio milestones
#   strasbBfm.xml        <w>-tokenized prose, no lemmas — the token-join rules;
#                        also one of the corpus's 8 CC BY-NC-SA-flagged files
#   AlexisRaM.xml        <w type lemma>-tokenized verse with <lb ed="norm">,
#                        editorial <note resp="#eds"> apparatus, <choice>
#                        sic/corr — the lemma lane + the apparatus drop
#
# THE D45-c LICENSE VERDICT (from bytes): every file's reading text + TEI
# markup is "libres de droit" / Licence Ouverte (Etalab) 2.0 → class
# attribution; the CC BY-NC-SA 3.0 FR layer covers ONLY the apparat critique
# (editorial notes/introductions/glossaries), which this parser drops from
# the reading stream by construction — no NC bytes reach the catalog.
#
# THE COMPOSE VERDICT: the bytes refute reuse of croala-tei (and every
# container-based reading-TEI family) — BFM verse lines are <lb/> MILESTONES
# inside <ab> verse groups, not <l> containers (croala folds lb to a space,
# collapsing a 625-line poem into strophe blobs), and the tokenized texts
# need <w>-boundary reconstruction (elision "d'" + "ist" → "d'ist",
# punctuation attach-left). So a bespoke `bfm-tei` family, borrowing
# croala-tei's positional-citation architecture.
class BfmTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  ALEXIS = "urn:nabu:bfm:AlexisRaM"
  REGLE = "urn:nabu:bfm:RegleSBenCotton"
  NABARET = "urn:nabu:bfm:nabaret"
  STRASB = "urn:nabu:bfm:strasbBfm"

  def conformance_adapter = Nabu::Adapters::Bfm.new

  def conformance_workdir = Nabu::TestSupport.fixtures("bfm")

  def conformance_expected_source_id = "bfm"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_xml_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [ALEXIS, REGLE, NABARET, STRASB], refs.map(&:id),
                 "one document per xml/<stem>.xml, urn urn:nabu:bfm:<stem>, sorted"
    assert(refs.all? { |ref| ref.source_id == "bfm" })
  end

  # -- plain verse: line grain off <lb> milestones ----------------------------

  def test_plain_verse_is_line_grain_split_on_lb_milestones
    document = adapter.parse(ref_for(NABARET))
    assert_equal "fro", document.language
    assert_equal 48, document.count, "48 <lb n> milestones → 48 verse lines"
    first = document.first
    assert_equal "#{NABARET}:d1.l1", first.urn,
                 "citation = <div-path>.<unit>: the unnumbered div is d1, its first line l1"
    assert_equal "En Bretaigne fu li laiz fet", first.text
    assert_equal "1", first.annotations["n"], "the opening <lb n=\"1\"/> rides as 'n'"
    assert_equal "l", first.annotations["unit"]
    last = document.to_a.last
    assert_equal "#{NABARET}:d1.l48", last.urn
    assert_equal "e de sun nun le lai nomerent.", last.text
  end

  def test_plain_verse_keeps_q_content_and_direct_speech_guillemets
    document = adapter.parse(ref_for(NABARET))
    spoken = document.find { |p| p.urn == "#{NABARET}:d1.l33" }
    assert_includes spoken.text, "Seignurs, fet ele, si vus plest",
                    "<q> direct speech is transparent reading text"
  end

  def test_nabaret_header_metadata_feeds_title_author_date_and_dialect
    document = adapter.parse(ref_for(NABARET))
    assert_equal "Nabaret", document.title
    metadata = document.metadata
    assert_equal "anonyme", metadata["author"]
    assert_equal "entre 1178 et 1230", metadata["date"]
    assert_equal "1209-01-01", metadata["date_when"]
    assert_equal "1178-01-01", metadata["date_not_before"]
    assert_equal "1230-01-01", metadata["date_not_after"]
    assert_equal "vers", metadata["forme"]
    assert_equal "anglo-normand", metadata["dialect"]
    assert_equal "https://www.etalab.gouv.fr/licence-ouverte-open-licence",
                 metadata["license_url"], "the in-file <licence target> rides verbatim"
  end

  # -- plain prose: block grain, div @n components ----------------------------

  def test_plain_prose_is_block_grain_with_div_n_components
    document = adapter.parse(ref_for(REGLE))
    assert_equal 2, document.count, "two chapter divs, one <p> each"
    assert_equal ["#{REGLE}:d49.p1", "#{REGLE}:d48.p1"], document.map(&:urn),
                 "the div @n (chapter number) is the path component, in file order"
    first = document.first
    assert first.text.start_with?("Ja seit iceo ke vie de moine en tuz tens"),
           "the chapter prose is one passage"
    refute_includes first.text, "121r", "folio <milestone> folds to a space, never text"
    assert_equal "chapter", first.annotations["div_type"]
    assert_equal "Règle de saint Benoît", document.title
    assert_equal "prose", document.metadata["forme"]
  end

  # -- tokenized prose: the <w> boundary reconstruction -----------------------

  def test_tokenized_prose_joins_words_with_elision_and_punctuation_rules
    document = adapter.parse(ref_for(STRASB))
    assert_equal 2, document.count, "two serment divs, one <p> each → block grain"
    assert_equal ["#{STRASB}:d1.p1", "#{STRASB}:d2.p1"], document.map(&:urn)
    oath = document.first.text
    assert oath.start_with?("Pro Deo amur et pro Christian poblo et nostro commun salvament,"),
           "punctuation tokens attach left (no space before the comma)"
    assert_includes oath, "d'ist di in avant",
                    "an elided token (d') joins the next word without a space"
    assert_includes oath, "in o quid il mi altresi fazet.",
                    "<space dim=…/> folds to a single space"
    assert document.to_a.last.text.start_with?("Si Lodhuvigs sagrament,")
  end

  def test_tokenized_words_without_lemma_mint_no_tokens_annotation
    document = adapter.parse(ref_for(STRASB))
    document.each do |passage|
      refute passage.annotations.key?("tokens"),
             "strasbBfm <w> carry no @lemma — no tokens annotation to mint"
    end
  end

  # -- lemmatized verse: tokens, apparatus drop, choice policy ----------------

  def test_lemmatized_verse_is_line_grain_with_norm_lb_numbering
    document = adapter.parse(ref_for(ALEXIS))
    assert_equal 15, document.count, "strophes 1, 2 and 10 → 5 + 5 + 5 verse lines"
    first = document.first
    assert_equal "#{ALEXIS}:d1.l1", first.urn
    assert_equal "Bons fut li secles al tens ancïenur", first.text,
                 "the inline editorial <note> between tokens is dropped"
    assert_equal "1", first.annotations["n"]
    fifth = document.to_a[4]
    assert_equal "ja mais n'iert tel cum fut as anceisurs.", fifth.text
    assert_equal "Vie de saint Alexis", document.title
    assert_equal "1050-01-01", document.metadata["date_when"]
    assert_equal "1025-01-01", document.metadata["date_not_before"]
  end

  def test_editorial_notes_and_mentioned_never_enter_the_reading_text
    document = adapter.parse(ref_for(ALEXIS))
    document.each do |passage|
      refute_includes passage.text, "Le manuscrit L",
                      "<note resp=\"#eds\"> is the CC BY-NC-SA apparat critique — dropped"
      refute_includes passage.text, "esperluette"
    end
  end

  def test_choice_takes_the_editorial_corr_over_the_scribal_sic
    document = adapter.parse(ref_for(ALEXIS))
    line = document.find { |p| p.urn == "#{ALEXIS}:d1.l11" }
    assert_equal "Donnent lur terme de lur adaisement,", line.text,
                 "Do<choice><sic>m</sic><corr>nn</corr></choice>ent reads Donnent"
    assert_equal "46", line.annotations["n"],
                 "the strophe-10 line keeps its upstream <lb ed=\"norm\" n=\"46\"> as 'n'"
  end

  def test_elision_within_lemmatized_verse_joins_tokens
    document = adapter.parse(ref_for(ALEXIS))
    line = document.find { |p| p.urn == "#{ALEXIS}:d1.l13" }
    assert_equal "danz Alexis l'espuset belament,", line.text
  end

  def test_lemma_bearing_tokens_ride_the_tokens_annotation
    document = adapter.parse(ref_for(ALEXIS))
    tokens = document.first.annotations["tokens"]
    assert_equal(%w[Bons fut li secles al tens ancïenur], tokens.map { |t| t["form"] })
    assert_equal({ "form" => "Bons", "lemma" => "bon", "pos" => "ADJqua" }, tokens.first)
    punctuated = document.to_a[1].annotations["tokens"]
    comma = punctuated.last
    assert_equal ",", comma["form"]
    refute comma.key?("lemma"), "a punctuation token (PON*) carries no lemma key"
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 67, db[:passages].count, "48 nabaret + 2 Regle + 2 strasb + 15 Alexis"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 67, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch: the sha1-pinned NAKALA inventory crawl (WebMock only) -----------

  def test_fetch_downloads_pinned_files_verifies_sha1_and_is_resumable
    Dir.mktmpdir("nabu-bfm-fetch") do |work|
      bfm = pinned_adapter(
        "nabaret" => ["10.34847/nkl.03afsboc", sha1_of("nabaret.xml")],
        "strasbBfm" => ["10.34847/nkl.f57b23q4", sha1_of("strasbBfm.xml")]
      )
      stub_data("10.34847/nkl.03afsboc", sha1_of("nabaret.xml"), fixture_bytes("nabaret.xml"))
      stub_data("10.34847/nkl.f57b23q4", sha1_of("strasbBfm.xml"), fixture_bytes("strasbBfm.xml"))

      report = bfm.fetch(work)
      assert_kind_of Nabu::FetchReport, report
      assert_equal fixture_bytes("nabaret.xml"), File.binread(File.join(work, "xml", "nabaret.xml"))
      assert File.file?(File.join(work, "xml", "strasbBfm.xml"))
      assert_includes report.notes, "2 file(s) pinned"
      assert_includes report.notes, "2 downloaded"

      WebMock.reset!
      resumed = bfm.fetch(work)
      assert_includes resumed.notes, "0 downloaded",
                      "a file already present at its pinned sha1 is never re-downloaded"
      refute_empty bfm.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  def test_fetch_rejects_a_body_that_misses_the_pinned_sha1
    Dir.mktmpdir("nabu-bfm-fetch") do |work|
      pin = sha1_of("nabaret.xml")
      bfm = pinned_adapter("nabaret" => ["10.34847/nkl.03afsboc", pin])
      stub_data("10.34847/nkl.03afsboc", pin, "not the pinned bytes")

      error = assert_raises(Nabu::FetchError) { bfm.fetch(work) }
      assert_match(/sha1 mismatch/, error.message)
      refute File.exist?(File.join(work, "xml", "nabaret.xml")),
             "a mismatched body must never land in canonical"
    end
  end

  def test_fetch_attics_a_stray_file_the_inventory_no_longer_pins
    Dir.mktmpdir("nabu-bfm-fetch") do |work|
      FileUtils.mkdir_p(File.join(work, "xml"))
      File.write(File.join(work, "xml", "withdrawn.xml"), "<TEI/>")
      # Four pinned files so the one stray sits under the 20% mass-deletion
      # breaker (the ordinary small re-pin shape; a gutting re-pin still
      # demands --force via the base-class guard).
      pins = { "AlexisRaM" => "10.34847/nkl.7bbe37x6", "RegleSBenCotton" => "10.34847/nkl.879d4s17",
               "nabaret" => "10.34847/nkl.03afsboc", "strasbBfm" => "10.34847/nkl.f57b23q4" }
      inventory = pins.to_h { |stem, doi| [stem, [doi, sha1_of("#{stem}.xml")]] }
      pins.each { |stem, doi| stub_data(doi, sha1_of("#{stem}.xml"), fixture_bytes("#{stem}.xml")) }
      bfm = pinned_adapter(inventory)

      bfm.fetch(work)
      refute File.exist?(File.join(work, "xml", "withdrawn.xml")),
             "an unpinned file leaves the live tree"
      assert File.file?(File.join(work, ".attic", "xml", "withdrawn.xml")),
             "…but is retained in the attic, never hard-deleted"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "bfm", name: "Base de français médiéval", adapter_class: "Nabu::Adapters::Bfm",
      license_class: "attribution"
    )
  end

  def pinned_adapter(inventory)
    bfm = adapter
    bfm.define_singleton_method(:inventory) { inventory }
    bfm
  end

  def fixture_bytes(name)
    File.binread(File.join(workdir, "xml", name))
  end

  def sha1_of(name)
    Digest::SHA1.hexdigest(fixture_bytes(name))
  end

  def stub_data(doi, sha1, body)
    stub_request(:get, "https://api.nakala.fr/data/#{doi}/#{sha1}")
      .to_return(status: 200, body: body)
  end
end
