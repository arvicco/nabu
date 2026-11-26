# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# PCMEP adapter tests: the Parsed Corpus of Middle English Poetry
# (R. Zimmermann; pcmep.net) on the penn-psd family's :ppche profile,
# acquired by manual drop. The corpus is research_private (the pcmep.net
# download terms: no redistribution without the creators' consent), so its
# bytes NEVER enter the public repo: the samples live under the gitignored
# local/fixtures/pcmep/ (two tree-trimmed .psd members, README with the
# re-cut recipe) and every data-bearing case skips when they are absent —
# the corpus-oudnederlands restricted-fixture mold. The canonical asset is
# the release ZIP itself; the tests build it at run time from the samples
# (the ptg zip-shape mold), LF as cut and CRLF as upstream ships.
class PcmepTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  SLUG = "pcmep"
  GRAVE = "urn:nabu:pcmep:TheGrave"
  ASSUMP = "urn:nabu:pcmep:AssumpVirg"
  MEMBERS = %w[M1a.TheGrave.psd M1b.AssumpVirg.psd].freeze

  # One zipped workdir per process for the conformance hooks (built lazily,
  # removed at exit).
  def self.shared_workdir(fixtures)
    @shared_workdir ||= begin
      dir = Dir.mktmpdir("pcmep-conformance")
      Minitest.after_run { FileUtils.rm_rf(dir) }
      PcmepTest.zip_members(dir, fixtures, MEMBERS.to_h { |m| [m, m] })
      dir
    end
  end

  # Zip +members+ ({ name inside the zip => fixture file name, or a
  # String body when the value is a Hash {body:} }) into dir/pcmep.zip.
  def self.zip_members(dir, fixtures, members, crlf: false)
    staging = File.join(dir, "staging")
    members.each do |name, from|
      path = File.join(staging, name)
      FileUtils.mkdir_p(File.dirname(path))
      body = from.is_a?(Hash) ? from.fetch(:body) : File.binread(File.join(fixtures, from))
      body = body.gsub(/\r?\n/, "\r\n") if crlf && !from.is_a?(Hash)
      File.binwrite(path, body)
    end
    Nabu::Shell.run("zip", "-q", "-r", File.join(dir, "pcmep.zip"), *members.keys, chdir: staging)
    FileUtils.rm_rf(staging)
    File.join(dir, "pcmep.zip")
  end

  # --- conformance hooks (data-bearing → skip when the local fixtures absent) --

  def conformance_adapter = Nabu::Adapters::Pcmep.new

  def conformance_workdir
    require_fixtures!
    self.class.shared_workdir(fixtures)
  end

  def conformance_expected_source_id = SLUG

  def adapter = Nabu::Adapters::Pcmep.new

  # --- manifest: the research_private posture (runs without bytes) --------------

  def test_manifest_is_research_private_with_the_verbatim_terms
    manifest = Nabu::Adapters::Pcmep.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class
    assert_includes manifest.license, "The corpus must not be re-distributed without the consent of the " \
                                      "creators of the Parsed Corpus of Middle English Poetry"
    assert_includes manifest.license, "2026-11-23"
    assert_equal "penn-psd", manifest.parser_family
    assert_equal "https://pcmep.net/download.php", manifest.upstream_url
  end

  # --- the Manual Adapter contract (the card runs without any bytes) -----------

  def test_manual_acquisition_spec_names_the_zip_and_the_site
    spec = Nabu::Adapters::Pcmep.manual_acquisition
    assert_equal SLUG, spec.slug
    assert_equal ["pcmep.zip"], spec.files.map(&:name)
    assert spec.files.first.required
    assert_equal "https://pcmep.net/download.php", spec.upstream_url
    assert(spec.steps.any? { |step| step.include?("PCMEP_Nov2025.zip") }, "the card names the held release")
  end

  def test_sync_prints_the_acquisition_card_while_no_drop_is_present
    Dir.mktmpdir do |root|
      workdir = File.join(root, "canonical", SLUG)
      FileUtils.mkdir_p(workdir)
      error = assert_raises(Nabu::ManualDrop::AwaitingAcquisition) { adapter.fetch(workdir) }
      assert_match("pcmep.zip", error.message)
      assert_match("incoming/pcmep", error.message.tr(File::SEPARATOR, "/"))
    end
  end

  def test_the_sniff_refuses_a_non_zip_and_a_zip_without_psd_members
    Dir.mktmpdir do |dir|
      page = File.join(dir, "login.html")
      File.write(page, "<html>Please log in</html>")
      assert_match(/not a readable ZIP/, Nabu::Adapters::Pcmep.zip_complaint(page))

      zip = self.class.zip_members(dir, dir, { "README.txt" => { body: "notes\n" } })
      assert_match(/no period-band \.psd members/, Nabu::Adapters::Pcmep.zip_complaint(zip))
    end
  end

  def test_the_sniff_accepts_the_release_shape
    require_fixtures!
    zip = File.join(self.class.shared_workdir(fixtures), "pcmep.zip")
    assert_nil Nabu::Adapters::Pcmep.zip_complaint(zip)
  end

  def test_the_pre_acquisition_workdir_discovers_nothing
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  # --- period bands (pure, runs without bytes) -----------------------------------

  def test_the_file_name_period_band_maps_onto_the_sites_own_spans
    expected = { "M1a" => [1150, 1200], "M1b" => [1200, 1250], "M2a" => [1250, 1300],
                 "M2b" => [1300, 1350], "M3" => [1350, 1420], "M1" => [1150, 1250], "M2" => [1250, 1350] }
    expected.each do |band, (from, to)|
      assert_equal({ "not_before" => from, "not_after" => to, "raw" => band }, Nabu::Adapters::Pcmep.band_date(band))
    end
    assert_nil Nabu::Adapters::Pcmep.band_date("M9z"), "an unknown band mints no date, never a guess"
  end

  def test_the_escapes_decode_to_the_middle_english_letters
    assert_equal "Ðe þu ȝyt bringæð Þat Ȝ Æ", Nabu::Adapters::Pcmep.decode("+De +tu +gyt bring+a+d +Tat +G +A")
    assert_equal "a+b", Nabu::Adapters::Pcmep.decode("a+b"), "an unknown escape stays verbatim"
  end

  # --- discover (data-bearing) ---------------------------------------------------

  def test_discover_mints_one_ref_per_band_prefixed_psd_member
    require_fixtures!
    refs = adapter.discover(conformance_workdir).to_a
    assert_equal [ASSUMP, GRAVE], refs.map(&:id), "one ref per text, sorted by the text code"
    grave = refs.find { |r| r.id == GRAVE }
    assert_equal "M1a.TheGrave.psd", grave.metadata.fetch("member")
    assert_equal "M1a", grave.metadata.fetch("period")
  end

  def test_members_are_found_inside_a_release_directory_and_junk_is_counted
    require_fixtures!
    Dir.mktmpdir do |dir|
      self.class.zip_members(dir, fixtures, {
                               "PCMEP_Nov2025/M1a.TheGrave.psd" => "M1a.TheGrave.psd",
                               "PCMEP_Nov2025/readme.txt" => { body: "about the corpus\n" },
                               "PCMEP_Nov2025/TheGrave.pos" => { body: "pos view\n" },
                               "__MACOSX/PCMEP_Nov2025/._M1a.TheGrave.psd" => { body: "junk" },
                               "PCMEP_Nov2025/.DS_Store" => { body: "junk" }
                             })
      assert_equal [GRAVE], adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule, "the macOS archiver litter skips by rule"
      assert_equal 2, skips.unrecognized, "the unknown members are counted, never dropped silently"
      assert(skips.notes.any? { |n| n.include?("PCMEP_Nov2025/readme.txt") })
      assert(skips.notes.any? { |n| n.include?("PCMEP_Nov2025/TheGrave.pos") })
    end
  end

  # --- parse (data-bearing) --------------------------------------------------------

  def test_passage_censuses_and_citations
    require_fixtures!
    counts = refs.to_h { |ref| [ref.id, adapter.parse(ref).size] }
    assert_equal({ ASSUMP => 5, GRAVE => 6 }, counts, "one passage per tree, the trimmed samples")
    grave = document(GRAVE)
    assert_equal(%w[1.1 2.2 3.3 4.4 5.5 6.6], grave.map { |p| p.urn.delete_prefix("#{GRAVE}:") })
    assert_equal(%w[111.2.1 111.6.2 111.8.3 111.21.10 112.22.11],
                 document(ASSUMP).map { |p| p.urn.delete_prefix("#{ASSUMP}:") })
    assert_equal "TheGrave,1.1", grave.first.annotations.fetch("id")
    assert_equal "enm", grave.language
    assert_equal "TheGrave", grave.title
  end

  def test_the_surface_decodes_the_escapes_and_drops_line_breaks_and_traces
    require_fixtures!
    grave = document(GRAVE)
    assert_equal "Ðe wes bold ȝebyld, er þu iboren were.", grave.first.text
    assert_equal "Nes ȝyt iloced, hu long hit þe were.", grave.passages[3].text,
                 "*exp*, *T*-2 and the zero complementizer leave no surface"
    assert_equal "Nu me þe bringæð, þer ðu beon scealt.", grave.passages[4].text
    assert_equal "Þe kyng of heuene hem blessi Þat þis listneþ and wel herkni.", document(ASSUMP).passages[2].text
  end

  def test_tokens_lane_carries_decoded_forms_line_breaks_and_empties
    require_fixtures!
    tokens = document(GRAVE).first.annotations.fetch("tokens")
    assert_equal({ "code" => "LB" }, tokens.first, "the verse-line break rides the code lane, as HeliPaD's <R_n>")
    assert_equal({ "code" => "LB" }, tokens.last)
    assert_includes tokens, { "form" => "Ðe", "pos" => "PRO" }
    assert_includes tokens, { "tag" => "C", "empty" => "0" }
    refute(tokens.any? { |t| t["form"] == "||" })
    assert_includes document(GRAVE).first.annotations.fetch("tree"), "(PRO +De)", "the tree stays verbatim"
  end

  def test_code_comments_ride_the_tokens_lane_and_never_the_text
    require_fixtures!
    passage = document(ASSUMP).passages[3]
    assert_equal "Mine fet and honden of blod buþ red;", passage.text
    refute_includes passage.text, "COMMENT"
    assert_includes passage.annotations.fetch("tokens"),
                    { "code" => "{COMMENT:bu+t_red_ILLEGIBLE;_MS._ADD._10036_HAS_ben_rede}" }
  end

  def test_the_document_carries_the_period_band_as_metadata
    require_fixtures!
    metadata = document(ASSUMP).metadata
    assert_equal "M1b", metadata.fetch("period")
    assert_equal({ "not_before" => 1200, "not_after" => 1250, "raw" => "M1b" }, metadata.fetch("date"))
    assert_equal "M1b.AssumpVirg.psd", metadata.fetch("file")
  end

  def test_crlf_members_parse_identically_to_lf
    require_fixtures!
    Dir.mktmpdir do |dir|
      self.class.zip_members(dir, fixtures, MEMBERS.to_h { |m| [m, m] }, crlf: true)
      zip = Nabu::ZipReader.new(File.binread(File.join(dir, "pcmep.zip")))
      assert(zip.entries.all? { |e| zip.extract(e).include?("\r\n") }, "the CRLF specimen really is CRLF")
      crlf = adapter.discover(dir).to_h { |ref| [ref.id, adapter.parse(ref).map { |p| [p.urn, p.text] }] }
      lf = refs.to_h { |ref| [ref.id, adapter.parse(ref).map { |p| [p.urn, p.text] }] }
      assert_equal lf, crlf
    end
  end

  # --- store: idempotent double-load ------------------------------------------------

  def test_loads_idempotently_into_the_store
    require_fixtures!
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: SLUG, name: "PCMEP", adapter_class: "Nabu::Adapters::Pcmep",
                                        license_class: "research_private")
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: conformance_workdir, full: true)
    assert_equal 2, first.added
    assert_equal 0, first.errored
    assert_equal 11, catalog[:passages].count
    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: conformance_workdir, full: true)
    assert_equal 0, second.errored
    assert_equal 2, second.skipped, "a byte-identical reload skips every document"
    assert_equal 11, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- registry round-trip (runs without bytes) ----------------------------------

  def test_registry_resolves_the_source_unwired_and_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "#{SLUG} must be registered in config/sources/"
    assert_equal Nabu::Adapters::Pcmep, entry.adapter_class
    refute entry.wired, "wired only after the first real sync is verified"
    assert_equal "manual", entry.sync_policy
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (pcmep.net terms: no redistribution — bytes never in git)"
  end

  def fixtures = Nabu::TestSupport.local_fixtures(SLUG)

  def refs = adapter.discover(conformance_workdir).to_a

  def document(urn)
    ref = refs.find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end
end
