# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Perseus adapter tests (P2-3). The adapter composes EpidocParser with
# PerseusDL repo-layout knowledge: discover walks data/<tg>/<work>/ for
# original-language editions, resolves titles/urns via __cts__.xml; fetch is a
# git clone/pull; parse delegates to EpidocParser.
#
# Includes the shared AdapterConformance suite against the checked-in greekLit
# fixtures. No network: fetch is exercised against a local git repo created in
# a tmpdir (git is a local process, allowed by CLAUDE.md) plus a Shell-failure
# path against a nonexistent upstream.
class PerseusTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("perseus") # NABU_FIXTURE_DIR-aware (fixtures:check)
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")

  ILIAD_URN = "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2"
  HH13_URN = "urn:cts:greekLit:tlg0013.tlg013.perseus-grc2"
  HH14_URN = "urn:cts:greekLit:tlg0013.tlg014.perseus-grc2"
  JOHN2_URN = "urn:cts:greekLit:tlg0031.tlg024.perseus-grc2"

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Perseus.new
  end

  def conformance_workdir
    GREEK_WORKDIR
  end

  def conformance_expected_source_id
    "perseus-greek"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest_is_the_greeklit_manifest
    manifest = Nabu::Adapters::Perseus.manifest
    assert_equal "perseus-greek", manifest.id
    assert_equal "Perseus Digital Library — canonical Greek literature", manifest.name
    assert_equal "CC BY-SA 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/PerseusDL/canonical-greekLit", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::Perseus.manifest, Nabu::Adapters::Perseus.new.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_the_four_greeklit_editions_sorted
    refs = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a
    assert_equal [ILIAD_URN, HH13_URN, HH14_URN, JOHN2_URN], refs.map(&:id)
  end

  def test_discover_sets_source_id_language_and_absolute_path
    refs = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a
    refs.each do |ref|
      assert_equal "perseus-greek", ref.source_id
      assert_equal "grc", ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end
  end

  def test_discover_resolves_titles_from_cts_metadata_preferring_english
    titles = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a.to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Iliad", titles.fetch(ILIAD_URN)
    assert_equal "Hymn 13 to Demeter", titles.fetch(HH13_URN)
    assert_equal "Hymn 14 to the Mother of the Gods", titles.fetch(HH14_URN)
    # 2 John has four <ti:title> aliases; the first eng one wins.
    assert_equal "2 John", titles.fetch(JOHN2_URN)
  end

  def test_discover_returns_an_enumerator_without_a_block
    assert_kind_of Enumerator, Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR)
  end

  def test_discover_prefers_the_highest_edition_version
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      refs = Nabu::Adapters::Perseus.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.perseus-grc2"], refs.map(&:id)
    end
  end

  def test_discover_skips_translation_files
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-eng2.xml"))
      refs = Nabu::Adapters::Perseus.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.perseus-grc2"], refs.map(&:id)
    end
  end

  def test_discover_falls_back_to_urn_tail_when_cts_metadata_missing
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      ref = Nabu::Adapters::Perseus.new.discover(dir).to_a.fetch(0)
      assert_equal "tlg9999.tlg001.perseus-grc2", ref.metadata["title"]
    end
  end

  # --- parse --------------------------------------------------------------

  def test_parse_round_trips_hh13
    adapter = Nabu::Adapters::Perseus.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == HH13_URN }
    document = adapter.parse(ref)
    assert_equal HH13_URN, document.urn
    assert_equal "grc", document.language
    assert_equal "Hymn 13 to Demeter", document.title
    assert_equal 3, document.size
    assert_equal "#{HH13_URN}:1", document.first.urn
    assert_includes document.first.text, "Δημήτηρ"
  end

  # --- fetch (local git only, no network) ---------------------------------

  def test_fetch_clones_when_no_local_repo_then_pulls_and_returns_fetch_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream, "one")
      head = git(upstream, "rev-parse", "HEAD")

      workdir = File.join(root, "work")
      adapter = perseus_pointing_at(upstream)

      # No .git yet → clone path. fetch returns a FetchReport (architecture §3).
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal head, report.sha
      assert_instance_of Time, report.fetched_at
      assert_nil report.notes
      assert File.directory?(File.join(workdir, ".git")), "clone must create a .git dir"

      # Second call with .git present → pull path (ff-only, up to date).
      assert_equal head, adapter.fetch(workdir).sha

      # A new upstream commit is pulled and reflected in the returned sha.
      File.write(File.join(upstream, "two.txt"), "two\n")
      git(upstream, "add", ".")
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "two")
      new_head = git(upstream, "rev-parse", "HEAD")
      refute_equal head, new_head
      assert_equal new_head, adapter.fetch(workdir).sha
    end
  end

  # The progress callback path (P2-6): clone + pull with --progress, streaming
  # git output to a collector. Still against a LOCAL tmpdir repo, no network.
  def test_fetch_with_progress_streams_lines_and_still_returns_fetch_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream, "one")
      head = git(upstream, "rev-parse", "HEAD")

      workdir = File.join(root, "work")
      adapter = perseus_pointing_at(upstream)

      lines = []
      report = adapter.fetch(workdir, progress: ->(line) { lines << line })

      assert_instance_of Nabu::FetchReport, report
      assert_equal head, report.sha
      refute_empty lines, "progress callback must receive lines during the clone"
      assert(lines.any? { |line| line.include?("Cloning") }, "expected the human 'Cloning…' banner")

      # Pull path with progress against an up-to-date repo also streams + reports.
      pull_lines = []
      assert_equal head, adapter.fetch(workdir, progress: ->(line) { pull_lines << line }).sha
      refute_empty pull_lines
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = perseus_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- retention: attic + pre-merge breaker (P5-2) --------------------------

  # Upstream deleting an ingestible edition beyond the threshold (here 1 of 2,
  # 50% > 20%) trips the mass-deletion breaker BEFORE the merge: the canonical
  # tree keeps the file, no attic appears. --force proceeds: the file is
  # atticked (relative path preserved), the merge applies, and the adapter
  # rediscovers the document from the attic as retained.
  def test_fetch_guards_upstream_deletions_and_force_attics_them
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      doomed_rel = File.join("data", "tlg0001", "tlg001", "tlg0001.tlg001.perseus-grc2.xml")
      make_git_repo_with(upstream,
                         doomed_rel => "<TEI/>\n",
                         File.join("data", "tlg0002", "tlg002", "tlg0002.tlg002.perseus-grc2.xml") => "<TEI/>\n")
      workdir = File.join(root, "work")
      adapter = perseus_pointing_at(upstream)
      adapter.fetch(workdir)

      git(upstream, "rm", "-q", doomed_rel)
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "scrap")

      assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
      assert File.file?(File.join(workdir, doomed_rel)), "a tripped breaker leaves the tree unchanged"
      refute Dir.exist?(File.join(workdir, ".attic"))

      report = adapter.fetch(workdir, force: true)
      assert_includes report.notes, "atticked 1"
      refute File.exist?(File.join(workdir, doomed_rel))
      assert File.file?(File.join(workdir, ".attic", doomed_rel))

      refs = adapter.discover_with_attic(workdir).to_a
      assert_equal ["urn:cts:greekLit:tlg0001.tlg001.perseus-grc2",
                    "urn:cts:greekLit:tlg0002.tlg002.perseus-grc2"], refs.map(&:id).sort
      retained = refs.find { |ref| ref.id.include?("tlg0001") }
      assert_equal true, retained.metadata["retained"]
      assert_equal git(upstream, "rev-parse", "HEAD"), retained.metadata["retired_sha"]
    end
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_perseus_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["perseus-greek"]
    refute_nil entry, "perseus-greek must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Perseus, entry.adapter_class
    assert_equal "perseus-greek", entry.manifest.id
    assert_equal Nabu::Adapters::Perseus.manifest, entry.manifest
  end

  # --- translations flag off: provably inert (P7-4) ------------------------

  # The frozen-urn pin: with the flag off (default), discover over a fixture
  # dir that NOW CONTAINS eng translation files yields the identical ref list
  # a pre-P7-4 adapter produced — same urns, paths, titles, languages, order.
  def test_discover_with_flag_off_is_identical_to_default_despite_eng_files_on_disk
    default_refs = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a
    flag_off_refs = Nabu::Adapters::Perseus.new(translations: false).discover(GREEK_WORKDIR).to_a
    assert_equal default_refs, flag_off_refs
    assert_equal [ILIAD_URN, HH13_URN, HH14_URN, JOHN2_URN], default_refs.map(&:id)
    assert(default_refs.all? { |ref| ref.metadata["language"] == "grc" })
  end

  private

  def perseus_pointing_at(upstream_url)
    adapter = Nabu::Adapters::Perseus.new
    adapter.define_singleton_method(:manifest) do
      Nabu::SourceManifest.new(
        id: "perseus-greek", name: "test", license: "CC BY-SA 4.0",
        license_class: "attribution", upstream_url: upstream_url, parser_family: "epidoc"
      )
    end
    adapter
  end

  def make_git_repo(dir, seed)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "#{seed}.txt"), "#{seed}\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", seed)
  end

  def make_git_repo_with(dir, files)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    files.each do |rel, content|
      FileUtils.mkdir_p(File.join(dir, File.dirname(rel)))
      File.write(File.join(dir, rel), content)
    end
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end

