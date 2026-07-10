# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# First1KGreek adapter tests (P3-2). OpenGreekAndLatin's First1KGreek ships the
# same CapiTainS/EpiDoc layout as PerseusDL, so the adapter is a thin SUBCLASS
# of Perseus (reusing discover/parse/fetch machinery wholesale) that overrides
# only the manifest and the original-language edition-slug acceptance rule.
#
# The distinguishing upstream fact: edition slugs are NOT uniformly
# `1st1K-grcN`. The same corpus mixes `opp-grcN`, `perseus-grcN`, etc., so the
# slug matcher accepts ANY `*-grcN[a-z]?` tail rather than a single family.
#
# Includes the shared AdapterConformance suite against the checked-in greekLit
# fixtures (P3-1). No network.
class First1kGreekTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("first1k") # NABU_FIXTURE_DIR-aware (fixtures:check)
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")

  # The fixture editions prove BOTH slug families are accepted: three
  # `1st1K-grc1` and one `opp-grc1`. Nicomachus (P6-1) exercises the
  # structural-retry citation path through the adapter seam.
  SEIKILOS_URN = "urn:cts:greekLit:tlg2139.tlg001.1st1K-grc1"
  ANUBION_URN = "urn:cts:greekLit:tlg1126.tlg003.1st1K-grc1"
  METHODIUS_URN = "urn:cts:greekLit:tlg2959.tlg008.opp-grc1"
  NICOMACHUS_URN = "urn:cts:greekLit:tlg0358.tlg001.1st1K-grc1"
  # The P9-1 parallel pair (Anonymus, De Incredibilibus): a grc original and its
  # eng translation, sharing the `section` citation scheme (see the eng-only
  # tests below). The grc side is an ordinary original — discovered flag-off too.
  PARADOX_GRC_URN = "urn:cts:greekLit:tlg4037.tlg001.1st1K-grc1"
  PARADOX_ENG_URN = "urn:cts:greekLit:tlg4037.tlg001.1st1K-eng1"
  # The P11-5 LXX witness: tlg0527 is Swete's Septuaginta — Genesis, chapter/
  # verse citation, the alignment hub's cts-verse extractor exemplar.
  LXX_GENESIS_URN = "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1"

  # All six original-language editions the fixture tree carries (flag-off).
  GRC_URNS = [NICOMACHUS_URN, ANUBION_URN, SEIKILOS_URN, METHODIUS_URN,
              PARADOX_GRC_URN, LXX_GENESIS_URN].freeze

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::First1kGreek.new
  end

  def conformance_workdir
    GREEK_WORKDIR
  end

  def conformance_expected_source_id
    "first1k-greek"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest_identifies_the_first1k_greek_source
    manifest = Nabu::Adapters::First1kGreek.manifest
    assert_equal "first1k-greek", manifest.id
    assert_equal "Open Greek and Latin — First1KGreek", manifest.name
    assert_equal "CC BY-SA 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/OpenGreekAndLatin/First1KGreek", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::First1kGreek.manifest, Nabu::Adapters::First1kGreek.new.manifest
  end

  def test_manifest_is_distinct_from_perseus
    refute_equal Nabu::Adapters::Perseus.manifest, Nabu::Adapters::First1kGreek.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_the_six_original_editions_across_slug_families
    refs = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a
    assert_equal GRC_URNS.sort, refs.map(&:id).sort
  end

  # Frozen-urn pin (P9-1 standing standard): with the flag off (default),
  # discover over a fixture tree that NOW CONTAINS an eng translation sibling
  # (tlg4037 eng1) yields the identical ref list a pre-P9-1 adapter produced —
  # same urns, all "grc", eng skipped. Toggling translations adds new docs; it
  # never changes the existing originals' set.
  def test_discover_with_flag_off_is_identical_to_default_despite_eng_files_on_disk
    default_refs = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a
    flag_off_refs = Nabu::Adapters::First1kGreek.new(translations: false).discover(GREEK_WORKDIR).to_a
    assert_equal default_refs, flag_off_refs
    assert_equal GRC_URNS.sort, default_refs.map(&:id).sort
    assert(default_refs.all? { |ref| ref.metadata["language"] == "grc" })
  end

  def test_discover_sets_source_id_language_and_absolute_path
    refs = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a
    refs.each do |ref|
      assert_equal "first1k-greek", ref.source_id
      assert_equal "grc", ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end
  end

  def test_discover_resolves_titles_from_cts_metadata
    titles = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a.to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Sicili Epitaphium", titles.fetch(SEIKILOS_URN)
    assert_equal "Fragmenta", titles.fetch(ANUBION_URN)
    assert_equal "De Martyribus (Fragmenta)", titles.fetch(METHODIUS_URN)
    assert_equal "Introductio arithmetica", titles.fetch(NICOMACHUS_URN)
    assert_equal "Genesis", titles.fetch(LXX_GENESIS_URN)
  end

  # The LXX witness (P11-5): tlg0527 cites chapter.verse — the passage urn
  # tails ARE verse refs ("1.1"), which is what the alignment hub's cts-verse
  # extractor rides on. Pin the shape and the famous opening words.
  def test_parse_round_trips_lxx_genesis_at_verse_grain
    adapter = Nabu::Adapters::First1kGreek.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == LXX_GENESIS_URN }
    document = adapter.parse(ref)
    assert_equal LXX_GENESIS_URN, document.urn
    assert_equal 31, document.size
    assert_equal "#{LXX_GENESIS_URN}:1.1", document.first.urn
    assert_equal "#{LXX_GENESIS_URN}:1.31", document.to_a.last.urn
    assert_includes document.first.text, "ΕΝ ΑΡΧΗ ἐποίησεν ὁ θεὸς"
  end

  def test_discover_returns_an_enumerator_without_a_block
    assert_kind_of Enumerator, Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR)
  end

  # Accept any `*-grcN` slug family, still one edition per work.
  def test_discover_accepts_perseus_and_opp_slug_families_in_first1k
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc1.xml"))
      other = File.join(dir, "data", "tlg9999", "tlg002")
      FileUtils.mkdir_p(other)
      FileUtils.touch(File.join(other, "tlg9999.tlg002.opp-grc3.xml"))
      refs = Nabu::Adapters::First1kGreek.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.perseus-grc1",
                    "urn:cts:greekLit:tlg9999.tlg002.opp-grc3"], refs.map(&:id).sort
    end
  end

  def test_discover_skips_non_greek_editions_and_translations
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-grc1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-eng1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-eng1a.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.opp-lat1.xml"))
      refs = Nabu::Adapters::First1kGreek.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.1st1K-grc1"], refs.map(&:id)
    end
  end

  # Version-preference rule (P3-2, documented): numeric part ascending, then a
  # letter suffix ascending. So grc1 < grc2 < grc2a — grc2a wins. The families
  # may differ (opp- vs 1st1K-); only the -grc<version> tail decides.
  def test_discover_prefers_highest_version_with_letter_suffix_winning
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-grc1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-grc2.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.opp-grc2a.xml"))
      refs = Nabu::Adapters::First1kGreek.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.opp-grc2a"], refs.map(&:id)
    end
  end

  # --- parse --------------------------------------------------------------

  def test_parse_round_trips_the_seikilos_epitaph
    adapter = Nabu::Adapters::First1kGreek.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == SEIKILOS_URN }
    document = adapter.parse(ref)
    assert_equal SEIKILOS_URN, document.urn
    assert_equal "grc", document.language
    assert_equal "Sicili Epitaphium", document.title
    assert_equal "#{SEIKILOS_URN}:1", document.first.urn
    # Distinctive phrase from the famous Seikilos epitaph.
    assert_includes document.first.text, "Σείκιλος"
  end

  # tlg1126 cites at a single level whose unit name is "work" (subtype="work"),
  # exercising the refsDecl-driven citation path against a non-"section" unit.
  def test_parse_round_trips_the_subtype_work_variant
    adapter = Nabu::Adapters::First1kGreek.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == ANUBION_URN }
    document = adapter.parse(ref)
    assert_equal ANUBION_URN, document.urn
    assert_equal "#{ANUBION_URN}:1", document.first.urn
    assert_includes document.first.text, "Ἀννουβίων"
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_first1k_greek_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["first1k-greek"]
    refute_nil entry, "first1k-greek must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::First1kGreek, entry.adapter_class
    assert_equal "first1k-greek", entry.manifest.id
    assert_equal Nabu::Adapters::First1kGreek.manifest, entry.manifest
  end

  # The registry now opts First1KGreek into translations (P9-1); the built
  # adapter must actually discover eng editions.
  def test_registry_builds_a_translations_on_adapter
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    adapter = registry["first1k-greek"].build_adapter
    langs = adapter.discover(GREEK_WORKDIR).map { |ref| ref.metadata["language"] }
    assert_includes langs, "eng", "registry-built first1k-greek must discover eng editions"
  end
