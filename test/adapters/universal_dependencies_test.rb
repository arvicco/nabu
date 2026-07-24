# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Universal Dependencies adapter tests (P3-3). The adapter composes ConlluParser
# with UD's git-repo-per-treebank layout: discover walks <slug>/*.conllu (one
# DocumentRef per file), parse delegates to ConlluParser, fetch clones/pulls
# each treebank repo. Includes the shared AdapterConformance suite against the
# checked-in UD fixtures. No network: fetch is exercised against a local git
# repo in a tmpdir plus a Shell-failure path.
class UniversalDependenciesTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = File.expand_path("../fixtures/ud", __dir__)

  EXPECTED_URNS = [
    "urn:nabu:ud:akkadian-pisandub:akk_pisandub-ud-test-head50",
    "urn:nabu:ud:akkadian-riao:akk_riao-ud-test-head50",
    "urn:nabu:ud:ancient-greek-perseus:grc_perseus-ud-test-head50",
    "urn:nabu:ud:classical-armenian-caval:xcl_caval-ud-test-head50",
    "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-dev-slices",
    "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-test-head50",
    "urn:nabu:ud:classical-chinese-tuecl:lzh_tuecl-ud-test-head50",
    "urn:nabu:ud:coptic-bohairic:cop_bohairic-ud-test-head50",
    "urn:nabu:ud:egyptian-pc:egy_pc-ud-test-head50",
    "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50",
    "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50",
    "urn:nabu:ud:greek-ptnk:grc_ptnk-ud-test-head50",
    "urn:nabu:ud:hebrew-ptnk:hbo_ptnk-ud-test-head50",
    "urn:nabu:ud:hittite-hittb:hit_hittb-ud-test-head50",
    "urn:nabu:ud:icelandic-icepahc:is_icepahc-ud-dev-head50",
    "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt",
    "urn:nabu:ud:latin-perseus:la_perseus-ud-test-head50",
    "urn:nabu:ud:middle-french-profiterole:frm_profiterole-ud-test-head50",
    "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50",
    "urn:nabu:ud:old-east-slavic-rnc:orv_rnc-ud-test-head50",
    "urn:nabu:ud:old-east-slavic-ruthenian:orv_ruthenian-ud-test-head50",
    "urn:nabu:ud:old-french-profiterole:fro_profiterole-ud-test-head50",
    "urn:nabu:ud:old-irish-dipsgg:sga_dipsgg-ud-test-head50",
    "urn:nabu:ud:old-irish-dipwbg:sga_dipwbg-ud-test",
    "urn:nabu:ud:ottoman-boun:ota_boun-ud-test-head50",
    "urn:nabu:ud:ottoman-dudu:ota_dudu-ud-test-head50",
    "urn:nabu:ud:sanskrit-vedic:sa_vedic-ud-test-head50"
  ].freeze

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::UniversalDependencies.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ud"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::UniversalDependencies.manifest
    assert_equal "ud", manifest.id
    assert_equal "Universal Dependencies — ancient treebanks", manifest.name
    assert_equal "nc", manifest.license_class
    assert_equal "https://github.com/UniversalDependencies", manifest.upstream_url
    assert_equal "conllu", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::UniversalDependencies.manifest,
                 Nabu::Adapters::UniversalDependencies.new.manifest
  end

  # --- dedup guard (P10-2) -------------------------------------------------

  # The UD repo ships CONVERSIONS of data Nabu already ingests natively:
  # UD_Church_Slavonic-PROIEL (slug would be chu-proiel) re-exports the PROIEL
  # OCS canon the `proiel` source syncs, and UD_Old_East_Slavic-TOROT
  # (orv-torot) re-exports the `torot` source. Adding either to TREEBANKS would
  # DOUBLE-LOAD the same sentences under a second urn scheme — the survey's
  # named hazard (.docs/surveys/slavic-survey.md §1). This test freezes their exclusion:
  # the two orv treebanks we DO add (Birchbark, RNC) are RNC-scheme conversions
  # with no PROIEL/TOROT overlap, so they are safe; the two below are not.
  def test_treebanks_excludes_the_chu_proiel_and_orv_torot_conversions
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    repos = treebanks.values.map { |tb| tb[:repo] }

    # The two UD repos that are CONVERSIONS of data Nabu already ingests
    # natively — UD_Church_Slavonic-PROIEL re-exports the PROIEL OCS canon the
    # `proiel` source syncs, UD_Old_East_Slavic-TOROT re-exports the `torot`
    # source. Adding either would attest every OCS sentence twice (once natively,
    # once under urn:nabu:ud:…), inflating the lemma index and corpus counts.
    # The two orv treebanks we DO add (Birchbark, RNC) are RNC-scheme
    # conversions with no PROIEL/TOROT overlap, so they are safe. Guard both by
    # repo name and — because Church Slavonic is served ONLY natively — by the
    # `chu` language tag, so no future chu-PROIEL slips in under a renamed slug.
    [
      "https://github.com/UniversalDependencies/UD_Church_Slavonic-PROIEL",
      "https://github.com/UniversalDependencies/UD_Old_East_Slavic-TOROT"
    ].each do |conversion_repo|
      refute_includes repos, conversion_repo,
                      "TREEBANKS must exclude #{conversion_repo}: it re-loads the native " \
                      "proiel/torot sync (double-load hazard, .docs/surveys/slavic-survey.md §1)"
    end

    chu = treebanks.select { |_slug, tb| tb[:language] == "chu" }.keys
    assert_empty chu,
                 "no TREEBANKS entry may carry language chu — the OCS canon is served only " \
                 "natively via proiel/torot; a chu UD treebank would double-load it. Found: #{chu.inspect}"
  end

  # --- registration pins (P31-6) -------------------------------------------
  #
  # The two Perseus treebanks (UD conversions of the native AGDT/LDT v2.1,
  # 02-sources row 17's UD half). The chu-PROIEL re-export guard does NOT
  # apply: nabu has never synced the native AGLDT — there is no double-load.
  # And no overlap with greek-proiel/latin-ittb (different upstream data).
  def test_treebanks_registers_the_two_perseus_treebanks
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    grc = treebanks.fetch("ancient-greek-perseus")
    assert_equal "https://github.com/UniversalDependencies/UD_Ancient_Greek-Perseus", grc[:repo]
    assert_equal "grc", grc[:language]
    lat = treebanks.fetch("latin-perseus")
    assert_equal "https://github.com/UniversalDependencies/UD_Latin-Perseus", lat[:repo]
    assert_equal "lat", lat[:language]
  end

  # --- registration pins (P32-0) -------------------------------------------
  #
  # The two Classical Chinese treebanks — the Sino axis's UD entry point.
  # classical-chinese-kyoto (UD_Classical_Chinese-Kyoto) is the Kyoto
  # University treebank: 86,239 sentences / 433,169 words across 論語, 孟子,
  # 禮記, 十八史略, 楚辭, 戰國策, 唐詩三百首 and three sutras;
  # classical-chinese-tuecl (UD_Classical_Chinese-TueCL) is the Tübingen
  # 100-sentence Zhuangzi 逍遥游 rider, test-set only (the DipWBG shape).
  # No re-export guard concern: neither converts a source nabu syncs.
  def test_treebanks_registers_the_two_classical_chinese_treebanks
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    kyoto = treebanks.fetch("classical-chinese-kyoto")
    assert_equal "https://github.com/UniversalDependencies/UD_Classical_Chinese-Kyoto", kyoto[:repo]
    assert_equal "lzh", kyoto[:language]
    tuecl = treebanks.fetch("classical-chinese-tuecl")
    assert_equal "https://github.com/UniversalDependencies/UD_Classical_Chinese-TueCL", tuecl[:repo]
    assert_equal "lzh", tuecl[:language]
  end

  # --- registration pin (P40-1) --------------------------------------------
  #
  # The one Icelandic treebank — the Germanic axis's IcePaHC entry point
  # (UD_Icelandic-IcePaHC, a rule-based UD conversion of the Icelandic Parsed
  # Historical Corpus). DIACHRONIC HONESTY: the corpus spans the 12th to the
  # 21st century (Old Norse sagas to modern prose), yet UD files it under the
  # ONE modern ISO 639 tag `is` — the same one-tag-per-treebank practice as
  # RNC's Middle Russian under `orv` (P10-2), recorded not hidden. No
  # re-export guard concern: nabu syncs no source IcePaHC converts.
  def test_treebanks_registers_the_icelandic_icepahc_treebank
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    icepahc = treebanks.fetch("icelandic-icepahc")
    assert_equal "https://github.com/UniversalDependencies/UD_Icelandic-IcePaHC", icepahc[:repo]
    assert_equal "is", icepahc[:language]
  end

  # --- registration + license pins (P43-1, the historical wave) ------------
  #
  # The eleven treebanks of the historical wave: four brand-new language lanes
  # (xcl/fro/frm/ota) and seven under languages the library already hosts
  # (grc/hbo/akk/cop/egy). Config-only, one .conllu fixture each. Repo + language
  # pinned here; licenses (read verbatim 2026-07-23) asserted in the override
  # tests below. Unlike the legacy nc treebanks (which stay bare and inherit the
  # source class), EVERY wave entry carries an EXPLICIT license_class — the nc
  # ones because their nc is a real per-treebank grant (BY-NC-SA / BY-NC),
  # sometimes conflicting across LICENSE.txt vs README, worth recording verbatim.
  P43_WAVE = {
    "classical-armenian-caval" => %w[UD_Classical_Armenian-CAVaL xcl nc],
    "old-french-profiterole" => %w[UD_Old_French-PROFITEROLE fro nc],
    "middle-french-profiterole" => %w[UD_Middle_French-PROFITEROLE frm nc],
    "ottoman-boun" => %w[UD_Ottoman_Turkish-BOUN ota attribution],
    "ottoman-dudu" => %w[UD_Ottoman_Turkish-DUDU ota attribution],
    "greek-ptnk" => %w[UD_Ancient_Greek-PTNK grc attribution],
    "hebrew-ptnk" => %w[UD_Ancient_Hebrew-PTNK hbo nc],
    "akkadian-riao" => %w[UD_Akkadian-RIAO akk attribution],
    "akkadian-pisandub" => %w[UD_Akkadian-PISANDUB akk attribution],
    "coptic-bohairic" => %w[UD_Coptic-Bohairic cop attribution],
    "egyptian-pc" => %w[UD_Egyptian-PC egy attribution]
  }.freeze

  # The verbatim license STRING per wave entry (scout-read 2026-07-23; the
  # file's plain-short-name idiom, conflict nuance in the adapter comments).
  P43_LICENSE_STRINGS = {
    "classical-armenian-caval" => "CC BY-NC-SA 4.0",
    "old-french-profiterole" => "CC BY-NC-SA 3.0",
    "middle-french-profiterole" => "CC BY-NC-SA 4.0",
    "ottoman-boun" => "CC BY-SA 4.0",
    "ottoman-dudu" => "CC BY-SA 4.0",
    "greek-ptnk" => "CC BY-SA 4.0",
    "hebrew-ptnk" => "CC BY-NC 4.0",
    "akkadian-riao" => "CC BY-SA 3.0",
    "akkadian-pisandub" => "CC BY-SA 4.0",
    "coptic-bohairic" => "CC BY 4.0",
    "egyptian-pc" => "CC BY-SA 4.0"
  }.freeze

  def test_p43_wave_registers_repo_and_language_for_all_eleven
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    P43_WAVE.each do |slug, (repo, language, _class)|
      entry = treebanks.fetch(slug)
      assert_equal "https://github.com/UniversalDependencies/#{repo}", entry[:repo], slug
      assert_equal language, entry[:language], slug
    end
  end

  # Every wave entry carries an explicit license_class + verbatim license string
  # (both the nc and attribution cases, unlike the legacy bare-nc treebanks).
  def test_p43_wave_carries_explicit_license_class_and_string
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    P43_WAVE.each do |slug, (_repo, _language, license_class)|
      assert_equal license_class, treebanks.fetch(slug)[:license_class], slug
      assert_equal P43_LICENSE_STRINGS.fetch(slug), treebanks.fetch(slug)[:license], slug
    end
  end

  # The license_class rides through parse to Document#license_override — the
  # nc entries surface "nc", the BY-SA/BY entries "attribution" (the P10-4
  # mechanics, now exercised for the explicit-nc case too).
  def test_p43_wave_parse_surfaces_the_explicit_license_override
    adapter = Nabu::Adapters::UniversalDependencies.new
    by_slug = adapter.discover(FIXTURES)
                     .select { |ref| P43_WAVE.key?(ref.metadata["treebank"]) }
                     .to_h { |ref| [ref.metadata["treebank"], adapter.parse(ref)] }
    P43_WAVE.each do |slug, (_repo, _language, license_class)|
      assert_equal license_class, by_slug.fetch(slug).license_override, slug
    end
    # The SOURCE class is unchanged — the most-restrictive present stays nc.
    assert_equal "nc", Nabu::Adapters::UniversalDependencies.manifest.license_class
  end

  # Round-trip each wave fixture: 50 sentence blocks, the declared language, the
  # opening passage urn (sent_id verbatim, colons and all) and a distinctive
  # real token. Hebrew is NFC-EXEMPT — its passage text is asserted byte-equal
  # to the source `# text` line (byte-honesty holds through ConlluParser with
  # no parser change, because the PTNK text ships already in NFC order).
  P43_OPENERS = {
    "classical-armenian-caval" => ["MATT_6.1", "Զգոյշ"],
    "old-french-profiterole" => ["633", "Se il fust vif"],
    "middle-french-profiterole" => %w[30 Morvillier],
    "ottoman-boun" => %w[nes_tn_76 Musahabeme],
    "ottoman-dudu" => %w[kan_1013 güderleridi],
    "greek-ptnk" => ["Septuagint-Genesis-19:1-grc", "ἄγγελοι"],
    "akkadian-riao" => %w[Q006048-1 Aššur-dan],
    "akkadian-pisandub" => %w[babylon7_amel-marduk_1_01 KÁ-DINGIR-RA-KI],
    "coptic-bohairic" => %w[bohairic_mark-bohairic_Mark_01_s0001 ⲉⲩⲁⲅⲅⲉⲗⲓⲟⲛ],
    "egyptian-pc" => %w[PT_Sethe_23_16a_Unas Wśr]
  }.freeze

  def test_p43_wave_round_trips_each_fixture
    adapter = Nabu::Adapters::UniversalDependencies.new
    by_slug = adapter.discover(FIXTURES)
                     .select { |ref| P43_WAVE.key?(ref.metadata["treebank"]) }
                     .to_h { |ref| [ref.metadata["treebank"], adapter.parse(ref)] }

    P43_WAVE.each do |slug, (_repo, language, _class)|
      document = by_slug.fetch(slug)
      assert_equal 50, document.size, "#{slug} must parse 50 sentence blocks"
      assert_equal language, document.language, slug
    end

    P43_OPENERS.each do |slug, (sent_id, token)|
      document = by_slug.fetch(slug)
      opening = document.passages.first
      assert_equal "#{document.urn}:#{sent_id}", opening.urn, slug
      assert_includes opening.text, token, slug
    end

    # Hebrew PTNK (hbo) — NFC-exempt, byte-verbatim. The opening passage text
    # must equal the source `# text` line exactly (Masoretic cantillation and
    # combining-mark order preserved).
    hbo_doc = by_slug.fetch("hebrew-ptnk")
    hbo = hbo_doc.passages.first
    assert_equal "#{hbo_doc.urn}:Masoretic-Genesis-19:1-hbo", hbo.urn
    assert_equal first_source_text("hebrew-ptnk"), hbo.text
    assert hbo.text.valid_encoding?, "hbo text must be well-formed UTF-8"
  end

  # The first `# text = …` comment of a treebank's fixture file, verbatim
  # (used to pin the hbo byte-honesty assertion against upstream bytes).
  def first_source_text(slug)
    path = Dir.glob(File.join(FIXTURES, slug, "*.conllu")).first
    line = File.foreach(path, mode: "r:UTF-8").find { |l| l.start_with?("# text = ") }
    line.sub(/\A# text = /, "").chomp
  end

  # --- per-treebank license override (P10-4; extended P25-2) ---------------
  #
  # UD's SOURCE class is nc (most-restrictive present, correct for the PROIEL-
  # derived treebanks). The three Old East Slavic treebanks (Birchbark, RNC,
  # Ruthenian), Old Irish DipWBG (P25-2, verbatim "CC BY-SA 4.0") and
  # Hittite HitTB (P31-0, LICENSE.txt verbatim the same BY-SA 4.0 grant) are
  # CC BY-SA 4.0 → attribution: they carry a per-document license_override so
  # the shareable shelf labels them honestly, while the bare treebanks —
  # the four legacy ones plus Old Irish DipSGG (P25-2, verbatim
  # "CC BY-NC-SA 4.0") — inherit the source class nc (override NULL).
  # P31-6: both Perseus treebanks are verbatim CC BY-NC-SA 2.5 Generic
  # (LICENSE.txt + README metadata agree) → NonCommercial → bare, no override
  # (the DipSGG posture).
  # P32-0: both Classical Chinese treebanks carry the BY-SA 4.0 LICENSE.txt
  # grant verbatim → attribution override. NB Kyoto's README metadata says
  # `License: PD` — a real upstream discrepancy, recorded in the fixture
  # README; LICENSE.txt is authoritative (the Ruthenian NOASSERTION
  # precedent: the in-repo grant governs). TueCL's README agrees with its
  # LICENSE.txt.
  # P40-1: Icelandic IcePaHC carries the BY-SA 4.0 grant verbatim (LICENSE.txt
  # + README metadata agree, verified 2026-07-22) → attribution override, the
  # same mechanics; the diachronic-under-`is` honesty is a language note, not
  # a license one.
  OVERRIDE_SLUGS = %w[classical-chinese-kyoto classical-chinese-tuecl hittite-hittb
                      icelandic-icepahc
                      old-east-slavic-birchbark old-east-slavic-rnc
                      old-east-slavic-ruthenian old-irish-dipwbg].freeze
  BARE_SLUGS = %w[ancient-greek-perseus gothic-proiel greek-proiel latin-ittb latin-perseus
                  sanskrit-vedic old-irish-dipsgg].freeze

  def test_treebanks_map_sets_attribution_only_on_the_by_sa_entries
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    OVERRIDE_SLUGS.each do |slug|
      assert_equal "attribution", treebanks.fetch(slug)[:license_class], "#{slug} must be attribution"
      assert_equal "CC BY-SA 4.0", treebanks.fetch(slug)[:license]
    end
    BARE_SLUGS.each do |slug|
      assert_nil treebanks.fetch(slug)[:license_class], "#{slug} must stay bare (source class applies)"
    end
  end

  def test_parse_surfaces_license_override_for_by_sa_and_nil_for_bare
    adapter = Nabu::Adapters::UniversalDependencies.new
    by_slug = adapter.discover(FIXTURES).to_h { |ref| [ref.metadata["treebank"], adapter.parse(ref)] }

    OVERRIDE_SLUGS.each { |slug| assert_equal "attribution", by_slug.fetch(slug).license_override }
    BARE_SLUGS.each { |slug| assert_nil by_slug.fetch(slug).license_override }
  end

  # End-to-end: after a fixture load, documents.license_override reads
  # attribution for the BY-SA treebanks and NULL for the bare ones,
  # while the source class remains nc.
  def test_fixture_load_writes_attribution_override_only_for_the_by_sa_treebanks
    catalog = store_test_db
    source = Nabu::Store::Source.create(
      slug: "ud", name: "Universal Dependencies",
      adapter_class: "Nabu::Adapters::UniversalDependencies", license_class: "nc"
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)

    override_by_slug = Nabu::Store::Document.where(source_id: source.id).all.to_h do |doc|
      [doc.urn.split(":")[3], doc.license_override]
    end
    OVERRIDE_SLUGS.each { |slug| assert_equal "attribution", override_by_slug.fetch(slug) }
    BARE_SLUGS.each { |slug| assert_nil override_by_slug.fetch(slug) }
    assert_equal "nc", source.license_class, "the source class is unchanged"
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_twenty_seven_files_sorted_by_urn
    refs = Nabu::Adapters::UniversalDependencies.new.discover(FIXTURES).to_a
    assert_equal EXPECTED_URNS, refs.map(&:id)
  end

  def test_discover_sets_source_id_language_treebank_and_absolute_path
    refs = Nabu::Adapters::UniversalDependencies.new.discover(FIXTURES).to_a
    by_urn = refs.to_h { |ref| [ref.id, ref] }

    expected_languages = {
      "urn:nabu:ud:akkadian-pisandub:akk_pisandub-ud-test-head50" => "akk",
      "urn:nabu:ud:akkadian-riao:akk_riao-ud-test-head50" => "akk",
      "urn:nabu:ud:classical-armenian-caval:xcl_caval-ud-test-head50" => "xcl",
      "urn:nabu:ud:coptic-bohairic:cop_bohairic-ud-test-head50" => "cop",
      "urn:nabu:ud:egyptian-pc:egy_pc-ud-test-head50" => "egy",
      "urn:nabu:ud:greek-ptnk:grc_ptnk-ud-test-head50" => "grc",
      "urn:nabu:ud:hebrew-ptnk:hbo_ptnk-ud-test-head50" => "hbo",
      "urn:nabu:ud:middle-french-profiterole:frm_profiterole-ud-test-head50" => "frm",
      "urn:nabu:ud:old-french-profiterole:fro_profiterole-ud-test-head50" => "fro",
      "urn:nabu:ud:ottoman-boun:ota_boun-ud-test-head50" => "ota",
      "urn:nabu:ud:ottoman-dudu:ota_dudu-ud-test-head50" => "ota",
      "urn:nabu:ud:ancient-greek-perseus:grc_perseus-ud-test-head50" => "grc",
      "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-dev-slices" => "lzh",
      "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-test-head50" => "lzh",
      "urn:nabu:ud:classical-chinese-tuecl:lzh_tuecl-ud-test-head50" => "lzh",
      "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50" => "got",
      "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50" => "grc",
      "urn:nabu:ud:hittite-hittb:hit_hittb-ud-test-head50" => "hit",
      "urn:nabu:ud:icelandic-icepahc:is_icepahc-ud-dev-head50" => "is",
      "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt" => "lat",
      "urn:nabu:ud:latin-perseus:la_perseus-ud-test-head50" => "lat",
      "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50" => "orv",
      "urn:nabu:ud:old-east-slavic-rnc:orv_rnc-ud-test-head50" => "orv",
      "urn:nabu:ud:old-east-slavic-ruthenian:orv_ruthenian-ud-test-head50" => "orv",
      "urn:nabu:ud:old-irish-dipsgg:sga_dipsgg-ud-test-head50" => "sga",
      "urn:nabu:ud:old-irish-dipwbg:sga_dipwbg-ud-test" => "sga",
      "urn:nabu:ud:sanskrit-vedic:sa_vedic-ud-test-head50" => "san"
    }
    expected_languages.each do |urn, language|
      ref = by_urn.fetch(urn)
      assert_equal "ud", ref.source_id
      assert_equal language, ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end

    got = by_urn.fetch("urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50")
    assert_equal "gothic-proiel", got.metadata["treebank"]
    assert_equal "UD_Gothic-PROIEL (got_proiel-ud-test-head50)", got.metadata["title"]
  end

  def test_discover_skips_unknown_subdirectories
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "gothic-proiel"))
      FileUtils.cp(
        File.join(FIXTURES, "gothic-proiel", "got_proiel-ud-test-head50.conllu"),
        File.join(root, "gothic-proiel")
      )
      # An unregistered treebank on disk must be ignored, not error.
      FileUtils.mkdir_p(File.join(root, "klingon-tng"))
      unknown = "# sent_id = 1\n# text = x\n1\tx\t_\t_\t_\t_\t0\troot\t_\t_\n\n"
      File.write(File.join(root, "klingon-tng", "tlh-ud-test.conllu"), unknown)

      refs = Nabu::Adapters::UniversalDependencies.new.discover(root).to_a
      assert_equal ["urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50"], refs.map(&:id)
    end
  end

  # --- parse round-trip ---------------------------------------------------

  def test_parse_delegates_to_conllu_parser_and_urn_matches_ref
    adapter = Nabu::Adapters::UniversalDependencies.new
    ref = adapter.discover(FIXTURES).find { |r| r.id.include?("gothic") }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal 50, document.size
    assert_equal "got", document.language
  end

  # P31-6 round-trip on the two Perseus fixtures. The Latin head-50 carries
  # exactly one multiword-token range (`5-6 mecum` → `me` + `cum`, sent @66) —
  # the ITTB essetque machinery on a second treebank; the Greek test split has
  # no MWT ranges file-wide (see the fixture README).
  def test_parse_round_trips_the_perseus_fixtures
    adapter = Nabu::Adapters::UniversalDependencies.new
    by_slug = adapter.discover(FIXTURES)
                     .select { |r| r.metadata["treebank"].include?("perseus") }
                     .to_h { |r| [r.metadata["treebank"], adapter.parse(r)] }

    grc = by_slug.fetch("ancient-greek-perseus")
    assert_equal "urn:nabu:ud:ancient-greek-perseus:grc_perseus-ud-test-head50", grc.urn
    assert_equal 50, grc.size
    assert_equal "grc", grc.language
    opening = grc.passages.first
    assert_equal "#{grc.urn}:tlg0008.tlg001.perseus-grc1.12.tb.xml@197", opening.urn
    assert_includes opening.text, "ζῶσι δὲ καὶ οὗτοι τὸν αὐτὸν τρόπον"

    lat = by_slug.fetch("latin-perseus")
    assert_equal "urn:nabu:ud:latin-perseus:la_perseus-ud-test-head50", lat.urn
    assert_equal 50, lat.size
    assert_equal "lat", lat.language
    mwt = lat.passages.find { |p| p.urn.end_with?(":phi0690.phi003.perseus-lat1.tb.xml@66") }
    refute_nil mwt, "the one MWT sentence of the head-50 must parse"
    assert_includes mwt.text, "animo mecum ante peregi"
  end

  # P32-0 round-trip on the two Classical Chinese fixtures. Neither test
  # split contains any MWT range or empty node file-wide (see the fixture
  # README — Classical Chinese is written character-per-word, no clitic
  # fusion). TueCL's free-form Chinese working-note comments (`# ???…`,
  # bare `# 北方的海里…` lines with no `=`) must ride through ignored —
  # only sent_id/text/source are interpreted by the parser.
  def test_parse_round_trips_the_classical_chinese_fixtures
    adapter = Nabu::Adapters::UniversalDependencies.new
    by_slug = adapter.discover(FIXTURES)
                     .select { |r| r.metadata["treebank"].start_with?("classical-chinese") }
                     .to_h { |r| [r.metadata["treebank"], adapter.parse(r)] }

    kyoto = by_slug.fetch("classical-chinese-kyoto")
    assert_equal "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-test-head50", kyoto.urn
    assert_equal 50, kyoto.size
    assert_equal "lzh", kyoto.language
    # The Analects opener (學而篇第一, sent KR1h0004_001_par1_3-7): 學而時習之
    # "to learn and in time practise it" — the head-50 is one newdoc,
    # KR1h0004_001 (論語 book 1).
    opening = kyoto.passages.find { |p| p.urn.end_with?(":KR1h0004_001_par1_3-7") }
    refute_nil opening, "the Analects 學而時習之 sentence must parse"
    assert_equal "學而時習之", opening.text

    tuecl = by_slug.fetch("classical-chinese-tuecl")
    assert_equal "urn:nabu:ud:classical-chinese-tuecl:lzh_tuecl-ud-test-head50", tuecl.urn
    assert_equal 50, tuecl.size
    assert_equal "lzh", tuecl.language
    # Zhuangzi 逍遥游 sentence 1: 北冥有魚 "In the Northern Ocean there is a
    # fish" — its block carries a bare no-`=` Chinese comment line.
    fish = tuecl.passages.first
    assert_equal "#{tuecl.urn}:1", fish.urn
    assert_equal "北冥有魚", fish.text
  end

  # P40-1 round-trip on the Icelandic IcePaHC fixture (the first-50 dev-split
  # trim). Census pins (see the fixture README): 50 sentences / 538 word
  # lines, exactly ONE multiword-token range in the head — `1-2 láttu` →
  # `lát`+`þú`, sent 1250.THETUBROT.NAR-SAG,39.39, the enclitic imperative —
  # so the Latin-ITTB essetque MWT machinery is exercised on a Germanic
  # treebank; no empty nodes. Language `is` (the diachronic-under-one-tag
  # note lives on the TREEBANKS entry).
  def test_parse_round_trips_the_icelandic_icepahc_fixture
    adapter = Nabu::Adapters::UniversalDependencies.new
    ref = adapter.discover(FIXTURES).find { |r| r.metadata["treebank"] == "icelandic-icepahc" }
    icepahc = adapter.parse(ref)

    assert_equal "urn:nabu:ud:icelandic-icepahc:is_icepahc-ud-dev-head50", icepahc.urn
    assert_equal 50, icepahc.size
    assert_equal "is", icepahc.language

    # The saga opener (Þáttr af Þóri, sent 1250.THETUBROT.NAR-SAG,1.1).
    opening = icepahc.passages.first
    assert_equal "#{icepahc.urn}:1250.THETUBROT.NAR-SAG,1.1", opening.urn
    assert_includes opening.text, "Nú fara fyrst sagði hann"

    # The one MWT sentence of the head-50 (láttu → lát + þú) must parse.
    mwt = icepahc.passages.find { |p| p.urn.end_with?(":1250.THETUBROT.NAR-SAG,39.39") }
    refute_nil mwt, "the one MWT sentence of the head-50 must parse"
    assert_equal "láttu mig heyra það.", mwt.text
  end

  # --- lemma plumbing for the orv treebanks (P10-2) -----------------------
  #
  # The acceptance gate: the CoNLL-U LEMMA column of the Old East Slavic
  # treebanks must flow through the UNCHANGED annotation→index plumbing
  # (ConlluParser "tokens"/"lemma"/"form" → Store::Indexer → passage_lemmas),
  # exactly as the existing treebanks do — no orv-specific code path.
  def test_fixture_load_produces_orv_lemma_rows_via_existing_plumbing
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: "ud", name: "Universal Dependencies",
      adapter_class: "Nabu::Adapters::UniversalDependencies", license_class: "nc"
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    lemmas = fulltext[:passage_lemmas]
    assert_operator lemmas.where(language: "orv").count, :>, 0,
                    "the orv treebanks must contribute passage_lemmas rows"

    # All three orv treebanks contribute (Birchbark, Middle-Russian RNC AND the
    # Ruthenian "prosta mova" added in P13-1b).
    assert_operator lemmas.where(Sequel.like(:urn, "%old-east-slavic-birchbark%")).count, :>, 0
    assert_operator lemmas.where(Sequel.like(:urn, "%old-east-slavic-rnc%")).count, :>, 0
    assert_operator lemmas.where(Sequel.like(:urn, "%old-east-slavic-ruthenian%")).count, :>, 0

    # A specific readable row: the birchbark NOUN lemma росомуха "wolverine"
    # (002-1), attested by the pristine surface form росомꙋха.
    row = lemmas.where(language: "orv", lemma_raw: "росомуха").first
    refute_nil row, "expected a passage_lemmas row for the orv lemma росомуха"
    assert_equal "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50:002-1", row[:urn]
    assert_includes row[:surface_forms], "росомꙋха"

    # And a Ruthenian readable row (P13-1b): the opening NOUN lemma артыкулъ
    # "article" of the Second Lithuanian Statute (StatutVKL1566-1), attested by
    # the pristine uppercase surface form АРТЫКУЛЪ.
    ruthenian_urn = "urn:nabu:ud:old-east-slavic-ruthenian:orv_ruthenian-ud-test-head50:StatutVKL1566-1"
    ruthenian_row = lemmas.where(language: "orv", urn: ruthenian_urn, lemma_raw: "артыкулъ").first
    refute_nil ruthenian_row, "expected a passage_lemmas row for the orv lemma артыкулъ"
    assert_includes ruthenian_row[:surface_forms], "АРТЫКУЛЪ"

    # P25-2: both Old Irish glosses treebanks flow through the same
    # unchanged plumbing — sga becomes a lemma-indexed language. A readable
    # row each: DipSGG gloss 1 "libardaib" lemmatized lebarda ("bookish"),
    # DipWBG gloss 1's airbág ("boasting", surface irbáig).
    assert_operator lemmas.where(language: "sga").count, :>, 0,
                    "the Old Irish treebanks must contribute passage_lemmas rows"
    sgg_row = lemmas.where(language: "sga", lemma_raw: "lebarda").first
    refute_nil sgg_row, "expected a passage_lemmas row for the sga lemma lebarda"
    assert_equal "urn:nabu:ud:old-irish-dipsgg:sga_dipsgg-ud-test-head50:1", sgg_row[:urn]
    assert_includes sgg_row[:surface_forms], "libardaib"
    wbg_row = lemmas.where(language: "sga", lemma_raw: "airbág").first
    refute_nil wbg_row, "expected a passage_lemmas row for the sga lemma airbág"
    assert_equal "urn:nabu:ud:old-irish-dipwbg:sga_dipwbg-ud-test:1", wbg_row[:urn]

    # P31-0: Hittite flows through the same unchanged plumbing — hit becomes
    # a lemma-indexed language. A readable row: Laws §10 (sent_id 5.7, the
    # KBo 6.2 i 16-17 example), verb ḫūnink- "injure", attested by the
    # transliterated surface form ḫu-ú-ni-ik-zi.
    assert_operator lemmas.where(language: "hit").count, :>, 0,
                    "the Hittite treebank must contribute passage_lemmas rows"
    hit_row = lemmas.where(language: "hit", lemma_raw: "ḫūnink-").first
    refute_nil hit_row, "expected a passage_lemmas row for the hit lemma ḫūnink-"
    assert_equal "urn:nabu:ud:hittite-hittb:hit_hittb-ud-test-head50:5.7", hit_row[:urn]
    assert_includes hit_row[:surface_forms], "ḫu-ú-ni-ik-zi"

    # P31-6: the two Perseus treebanks contribute lemma rows to the ALREADY
    # lemma-indexed grc/lat lanes through the same unchanged plumbing (filtered
    # by urn — greek-proiel/latin-ittb also populate those languages). Readable
    # rows: the Athenaeus opener's verb ζάω "live" (surface ζῶσι) and, from the
    # Aeneid MWT sentence (mecum → me + cum), the member-token lemma ego
    # (surface me) — MWT members index like plain words, the ITTB mechanics.
    grc_urn = "urn:nabu:ud:ancient-greek-perseus:grc_perseus-ud-test-head50:" \
              "tlg0008.tlg001.perseus-grc1.12.tb.xml@197"
    grc_row = lemmas.where(language: "grc", urn: grc_urn, lemma_raw: "ζάω").first
    refute_nil grc_row, "expected a passage_lemmas row for the grc lemma ζάω"
    assert_includes grc_row[:surface_forms], "ζῶσι"
    lat_urn = "urn:nabu:ud:latin-perseus:la_perseus-ud-test-head50:" \
              "phi0690.phi003.perseus-lat1.tb.xml@66"
    lat_row = lemmas.where(language: "lat", urn: lat_urn, lemma_raw: "ego").first
    refute_nil lat_row, "expected a passage_lemmas row for the lat lemma ego (MWT member)"
    assert_includes lat_row[:surface_forms], "me"

    # P32-0: both Classical Chinese treebanks flow through the same unchanged
    # plumbing — lzh becomes a lemma-indexed language (its first occupants:
    # no other source mints lzh today). Readable rows: the Analects
    # 學而時習之 verb lemma 學 "study" (Kyoto; lemma = surface, the
    # character-per-word norm) and the Zhuangzi opener's 魚 "fish" (TueCL).
    assert_operator lemmas.where(language: "lzh").count, :>, 0,
                    "the Classical Chinese treebanks must contribute passage_lemmas rows"
    kyoto_urn = "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-test-head50:KR1h0004_001_par1_3-7"
    kyoto_row = lemmas.where(language: "lzh", urn: kyoto_urn, lemma_raw: "學").first
    refute_nil kyoto_row, "expected a passage_lemmas row for the lzh lemma 學"
    assert_includes kyoto_row[:surface_forms], "學"
    tuecl_urn = "urn:nabu:ud:classical-chinese-tuecl:lzh_tuecl-ud-test-head50:1"
    tuecl_row = lemmas.where(language: "lzh", urn: tuecl_urn, lemma_raw: "魚").first
    refute_nil tuecl_row, "expected a passage_lemmas row for the lzh lemma 魚"
    assert_includes tuecl_row[:surface_forms], "魚"

    # P40-1: Icelandic IcePaHC flows through the same unchanged plumbing — `is`
    # becomes a lemma-indexed language (its first occupant; no other source
    # mints `is` today). Readable row from the head-50's one MWT sentence
    # (láttu → lát + þú): the member-token lemma láta "let" (surface lát) —
    # MWT members index like plain words, the ITTB/Perseus mechanics.
    assert_operator lemmas.where(language: "is").count, :>, 0,
                    "the Icelandic treebank must contribute passage_lemmas rows"
    icepahc_urn = "urn:nabu:ud:icelandic-icepahc:is_icepahc-ud-dev-head50:1250.THETUBROT.NAR-SAG,39.39"
    icepahc_row = lemmas.where(language: "is", urn: icepahc_urn, lemma_raw: "láta").first
    refute_nil icepahc_row, "expected a passage_lemmas row for the is lemma láta (MWT member)"
    assert_includes icepahc_row[:surface_forms], "lát"
  ensure
    fulltext&.disconnect
  end

  # --- fetch (local git only, no network) ---------------------------------

  def test_fetch_clones_each_treebank_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstreams = {}
      Nabu::Adapters::UniversalDependencies::TREEBANKS.each_key do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        upstreams[slug] = upstream
      end

      workdir = File.join(root, "work")
      adapter = ud_pointing_at(upstreams)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_instance_of Time, report.fetched_at

      # Every treebank was cloned into its own subdir.
      upstreams.each_key do |slug|
        assert File.directory?(File.join(workdir, slug, ".git")), "#{slug} must be cloned"
        head = git(upstreams[slug], "rev-parse", "HEAD")
        assert_includes report.notes, "#{slug}=#{head}"
      end

      # sha is the LAST treebank's HEAD; notes carries the whole summary.
      last_slug = upstreams.keys.last
      assert_equal git(upstreams[last_slug], "rev-parse", "HEAD"), report.sha

      # Second call → pull path, still succeeds and reports the same shas.
      assert_equal report.notes, adapter.fetch(workdir).notes
    end
  end

  # P6-3: the FetchReport carries per-repo pins { repo_url => head sha } so the
  # sync path can record one ledger pin per treebank. Keyed by the SAME
  # repo_url the remote probe reads (here the local tmpdirs the test points at).
  def test_fetch_reports_per_repo_pins_keyed_by_repo_url
    Dir.mktmpdir do |root|
      upstreams = {}
      Nabu::Adapters::UniversalDependencies::TREEBANKS.each_key do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        upstreams[slug] = upstream
      end
      adapter = ud_pointing_at(upstreams)

      report = adapter.fetch(File.join(root, "work"))

      expected = upstreams.values.to_h { |upstream| [upstream, git(upstream, "rev-parse", "HEAD")] }
      assert_equal expected, report.repos
      assert_equal report.sha, report.repos.values.last, "sha still pins the last treebank"
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = ud_pointing_at(Hash.new(File.join(root, "does-not-exist")))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- retention across N repos (P5-2) -------------------------------------
  #
  # UD is the multi-repo shape: the breaker must see the deletions of ALL
  # treebanks before ANY repo merges (a trip in the last repo may not leave
  # the first repo already mutated), and atticked files land under the
  # source-level attic — <workdir>/.attic/<treebank>/<file> — so the
  # adapter's own discover finds them there.
  def test_fetch_guards_deletions_across_all_repos_before_any_merge_and_force_attics
    Dir.mktmpdir do |root|
      slugs = Nabu::Adapters::UniversalDependencies::TREEBANKS.keys
      upstreams = slugs.to_h do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        File.write(File.join(upstream, "#{slug}.conllu"), conllu_stub(slug))
        git(upstream, "add", ".")
        git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "conllu")
        [slug, upstream]
      end
      workdir = File.join(root, "work")
      adapter = ud_pointing_at(upstreams)
      adapter.fetch(workdir)

      # First repo gains a file; the LAST SIX repos each lose their only
      # treebank file (6 of #{slugs.size} ingestible files = 23.1% > 20% →
      # trip; 6 is now the MINIMUM tripping count at twenty-six treebanks —
      # five deletions are 5/#{slugs.size} = 19.2%, BELOW the breaker
      # (the guard trips on strictly greater, `doomed > 0.2 × ingestible`),
      # so 5 does NOT trip now that the P43-1 historical wave grew the set to
      # twenty-six. Re-derived, not weakened: 6 > 0.2 × 26 = 5.2 holds;
      # 5 > 5.2 does not).
      first = slugs.first
      doomed = slugs.last(6)
      File.write(File.join(upstreams[first], "new.txt"), "new\n")
      git(upstreams[first], "add", ".")
      git(upstreams[first], "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "grow")
      doomed.each do |slug|
        git(upstreams[slug], "rm", "-q", "#{slug}.conllu")
        git(upstreams[slug], "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "scrap")
      end

      assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
      doomed.each do |slug|
        assert File.file?(File.join(workdir, slug, "#{slug}.conllu")), "no repo merged on a trip"
      end
      refute File.exist?(File.join(workdir, first, "new.txt")),
             "the trip must precede EVERY repo's merge, not just the deleting one"
      refute Dir.exist?(File.join(workdir, ".attic"))

      report = adapter.fetch(workdir, force: true)
      assert_includes report.notes, "atticked 6"
      doomed.each do |slug|
        assert File.file?(File.join(workdir, ".attic", slug, "#{slug}.conllu")),
               "the attic preserves the <treebank>/<file> shape discover expects"
      end
      assert File.file?(File.join(workdir, first, "new.txt"))

      retained = adapter.discover_with_attic(workdir).select { |ref| ref.metadata["retained"] }
      assert_equal doomed.map { |slug| "urn:nabu:ud:#{slug}:#{slug}" }.sort, retained.map(&:id).sort
    end
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_ud_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ud"]
    refute_nil entry, "ud must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::UniversalDependencies, entry.adapter_class
    assert_equal "ud", entry.manifest.id
    assert_equal Nabu::Adapters::UniversalDependencies.manifest, entry.manifest
  end

  # --- the Kyoto↔Kanripo crosswalk rider (P33-3) ---------------------------

  def test_declares_the_kyoto_kanripo_crosswalk_reference_producer
    assert Nabu::Adapters::UniversalDependencies.reference_edges?,
           "the Kyoto treebank's own Kanripo newdoc ids mint kind=reference edges after each sync"
    producer = Nabu::Adapters::UniversalDependencies.reference_producer(catalog: nil, journal: nil)
    assert_instance_of Nabu::KyotoKanripoCrosswalk, producer
  end

  private

  # An adapter whose repo_url resolves to local git tmpdirs (Perseus test
  # pattern), keeping fetch entirely off the network.
  def ud_pointing_at(upstreams)
    adapter = Nabu::Adapters::UniversalDependencies.new
    adapter.define_singleton_method(:repo_url) { |slug| upstreams[slug] }
    adapter
  end

  def make_git_repo(dir, seed)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "#{seed}.txt"), "#{seed}\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", seed)
  end

  # Minimal CoNLL-U body — discover only globs filenames, so shape suffices.
  def conllu_stub(slug)
    "# sent_id = #{slug}-1\n# text = x\n1\tx\tx\tX\t_\t_\t0\troot\t_\t_\n\n"
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