# The translations-on adapter (P7-4): `Perseus.new(translations: true)`
# additionally discovers the highest perseus-eng<n> edition per work as an
# ordinary aligned document — language "eng", its own edition urn, parsed from
# div[@type="translation"]. Everything below exercises exactly that surface;
# flag-off inertness is pinned in PerseusTest above.
class PerseusTranslationsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("perseus")
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")

  HH13_ENG_URN = "urn:cts:greekLit:tlg0013.tlg013.perseus-eng2"
  JOHN2_ENG_URN = "urn:cts:greekLit:tlg0031.tlg024.perseus-eng2"
  ILIAD_ENG_URN = "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4"
  ENG_URNS = [ILIAD_ENG_URN, HH13_ENG_URN, JOHN2_ENG_URN].freeze
  GRC_URNS = %w[
    urn:cts:greekLit:tlg0012.tlg001.perseus-grc2
    urn:cts:greekLit:tlg0013.tlg013.perseus-grc2
    urn:cts:greekLit:tlg0013.tlg014.perseus-grc2
    urn:cts:greekLit:tlg0031.tlg024.perseus-grc2
  ].freeze

  def adapter
    Nabu::Adapters::Perseus.new(translations: true)
  end

  # --- discover -------------------------------------------------------------

  def test_discover_adds_eng_editions_alongside_originals_sorted_by_urn
    refs = adapter.discover(GREEK_WORKDIR).to_a
    assert_equal (GRC_URNS + ENG_URNS).sort, refs.map(&:id)
    assert_equal refs.map(&:id).sort, refs.map(&:id), "discover stays urn-sorted"
  end

  def test_translation_refs_carry_eng_language_and_the_work_title
    refs = adapter.discover(GREEK_WORKDIR).to_a
    eng = refs.select { |ref| ref.metadata["language"] == "eng" }
    assert_equal ENG_URNS.sort, eng.map(&:id).sort
    titles = eng.to_h { |ref| [ref.id, ref.metadata["title"]] }
    assert_equal "Iliad", titles.fetch(ILIAD_ENG_URN)
    assert_equal "Hymn 13 to Demeter", titles.fetch(HH13_ENG_URN)
    assert_equal "2 John", titles.fetch(JOHN2_ENG_URN)
    eng.each { |ref| assert_equal "perseus-greek", ref.source_id }
  end

  def test_discover_prefers_the_highest_eng_version_independently_of_the_original
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      %w[perseus-grc1 perseus-grc3 perseus-eng2 perseus-eng4].each do |slug|
        FileUtils.touch(File.join(work, "tlg9999.tlg001.#{slug}.xml"))
      end
      refs = adapter.discover(dir).to_a
      assert_equal %w[urn:cts:greekLit:tlg9999.tlg001.perseus-eng4
                      urn:cts:greekLit:tlg9999.tlg001.perseus-grc3], refs.map(&:id)
    end
  end

  def test_non_eng_translation_slugs_are_still_skipped
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      %w[perseus-grc2 perseus-fre1 perseus-ger1 1st1K-eng2].each do |slug|
        FileUtils.touch(File.join(work, "tlg9999.tlg001.#{slug}.xml"))
      end
      refs = adapter.discover(dir).to_a
      assert_equal %w[urn:cts:greekLit:tlg9999.tlg001.perseus-grc2], refs.map(&:id)
    end
  end

  # --- parse ------------------------------------------------------------------

  # Hymn 13's translation is ONE merged <l n="1"> inside div[@type="translation"]
  # covering the Greek's three lines — the honest one-sided alignment case.
  def test_parse_hh13_translation_yields_one_eng_passage_from_the_translation_div
    document = parse_ref(HH13_ENG_URN)
    assert_equal HH13_ENG_URN, document.urn
    assert_equal "eng", document.language
    assert_equal 1, document.size
    passage = document.first
    assert_equal "#{HH13_ENG_URN}:1", passage.urn
    assert_equal "eng", passage.language
    assert_includes passage.text, "rich-haired Demeter"
    assert_equal Nabu::Normalize.search_form(passage.text, language: "eng"), passage.text_normalized
  end

  # 2 John translates verse for verse: the eng edition mints exactly the same
  # citation suffixes as the grc edition — passage-level alignment for free.
  def test_parse_john2_translation_aligns_verse_suffixes_with_the_original
    eng = parse_ref(JOHN2_ENG_URN)
    grc = parse_ref("urn:cts:greekLit:tlg0031.tlg024.perseus-grc2")
    suffixes = ->(doc) { doc.map { |p| p.urn.delete_prefix(doc.urn) } }
    assert_equal 13, eng.size
    assert_equal suffixes.call(grc), suffixes.call(eng)
  end

  # The Iliad's Butler translation is CARD-cited (book.card), not line-cited:
  # each card anchors one prose block at its first line — div[@type="card"]
  # under div[@subtype="book"]. The P8-1b span-grouped display exists for
  # exactly this shape; this pins that the fixture parses to card suffixes.
  def test_parse_iliad_translation_yields_card_cited_prose_blocks
    document = parse_ref(ILIAD_ENG_URN)
    assert_equal ILIAD_ENG_URN, document.urn
    assert_equal "eng", document.language
    suffixes = document.map { |p| p.urn.delete_prefix(document.urn) }
    assert_equal %w[:1.1 :1.40], suffixes, "book.card suffixes anchored at each card's first line"
    assert_includes document.first.text, "Sing, O goddess, the anger"
  end

  private

  def parse_ref(urn)
    a = adapter
    ref = a.discover(GREEK_WORKDIR).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    a.parse(ref)
  end
end

# The shared conformance suite against a translations-on Perseus instance:
# eng documents must satisfy every adapter guarantee (urn uniqueness across
# the widened discover set, stability, NFC, minted search form, ref-id ==
# document urn) exactly like originals.
class PerseusTranslationsConformanceTest < Minitest::Test
  include AdapterConformance

  def conformance_adapter
    Nabu::Adapters::Perseus.new(translations: true)
  end

  def conformance_workdir
    File.join(Nabu::TestSupport.fixtures("perseus"), "greekLit")
  end

  def conformance_expected_source_id
    "perseus-greek"
  end
end
