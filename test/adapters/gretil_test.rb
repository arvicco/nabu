# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# GRETIL adapter tests (P9-4b). The adapter composes GretilParser (a new
# bespoke family) with the mass-converted TEI corpus layout: discover globs
# **/*.xml, peeking each header for title + <text>/@xml:lang (mapped sa→san);
# parse delegates to GretilParser; fetch clones/pulls the single upstream TEI
# mirror. The three fixtures span the three addressability rungs — attribute-
# cited <l>/@n (Ṛgveda), in-text // BrbUp_N // markers (Brahmabindu), and
# unaddressed prose ordinals (Heart Sūtra). Includes the shared
# AdapterConformance suite. No network: fetch runs against a local git repo.
class GretilTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("gretil") # NABU_FIXTURE_DIR-aware (fixtures:check)

  RGVEDA = "urn:nabu:gretil:sa_Rgveda-edAufrecht-m1s1-3"
  BRAHMABINDU = "urn:nabu:gretil:sa_brahmabindUpaniSad"
  HEART_SUTRA = "urn:nabu:gretil:sa_prajJApAramitAhRdayasUtra"
  # P9-4c quarantine-recovery fixtures.
  RGVIDHANA = "urn:nabu:gretil:sa_RgvidhAna-a1" # xml:id rung (fix 1)
  BRAHMASUTRA = "urn:nabu:gretil:sa_bAdarAyaNa-brahmasUtra" # pipe markers (fix 2)
  VALLALACARITA = "urn:nabu:gretil:sa_AnandabhaTTa-vallAlacarita-c1" # single-prefix collision (fix 3)
  DHVANYALOKA = "urn:nabu:gretil:sa_Anandavardhana-dhvanyAloka-comm-u1" # multi-prefix (fix 3)
  # P10-3 line-terminated marker recovery fixtures.
  ABHIDHARMADIPA = "urn:nabu:gretil:sa_vimalamitra-abhidharmadIpa-h1" # hyphenated closed "// Abhidh-d_N //"
  SOMANANDA = "urn:nabu:gretil:sa_somAnanda-zAktavijJAna-l1" # leading-"//"-only "// SomSv_N</l>"
  # Single-blob re-split fixtures: lg/marker shapes a trailing <p> mashed into ONE p1.
  MANUSMRTI = "urn:nabu:gretil:sa_manusmRti-a1a2" # <lg xml:id="Manu_N.N"> + colophon <p>
  ASTADHYAYI = "urn:nabu:gretil:sa_pANini-aSTAdhyAyI-s1" # "|| PS_1,1.1 ||" + one <p> sūtra

  ALL_FIXTURES = [
    RGVEDA, BRAHMABINDU, HEART_SUTRA, RGVIDHANA, BRAHMASUTRA, VALLALACARITA, DHVANYALOKA,
    ABHIDHARMADIPA, SOMANANDA, MANUSMRTI, ASTADHYAYI
  ].freeze

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Gretil.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "gretil"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Gretil.manifest
    assert_equal "gretil", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_equal "https://github.com/mmehner/gretil-corpus-tei", manifest.upstream_url
    assert_equal "gretil", manifest.parser_family
  end

  # --- discover -----------------------------------------------------------

  def test_discover_mints_literal_filename_slugs_and_peeks_language_title
    refs = Nabu::Adapters::Gretil.new.discover(FIXTURES).to_a
    assert_equal ALL_FIXTURES.sort, refs.map(&:id)
    refs.each do |ref|
      assert_equal "gretil", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert_equal "san-Latn", ref.metadata["language"]
      refute_nil ref.metadata["title"]
    end
  end

  def test_discover_skips_non_gretil_xml_without_a_text_language
    Dir.mktmpdir do |root|
      FileUtils.cp(File.join(FIXTURES, "sa_brahmabindUpaniSad.xml"), root)
      File.write(File.join(root, "stray.xml"), "<TEI><teiHeader/></TEI>\n")
      refs = Nabu::Adapters::Gretil.new.discover(root).to_a
      assert_equal [BRAHMABINDU], refs.map(&:id)
    end
  end

  # --- P11-7 fix 6: editions whose <text> lacks @xml:lang are recovered ------

  # sa_haribhadrasUri-zAstravArttAsamuccaya (and the 1.8 MB Mitākṣarā) carry a
  # <text> with NO @xml:lang — peek_header returned nil and discovery dropped
  # them INVISIBLY. The language now falls back to <body>/@xml:lang (san-Latn),
  # so the genuine edition is recovered rather than silently lost.
  STRAYS = Nabu::TestSupport.fixtures("gretil_p11_7")
  HARIBHADRA = "urn:nabu:gretil:sa_haribhadrasUri-zAstravArttAsamuccaya"

  def test_edition_without_text_xml_lang_is_recovered_via_body_lang
    adapter = Nabu::Adapters::Gretil.new
    ref = adapter.discover(STRAYS).find { |r| r.id == HARIBHADRA }
    refute_nil ref, "the <text>-lang-less edition must be discovered, not dropped"
    assert_equal "san-Latn", ref.metadata["language"] # from <body xml:lang="sa-Latn">

    doc = adapter.parse(ref)
    assert_equal "san-Latn", doc.language
    refute_empty doc
    assert_equal(%w[1.1.1 1.1.2 1.1.3], doc.map { |p| p.urn.split(":").last })
  end

  def test_stray_recovery_leaves_no_silent_discovery_skip
    skips = Nabu::Adapters::Gretil.new.discovery_skips(STRAYS)
    assert_equal 0, skips.skipped_by_rule, "the recovered edition must not read as skipped"
  end

  # --- rung (a): attribute-cited <l>/@n, accents preserved pristine ---------

  def test_rgveda_attribute_citations_with_pristine_accented_text
    doc = parse(RGVEDA)
    assert_equal "san-Latn", doc.language
    assert_equal 60, doc.size # 30 verses x 2 padas, Maṇḍala 1 Sūktas 1-3

    first = doc.to_a.first
    assert_equal "#{RGVEDA}:1.001.01a", first.urn
    # The Vedic accents (combining U+0331 anudātta, U+030D udātta) survive
    # verbatim in the pristine text — the orig-KEPT policy.
    assert_equal "a̱gnim ī̍ḻe pu̱rohi̍taṁ ya̱jñasya̍ de̱vam ṛ̱tvija̍m |",
                 first.text
    assert_includes first.text, "̱", "anudātta combining mark must be preserved"
    # The generic `san` fold strips the accents for the search form.
    assert_equal "agnim ile purohitam yajnasya devam rtvijam |", first.text_normalized
    # Enclosing lg/@xml:id and the div path ride along as context.
    assert_equal "attribute", first.annotations["addressing"]
    assert_equal "RV_1.001.01", first.annotations["lg"]
    assert_equal({ "maṇḍala" => "1", "sūkta" => "001" }, first.annotations["div"])

    assert_equal "#{RGVEDA}:1.003.12c", doc.to_a.last.urn
  end

  # --- rung (b): in-text // BrbUp_N // markers, stripped from the text -------

  def test_brahmabindu_marker_citations_with_marker_stripped
    doc = parse(BRAHMABINDU)
    assert_equal 22, doc.size

    v1 = doc.to_a.first
    assert_equal "#{BRAHMABINDU}:1", v1.urn
    assert_equal "verse-marker", v1.annotations["addressing"]
    # The whole verse (across its <l> lines) is one passage; the "// BrbUp_1 //"
    # marker is stripped, the half-verse daṇḍa "/" is kept as reading text.
    assert_equal "oṃ mano hi dvividhaṃ proktaṃ śuddhaṃ cāśuddham eva ca / " \
                 "aśuddhaṃ kāmasaṃkalpaṃ śuddhaṃ kāmavivarjitam", v1.text
    refute_includes v1.text, "//", "the verse marker delimiter must be stripped"
    refute_includes v1.text, "BrbUp", "the verse marker abbreviation must be stripped"

    assert_equal "#{BRAHMABINDU}:22", doc.to_a.last.urn
    assert_equal(%w[1 2 3], doc.to_a.first(3).map { |p| p.urn.split(":").last })
  end

  # --- rung (c): unaddressed prose → paragraph ordinals ---------------------

  def test_heart_sutra_prose_paragraph_ordinals_flagged_non_canonical
    doc = parse(HEART_SUTRA)
    assert_equal 8, doc.size
    assert_equal(%w[p1 p2 p3 p4 p5 p6 p7 p8], doc.map { |p| p.urn.split(":").last })
    first = doc.to_a.first
    assert_equal "#{HEART_SUTRA}:p1", first.urn
    assert_equal "Prajñāpāramitā-hṛdaya-sūtra", first.text
    # Prose addressing is flagged non-canonical so a future re-chunk is honest.
    assert_equal "prose-ordinal", first.annotations["addressing"]
  end

  # --- P9-4c fix 1: xml:id rung (lg-level), fallback when primary is empty ---

  def test_rgvidhana_xml_id_lg_rung
    doc = parse(RGVIDHANA)
    assert_equal "san-Latn", doc.language
    # 8 lg groups (Adhyāya 1); the <lg xml:id="RgV_1.1.1"> IS the passage, its
    # two <l xml:id="…a/…b"> children are pada rows, not separate citations.
    assert_equal(
      %w[1.1.1 1.1.2 1.1.3 1.1.4 1.1.5 1.1.6 1.2.7 1.2.8],
      doc.map { |p| p.urn.split(":").last }
    )
    first = doc.to_a.first
    assert_equal "#{RGVIDHANA}:1.1.1", first.urn
    assert_equal "xml-id", first.annotations["addressing"]
    # Citation is the lg @xml:id with the "RgV_" prefix stripped, dotted path kept.
    assert_equal "svayambhuve.brahmaṇe.viśvagoptre.namaskṛtvā.mantradṛgbhyas.tathaiva./ " \
                 "vivakṣur.asmy.ṛgvidhānam.purāṇam.purādṛṣṭam.ṛṣibhir.mantra.dṛgbhiḥ.//",
                 first.text
    assert_equal "#{RGVIDHANA}:1.2.8", doc.to_a.last.urn
  end

  # --- P9-4c fix 2: single-pipe "| Abbr_1,1.1 |" markers (fallback pass) -----

  def test_brahmasutra_pipe_markers
    doc = parse(BRAHMASUTRA)
    assert_equal 545, doc.size
    first = doc.to_a.first
    assert_equal "#{BRAHMASUTRA}:1,1.1", first.urn
    assert_equal "verse-marker", first.annotations["addressing"]
    # The single-pipe marker is stripped; the comma level separator survives in
    # the citation exactly as the "//" rung keeps it.
    assert_equal "athāto brahmajijñāsā", first.text
    refute_includes first.text, "|", "the single-pipe marker delimiter must be stripped"
    refute_includes first.text, "BBs", "the marker abbreviation must be stripped"
    assert_equal "#{BRAHMASUTRA}:4,4.22", doc.to_a.last.urn
  end

  # --- P9-4c fix 3: single-prefix collision → deterministic :b<k> suffix -----

  def test_vallalacarita_collision_suffix
    doc = parse(VALLALACARITA)
    citations = doc.map { |p| p.urn.delete_prefix("#{VALLALACARITA}:") }
    # The real upstream duplicate 1.70 (two different verses both numbered
    # Valc_1.70) is disambiguated in document order; neighbours untouched.
    assert_equal(%w[1.70 1.71 1.72 1.73 1.74 1.75 1.76 1.70:b2], citations)
    assert_equal citations.uniq, citations, "collision suffixing must yield unique citations"
    first_dup, second_dup = doc.to_a.values_at(0, 7)
    assert_equal "#{VALLALACARITA}:1.70", first_dup.urn
    assert_equal "#{VALLALACARITA}:1.70:b2", second_dup.urn
    refute_equal first_dup.text, second_dup.text, "the two 1.70 verses are different text"
  end

  # --- P9-4c fix 3: multi-prefix join (DhvK_ kārikā vs DhvA_ commentary) -----

  def test_dhvanyaloka_multi_prefix_join
    doc = parse(DHVANYALOKA)
    # Two distinct marker prefixes whose bare numbers collide (DhvK_1.1 vs
    # DhvA_1.1) → the prefix joins the citation so the layers do not share a urn.
    assert_equal(%w[DhvK.1.1 DhvA.1.1 DhvK.1.2], doc.map { |p| p.urn.delete_prefix("#{DHVANYALOKA}:") })
    assert_equal "#{DHVANYALOKA}:DhvK.1.1", doc.to_a.first.urn
    assert_equal "verse-marker", doc.to_a.first.annotations["addressing"]
  end

  # --- P10-3: hyphenated closed marker "// Abhidh-d_N //" (line-marker pass) --

  def test_abhidharmadipa_hyphenated_closed_markers
    doc = parse(ABHIDHARMADIPA)
    assert_equal "san-Latn", doc.language
    assert_equal 4, doc.size # 4 lg, one "// Abhidh-d_N //" each
    assert_equal(%w[1 2 3 4], doc.map { |p| p.urn.split(":").last })

    first = doc.to_a.first
    assert_equal "#{ABHIDHARMADIPA}:1", first.urn
    assert_equal "verse-marker", first.annotations["addressing"]
    # Both padas of the verse (across its two <l>) join into one passage; the
    # hyphenated "// Abhidh-d_1 //" marker is stripped, the half-verse daṇḍa kept.
    assert_equal "yo duḥkhahetuvyupaśāntimārgaṃ pradarśayāmāsa narāmarebhyaḥ / " \
                 "taṃ satpathajñaṃ praṇipatya buddhaṃ śāstraṃ kariṣyāmyabhidharmadīpam",
                 first.text
    refute_includes first.text, "//", "the verse marker delimiter must be stripped"
    refute_includes first.text, "Abhidh", "the hyphenated marker abbreviation must be stripped"
  end

  # --- P10-3: leading-"//"-only marker "// SomSv_N</l>" (line-marker pass) -----

  def test_somananda_leading_only_markers
    doc = parse(SOMANANDA)
    assert_equal 4, doc.size # 4 lg, one leading-only "// SomSv_N" each
    assert_equal(%w[1 2 3 4], doc.map { |p| p.urn.split(":").last })

    first = doc.to_a.first
    assert_equal "#{SOMANANDA}:1", first.urn
    assert_equal "verse-marker", first.annotations["addressing"]
    # No closing "//": the </l> boundary terminates the marker, which is stripped.
    assert_equal "sthānaṃ praveśo rūpaṃ ca lakṣaṃ lakṣaṇameva ca / " \
                 "utthāpanaṃ bodhanaṃ ca cakraviśrāmameva ca",
                 first.text
    refute_includes first.text, "//", "the leading marker delimiter must be stripped"
    refute_includes first.text, "SomSv", "the marker abbreviation must be stripped"
  end

  # Guard: the line-marker fallback must NOT fire on a doc the primary "// … //"
  # pass already addresses. The Brahmabindu (whole "// BrbUp_N //") is handled by
  # the PRIMARY pass; if the line-marker pass leaked in-line (or the primary pass
  # regressed) its citations would change. They stay the bare primary-pass 1..22.
  def test_line_marker_pass_does_not_fire_on_primary_marker_file
    doc = parse(BRAHMABINDU)
    assert_equal((1..22).map(&:to_s), doc.map { |p| p.urn.split(":").last })
    doc.each { |p| assert_equal "verse-marker", p.annotations["addressing"] }
  end

  # Guard: multi-prefix handling must NOT fire on a single-prefix file — the
  # Brahmabindu (all "// BrbUp_N //") keeps bare-number citations, never
  # "BrbUp.N" (frozen-urn: single-prefix collisions get :b<k>, never a prefix).
  def test_multi_prefix_does_not_fire_on_single_prefix_file
    citations = parse(BRAHMABINDU).map { |p| p.urn.split(":").last }
    assert_equal((1..22).map(&:to_s), citations)
    citations.each { |c| refute_includes c, "BrbUp", "single-prefix file must not be prefix-joined" }
  end

  # --- single-blob re-split: a lone trailing <p> must not swallow the text -----

  # sa_manusmRti addresses every verse by <lg xml:id="Manu_A.V"> (no @n, no
  # in-text marker) and closes with a colophon <p>. The primary pass used to
  # accumulate all 2,7xx verses unflushed and dump them into that <p> as ONE
  # prose ordinal p1 — so the fallbacks never ran. A primary result that is a
  # single prose-ordinal blob is now treated as degenerate: the xml:id rung
  # addresses the verses (Manu_1.1 → 1.1; the analysis <note> copies dropped).
  def test_manusmrti_resplits_to_verse_grain_via_xml_id
    doc = parse(MANUSMRTI)
    assert_equal(%w[1.1 1.2 1.3 2.1], doc.map { |p| p.urn.split(":").last })
    first = doc.to_a.first
    assert_equal "#{MANUSMRTI}:1.1", first.urn
    assert_equal "xml-id", first.annotations["addressing"]
    assert_equal "manum ekāgram āsīnam abhigamya maharṣayaḥ pratipūjya yathānyāyam idaṃ vacanam abruvan //",
                 first.text
    refute(doc.any? { |p| p.text.include?("ekāgram") && p.urn.end_with?(":1.2") },
           "each verse is its own passage, never the running blob")
  end

  # sa_pANini-aSTAdhyAyI marks each sūtra "|| PS_1,1.1 ||" (DOUBLE-pipe
  # delimiters) at the end of its <l>, and one sūtra (6,1.130) sits in a <p>
  # — which flushed the whole unflushed text as p1. Re-split by the pipe
  # fallback, the doubled pipe now a delimiter in its own right, so no stray
  # "|" survives on either side of a sūtra.
  def test_astadhyayi_resplits_to_sutra_grain_with_double_pipe_markers
    doc = parse(ASTADHYAYI)
    assert_equal(%w[1,1.1 1,1.2 1,1.3 1,1.4 1,1.5 1,1.6 6,1.128 6,1.129 6,1.130 6,1.131],
                 doc.map { |p| p.urn.split(":").last })
    first = doc.to_a.first
    assert_equal "verse-marker", first.annotations["addressing"]
    assert_equal "vṛddhir ād-aic", first.text
    doc.each do |passage|
      refute_includes passage.text, "|", "#{passage.urn}: the double-pipe marker must be stripped whole"
      refute_includes passage.text, "PS_", "#{passage.urn}: the marker abbreviation must be stripped"
    end
    assert_equal "ī3 cākravarmaṇasya", doc.find { |p| p.urn.end_with?(":6,1.130") }.text
  end

  # Guard: a GENUINE one-paragraph prose text (no verse addressing anywhere)
  # keeps its p1 — the degenerate-blob gate only swaps in a fallback that
  # actually addresses more than one passage.
  def test_single_paragraph_prose_without_addressing_keeps_its_p1
    Dir.mktmpdir do |root|
      body = File.read(File.join(FIXTURES, "sa_prajJApAramitAhRdayasUtra.xml"))
      one = body.sub(%r{<body>.*</body>}m, "<body><p>evaṃ mayā śrutam ekasmin samaye</p></body>")
      path = File.join(root, "sa_one.xml")
      File.write(path, one)
      doc = Nabu::Adapters::GretilParser.new.parse(path, urn: "urn:nabu:gretil:sa_one", language: "san-Latn")
      assert_equal ["urn:nabu:gretil:sa_one:p1"], doc.map(&:urn)
    end
  end

  # --- header mining: author, genre ladder, source edition --------------------

  # The teiHeader carries the titleStmt <author> (on 427 of 784 files), the
  # GRETIL genre ladder in profileDesc/textClass/keywords/term (on every
  # file) and the sourceDesc edition (a <bibl>, or <biblStruct> monographs).
  def test_header_author_genre_and_edition_ride_metadata
    doc = parse(VALLALACARITA)
    assert_equal "Ānandabhaṭṭa", doc.metadata["author"]
    assert_equal ["Sanskrit -- Poetry -- Kāvya"], doc.metadata["genre"]
    assert_equal ["Haraprasāda Śāstrī: Vallāla Caritam, Calcutta : Asiatic Society 1904 " \
                  "(Bibliotheca Indica, 164)"], doc.metadata["edition"]
  end

  def test_empty_author_and_empty_bibl_mint_nothing
    meta = parse(HEART_SUTRA).metadata
    refute meta.key?("author"), "an empty <author/> is absence, never a blank author"
    refute meta.key?("edition"), "an empty <bibl/> is absence"
    assert_equal ["Sanskrit -- Religious Literature -- Buddhist"], meta["genre"]

    meta = parse(BRAHMABINDU).metadata
    refute meta.key?("author")
    assert_equal ["Sanskrit -- Veda -- Upaniṣad"], meta["genre"]
  end

  # The 33 biblStruct-only headers (the Aufrecht Ṛgveda) render each
  # monograph in GRETIL's own bibl order: editor: title, place: publisher year.
  def test_bibl_struct_editions_render_one_line_per_monograph
    assert_equal ["Theodor Aufrecht: Die Hymnen des Rigveda. Mandala I-VI, Bonn: Mareus 1877",
                  "Theodor Aufrecht: Die Hymnen des Rigveda. Mandala VII-X, Bonn: Mareus 1877"],
                 parse(RGVEDA).metadata["edition"]
  end

  # --- urn stability across two independent parses (belt-and-braces) --------

  def test_urns_are_stable_across_two_parses_per_rung
    ALL_FIXTURES.each do |urn|
      first = parse(urn).map(&:urn)
      second = parse(urn).map(&:urn)
      assert_equal first, second, "#{urn}: passage urns must be identical across two parses"
    end
  end

  # --- language mapping ------------------------------------------------------

  def test_normalize_language_maps_iso_639_1_to_639_3_preserving_script
    assert_equal "san-Latn", Nabu::Adapters::GretilParser.normalize_language("sa-Latn")
    assert_equal "san", Nabu::Adapters::GretilParser.normalize_language("sa")
    assert_nil Nabu::Adapters::GretilParser.normalize_language(nil)
    # Unknown primary subtags pass through (some GRETIL texts are other Indic
    # languages the fixtures do not exercise).
    assert_equal "pra-Latn", Nabu::Adapters::GretilParser.normalize_language("pra-Latn")
  end

  # --- fetch (local git only, no network) -----------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = gretil_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
      # Second call → pull path, same sha.
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = gretil_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip --------------------------------------------------

  def test_registry_resolves_gretil_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["gretil"]
    refute_nil entry, "gretil must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Gretil, entry.adapter_class
    assert_equal "manual", entry.sync_policy
    assert entry.wired, "gretil is live (owner sign-off 2026-07-08 after first real sync + P9-4c recovery)"
  end

  private

  def parse(urn)
    adapter = Nabu::Adapters::Gretil.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } or flunk "no ref for #{urn}"
    adapter.parse(ref)
  end

  def gretil_pointing_at(upstream)
    adapter = Nabu::Adapters::Gretil.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "sa_dummy.xml"), "<TEI/>\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
