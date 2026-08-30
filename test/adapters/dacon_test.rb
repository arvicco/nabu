# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::Dacon (P88-A4): DACON — the Diachronic Annotated Corpus of
# Newar (O'Neill & Meelen, AHRC "The Emergence of Egophoricity"; Zenodo
# record 12887386, CC BY 4.0) — segmented + POS-tagged Classical Newar
# (nwc), 12th–19th c., IAST romanization. Four texts upstream; the fixture
# set carries the three FORMAT VARIANTS the 2026-08-29 census found:
#
#   cnew12   LF, NO header, 4-space separator, ZERO <utt> lines (whole file)
#   cnew13_14  UTF-8 BOM + CRLF + "form    POS" header, 4-space, <utt> blocks
#   cnew17   CRLF + "form\tPOS" header, TAB separator (head trim, no <utt>)
#
# The passage grain is upstream's own <utt> segmentation — the trailing
# block after the last <utt> mints too, and a file with no <utt> at all
# (the tiny Ukubāhāḥ inscription) honestly yields ONE passage. `fol`-tagged
# foliation tokens ([1], *fn30a) never enter the text or the token list;
# they ride the passage's "folios" annotation in order.
class DaconTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("dacon")

  UKUBAHAH = "urn:nabu:dacon:cnew12-ukubahah"
  GOPALA = "urn:nabu:dacon:cnew13_14-gopala"
  VETALA = "urn:nabu:dacon:cnew17-vetala-msb-10000"

  def adapter = Nabu::Adapters::Dacon.new
  def conformance_adapter = Nabu::Adapters::Dacon.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "dacon"

  # --- manifest -------------------------------------------------------------

  def test_manifest_identifies_the_dacon_source
    manifest = adapter.manifest
    assert_equal "dacon", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(%r{10\.5281/zenodo\.12887386}, manifest.license,
                 "the citable DOI rides the license text")
    assert_equal "dacon-pos", manifest.parser_family
  end

  # --- discover -------------------------------------------------------------

  def test_discover_yields_one_ref_per_pos_file_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal [UKUBAHAH, GOPALA, VETALA], refs.map(&:id),
                 "one ref per *_POS.txt, urn = downcased stem, sorted"
  end

  def test_seg_renditions_are_censused_discovery_skips
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule,
                 "the *_SEG.txt files are renditions of the same documents, never documents"
  end

  # --- parse: the three format variants -------------------------------------

  def test_the_headerless_lf_inscription_parses_whole_as_one_passage
    document = adapter.parse(ref_for(UKUBAHAH))
    assert_equal "nwc", document.language
    assert_equal 1, document.passages.size, "no <utt> lines — the whole inscription is one passage"
    passage = document.passages.first
    assert_equal "#{UKUBAHAH}:utt-1", passage.urn
    assert passage.text.start_with?("siddhaṃ svasti . sambat ā la hṛ mārgasira kṛṣṇa"),
           "text is the space-joined forms; got #{passage.text[0, 60].inspect}"
    assert_equal %w[[1] [2] [3] [4] [5]], passage.annotations.fetch("folios"),
                 "fol-tagged markers ride the folios annotation in order"
    assert_equal 229, passage.annotations.fetch("tokens").size,
                 "fol tokens never enter the token list"
    refute passage.text.include?("[1]"), "fol markers never enter the text"
  end

  def test_the_bom_crlf_headered_file_splits_on_utt_blocks
    document = adapter.parse(ref_for(GOPALA))
    assert_equal 5, document.passages.size, "4 <utt> boundaries + the trailing block"
    first = document.passages.first
    assert_equal "#{GOPALA}:utt-1", first.urn
    assert_equal "samvat 501 mārgaśira va 12 oṃ śrīviṣṇugupta rājā sana prathamasa ,", first.text
    assert_equal ["*fn30a", "fn30b"], first.annotations.fetch("folios")
    assert_equal 11, first.annotations.fetch("tokens").size
    assert_equal({ "form" => "samvat", "pos" => "n" }, first.annotations.fetch("tokens").first)
    refute first.text.include?("form"), "the form/POS header line is never a token"
    assert_equal "thva yocaṃguṃ dhāye ..", document.passages.last.text
  end

  def test_the_tab_separated_file_parses
    document = adapter.parse(ref_for(VETALA))
    assert_equal 1, document.passages.size
    passage = document.passages.first
    assert passage.text.start_with?("oṃ namaḥ śivāya || namāmi maṃjuśriyam"),
           "got #{passage.text[0, 60].inspect}"
    assert_equal ["fn1b"], passage.annotations.fetch("folios")
    assert_equal 118, passage.annotations.fetch("tokens").size
  end

  # --- dating: the century envelope from the deposit's own stems ------------

  def test_documents_carry_the_century_envelope_from_their_stems
    ukubahah = adapter.parse(ref_for(UKUBAHAH))
    assert_equal({ "not_before" => 1101, "not_after" => 1200, "raw" => "12th century" },
                 ukubahah.metadata.fetch("date"))
    gopala = adapter.parse(ref_for(GOPALA))
    assert_equal({ "not_before" => 1201, "not_after" => 1400, "raw" => "13th–14th century" },
                 gopala.metadata.fetch("date"))
    assert_equal "Gopālarājavaṃśāvalī", gopala.title
    vetala = adapter.parse(ref_for(VETALA))
    assert_equal({ "not_before" => 1601, "not_after" => 1700, "raw" => "17th century" },
                 vetala.metadata.fetch("date"))
  end

  # --- the 26 censused dirty lines tolerate honestly ------------------------

  def test_censused_dirty_line_shapes_mint_honest_tokens
    # The real irregular lines verbatim (2026-08-29 census: cnew13_14 ×21 +
    # cnew17 ×5): tag-less forms, a glued form+tag, a separator-only line,
    # and the deposit's single three-field line.
    io = StringIO.new("sambat\tn\n..\n*saṃvat\n\t\nśuklaadj\nnan    na    case.abl\n")
    document = Nabu::Adapters::DaconPosParser.new.parse(
      io, urn: "urn:nabu:dacon:cnew13_14-gopala", language: "nwc"
    )
    tokens = document.passages.first.annotations.fetch("tokens")
    assert_equal [{ "form" => "sambat", "pos" => "n" }, { "form" => ".." },
                  { "form" => "*saṃvat" }, { "form" => "śuklaadj" },
                  { "form" => "nan na", "pos" => "case.abl" }], tokens,
                 "one field = form-only (no invented pos); whitespace-only skips; " \
                 "extra fields anchor the tag on the LAST separator"
  end

  # --- loader round-trip + idempotency --------------------------------------

  def test_load_twice_is_idempotent
    db = store_test_db
    source = create_source
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 7, db[:passages].count, "1 + 5 + 1 across the three fixture variants"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 7, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  private

  def ref_for(urn)
    adapter.discover(FIXTURES).find { |ref| ref.id == urn } ||
      flunk("no fixture ref #{urn}")
  end

  def create_source
    Nabu::Store::Source.create(
      slug: "dacon", name: "DACON", adapter_class: "Nabu::Adapters::Dacon",
      license_class: "attribution"
    )
  end
end