end

# The translations-on First1KGreek (P9-1): `First1kGreek.new(translations: true)`
# additionally discovers the highest `-eng<n>` edition per work — mirroring the
# perseus mechanism (P7-4) but over First1K's family-agnostic slug family
# (1st1K-eng<n>, opp-eng<n>, letter-suffixed). eng bodies anchor on
# div[@type="translation"]. Flag-off inertness is pinned in First1kGreekTest.
class First1kGreekTranslationsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("first1k")
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")

  GRC_URNS = First1kGreekTest::GRC_URNS
  ENG_URN = First1kGreekTest::PARADOX_ENG_URN
  GRC_URN = First1kGreekTest::PARADOX_GRC_URN

  def adapter
    Nabu::Adapters::First1kGreek.new(translations: true)
  end

  # --- discover -------------------------------------------------------------

  def test_discover_adds_the_eng_edition_alongside_originals_sorted_by_urn
    refs = adapter.discover(GREEK_WORKDIR).to_a
    assert_equal (GRC_URNS + [ENG_URN]).sort, refs.map(&:id)
    assert_equal refs.map(&:id).sort, refs.map(&:id), "discover stays urn-sorted"
  end

  def test_translation_ref_carries_eng_language_title_and_source_id
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.metadata["language"] == "eng" }
    refute_nil ref
    assert_equal ENG_URN, ref.id
    assert_equal "first1k-greek", ref.source_id
    assert_equal "De Incredibilibus (excerpta Vaticana)", ref.metadata["title"]
  end

  # Family-agnostic acceptance, mirroring the originals' rule: only the
  # `-eng<version>` tail matters, so opp-eng / letter-suffixed slugs match too,
  # while non-eng translations (ger/fre/lat) are still skipped.
  def test_discover_accepts_any_eng_family_and_skips_other_translation_languages
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      %w[1st1K-grc1 opp-eng2 1st1K-ger1 opp-lat1].each do |slug|
        FileUtils.touch(File.join(work, "tlg9999.tlg001.#{slug}.xml"))
      end
      refs = adapter.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.1st1K-grc1",
                    "urn:cts:greekLit:tlg9999.tlg001.opp-eng2"], refs.map(&:id).sort
    end
  end

  # --- parse ----------------------------------------------------------------

  def test_parse_yields_eng_passages_from_the_translation_div
    document = parse_ref(ENG_URN)
    assert_equal ENG_URN, document.urn
    assert_equal "eng", document.language
    assert_equal 3, document.size
    suffixes = document.map { |p| p.urn.delete_prefix(document.urn) }
    assert_equal %w[:1 :2 :3], suffixes
    assert_includes document.first.text, "Egyptians"
    assert_equal Nabu::Normalize.search_form(document.first.text, language: "eng"),
                 document.first.text_normalized
  end

  # The pair aligns section-for-section: the eng edition mints exactly the same
  # citation suffixes as the grc edition — passage-level alignment for free.
  def test_eng_and_grc_share_the_same_section_suffixes
    eng = parse_ref(ENG_URN)
    grc = parse_ref(GRC_URN)
    suffixes = ->(doc) { doc.map { |p| p.urn.delete_prefix(doc.urn) } }
    assert_equal %w[:1 :2 :3], suffixes.call(grc)
    assert_equal suffixes.call(grc), suffixes.call(eng)
  end

  private

  def parse_ref(urn)
    a = adapter
    ref = a.discover(GREEK_WORKDIR).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    a.parse(ref)
  end
