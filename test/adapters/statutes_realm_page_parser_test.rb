# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The statutes-realm parser family: StatutesRealmToc (a BHO volume TOC
# page → its rows, each classed by grain, + the pager's next page) and
# StatutesRealmPageParser (one act page → a Document whose passages are
# the act's sections). Fixtures: test/fixtures/statutes-realm (README) —
# trimmed real BHO pages, retrieved 2026-11-05.
class StatutesRealmPageParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/statutes-realm", __dir__)

  def toc(name, volume)
    Nabu::Adapters::StatutesRealmToc.rows(File.read(File.join(FIXTURES, "toc", name), encoding: "UTF-8"),
                                          volume: volume)
  end

  def parse(rel, row: nil)
    volume, slug = rel.delete_suffix(".html").split("/")
    Nabu::Adapters::StatutesRealmPageParser.new.parse(
      File.join(FIXTURES, rel), urn: "urn:nabu:statutes-realm:#{volume}:#{slug}", row: row
    )
  end

  # --- the TOC --------------------------------------------------------------

  def test_toc_rows_carry_slug_title_pages_and_grain
    rows = toc("vol5-page-0.html", 5)
    assert_equal %w[p1 iii-iv v-xix p1a pp255-259 pp421-422], rows.map(&:slug)
    assert_equal %i[engraving front_matter front_matter act act act], rows.map(&:grain)
    act = rows[3]
    assert_equal 5, act.volume
    assert_equal "1", act.pages
    assert_equal "Charles I, 1625: An Acte for punishing of divers abuses co[m]mitted on the Lords day called Sunday.",
                 act.title
    assert act.accepted?
    refute rows[0].accepted?
  end

  def test_index_and_private_acts_rows_are_classed
    rows = toc("vol7-page-2.html", 7)
    assert_equal([%w[p750 private_acts], %w[pp3-5 index]], rows.map { |row| [row.slug, row.grain.to_s] })
    assert rows.first.accepted?, "the roll's own schedule of private-act titles is text"
    assert_equal %i[index], toc("vol5-page-3.html", 5).map(&:grain)
  end

  def test_the_pager_names_the_next_page_until_the_last
    assert_equal 1,
                 Nabu::Adapters::StatutesRealmToc.next_page(File.read(File.join(FIXTURES, "toc", "vol5-page-0.html")))
    assert_equal 2,
                 Nabu::Adapters::StatutesRealmToc.next_page(File.read(File.join(FIXTURES, "toc", "vol7-page-1.html")))
    assert_nil Nabu::Adapters::StatutesRealmToc.next_page(File.read(File.join(FIXTURES, "toc", "vol7-page-2.html")))
  end

  def test_grain_classes_every_title_shape
    {
      "Index: U & V, W, Y" => :index, "Preface" => :front_matter,
      "Chronological table of the titles of all the acts of parliament: Passed in the reigns of King Charles I and " \
      "King Charles II" => :front_matter,
      "Engraving: Attainder of the pretended Prince of Wales for High Treason" => :engraving,
      "William III, 1698: The Private Acts" => :private_acts,
      "William and Mary, 1692: An Act for continuing the Acts For prohibiting all Trade" => :act,
      "Something new upstream" => :unknown
    }.each { |title, grain| assert_equal grain, Nabu::Adapters::StatutesRealmToc.grain(title), title }
  end

  # --- an act page ------------------------------------------------------------

  def test_an_act_page_parses_to_its_sections
    document = parse("vol5/p1a.html")
    assert_equal "en", document.language
    assert_equal "Charles I, 1625: An Acte for punishing of divers abuses co[m]mitted on the Lords day called Sunday.",
                 document.title
    assert_equal 1, document.size
    passage = document.passages.first
    assert_equal "urn:nabu:statutes-realm:vol5:p1a:s1", passage.urn
    assert passage.text.start_with?("FORASMUCH as there is nothing more acceptable to God")
    assert passage.text.end_with?("untill the end of the first Session of the next Parliament, and no longer.")
    assert_equal "Profanation of the Lord's Day;", passage.annotations["heading"]
  end

  def test_the_marginal_summary_rides_aside_and_footnote_markers_leave_the_text
    passage = parse("vol5/p1a.html").passages.first
    assert_match(/\ANo Meetings for Sports by People out of their own Parishes/,
                 passage.annotations["marginal_notes"].first)
    refute_includes passage.text, "(fn. 1)"
    assert_includes passage.text, "[Constables ]", "the editor's bracket stays; only the marker leaves"
    assert_equal [{ "n" => "1", "text" => "Constable O." }], passage.annotations["footnotes"]
  end

  def test_upstream_text_is_kept_as_rekeyed
    # The rekeying dropped the contraction marks (enaed for enacted, Cmons
    # for Commons) — canonical means canonical; no repair at parse.
    assert_includes parse("vol5/p1a.html").passages.first.text, "Be it enaed by the King most Excellent Majestie"
  end

  def test_numbered_sections_take_upstream_ids
    document = parse("vol7/p641a.html")
    assert_equal(%w[s1 s2], document.passages.map { |passage| passage.urn.split(":").last })
    assert_equal "II. The said Acts to be taken as Public Acts", document.passages.last.annotations["heading"]
    assert_equal [{ "n" => "1", "text" => "interlined on the Roll." }, { "n" => "2", "text" => "unto O." }],
                 document.passages.first.annotations["footnotes"], "a reused note is listed once"
  end

  def test_page_anchored_heads_mint_distinct_section_ids
    # Some act pages anchor their heads h2-p1/h3-p2… (page anchors) instead
    # of hN-sK — found live on vol5/pp421-422 (Charles II, 1662, the Butter
    # Act), where the -s fallback collapsed every section to :s0 and the
    # duplicate passage urns quarantined a real act. Upstream's own id is
    # still the stable key: the urn keeps its full suffix (:sp1, :sp2, …).
    document = parse("vol5/pp421-422.html")
    assert_equal(%w[sp1 sp2 sp3], document.passages.map { |passage| passage.urn.split(":").last })
    assert_match(/\ARecital that great Quantities of Butter are exported/,
                 document.passages.first.annotations["heading"])
  end

  def test_tables_render_one_line_per_row
    passage = parse("vol5/pp255-259.html").passages.first
    lines = passage.text.split("\n")
    assert_includes lines, "For every Gallon of Coffee made and sold to be paid by the maker Foure pence | iiij d."
    assert_equal(%w[1 2 3], passage.annotations["footnotes"].map { |note| note["n"] })
  end

  def test_the_private_acts_schedule_parses_with_its_roll_formula
    document = parse("vol7/p750.html")
    passage = document.passages.first
    assert_match(/\AItem quedam Petitiones privatas Personas concernentes/, passage.annotations["heading"])
    assert_includes passage.text, "An Act to naturalize Charlotte the Wife of Hugh Boscowen Esquire"
    assert_equal "private acts list", document.metadata["document_type"]
  end

  # --- metadata -------------------------------------------------------------------

  def test_metadata_carries_the_edition_reign_session_and_date
    row = toc("vol7-page-1.html", 7).first
    meta = parse("vol7/p641a.html", row: row).metadata
    assert_equal 7, meta["volume"]
    assert_equal "Statutes of the Realm: Volume 7, 1695-1701", meta["volume_title"]
    assert_equal "Great Britain Record Commission, s.l, 1820", meta["originally_published"]
    assert_equal "John Raithby", meta["editor"]
    assert_equal "https://www.british-history.ac.uk/statutes-realm/vol7/p641a", meta["upstream_url"]
    assert_equal "641", meta["pages"]
    assert_equal "William III", meta["reign"]
    assert_equal "1700 & 1701", meta["session"]
    assert_equal "VI", meta["chapter"]
    assert_equal "Rot. Parl. 12 § 13 Gul. III. p. 1. n. 6.", meta["roll_reference"]
    assert_equal [12, 13], meta["regnal"]["years"]
    assert_equal 1700, meta["date"]["not_before"]
    assert_equal 1701, meta["date"]["not_after"]
    assert_equal "act", meta["document_type"]
    assert_equal "This free content was digitised by double rekeying. Public Domain.", meta["license_statement"]
  end

  def test_a_page_without_the_public_domain_line_is_refused
    html = File.read(File.join(FIXTURES, "vol5", "p1a.html"), encoding: "UTF-8").sub("Public Domain.",
                                                                                     "All rights reserved.")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p1a.html")
      File.write(path, html)
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::StatutesRealmPageParser.new.parse(path, urn: "urn:nabu:statutes-realm:vol5:p1a")
      end
      assert_match(/Public Domain/, error.message)
    end
  end

  def test_a_page_with_no_text_is_refused
    error = assert_raises(Nabu::ParseError) { parse("vol5/p1.html") }
    assert_match(/no act text/, error.message)
  end
end
