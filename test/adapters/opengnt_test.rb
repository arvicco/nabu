# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"
require "tmpdir"
require "fileutils"

# OpenGNT adapter tests: eliranwong/OpenGNT's base-text CSV
# (OpenGNT_version3_3.csv, one row per word, tab-separated, 〔…｜…〕-packed
# sub-columns), one document per NT book, one passage per verse. Includes
# the shared AdapterConformance suite against the trimmed real CSV (real
# header row; Matthew and Mark verse picks, 3 John whole). No network:
# fetch runs against WebMock.
class OpengntTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("opengnt")
  CSV_PATH = File.join(FIXTURES, "OpenGNT_version3_3.csv")

  BOOK_URNS = %w[urn:nabu:opengnt:3john urn:nabu:opengnt:mark urn:nabu:opengnt:matt].freeze

  def conformance_adapter
    Nabu::Adapters::Opengnt.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "opengnt"
  end

  def adapter = Nabu::Adapters::Opengnt.new

  def document(urn)
    a = adapter
    a.parse(a.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  def verse(urn)
    document(urn.sub(/:[^:]+\z/, "")).find { |p| p.urn == urn }
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_opengnt_source
    manifest = Nabu::Adapters::Opengnt.manifest
    assert_equal "opengnt", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_equal "https://github.com/eliranwong/OpenGNT", manifest.upstream_url
    assert_equal "opengnt-csv", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_with_sblgnt_stems
    refs = adapter.discover(FIXTURES).to_a
    assert_equal BOOK_URNS, refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "opengnt" && r.path == File.expand_path(CSV_PATH) })
    matt = refs.find { |r| r.id.end_with?(":matt") }
    assert_equal 40, matt.metadata["book_number"]
    assert_equal "Matthew", matt.metadata["title"]
  end

  def test_book_stems_mirror_the_sblgnt_minting_for_all_27_books
    stems = Nabu::Adapters::Opengnt::BOOKS.values.map(&:first)
    assert_equal 27, stems.size
    assert_equal (40..66).to_a, Nabu::Adapters::Opengnt::BOOKS.keys
    assert_equal %w[matt mark luke john acts rom 1cor 2cor gal eph phil col 1thess 2thess
                    1tim 2tim titus phlm heb jas 1pet 2pet 1john 2john 3john jude rev], stems
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  def test_an_unknown_book_number_is_a_loud_parse_error
    Dir.mktmpdir do |dir|
      lines = File.readlines(CSV_PATH)
      File.write(File.join(dir, "OpenGNT_version3_3.csv"),
                 lines[0] + lines[1].sub("〔40｜1｜1〕", "〔39｜1｜1〕"))
      error = assert_raises(Nabu::ParseError) { adapter.discover(dir).to_a }
      assert_match(/book number 39/, error.message)
    end
  end

  # The zip's only other member is the macOS AppleDouble resource fork
  # (__MACOSX/._OpenGNT_version3_3.csv, 319 bytes) — a rejected grain,
  # pinned real in the fixture tree and counted by rule.
  def test_discovery_skips_count_the_appledouble_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |n| n.include?("__MACOSX/._OpenGNT_version3_3.csv") })
  end

  def test_an_unexpected_file_in_the_tree_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp(CSV_PATH, dir)
      File.write(File.join(dir, "stray.tsv"), "x\n")
      File.write(File.join(dir, Nabu::ZipFetch::STATE_FILE), "{}")
      skips = adapter.discovery_skips(dir)
      assert_equal 0, skips.skipped_by_rule
      assert_equal 1, skips.unrecognized, "the ZipFetch state file is fetch bookkeeping, never counted"
      assert(skips.notes.any? { |n| n.include?("stray.tsv") })
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_matthew_at_verse_grain
    doc = document("urn:nabu:opengnt:matt")
    assert_equal "grc", doc.language
    assert_equal "Matthew", doc.title
    assert_equal(%w[1.1 1.2 1.23 2.16 4.16 8.8], doc.map { |p| p.urn.split(":").last })
    assert_equal "Βίβλος γενέσεως Ἰησοῦ Χριστοῦ υἱοῦ Δαυὶδ υἱοῦ Ἀβραάμ.", doc.first.text,
                 "the accented OGNTa column with its punctuation; the ¶ paragraph mark is layout"
  end

  def test_tokens_carry_lemma_morphology_strongs_and_louw_nida
    tokens = verse("urn:nabu:opengnt:matt:1.1").annotations.fetch("tokens")
    assert_equal 8, tokens.size
    assert_equal({ "id" => "000001", "form" => "Βίβλος", "lemma" => "βίβλος", "rmac" => "N-NSF",
                   "strong" => "G976", "ln" => "LN-33.38" }, tokens.first)
    assert_equal({ "id" => "000008", "form" => "Ἀβραάμ", "lemma" => "Ἀβραάμ", "rmac" => "N-GSM-P",
                   "strong" => "G11", "ln" => "LN-93.7", "pmf" => ".¶" }, tokens.last)
  end

  # ¬ (TANTT's line-layout mark before a quoted/poetic line) and ¶ are layout,
  # not text: kept verbatim on the token, never in the running text.
  def test_layout_marks_ride_tokens_not_text
    passage = verse("urn:nabu:opengnt:matt:1.23")
    refute_match(/[¬¶]/, passage.text)
    assert passage.text.start_with?("Ἰδοὺ ἡ παρθένος ἐν γαστρὶ ἕξει")
    assert_equal "¬", passage.annotations["tokens"].first["pmp"]
  end

  # Mark 16:20 carries the shorter ending inside the verse, bracketed [[ ]].
  def test_double_brackets_stay_in_the_text
    text = verse("urn:nabu:opengnt:mark:16.20").text
    assert_includes text, "σημείων.]] [[πάντα δὲ τὰ παρηγγελμένα"
    assert text.end_with?("ἀμήν.]]")
  end

  # The NA28-comparison columns: the Note marker (＊ differs from NA28, ＝
  # orthographic variant, ＋BYZ/＋BHP added words) and the NA28 reading.
  def test_na28_variant_columns_ride_the_token
    sk = verse("urn:nabu:opengnt:matt:4.16").annotations["tokens"].find { |t| t["form"] == "σκοτίᾳ" }
    assert_equal({ "note" => "＊", "mvar" => "σκότει", "mlexeme" => "σκότος", "mrmac" => "N-DSN",
                   "msn" => "G4655" }, sk.slice("note", "mvar", "mlexeme", "mrmac", "msn"))
    byz = verse("urn:nabu:opengnt:matt:8.8").annotations["tokens"].first
    assert_equal "＋BYZ", byz["note"]
    refute byz.key?("mvar"), "an added word has no NA28 reading"
  end

  # Upstream's lexeme column carries U+1FC6 U+0345 for πεζῇ (Mark 6:33) —
  # NFC at the boundary composes it to U+1FC7.
  def test_non_nfc_lemma_bytes_are_normalized
    raw = File.readlines(CSV_PATH).find { |l| l.include?("〔41｜6｜33〕") && l.include?("πεζη") }
    assert_includes raw, "πεζῇ", "the fixture keeps upstream's decomposed bytes"
    token = verse("urn:nabu:opengnt:mark:6.33").annotations["tokens"].find { |t| t["rmac"] == "ADV" }
    assert_equal "πεζῇ", token["lemma"]
    assert(token.values.all? { |v| v.unicode_normalized?(:nfc) })
  end

  def test_third_john_parses_whole
    doc = document("urn:nabu:opengnt:3john")
    assert_equal 15, doc.size
    assert_equal(218, doc.sum { |p| p.annotations["tokens"].size })
    assert_equal "Ὁ πρεσβύτερος Γαΐῳ τῷ ἀγαπητῷ, ὃν ἐγὼ ἀγαπῶ ἐν ἀληθείᾳ.", doc.first.text
    assert_equal "Εἰρήνη σοι. Ἀσπάζονταί σε οἱ φίλοι. Ἀσπάζου τοὺς φίλους κατ᾽ ὄνομα.", doc.passages.last.text
  end

  # --- the license split: excluded columns never emitted ---------------------

  # The bundled glosses/translations (TBESG, the Berean IT/LT/ST, the Spanish
  # literal — column 11, plus the NA28 variant's MTBESG gloss) and the SIL
  # Levinsohn discourse layer (LevinsohnClauseID, OTquotation) carry terms
  # outside the core CC BY-SA grant. They are excluded at parse: no token key
  # names them and no stored field carries their content.
  def test_excluded_columns_never_reach_any_passage_or_field
    excluded = excluded_column_values
    assert_includes excluded[:glosses], "[The] book", "Matt 1:1's Berean interlinear gloss is in the checked set"
    assert_includes excluded[:levinsohn], "c1"
    # A leak would surface as a whole stored value (a metadata or annotation
    # leaf) or inside the running text; the adapter's own vocabulary (key
    # names, the English book titles) is not upstream gloss content.
    values = []
    texts = []
    each_fixture_document do |doc|
      values.concat(leaves(doc.metadata))
      doc.each do |p|
        texts << p.text
        values.concat(leaves(p.annotations))
      end
    end
    text_blob = texts.join("\n")
    excluded[:glosses].each do |gloss|
      refute_includes values, gloss, "excluded gloss/translation #{gloss.inspect} stored as a value"
      refute_includes text_blob, gloss, "excluded gloss/translation #{gloss.inspect} leaked into text"
    end
    tokens = []
    each_fixture_document { |doc| doc.each { |p| tokens.concat(p.annotations["tokens"]) } }
    allowed = %w[id form lemma rmac strong ln pmp pmf note mvar mlexeme mrmac msn]
    assert_empty tokens.flat_map(&:keys).uniq - allowed
    values = tokens.flat_map(&:values)
    assert_empty values & excluded[:levinsohn], "Levinsohn clause ids / OT flags never ride a token"
  end

  # --- idempotency -------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "opengnt", name: "OpenGNT",
                                        adapter_class: "Nabu::Adapters::Opengnt",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 26, catalog[:passages].count

    second = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      FileUtils.cp(CSV_PATH, dir)
      FileUtils.cp_r(File.join(FIXTURES, "__MACOSX"), dir)
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "OpenGNT_version3_3.csv", "__MACOSX") }
      File.binread(zip)
    end
  end

  def test_artifact_url_is_pinned_to_the_commit_sha
    url = Nabu::Adapters::Opengnt::ARTIFACT_URL
    assert_includes url, Nabu::Adapters::Opengnt::COMMIT_SHA
    assert_match(/\A[0-9a-f]{40}\z/, Nabu::Adapters::Opengnt::COMMIT_SHA)
    assert url.end_with?("/OpenGNT_BASE_TEXT.zip")
  end

  def test_fetch_pins_the_zip_sha_and_discovers_the_books
    body = zip_body
    stub_request(:get, Nabu::Adapters::Opengnt::ARTIFACT_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      fetcher = Nabu::Adapters::Opengnt.new(pin: Digest::SHA256.hexdigest(body))
      report = fetcher.fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal BOOK_URNS, fetcher.discover(workdir).map(&:id)
      assert_equal 1, fetcher.discovery_skips(workdir).skipped_by_rule
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_pin
    stub_request(:get, Nabu::Adapters::Opengnt::ARTIFACT_URL).to_return(status: 200, body: zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256/, error.message)
      assert_empty Dir.glob(File.join(workdir, "*.csv")), "a refused fetch leaves no tree"
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_row_is_wired_manual_on_the_biblical_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["opengnt"]
    refute_nil entry, "opengnt must be registered in config/sources/"
    assert_equal Nabu::Adapters::Opengnt, entry.adapter_class
    assert entry.wired, "wired after the verified first sync"
    assert_equal "manual", entry.sync_policy
    assert_equal ["biblical"], entry.axes
    assert_equal Nabu::Adapters::Opengnt.manifest, entry.manifest
  end

  private

  def leaves(value)
    case value
    when Hash then value.values.map { |v| leaves(v) }
    when Array then value.map { |v| leaves(v) }
    else [value.to_s]
    end
  end

  def each_fixture_document(&)
    a = adapter
    a.discover(FIXTURES).each { |ref| yield a.parse(ref) }
  end

  # Every excluded column's content, read straight from the fixture CSV.
  def excluded_column_values
    glosses = []
    levinsohn = []
    File.readlines(CSV_PATH, chomp: true).drop(1).each do |line|
      cols = line.split("\t", -1)
      levinsohn << cols[3] << cols[4]
      glosses.concat(cols[10].delete("〔〕").split("｜", -1))
      glosses << cols[12].delete("〔〕").split("｜", -1).last
    end
    # Glosses: whole values only, and only those carrying a Latin letter
    # (a lone punctuation gloss could never be told apart from the text).
    glosses = glosses.map { |g| Nabu::Normalize.nfc(g) }.uniq.select { |g| g.length >= 3 && g.match?(/[A-Za-z]/) }
    { glosses: glosses, levinsohn: levinsohn.uniq }
  end
end
