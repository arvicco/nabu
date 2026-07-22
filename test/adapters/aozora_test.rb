# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Aozora Bunko adapter tests (P38-3, first of the aozora-ruby family).
# Fixtures are three REAL upstream work zips (Irving trans.: 驛傳馬車 056078,
# old kanji/kana + gaiji; ウェストミンスター寺院 059898, ruby-dense; and the
# P38-i1 regression exemplar 検疫と荷物検査 051135, whose zip member name is
# invalid in UTF-8 AND CP932) plus the index CSV trimmed to their person-work
# rows AND the in-copyright work 054333 — whose zip is deliberately absent:
# D38-a says discovery excludes in-copyright works BEFORE any file access,
# and this suite pins exactly that. A documented 4 KB trim of upstream's
# genuinely corrupt 56151_ruby_60063.zip (no central directory) pins the
# quarantine-not-abort error contract.
class AozoraTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("aozora")

  URN_51135 = "urn:nabu:aozora:051135"
  URN_56078 = "urn:nabu:aozora:056078"
  URN_59898 = "urn:nabu:aozora:059898"
  ALL_URNS = [URN_51135, URN_56078, URN_59898].freeze # discover order (work-id sorted)

  # --- AdapterConformance hooks ----------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Aozora.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "aozora"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Aozora.manifest
    assert_equal "aozora", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/自由に複製・再配布/, manifest.license)
    assert_match(/底本/, manifest.license)
    assert_equal "https://github.com/aozorabunko/aozorabunko", manifest.upstream_url
    assert_equal "aozora-ruby", manifest.parser_family
  end

  # --- discover (index-driven, D38-a) -----------------------------------------

  def test_discover_yields_pd_works_with_text_deduped_by_work_id
    refs = Nabu::Adapters::Aozora.new.discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id)
    refs.each do |ref|
      assert_equal "aozora", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "the PD fixture zips exist on disk"
    end
    by_id = refs.to_h { |ref| [ref.id, ref] }
    ref = by_id[URN_56078]
    assert_equal "056078", ref.metadata["work_id"]
    assert_equal "駅伝馬車", ref.metadata["index_title"]
    assert_equal "旧字旧仮名", ref.metadata["orthography"]
    assert_equal "https://www.aozora.gr.jp/cards/001257/card56078.html", ref.metadata["card_url"]
    assert_equal ["アーヴィング ワシントン"], ref.metadata["authors"]
    assert_equal ["高垣 松雄"], ref.metadata["translators"]
    assert ref.path.end_with?("cards/001257/files/56078_ruby_51155.zip"),
           "zip path maps through the card-url author id: #{ref.path}"
  end

  # THE D38-a PIN: the in-copyright work (作品著作権フラグ=あり) is present in
  # the fixture index and its zip is deliberately absent — discovery must
  # exclude it by rule, silently-as-in-no-error but censused, without ever
  # touching the filesystem for it.
  def test_discover_excludes_the_in_copyright_work_before_any_file_access
    adapter = Nabu::Adapters::Aozora.new
    refs = adapter.discover(FIXTURES).to_a
    refute refs.any? { |ref| ref.id.include?("054333") },
           "in-copyright work 054333 must never be discovered (D38-a)"
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule, "the excluded in-copyright work is censused"
    # The corrupt-zip fixture (56151_ruby_60063.zip, P38-i1) has no index
    # row — upstream re-proofed the work, so the live index points at
    # …_70005.zip — which makes it a REAL stranded-zip exemplar for the
    # unrecognized lane: loudly censused, never silently ignored.
    assert_equal 1, skips.unrecognized
    assert_match(/56151_ruby_60063\.zip/, skips.notes.join)
  end

  def test_discover_reads_the_index_from_the_upstream_zip_form_too
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "cards"), root)
      FileUtils.mkdir_p(File.join(root, "index_pages"))
      Dir.mktmpdir do |staging|
        FileUtils.cp(File.join(FIXTURES, "index_pages", "list_person_all_extended_utf8.csv"), staging)
        Nabu::Shell.run("zip", "-q", "-j",
                        File.join(root, "index_pages", "list_person_all_extended_utf8.zip"),
                        File.join(staging, "list_person_all_extended_utf8.csv"))
      end
      refs = Nabu::Adapters::Aozora.new.discover(root).to_a
      assert_equal ALL_URNS, refs.map(&:id)
    end
  end

  def test_discover_yields_nothing_without_an_index
    Dir.mktmpdir do |root|
      assert_empty Nabu::Adapters::Aozora.new.discover(root).to_a
    end
  end

  def test_a_zip_on_disk_with_no_index_row_is_unrecognized
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "cards"), root)
      FileUtils.cp_r(File.join(FIXTURES, "index_pages"), root)
      stray = File.join(root, "cards", "000148", "files")
      FileUtils.mkdir_p(stray)
      File.write(File.join(stray, "773_ruby_5968.zip"), "stub")
      skips = Nabu::Adapters::Aozora.new.discovery_skips(root)
      # 2 = the added stub + the corrupt row-less fixture zip copied along
      # (56151_ruby_60063.zip, the P38-i1 stranded exemplar).
      assert_equal 2, skips.unrecognized
      refute_predicate skips, :clean?
      assert_match(/773_ruby_5968\.zip/, skips.notes.join)
      assert_match(/56151_ruby_60063\.zip/, skips.notes.join)
    end
  end

  # A PD work whose zip is MISSING from the sparse checkout is loud at parse
  # (quarantine), never a silent skip.
  def test_parse_is_loud_when_a_pd_work_zip_is_absent
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "index_pages"), root)
      adapter = Nabu::Adapters::Aozora.new
      ref = adapter.discover(root).to_a.find { |r| r.id == URN_56078 }
      refute_nil ref, "PD works are discovered from the index even when the zip is absent"
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/missing from the sparse checkout/, error.message)
    end
  end

  # --- parse: the P38-i1 incident regressions ---------------------------------

  # THE ENCODING REGRESSION (incident P38-i1): 51135_ruby_65180.zip is a
  # real, whole upstream zip whose single member is named
  # ken\xFCfekito_nimotsu_kensa.txt — 0xFC is invalid in UTF-8 AND CP932.
  # Pre-fix, String#split on the `unzip -Z1` listing raised ArgumentError
  # and killed the whole sync at document ~9,471. This test feeds those real
  # listing bytes through the real path: the work must parse SUCCESSFULLY
  # (binary-safe member handling; the junk name is never decoded — the
  # single-member zip extracts positionally, name unspoken).
  def test_a_zip_with_a_non_utf8_member_name_parses_successfully
    document = parse(URN_51135)
    assert_equal "検疫と荷物検査", document.title
    assert_equal 9, document.size, "9 non-blank body lines, none command-only"
    first = document.passages.first
    assert_includes first.text, "ゴールデンゲートを過ぎてから"
    assert_includes first.annotations["ruby"], { "base" => "午後", "reading" => "ごゞ" }
    assert_includes first.annotations["ruby"], { "base" => "時", "reading" => "じ" }, "the ｜-scoped 三｜時《じ》"
  end

  # THE ERROR-CONTRACT REGRESSION (incident P38-i1): upstream ships
  # genuinely corrupt zips (this fixture is a documented 4 KB trim of the
  # real 549 KB 56151_ruby_60063.zip — "central directory not found" either
  # way). Any per-document zip failure must be ParseError (loud quarantine,
  # sync continues), never an escaping Shell::Error/ArgumentError that
  # aborts a 17.5k-doc sync.
  def test_a_corrupt_zip_quarantines_with_parse_error_never_aborts
    corrupt = File.join(FIXTURES, "cards", "001562", "files", "56151_ruby_60063.zip")
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::AozoraRubyParser.new.parse(corrupt, urn: "urn:nabu:aozora:056151")
    end
    assert_match(/56151_ruby_60063\.zip/, error.message)
    assert_match(/unreadable zip/, error.message)
  end

  # --- parse: the no-legend legacy shape (P39-2 quarantine recovery) -----------

  # The first full sync quarantined 1,191 works, ALL "no legend delimiter":
  # 1,185 no-ruby _txt_ works + 6 legacy _ruby_ works that carry no 55-hyphen
  # legend block (there is no markup to explain). Censused shape: title/byline,
  # blank line, body, 底本 colophon. These two fixtures are REAL, WHOLE upstream
  # zips from the owner's canonical (retrieved 2026-07-22), both formerly
  # quarantined, both recover here. See test/fixtures/aozora/README.md.
  LEGACY_TXT = "legacy/53411_txt_43155.zip"  # 看痾, 宮沢賢治 (no-ruby _txt_ variant)
  LEGACY_RUBY = "legacy/4356_ruby_7914.zip"  # 五所川原, 太宰治 (_ruby_-named, no legend)

  def test_no_legend_txt_variant_parses_via_the_legacy_shape
    document = parse_zip(LEGACY_TXT, "urn:nabu:aozora:053411")
    assert_equal "看痾", document.title, "line 0 is the title even with no legend delimiter"
    assert_equal ["宮沢賢治"], document.metadata["header"], "the byline rides header metadata"
    assert_equal "no_legend", document.metadata["parser_shape"], "the widened path is stamped, never silent"
    assert_equal 4, document.size, "4 verse body lines mint passages; blanks and colophon do not"
    assert_equal "七月はさやに来れど", document.passages.first.text
    assert_equal "「新修宮沢賢治全集　第六巻」筑摩書房", document.metadata["teihon"]
    document.each do |passage|
      refute_includes passage.text, "底本", "colophon lines never leak into passages"
    end
  end

  def test_no_legend_ruby_variant_parses_via_the_legacy_shape
    document = parse_zip(LEGACY_RUBY, "urn:nabu:aozora:004356")
    assert_equal "五所川原", document.title
    assert_equal ["太宰治"], document.metadata["header"]
    assert_equal "no_legend", document.metadata["parser_shape"]
    assert_equal 3, document.size, "3 body paragraphs mint passages"
    assert_includes document.passages.first.text, "叔母が五所川原にゐるので"
    assert_equal "「太宰治全集　10」筑摩書房", document.metadata["teihon"]
    assert_equal "砂場清隆", document.metadata["inputter"]
  end

  # The fence: a decoded file with no blank line separating a header from a
  # body is genuinely structureless — it stays quarantined (never guessed at).
  def test_a_structureless_file_still_quarantines
    Dir.mktmpdir do |dir|
      txt = File.join(dir, "junk.txt")
      File.write(txt, "只有一行文字並無空行".encode(Encoding::Windows_31J), mode: "wb")
      zip = File.join(dir, "900002_txt_1.zip")
      Nabu::Shell.run("zip", "-q", "-j", zip, txt)
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::AozoraRubyParser.new.parse(zip, urn: "urn:nabu:aozora:900002")
      end
      assert_match(%r{no header/body separation}, error.message)
    end
  end

  # --- parse: index-declared encoding (P39-2) ---------------------------------

  # CP932 is the near-universal encoding, but the index self-declares per file
  # (テキストファイル符号化方式). When it says UTF-8, the parser must honor it,
  # not force CP932. (The 5 UTF-8 works upstream are all in-copyright + off-repo
  # so never discovered today; this pins the honest seam, not a live case.)
  def test_index_declared_utf8_encoding_is_honored
    document = parse_rig("　これはユニコードの本文である。\n", encoding: Encoding::UTF_8, file_encoding: "UTF-8")
    assert_equal "　これはユニコードの本文である。", document.passages.first.text
  end

  # Absent/blank declaration falls back to CP932 (the upstream default).
  def test_absent_encoding_declaration_defaults_to_cp932
    document = parse_rig("　通常のＣＰ９３２本文。\n")
    assert_equal "　通常のＣＰ９３２本文。", document.passages.first.text
  end

  # --- parse: structure --------------------------------------------------------

  def test_56078_parses_header_body_colophon
    document = parse(URN_56078)
    assert_equal "驛傳馬車", document.title, "title = the file's own header line (kyūjitai), not the index's"
    assert_equal "jpn", document.language
    assert_equal 26, document.size, "26 body lines mint passages (30 non-blank minus 4 command-only)"
    assert_equal "いざ、これより樂しまむ、", document.passages.first.text
    assert_equal "#{URN_56078}:1", document.passages.first.urn
    assert_equal %w[アーヴィング 高垣松雄訳], document.metadata["header"]
    # The colophon is provenance metadata, never passage text.
    assert_includes document.metadata["colophon"], "底本：「スケッチ・ブック」岩波文庫、岩波書店"
    assert_equal "「スケッチ・ブック」岩波文庫、岩波書店", document.metadata["teihon"]
    assert_equal "雀", document.metadata["inputter"]
    assert_equal "小林繁雄", document.metadata["proofer"]
    document.each do |passage|
      refute_includes passage.text, "底本", "colophon lines must not leak into passages"
      refute_includes passage.text, "【テキスト中に現れる記号について】", "the legend is not text"
    end
  end

  def test_59898_parses_with_index_metadata_carried
    document = parse(URN_59898)
    assert_equal "ウェストミンスター寺院", document.title
    assert_equal 45, document.size, "45 body lines mint passages (51 non-blank minus 6 command-only)"
    assert_equal "新字新仮名", document.metadata["orthography"]
    assert_equal "059898", document.metadata["work_id"]
  end

  # --- parse: ruby (furigana) --------------------------------------------------

  def test_ruby_is_stripped_from_text_and_kept_as_annotations
    document = parse(URN_56078)
    passage = find_passage(document, "洋燈")
    refute_includes passage.text, "《", "ruby markup never survives into passage text"
    refute_includes passage.text, "》"
    assert_includes passage.text, "洋燈の光"
    assert_includes passage.annotations["ruby"], { "base" => "洋燈", "reading" => "ランプ" }
  end

  def test_ruby_auto_boundary_takes_the_maximal_same_class_run
    document = parse(URN_56078)
    # 「ありとあらゆる端下《はした》仕事」: the hiragana る stops the kanji
    # run, so the base is exactly 端下 — never あらゆる端下.
    passage = find_passage(document, "端下仕事")
    assert_includes passage.annotations["ruby"], { "base" => "端下", "reading" => "はした" }
    total = document.sum { |p| (p.annotations["ruby"] || []).size }
    assert_equal 22, total, "every 《…》 in the 56078 body is a ruby annotation"
  end

  def test_ruby_explicit_pipe_scopes_the_base_and_is_removed
    document = parse(URN_59898)
    # The survey's own example is real body text here: 物｜云《い》わぬ.
    passage = find_passage(document, "物云わぬ魂")
    refute_includes passage.text, "｜", "the U+FF5C boundary marker never survives into text"
    assert_includes passage.annotations["ruby"], { "base" => "云", "reading" => "い" }
    total = document.sum { |p| (p.annotations["ruby"] || []).size }
    assert_equal 124, total
  end

  # --- parse: gaiji ------------------------------------------------------------

  # 56078 carries 4 gaiji notations in the raw file; one is the legend's
  # example, so the BODY carries 3 — all class (a) JIS X 0213 kuten, all
  # mechanically resolved into the text (upstream's own identity claim).
  def test_kuten_gaiji_resolve_into_the_text_with_annotations
    document = parse(URN_56078)
    entries = document.flat_map { |p| p.annotations["gaiji"] || [] }
    assert_equal 3, entries.size
    assert_equal 0, document.metadata.fetch("gaiji_unresolved", 0)

    # 第4水準2-13-28 → U+63F7 揷 (「插」でつくりの縦棒が下に突き抜けている).
    passage = find_passage(document, "釦孔に揷")
    refute_includes passage.text, "※［＃", "resolved gaiji leave no notation behind"
    entry = passage.annotations["gaiji"].first
    assert_equal "kuten", entry["class"]
    assert_equal "2-13-28", entry["kuten"]
    assert_equal "揷", entry["char"]
    assert_equal "「插」でつくりの縦棒が下に突き抜けている", entry["desc"]

    # 第3水準1-93-84 → U+97DB 韛 — and the following ruby 《ふいご》 attaches
    # to the RESOLVED character (gaiji resolve before ruby scoping).
    passage = find_passage(document, "韛に風を送つてゐる")
    assert_includes passage.annotations["ruby"], { "base" => "韛", "reading" => "ふいご" }
    assert(passage.annotations["gaiji"].any? { |g| g["char"] == "韛" && g["kuten"] == "1-93-84" })
  end

  # Classes (b) and (c) have no fixture instance (the two PD fixture works
  # carry only kuten gaiji); they are exercised on a rig zip carrying the
  # survey's VERBATIM upstream examples (aozora-survey §4c, quoted from
  # fetched files — never invented notation).
  def test_explicit_unicode_gaiji_resolves_directly_into_text
    document = parse_rig(<<~BODY)
      　彼は※［＃「執／糸」、U+7E36、171-本文-4］の字を書いた。
      　石は※［＃「石＋炯のつくり」、U+2544E、103-本文-11］であった。
    BODY
    assert_equal 2, document.size
    first, second = document.passages
    assert_includes first.text, "縶の字"
    entry = first.annotations["gaiji"].first
    assert_equal({ "class" => "unicode", "desc" => "執／糸", "codepoint" => "U+7E36",
                   "char" => "縶", "loc" => "171-本文-4" }, entry)
    # Plane-2 (SIP) codepoints resolve too.
    assert_includes second.text, [0x2544E].pack("U*")
  end

  def test_component_description_gaiji_stays_a_loud_verbatim_sentinel
    # Survey verbatim modulo the decoder: the survey shows 叟−又 (U+2212, the
    # plain-Shift_JIS reading of byte 0x817C); CP932/Windows-31J — the P38-3
    # decode ruling for real files — maps that byte to U+FF0D, so the
    # round-tripped rig carries －.
    notation = "※［＃「娉」の「由」に代えて「叟－又」、161-本文-1］"
    document = parse_rig("　まことに#{notation}の字なり。\n")
    passage = document.passages.first
    assert_includes passage.text, notation, "the unresolvable notation stays verbatim in the text"
    entry = passage.annotations["gaiji"].first
    assert_equal "unresolved", entry["class"]
    assert_equal notation, entry["notation"]
    assert_equal 1, document.metadata["gaiji_unresolved"], "counted loudly at document level"
  end

  # A kuten reference the table cannot resolve is NEVER guessed: it falls to
  # the same loud sentinel path.
  def test_unmapped_kuten_falls_back_to_the_sentinel
    notation = "※［＃「金＋且」、第3水準1-99-99］"
    document = parse_rig("　例の#{notation}の字。\n")
    passage = document.passages.first
    assert_includes passage.text, notation
    assert_equal "unresolved", passage.annotations["gaiji"].first["class"]
    assert_equal 1, document.metadata["gaiji_unresolved"]
  end

  # P39-r1: the BARE men-ku-ten form ※［＃<name>、N-N-N［、loc］］ carries the
  # SAME JIS X 0213 identity as the prefixed 第N水準 form — upstream states the
  # plane-row-cell directly and the 第N水準 level word is documentation. The
  # live census (2026-07-22) is 16,137 such occurrences, 85% of the unresolved
  # pool; every one resolves through the shipped table. So the bare form
  # resolves into the text exactly like the prefixed form. Notations below are
  # the census's own top glyphs, never invented.
  def test_bare_kuten_gaiji_resolves_into_the_text
    document = parse_rig("　これは※［＃二の字点、1-2-22］の記号。\n")
    passage = document.passages.first
    refute_includes passage.text, "※［＃", "the bare-kuten notation resolves, leaving no sentinel"
    assert_includes passage.text, "〻", "1-2-22 → 〻 (U+303B) goes into the text"
    entry = passage.annotations["gaiji"].first
    assert_equal({ "class" => "kuten", "desc" => "二の字点", "kuten" => "1-2-22", "char" => "〻" }, entry)
    assert_equal 0, document.metadata.fetch("gaiji_unresolved", 0)
  end

  # The name may itself wrap 「…」 and a page locator may trail the code — both
  # ride through. And a plane-2 identity resolves too: 「宀／成」、2-8-2 is a
  # composition-STYLE name that nonetheless carries a real men-ku-ten, so the
  # identity claim wins (the ／ is only documentation, U+5BAC 宬 the truth).
  def test_bare_kuten_with_bracketed_name_locator_and_plane_two
    document = parse_rig(<<~BODY)
      　終わり※［＃終わり二重括弧、1-2-55、279-2］の記号。
      　これは※［＃「宀／成」、2-8-2、199-10］の字。
    BODY
    first, second = document.passages
    assert_includes first.text, [0xFF60].pack("U*"), "1-2-55 → ｠"
    entry = first.annotations["gaiji"].first
    assert_equal "kuten", entry["class"]
    assert_equal "279-2", entry["loc"]
    assert_includes second.text, "宬", "plane-2 2-8-2 → 宬 (U+5BAC)"
    assert_equal "宀／成", second.annotations["gaiji"].first["desc"]
    assert_equal 0, document.metadata.fetch("gaiji_unresolved", 0)
  end

  # A bare code the table cannot map is NEVER guessed — it falls to the same
  # loud sentinel as an unmapped prefixed code (the resolve() guard, mirroring
  # test_unmapped_kuten_...; ku 99 is out of the 1..94 range, so the cell is
  # unmapped and the notation stays verbatim).
  def test_unmapped_bare_kuten_falls_back_to_the_sentinel
    notation = "※［＃感嘆符二つ、1-99-99］"
    document = parse_rig("　例の#{notation}の字。\n")
    passage = document.passages.first
    assert_includes passage.text, notation
    assert_equal "unresolved", passage.annotations["gaiji"].first["class"]
    assert_equal 1, document.metadata["gaiji_unresolved"]
  end

  # DISJOINTNESS 1 — the P39-5 component-description lane is untouched: a
  # composition formula whose trailing token is a PAGE locator (two numeric
  # groups, 305-11) is NOT a men-ku-ten (three groups), so it never resolves
  # and stays the loud verbatim sentinel. (「木／喬」 is a live census desc.)
  def test_component_description_with_page_locator_is_not_read_as_kuten
    notation = "※［＃「木／喬」、305-11］"
    document = parse_rig("　その#{notation}の木。\n")
    passage = document.passages.first
    assert_includes passage.text, notation, "a 2-group page locator never resolves as a codepoint"
    entry = passage.annotations["gaiji"].first
    assert_equal "unresolved", entry["class"]
    assert_equal "木／喬", entry["desc"]
    assert_equal 1, document.metadata["gaiji_unresolved"]
  end

  # DISJOINTNESS 2 — a formatting command ［＃…］ (no ※) never enters the gaiji
  # grammar: the ※ gate (GAIJI scanned before COMMAND) means the widened bare-
  # kuten rule cannot swallow a bracket command.
  def test_formatting_command_is_not_swallowed_by_bare_kuten
    document = parse_rig("　本文［＃ここから２字下げ］の段落。\n")
    passage = document.passages.first
    assert_equal "　本文の段落。", passage.text
    assert_nil passage.annotations["gaiji"], "no ［＃…］-without-※ ever becomes a gaiji"
    assert_includes passage.annotations["commands"], "ここから２字下げ"
  end

  # --- parse: formatting commands ---------------------------------------------

  def test_formatting_commands_never_reach_passage_text
    # Both fixture works resolve all their gaiji, so no ［＃ of any kind may
    # survive into text (an unresolved-gaiji sentinel would be the one
    # legitimate carrier — none here).
    [URN_56078, URN_59898].each do |urn|
      parse(urn).each do |passage|
        refute_match(/［＃/, passage.text, "#{passage.urn}: bracket commands must be stripped")
      end
    end
  end

  def test_block_commands_on_their_own_line_annotate_the_next_passage
    document = parse(URN_56078)
    first = document.passages.first
    assert_includes first.annotations["commands"], "ここから２字下げ"
  end

  def test_inline_commands_annotate_their_own_passage
    document = parse(URN_56078)
    passage = find_passage(document, "――學校休暇の歌")
    assert_includes passage.annotations["commands"], "地から２字上げ"
    # Emphasis command: 「まし」に傍点 — the quoted text stays in the passage.
    passage = find_passage(document, "一人で食べるよりはまし")
    assert_includes passage.annotations["commands"], "「まし」に傍点"
  end

  # An UNKNOWN bracket command is annotation + a loud document-level count —
  # never passage text, and never a quarantine (a 17.5k-work corpus with a
  # long-tail command vocabulary would quarantine absurdly; the loud census
  # is the honesty mechanism).
  def test_unknown_commands_are_annotated_and_counted_never_quarantined
    document = parse_rig("　本文の前に。\n［＃ここから謎の未知組版指定］\n　本文の後に。\n")
    assert_equal 2, document.size
    second = document.passages.last
    assert_includes second.annotations["unknown_commands"], "ここから謎の未知組版指定"
    assert_equal ["ここから謎の未知組版指定"], document.metadata["unknown_commands"]
    document.each { |p| refute_includes p.text, "［＃" }
  end

  def test_a_heading_command_maps_to_structure
    document = parse_rig("江戸城の秋［＃「江戸城の秋」は中見出し］\n　本文である。\n")
    heading = document.passages.first
    assert_equal "江戸城の秋", heading.text
    assert_equal({ "text" => "江戸城の秋", "kind" => "中見出し" }, heading.annotations["heading"])
  end

  # --- load: idempotency (the house double-load rule) -------------------------

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = aozora_source
    loader = Nabu::Store::Loader.new(db: catalog, source: source)
    first = loader.load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal 3, first.added
    assert_equal 0, first.errored

    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                 "an unchanged corpus must not fake content revisions"
  end

  # --- fetch (local git only, no network) -------------------------------------

  def test_fetch_materializes_only_the_sparse_text_cone
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_upstream_repo(upstream)
      workdir = File.join(root, "work")
      adapter = aozora_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.file?(File.join(workdir, "cards", "001257", "files", "56078_ruby_51155.zip"))
      assert File.file?(File.join(workdir, "cards", "001657", "files", "54333_ruby_67471.zip")),
             "the cone is license-blind — the index, not the cone, excludes in-copyright works"
      assert File.file?(File.join(workdir, "index_pages", "list_person_all_extended_utf8.zip"))
      refute File.exist?(File.join(workdir, "cards", "001257", "card56078.html")),
             "card pages stay outside the cone"
      refute File.exist?(File.join(workdir, "cards", "001257", "files", "56078_51422.html")),
             "per-work XHTML stays outside the cone"
      refute File.exist?(File.join(workdir, "index.html")), "site pages stay outside the cone"

      # And the materialized tree discovers PD works only, from the zipped
      # index — even though the in-copyright STUB zip sits on disk, it is
      # never opened (it is not even a valid zip).
      # 051135 is discovered from the index too (its zip is not in this
      # rig — discovery is index-driven and never opens files).
      assert_equal ALL_URNS, adapter.discover(workdir).to_a.map(&:id)
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = aozora_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_aozora_enabled_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["aozora"]
    refute_nil entry, "aozora must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Aozora, entry.adapter_class
    assert_equal "manual", entry.sync_policy
    assert entry.enabled, "first real sync verified + owner-flipped 2026-07-21 (16,004 works)"
  end

  private

  def parse(urn)
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).to_a.find { |r| r.id == urn }
    adapter.parse(ref)
  end

  # Parse a real fixture zip directly (bypassing index discovery — the legacy
  # fixtures live under legacy/, outside cards/*/files/, so they never disturb
  # the discovery-skip census the cards/ fixtures pin).
  def parse_zip(relative, urn)
    Nabu::Adapters::AozoraRubyParser.new.parse(File.join(FIXTURES, relative), urn: urn)
  end

  def find_passage(document, snippet)
    passage = document.find { |p| p.text.include?(snippet) }
    refute_nil passage, "no passage contains #{snippet.inspect}"
    passage
  end

  # Parse a rig work: +body+ wrapped in the real Aozora file structure
  # (header, 55-hyphen legend delimiters, 底本 colophon), CP932-encoded and
  # zipped like upstream. Used ONLY for shapes the two PD fixture works do
  # not carry (gaiji classes b/c, unknown commands, heading references) —
  # with the survey's verbatim upstream examples, never invented notation.
  def parse_rig(body, encoding: Encoding::Windows_31J, file_encoding: nil)
    Dir.mktmpdir do |dir|
      txt = File.join(dir, "rig_no_sakuhin.txt")
      content = <<~TEXT
        試驗用作品
        試驗著者

        #{'-' * 55}
        【テキスト中に現れる記号について】

        《》：ルビ
        （例）端下《はした》
        #{'-' * 55}

        #{body.chomp}

        底本：「試驗全集」試驗文庫、試驗書店
        入力：試驗
        校正：試驗
      TEXT
      File.write(txt, content.encode(encoding), mode: "wb")
      zip = File.join(dir, "900001_ruby_1.zip")
      Nabu::Shell.run("zip", "-q", "-j", zip, txt)
      metadata = { "work_id" => "900001" }
      metadata["file_encoding"] = file_encoding if file_encoding
      Nabu::Adapters::AozoraRubyParser.new.parse(
        zip, urn: "urn:nabu:aozora:900001", metadata: metadata
      )
    end
  end

  def aozora_source
    Nabu::Store::Source.create(
      slug: "aozora", name: "Aozora Bunko", adapter_class: "Nabu::Adapters::Aozora",
      license_class: "open"
    )
  end

  def aozora_pointing_at(upstream)
    adapter = Nabu::Adapters::Aozora.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  # A miniature upstream with the real layout: work zips + card/XHTML pages
  # + the zipped index + site pages. The cone must take exactly the text
  # zips and the index zip. The in-copyright 54333 zip is a stub — discovery
  # never opens it (D38-a excludes before file access), which the discover
  # assertion above proves by not crashing on an invalid zip.
  def make_upstream_repo(dir)
    files = File.join(dir, "cards", "001257", "files")
    FileUtils.mkdir_p(files)
    %w[56078_ruby_51155.zip 59898_ruby_70679.zip].each do |name|
      FileUtils.cp(File.join(FIXTURES, "cards", "001257", "files", name), files)
    end
    File.write(File.join(files, "56078_51422.html"), "<html/>\n")
    File.write(File.join(dir, "cards", "001257", "card56078.html"), "<html/>\n")
    copyright_files = File.join(dir, "cards", "001657", "files")
    FileUtils.mkdir_p(copyright_files)
    File.write(File.join(copyright_files, "54333_ruby_67471.zip"), "in-copyright stub, never opened")
    FileUtils.mkdir_p(File.join(dir, "index_pages"))
    Dir.mktmpdir do |staging|
      FileUtils.cp(File.join(FIXTURES, "index_pages", "list_person_all_extended_utf8.csv"), staging)
      Nabu::Shell.run("zip", "-q", "-j",
                      File.join(dir, "index_pages", "list_person_all_extended_utf8.zip"),
                      File.join(staging, "list_person_all_extended_utf8.csv"))
    end
    File.write(File.join(dir, "index.html"), "<html/>\n")
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
