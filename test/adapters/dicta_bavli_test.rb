# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Dicta's vocalized Babylonian Talmud (Talmud-Bavli-with-Nikud): one
# document per tractate, one passage per paragraph line under its daf/amud
# header. The ktiv male file is the passage text; the line-aligned ktiv haser
# sibling rides each differing passage's annotations. The fixture holds three
# real tractate trims (Berakhot 2a–3a, Tamid 25a–26a, Meilah 2a) plus the
# rejected grains: the byte-identical Meila duplicate directory and the
# Berakhot corrections .docx. No network: fetch runs against a local git repo.
class DictaBavliTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("dicta-bavli")
  URN = "urn:nabu:dicta-bavli:"

  def conformance_adapter
    Nabu::Adapters::DictaBavli.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "dicta-bavli"
  end

  def adapter = Nabu::Adapters::DictaBavli.new

  def document(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "#{URN}#{slug}" }
    refute_nil ref, "no ref for #{slug}"
    adapter.parse(ref)
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_records_the_readme_grant_verbatim
    manifest = Nabu::Adapters::DictaBavli.manifest
    assert_equal "dicta-bavli", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license,
                    "This vocalized text of the Babylonian Talmud is released under a CC BY-SA license."
    assert_includes manifest.credit,
                    "This text of the Babylonian Talmud was vocalized by Dicta: The Israel Center for " \
                    "Text Analysis (www.dicta.org.il)"
    assert_equal "https://github.com/Dicta-Israel-Center-for-Text-Analysis/Talmud-Bavli-with-Nikud",
                 manifest.upstream_url
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_tractate_and_skips_the_meila_duplicate
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %W[#{URN}berakhot #{URN}meilah #{URN}tamid], refs.map(&:id)
    berakhot = refs.first
    assert_equal "Berakhot", berakhot.metadata["tractate_dir"]
    assert berakhot.path.end_with?("ברכות.combinedfullmaleh.txt")
  end

  def test_discovery_skips_count_the_rejected_grains_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule, "the Meila duplicate dir + the corrections .docx"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("Meila") && note.include?("Meilah") })
    assert(skips.notes.any? { |note| note.include?(".docx") })
  end

  def test_a_tractate_without_its_male_file_is_unrecognized_loudly
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "Tamid"))
      FileUtils.cp(Dir.glob(File.join(FIXTURES, "Tamid", "*haser.txt")).first, File.join(dir, "Tamid"))
      assert_empty adapter.discover(dir).to_a
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- parse ------------------------------------------------------------------

  def test_berakhot_parses_at_paragraph_grain_under_daf_and_amud
    doc = document("berakhot")
    assert_equal "Berakhot", doc.title
    assert_equal "arc", doc.language
    assert_equal 18, doc.size, "5 paragraphs on 2a, 6 on 2b, 7 on 3a"
    assert_equal(%W[#{URN}berakhot:2a.1 #{URN}berakhot:2a.2], doc.first(2).map(&:urn))
    assert_equal "#{URN}berakhot:3a.7", doc.to_a.last.urn
    opening = doc.first
    opening_words = "מֵאֵימָתַי קוֹרִין אֶת שְׁמַע בָּעֲרָבִין מִשָּׁעָה שֶׁהַכֹּהֲנִים נִכְנָסִים לֶאֱכוֹל"
    assert nfc(opening.text).start_with?(nfc(opening_words))
    assert_equal "גמ'", doc.to_a[1].text, "the Gemara marker line is upstream text, kept verbatim"
    assert_equal({ "daf" => 2, "amud" => "a" }, opening.annotations.slice("daf", "amud"))
  end

  def test_the_haser_variant_rides_the_annotations_where_it_differs
    doc = document("berakhot")
    opening = doc.first
    haser = opening.annotations.fetch("ktiv_haser")
    assert nfc(haser).include?(nfc("לֶאֱכֹל בִּתְרוּמָתָן")), "haser drops the mater lectionis the male text keeps"
    refute nfc(opening.text).include?(nfc("לֶאֱכֹל בִּתְרוּמָתָן"))
    refute doc.to_a[1].annotations.key?("ktiv_haser"), "identical lines carry no duplicate"
    assert_equal "aligned", doc.metadata["ktiv_haser"]
  end

  def test_male_text_is_stored_byte_verbatim_on_the_nfc_exempt_aramaic_code
    path = Dir.glob(File.join(FIXTURES, "Berakhot", "*maleh.txt")).first
    raw_line = File.read(path, encoding: "UTF-8").split("\n")[3]
    refute raw_line.unicode_normalized?(:nfc), "upstream's mark order is not NFC — the exemption is real here"
    assert_equal raw_line, document("berakhot").first.text
  end

  def test_tamid_starts_on_its_own_first_daf
    doc = document("tamid")
    assert_equal 13, doc.size
    assert_equal "#{URN}tamid:25a.1", doc.first.urn
    assert nfc(doc.first.text).start_with?(nfc("מַתְנִי' בִּשְׁלֹשָׁה מְקוֹמוֹת הַכֹּהֲנִים שׁוֹמְרִים"))
    assert_equal "#{URN}tamid:26a.1", doc.to_a[3].urn
  end

  def test_document_metadata_mines_seder_genre_and_hebrew_title
    meta = document("berakhot").metadata
    assert_equal "ברכות", meta["he_title"]
    assert_equal "Talmud Bavli", meta["genre"]
    assert_equal({ "value" => "seder-zeraim", "raw" => "Zeraim" }, meta.dig("facets", "seder"))
    assert_equal "vocalized", meta["text_layer"]
    assert_equal "seder-kodashim", document("meilah").metadata.dig("facets", "seder", "value")
  end

  def test_multiword_tractate_titles_and_the_trailing_dot_filename
    Dir.mktmpdir do |dir|
      %w[Yevamot Bava_Batra].each do |name|
        FileUtils.mkdir_p(File.join(dir, name))
      end
      src = Dir.glob(File.join(FIXTURES, "Tamid", "*"))
      FileUtils.cp(src[0], File.join(dir, "Yevamot", "יבמות..combinedfullhaser.txt"))
      FileUtils.cp(src[1], File.join(dir, "Yevamot", "יבמות..combinedfullmaleh.txt"))
      FileUtils.cp(src[1], File.join(dir, "Bava_Batra", "בבא_בתרא.combinedfullmaleh.txt"))
      refs = adapter.discover(dir).to_a
      assert_equal %W[#{URN}bava-batra #{URN}yevamot], refs.map(&:id)
      docs = refs.map { |ref| adapter.parse(ref) }
      assert_equal ["Bava Batra", "Yevamot"], docs.map(&:title)
      assert_equal(["בבא בתרא", "יבמות"], docs.map { |d| d.metadata["he_title"] })
      assert_equal "absent", docs.first.metadata["ktiv_haser"]
    end
  end

  def test_a_misaligned_haser_file_is_declared_never_paired_by_guess
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "Tamid"), dir)
      haser = Dir.glob(File.join(dir, "Tamid", "*haser.txt")).first
      File.write(haser, File.read(haser).lines.drop(1).join)
      doc = adapter.parse(adapter.discover(dir).first)
      assert_equal "unaligned", doc.metadata["ktiv_haser"]
      assert(doc.none? { |p| p.annotations.key?("ktiv_haser") })
    end
  end

  def test_text_before_the_first_daf_header_is_damage
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "Tamid"))
      male = Dir.glob(File.join(FIXTURES, "Tamid", "*maleh.txt")).first
      File.write(File.join(dir, "Tamid", File.basename(male)), "stray line\n#{File.read(male)}")
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  def test_daf_numerals_read_as_gematria
    assert_equal 2, Nabu::Adapters::DictaBavli.daf_number("ב")
    assert_equal 15, Nabu::Adapters::DictaBavli.daf_number("טו")
    assert_equal 16, Nabu::Adapters::DictaBavli.daf_number("טז")
    assert_equal 176, Nabu::Adapters::DictaBavli.daf_number("קעו")
    assert_raises(Nabu::ParseError) { Nabu::Adapters::DictaBavli.daf_number("x") }
  end

  # --- fetch (local git only, no network) ---------------------------------------

  def test_fetch_clones_the_repo_and_returns_a_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      bavli = adapter
      bavli.define_singleton_method(:repo_url) { upstream }
      report = bavli.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal 3, bavli.discover(workdir).count
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_dicta_bavli_wired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["dicta-bavli"]
    refute_nil entry
    assert_equal Nabu::Adapters::DictaBavli, entry.adapter_class
    assert entry.wired,
           "wired: true since the verified first sync " \
           "(+37 tractates / 78,782 passages, 0 errored; shown + search probed with credit)"
  end

  private

  # Stored text keeps upstream's mark order (arc is NFC-exempt); compare
  # snippets canonically.
  def nfc(text) = text.unicode_normalize(:nfc)

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")).reject { |p| File.basename(p).match?(/README|manifest/) }, dir)
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