end

# The parallel render (Nabu::Query::Parallel, P7-4 / span-grouped P8-1b) over the
# real fixture pair: discover → parse both editions, load through the real
# Loader, and assert the alignment reality gives. tlg4037's grc and eng both
# cite one `section` level with identical @n, so every anchor is a 1:1 PAIR
# (verse-for-verse), not a coarse block.
class First1kGreekParallelRenderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("first1k")
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")
  ENG_URN = First1kGreekTest::PARADOX_ENG_URN
  GRC_URN = First1kGreekTest::PARADOX_GRC_URN

  def setup
    @catalog = store_test_db
    source = Nabu::Store::Source.create(
      slug: "first1k-greek", name: "First1KGreek", adapter_class: "Nabu::Adapters::First1kGreek",
      license_class: "attribution"
    )
    loader = Nabu::Store::Loader.new(db: @catalog, source: source)
    adapter = Nabu::Adapters::First1kGreek.new(translations: true)
    docs = adapter.discover(GREEK_WORKDIR)
                  .select { |ref| ref.id.include?("tlg4037") }
                  .map { |ref| adapter.parse(ref) }
    loader.load(docs, full: true)
  end

  def test_parallel_render_of_the_pair_is_verse_for_verse_pairs
    result = Nabu::Query::Parallel.new(catalog: @catalog).run(GRC_URN, lang: "eng")
    refute_nil result.right, "eng sibling of the same CTS work must be found"
    assert_equal ENG_URN, result.right.urn
    assert_equal %i[pair pair pair], result.groups.map(&:kind)

    one = result.groups.first
    assert_equal ":1", one.anchor
    assert_includes one.originals.first.text, "Ἰστέον"
    assert_includes one.translation.text, "Egyptians"
    refute one.clipped
  end

  def test_parallel_is_symmetric_from_the_translation_side
    result = Nabu::Query::Parallel.new(catalog: @catalog).run(ENG_URN, lang: "grc")
    assert_equal ENG_URN, result.left.urn
    assert_equal GRC_URN, result.right.urn
    assert_equal %i[pair pair pair], result.groups.map(&:kind)
  end
end

# The shared conformance suite against a translations-on First1KGreek instance:
# the eng document must satisfy every adapter guarantee (urn uniqueness across
# the widened discover set, stability across two parses, NFC, minted search
# form) exactly like the originals.
class First1kGreekTranslationsConformanceTest < Minitest::Test
  include AdapterConformance

  def conformance_adapter
    Nabu::Adapters::First1kGreek.new(translations: true)
  end

  def conformance_workdir
    File.join(Nabu::TestSupport.fixtures("first1k"), "greekLit")
  end

  def conformance_expected_source_id
    "first1k-greek"
  end
end
