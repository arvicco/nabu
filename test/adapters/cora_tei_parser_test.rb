# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# CoraTeiParser tests (P40-5): the cora-tei family — the TEI P5 serialisation
# of the CorA-derived DDD reference corpora (ReM now; ReA/ReN ride the same
# family when their licenses confirm). Censused from the two real ReM v2.1
# fixtures (test/fixtures/rem/README.md):
#
#   - tokens are <w xml:id="tN_mM" norm lemma [join]> whose ELEMENT TEXT is
#     the diplomatic form (long ſ, combining marks, <unclear>/<supplied>
#     wrappers, <space quantity unit="chars"/> scribal gaps); punctuation is
#     <pc>; multi-part tokens share a base id (t9_m1/t9_m2) and join
#     right/left marks written-together tokens;
#   - layout is <pb n ed>/<lb n ed> milestones inside one <ab>; ed="1" is the
#     manuscript line (the primary layout unit per encodingDesc), ed="2" the
#     edition lineation;
#   - the header carries title, token extent, licence, langUsage dialect
#     chain, textClass genre/keywords, msDesc repository+idno, and (in these
#     fixtures placeholder-only) origDate/origPlace.
#
# The TEI export carries NO pos/msd attributes — norm + lemma only (the
# CorA-XML sibling zips hold the fuller annotation); the parser census pins
# that honestly.
class CoraTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("rem")
  M058 = File.join(FIXTURES, "M058.xml")
  M218B = File.join(FIXTURES, "M218B.xml")

  def parser
    Nabu::Adapters::CoraTeiParser.new
  end

  # --- header ---------------------------------------------------------------

  def test_header_reads_identity_title_and_extent
    header = parser.header(M058)
    assert_equal "M058", header.text_id
    assert_equal "Sangspruchstrophe MF 'Namenlos IV'", header.title
    assert_equal 23, header.token_count
  end

  def test_header_reads_the_licence_verbatim
    header = parser.header(M058)
    assert_equal "Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA)",
                 header.licence
  end

  def test_header_reads_the_dialect_chain_and_language_idents
    header = parser.header(M058)
    assert_equal %w[gmh], header.language_idents
    assert_equal %w[mhd oberdeutsch ostoberdeutsch bairisch], header.dialects,
                 "the langUsage values are the time/place classification; the '-' placeholder drops"
  end

  def test_header_reads_textclass_and_ms_identity
    header = parser.header(M058)
    assert_equal "V", header.genre
    assert_equal "Poesie", header.topic
    assert_equal "Spruchdichtung", header.text_type
    assert_equal "Wien, Österr. Nationalbibl.", header.repository
    assert_equal "Cod. 160", header.ms_idno
  end

  def test_header_placeholder_dating_reads_as_nil
    header = parser.header(M058)
    assert_nil header.orig_date, "both fixtures carry the '--' placeholder, honestly nil"
    assert_nil header.orig_place
  end

  def test_header_reads_the_derivation_of_a_translation_text
    assert_equal "latein", parser.header(M218B).derived_from,
                 "the St. Galler Schularbeit is a school translation from Latin"
    assert_nil parser.header(M058).derived_from, "'-' placeholder drops"
  end

  # --- body: lines ----------------------------------------------------------

  def test_body_yields_one_line_per_primary_lb
    lines = parser.body(M058).lines
    assert_equal [%w[100v 5], %w[100v 6]], lines.map { |l| [l.page, l.n] },
                 "M058: folio 100v, manuscript lines 5-6 (a four-verse Nachtrag)"
  end

  def test_line_text_is_the_diplomatic_surface_with_join_honored
    lines = parser.body(M058).lines
    assert_equal "al diu welt mit grínme ſtet. der darundir muͦzic get. der",
                 lines[0].text,
                 "long ſ and combining marks kept; join right/left glues ſtet+. and dar+undir"
    assert_equal "ginge wol uerwerden. ſin ere muͦz erſterben.",
                 lines[1].text,
                 "<supplied>gin</supplied>g<unclear>e</unclear> reads through as ginge"
  end

  def test_scribal_space_elements_read_as_a_space_in_the_diplomatic_form
    lines = parser.body(M218B).lines
    assert_equal "únde ge uuíſhéit téro nóh úr óugôn;",
                 lines[3].text,
                 "<space quantity='1' unit='chars'/> inside <w> is a witness gap, kept as one space"
  end

  def test_secondary_lineation_rides_edition_lines
    lines = parser.body(M218B).lines
    assert_equal [["06"], ["07"], ["08"], ["09"]], lines.map(&:edition_lines),
                 "ed='2' lb milestones never split a manuscript line; their labels ride along"
  end

  # --- body: tokens ---------------------------------------------------------

  def test_tokens_carry_diplomatic_form_norm_and_lemma
    token = parser.body(M058).lines[0].tokens.find { |t| t["id"] == "t5_m1" }
    assert_equal({ "id" => "t5_m1", "form" => "grínme", "norm" => "grinme", "lemma" => "grimme" },
                 token)
  end

  def test_multipart_tokens_stay_separate_records_with_the_shared_base_id_visible
    tokens = parser.body(M058).lines[0].tokens
    dar = tokens.find { |t| t["id"] == "t9_m1" }
    undir = tokens.find { |t| t["id"] == "t9_m2" }
    assert_equal({ "id" => "t9_m1", "form" => "dar", "norm" => "dar",
                   "lemma" => "dâr", "join" => "right" }, dar)
    assert_equal({ "id" => "t9_m2", "form" => "undir", "norm" => "undir",
                   "lemma" => "under", "join" => "left" }, undir)
  end

  def test_punctuation_tokens_are_flagged_and_their_null_lemma_drops
    token = parser.body(M058).lines[0].tokens.find { |t| t["id"] == "t7_m1" }
    assert_equal({ "id" => "t7_m1", "form" => ".", "norm" => ".", "join" => "left", "pc" => true },
                 token, "upstream's '--' null lemma never rides as data")
  end

  def test_editorial_status_rides_as_token_flags
    lines = parser.body(M058).lines
    assert_equal true, lines[0].tokens.find { |t| t["id"] == "t1_m1" }["unclear"]
    ginge = lines[1].tokens.find { |t| t["id"] == "t14_m1" }
    assert_equal true, ginge["supplied"]
    assert_equal true, ginge["unclear"]
    assert_nil lines[0].tokens.find { |t| t["id"] == "t3_m1" }["unclear"]
  end

  def test_untagged_latin_tokens_keep_norm_but_no_lemma
    fides = parser.body(M218B).lines[0].tokens.find { |t| t["id"] == "t1_m1" }
    assert_equal({ "id" => "t1_m1", "form" => "Fídeſ", "norm" => "Fides" }, fides,
                 "the Latin lemma slot is upstream's '--' null")
  end

  def test_token_counts_match_the_header_extent
    [[M058, 23], [M218B, 34]].each do |path, expected|
      body = parser.body(path)
      assert_equal expected, body.lines.sum { |l| l.tokens.size },
                   "#{File.basename(path)}: header extent counts w AND pc tokens"
    end
  end

  # --- loudness -------------------------------------------------------------

  def test_body_census_is_clean_on_the_real_fixtures
    assert_empty parser.body(M058).unrecognized
    assert_empty parser.body(M218B).unrecognized
  end

  def test_unrecognized_elements_are_censused_not_fatal
    doctored = doctor(M058) do |xml|
      xml.sub("<w xml:id=\"t3_m1\"", "<seg>x</seg><w xml:id=\"t3_m1\"")
    end
    body = parser.body(doctored)
    assert_equal({ "#text" => 1, "seg" => 1 }, body.unrecognized,
                 "the element AND its untokenized text both count — nothing is dropped silently")
    assert_equal 2, body.lines.size, "the lines still parse"
  end

  def test_a_token_outside_any_line_is_structural_breakage
    doctored = doctor(M058) { |xml| xml.sub(%r{<lb n="5" ed="1"/>\s*}, "") }
    assert_raises(Nabu::ParseError) { parser.body(doctored) }
  end

  def test_malformed_xml_is_a_parse_error
    doctored = doctor(M058) { |xml| xml.sub("</TEI>", "") }
    assert_raises(Nabu::ParseError) { parser.body(doctored) }
  end

  private

  # A behavior probe: the REAL fixture with one surgical edit, in a tmpdir
  # (fixtures stay pristine; the edited copy documents the failure mode).
  def doctor(path)
    dir = Dir.mktmpdir("cora-tei-test")
    doctored = File.join(dir, File.basename(path))
    File.write(doctored, yield(File.read(path)))
    doctored
  end
end
