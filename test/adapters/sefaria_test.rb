# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Sefaria adapter tests (P30-3 Targum shelf; P46-1 Rabbinic wave 1):
# Sefaria's restructured export. Discovery is GLOB-DRIVEN over the fetched
# version files (each file is self-describing: title/versionTitle/license/
# categories ride beside the text), so the attic rediscovers without the
# index; the index (books.json) only drives fetch selection — now through
# the PINNED SHELF TABLE (Sefaria::SHELVES: category prefixes, per-shelf
# language rulings, named-version fetch selection). THE LICENSE GATE is
# the heart of the adapter: license class per version file, merged files
# and unlicensed versions never become refs.
class SefariaTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("sefaria")
  TARGUM = File.join(FIXTURES, "json/Tanakh/Targum")
  OBADIAH_FIXTURE = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Obadiah/" \
                                      "Hebrew/Mikraot Gedolot.json")
  KAUFMANN_FIXTURE = File.join(FIXTURES, "json/Mishnah/Seder Kodashim/Mishnah Tamid/Hebrew/" \
                                         "Mishnah based on the Kaufmann manuscript, edited by Dan Be'eri.json")
  TAMID_WIKISOURCE_URN = "urn:nabu:sefaria:tamid:he:wikisource-talmud-bavli"
  KAUFMANN_URN = "urn:nabu:sefaria:mishnah-tamid:he:mishnah-based-on-the-kaufmann-manuscript-" \
                 "edited-by-dan-be-eri"
  TOSEFTA_URN = "urn:nabu:sefaria:tosefta-chagigah-lieberman:he:the-tosefta-according-to-to-" \
                "codex-vienna-third-augmented-edition-jts-2001"
  MISHNAH_REL = "json/Mishnah/Seder Kodashim/Mishnah Tamid/Hebrew/V.json"
  RUTH_SMR_URN = "urn:nabu:sefaria:ruth-rabbah:en:the-sefaria-midrash-rabbah-2022"
  SIFREI_ZUTA_URN = "urn:nabu:sefaria:sifrei-zuta:he:leipzig-1917"
  ESTHER_TE_FIXTURE = File.join(FIXTURES, "json/Midrash/Aggadah/Midrash Rabbah/Esther Rabbah/Hebrew/" \
                                          "Midrash Rabbah -- TE.json")

  def conformance_adapter
    Nabu::Adapters::Sefaria.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "sefaria"
  end

  def refs
    conformance_adapter.discover(FIXTURES).to_a
  end

  def ref(urn)
    refs.find { |r| r.id == urn } || flunk("expected discover to yield #{urn}")
  end

  # --- identity ---------------------------------------------------------------

  def test_discover_mints_title_slash_version_urns_sorted
    urns = refs.map(&:id)
    assert_equal urns.sort, urns
    assert_equal (TARGUM_URNS + %W[
      urn:nabu:sefaria:mishnah-tamid:en:mishnah-yomit-by-dr-joshua-kulp
      #{KAUFMANN_URN}
      #{RUTH_SMR_URN}
      urn:nabu:sefaria:sifra:en:sifra-by-rabbi-shraga-silverstein
      urn:nabu:sefaria:tamid:en:sefaria-community-translation
      #{TAMID_WIKISOURCE_URN}
      urn:nabu:sefaria:tanna-debei-eliyahu-zuta:en:sefaria-community-translation
      #{SIFREI_ZUTA_URN}
      #{TOSEFTA_URN}
    ]).sort, urns, "17 licensed named versions; merged, unlicensed and excluded titles never mint"
  end

  # --- the Targum regression (P46-1: URNs FROZEN — the wave must not re-mint) -

  TARGUM_URNS = %w[
    urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot
    urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-to-the-yemenite-taj
    urn:nabu:sefaria:onkelos-numbers:sifsei-chachomim-chumash-metsudah-publications-2009
    urn:nabu:sefaria:targum-jerusalem:targum-jerusalem-on-torah
    urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot
    urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation
    urn:nabu:sefaria:targum-neofiti:sefaria-community-translation
    urn:nabu:sefaria:targum-sheni-on-esther:sefaria-community-translation
  ].freeze

  def test_targum_urns_are_byte_identical_to_the_p30_3_minting
    targum = refs.select { |r| r.path.start_with?(TARGUM) }
    assert_equal TARGUM_URNS.sort, targum.map(&:id).sort,
                 "the P30-3 shelf keeps producing EXACTLY its pre-wave documents — no axis " \
                 "segment, no re-mint (synced URNs are frozen forever)"
  end

  def test_targum_passage_urns_and_languages_are_unchanged
    document = conformance_adapter.parse(ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"))
    assert_equal "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot:1.1", document.first.urn
    assert_equal "arc", document.language
  end

  # --- THE LICENSE GATE (pinned per the P30-3 spec) ---------------------------

  def test_merged_files_are_never_ingested
    merged = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Jonah/Hebrew/merged.json")
    assert File.file?(merged), "the fixture must actually carry a real merged file"
    refute_nil JSON.parse(File.read(merged))["versions"], "a merged file lists its sources"
    assert_nil JSON.parse(File.read(merged))["license"], "a merged file carries NO license field"
    assert_empty(refs.select { |r| r.path == merged },
                 "merged.json carries no per-version license grant — NEVER a ref")
  end

  def test_a_named_version_without_a_license_field_is_skipped
    judges = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Judges/English/" \
                               "Sefaria Community Translation.json")
    assert File.file?(judges)
    assert_nil JSON.parse(File.read(judges))["license"],
               "the fixture pins the real upstream oddity: a named version with no license field"
    assert_empty(refs.select { |r| r.path == judges }, "no machine-readable grant → no ref")
  end

  def test_a_license_of_unknown_is_skipped
    lenihan = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Obadiah/English/" \
                                "Targum Obadiah, translated by Thomas Lenihan.json")
    assert_equal "unknown", JSON.parse(File.read(lenihan))["license"]
    assert_empty(refs.select { |r| r.path == lenihan }, '"unknown" is not a grant → no ref')
  end

  def test_public_domain_and_cc0_inherit_the_open_source_class
    [ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"),
     ref("urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation")].each do |r|
      adapter = conformance_adapter
      assert_nil adapter.parse(r).license_override,
                 "#{r.id}: PD/CC0 match the source class — no override minted"
    end
  end

  def test_cc_by_sa_rides_an_attribution_override
    r = ref("urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-to-the-yemenite-taj")
    assert_equal "attribution", conformance_adapter.parse(r).license_override
  end

  def test_cc_by_nc_rides_an_nc_override
    r = ref("urn:nabu:sefaria:onkelos-numbers:sifsei-chachomim-chumash-metsudah-publications-2009")
    document = conformance_adapter.parse(r)
    assert_equal "nc", document.license_override, "the P10-4 per-document mechanics — MCP-excluded downstream"
    assert_equal "CC-BY-NC", document.metadata["license"], "the verbatim upstream grant rides the metadata"
  end

  def test_the_literal_pd_string_maps_to_open
    document = conformance_adapter.parse(ref(KAUFMANN_URN))
    assert_nil document.license_override,
               'the Kaufmann MS files say literally "PD" (not "Public Domain") — owner-ratified ' \
               "D46-f: a PD grant in either spelling is the open source class"
    assert_equal "PD", document.metadata["license"], "the verbatim upstream string rides the metadata"
  end

  def test_a_stub_file_with_zero_text_leaves_quarantines_honestly
    with_version({ "text" => [[], ["", ""]] }, fixture: KAUFMANN_FIXTURE, rel: MISHNAH_REL) do |dir|
      adapter = conformance_adapter
      stub_refs = adapter.discover(dir).to_a
      assert_equal 1, stub_refs.size, "an SCT-style stub is licensed — it discovers, then quarantines"
      error = assert_raises(Nabu::ParseError) { adapter.parse(stub_refs.first) }
      assert_match(/no non-empty text leaves/, error.message,
                   "the known SCT stub noise (e.g. the Yerushalmi CC0 stubs) must quarantine " \
                   "per document, never crash the sync")
    end
  end

  def test_an_unmapped_license_string_stops_discovery_loudly
    with_version({ "license" => "Sefaria Community License 1.0" }) do |dir|
      error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(dir).to_a }
      assert_match(/Sefaria Community License 1.0/, error.message)
      assert_match(/owner decision/, error.message, "mislabeled documents are worse than an aborted run")
    end
  end

  def test_tafsir_rasag_is_excluded_by_rule
    tafsir = File.join(TARGUM, "Tafsir Rasag/Tafsir Rasag/English/Sefaria Community Translation.json")
    assert File.file?(tafsir)
    assert_equal "CC0", JSON.parse(File.read(tafsir))["license"],
                 "the exclusion is NOT license-driven — Tafsir Rasag is Saadia's Judeo-Arabic " \
                 "tafsir, not an Aramaic targum (the blanket he→arc ruling would mislabel it)"
    assert_empty(refs.select { |r| r.path == tafsir })
  end

  # --- languages (the per-shelf rulings, owner-ratified D46-e) ----------------

  def test_hebrew_column_maps_to_aramaic_and_english_to_eng
    assert_equal "arc", ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot")
      .metadata.fetch("language"),
                 "Sefaria's `Hebrew` axis on the Targum shelf IS the Aramaic column " \
                 "(upstream actualLanguage says `he` — the shelf ruling overrides)"
    assert_equal "eng", ref("urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation")
      .metadata.fetch("language")
  end

  def test_an_unknown_upstream_language_stops_discovery_loudly
    with_version({ "language" => "fr" }) do |dir|
      assert_raises(Nabu::FetchError) { conformance_adapter.discover(dir).to_a }
    end
  end

  def test_the_rabbinic_shelf_rulings_mishnah_tosefta_hbo_bavli_arc
    assert_equal "hbo", ref(KAUFMANN_URN).metadata.fetch("language"),
                 "Mishnah is Mishnaic HEBREW (hbo, NFC-exempt) — the Targum-era blanket " \
                 "he->arc mapping is dead"
    assert_equal "hbo", ref(TOSEFTA_URN).metadata.fetch("language")
    assert_equal "arc", ref(TAMID_WIKISOURCE_URN).metadata.fetch("language"),
                 "Bavli gemara -> arc (Jewish Babylonian Aramaic)"
    assert_equal "eng", ref("urn:nabu:sefaria:tamid:en:sefaria-community-translation")
      .metadata.fetch("language")
  end

  def test_an_unmapped_actual_language_on_a_rabbinic_shelf_quarantines_loudly
    # Real upstream noise: he-axis files with actualLanguage ar/yi, en-axis
    # files in de/fr/pt/es/ru/hu. Excluded LOUDLY-BY-RULE (D46-e): the ref
    # mints (deterministic urn), parse raises ParseError -> the loader
    # quarantines and journals that one document; the sync never crashes
    # and nothing slips through silently mislabeled.
    with_version({ "actualLanguage" => "yi" }, fixture: KAUFMANN_FIXTURE, rel: MISHNAH_REL) do |dir|
      adapter = conformance_adapter
      yid_refs = adapter.discover(dir).to_a
      assert_equal 1, yid_refs.size
      error = assert_raises(Nabu::ParseError) { adapter.parse(yid_refs.first) }
      assert_match(/actualLanguage "yi"/, error.message)
      assert_match(/D46-e/, error.message, "the error names the ruling to extend — an owner decision")
    end
  end

  def test_the_targum_shelf_ruling_stays_axis_keyed
    # The one on-disk Targum file whose actualLanguage differs from the
    # axis ([fr], license-unknown) predates the wave; the Targum shelf's
    # frozen P30-3 behavior keys on the axis field alone.
    with_version({ "actualLanguage" => "fr" }) do |dir|
      urns = conformance_adapter.discover(dir).map(&:id)
      assert_equal 1, urns.size, "a Targum-shelf file discovers on the axis ruling regardless " \
                                 "of actualLanguage — pre-wave behavior byte-frozen"
    end
  end

  # --- parse round-trip -------------------------------------------------------

  def test_parse_carries_shelf_metadata_and_facets
    document = conformance_adapter.parse(ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"))
    assert_equal "Targum Jonathan on Obadiah", document.metadata["title"]
    assert_equal "Mikraot Gedolot", document.metadata["version_title"]
    assert_equal "Public Domain", document.metadata["license"]
    assert_equal ["Tanakh", "Targum", "Targum Jonathan", "Prophets"], document.metadata["categories"]
    assert_equal({ "value" => "targum-jonathan", "raw" => "Targum Jonathan" },
                 document.metadata.dig("facets", "subshelf"))
    assert_equal({ "value" => "prophets", "raw" => "Prophets" },
                 document.metadata.dig("facets", "division"))
    assert_equal "arc", document.language
    assert_equal 21, document.size
  end

  def test_the_ot_hub_witness_documents_parse_to_cts_verse_tails
    document = conformance_adapter.parse(ref("urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot"))
    assert_equal "urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot:1.1", document.first.urn,
                 "passage urn = doc urn + chapter.verse tail — what the registry's cts-verse " \
                 "extractor folds into 'RUT 1.1'"
    assert_equal 85, document.size
  end

  def test_expected_passage_censuses
    counts = refs.to_h { |r| [r.id, conformance_adapter.parse(r).size] }
    assert_equal({
                   "urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot" => 85,
                   "urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-to-the-yemenite-taj" => 31,
                   "urn:nabu:sefaria:onkelos-numbers:sifsei-chachomim-chumash-metsudah-publications-2009" => 54,
                   "urn:nabu:sefaria:targum-jerusalem:targum-jerusalem-on-torah" => 39,
                   "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot" => 21,
                   "urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation" => 48,
                   "urn:nabu:sefaria:targum-neofiti:sefaria-community-translation" => 8,
                   "urn:nabu:sefaria:targum-sheni-on-esther:sefaria-community-translation" => 7,
                   TAMID_WIKISOURCE_URN => 207,
                   "urn:nabu:sefaria:tamid:en:sefaria-community-translation" => 1,
                   KAUFMANN_URN => 34,
                   "urn:nabu:sefaria:mishnah-tamid:en:mishnah-yomit-by-dr-joshua-kulp" => 34,
                   TOSEFTA_URN => 57,
                   RUTH_SMR_URN => 31,
                   SIFREI_ZUTA_URN => 163,
                   "urn:nabu:sefaria:tanna-debei-eliyahu-zuta:en:sefaria-community-translation" => 5,
                   "urn:nabu:sefaria:sifra:en:sifra-by-rabbi-shraga-silverstein" => 6
                 }, counts)
  end

  # --- the P46-1 wave: identity, daf citations, deep-path facets --------------

  def test_rabbinic_urns_carry_the_axis_segment_between_title_and_version
    # 3 known corpus-wide collisions (Ein Yaakov Glick, Otzar Midrashim NY
    # 1915, Tosefta Menachot Feuer) put the SAME title/versionTitle in both
    # language dirs — every post-Targum shelf disambiguates with the
    # upstream axis value ("he"/"en") as a urn segment. Same title, both
    # axes, distinct urns:
    assert_equal KAUFMANN_URN, ref(KAUFMANN_URN).id
    assert_equal "urn:nabu:sefaria:mishnah-tamid:en:mishnah-yomit-by-dr-joshua-kulp",
                 ref("urn:nabu:sefaria:mishnah-tamid:en:mishnah-yomit-by-dr-joshua-kulp").id
    assert_equal 2, refs.map(&:id).grep(/^urn:nabu:sefaria:mishnah-tamid:/).size
  end

  def test_bavli_passages_cite_daf_amud
    document = conformance_adapter.parse(ref(TAMID_WIKISOURCE_URN))
    assert_equal "#{TAMID_WIKISOURCE_URN}:25b.1", document.first.urn,
                 "Tamid's gemara starts at 25b (the real Vilna start) — the daf arithmetic " \
                 "is FROZEN before the first sync"
    assert_equal "33b.12", document.passages.last.urn.split(":").last
  end

  def test_deep_rabbinic_category_paths_generalize_the_facets
    tosefta = conformance_adapter.parse(ref(TOSEFTA_URN))
    assert_equal ["Tosefta", "Lieberman Edition", "Seder Moed"], tosefta.metadata["categories"]
    assert_equal({ "value" => "lieberman-edition", "raw" => "Lieberman Edition" },
                 tosefta.metadata.dig("facets", "subshelf"))
    assert_equal({ "value" => "seder-moed", "raw" => "Seder Moed" },
                 tosefta.metadata.dig("facets", "division"))
    assert_equal "The Tosefta according to to codex Vienna. Third Augmented Edition, JTS 2001",
                 tosefta.metadata["version_title"],
                 'upstream\'s own double "to" rides verbatim — canonical means canonical'

    bavli = conformance_adapter.parse(ref(TAMID_WIKISOURCE_URN))
    assert_equal({ "value" => "seder-kodashim", "raw" => "Seder Kodashim" },
                 bavli.metadata.dig("facets", "subshelf"))
    assert_nil bavli.metadata.dig("facets", "division"),
               "categories = [Talmud, Bavli, Seder Kodashim] — nothing beyond the subshelf"

    mishnah = conformance_adapter.parse(ref(KAUFMANN_URN))
    assert_equal({ "value" => "seder-kodashim", "raw" => "Seder Kodashim" },
                 mishnah.metadata.dig("facets", "subshelf"))
  end

  # --- the P55-3 wave: the midrash shelves (Rabbah + halakhic midrash) --------

  def test_midrash_language_rulings_hebrew_hbo_english_eng
    assert_equal "hbo", ref(SIFREI_ZUTA_URN).metadata.fetch("language"),
                 "halakhic midrash is tannaitic HEBREW — hbo like Mishnah/Tosefta, never arc"
    assert_equal "eng", ref(RUTH_SMR_URN).metadata.fetch("language")
    # The Rabbah Hebrew lane: the on-disk Esther TE fixture gate-skips
    # (license "unknown"), so the shelf ruling is exercised on a relicensed
    # derivative — upstream also ships PD TE files (Ruth Rabbah TE,
    # ranged-GET 2026-07-31).
    with_version({ "license" => "Public Domain" },
                 fixture: ESTHER_TE_FIXTURE,
                 rel: "json/Midrash/Aggadah/Midrash Rabbah/Esther Rabbah/Hebrew/V.json") do |dir|
      te_refs = conformance_adapter.discover(dir).to_a
      assert_equal 1, te_refs.size
      assert_equal "hbo", te_refs.first.metadata.fetch("language"),
                   "Rabbah midrash is rabbinic Hebrew matrix — hbo, actualLanguage-keyed (D46-e)"
    end
  end

  def test_the_sefaria_midrash_rabbah_2022_rides_a_cc_by_attribution_override
    document = conformance_adapter.parse(ref(RUTH_SMR_URN))
    assert_equal "attribution", document.license_override
    assert_equal "CC-BY", document.metadata["license"], "the verbatim upstream grant rides the metadata"
  end

  def test_a_te_file_with_unknown_license_is_censused_never_ingested
    assert_equal "unknown", JSON.parse(File.read(ESTHER_TE_FIXTURE))["license"],
                 "the TE lane is per-file MIXED (Ruth TE says Public Domain; Esther and Bereshit " \
                 "say unknown) — the named edition stays, the per-file gate censuses the unknowns " \
                 "(the wave-1 Kaufmann Pirkei Avot pattern)"
    assert_empty(refs.select { |r| r.path == ESTHER_TE_FIXTURE })
  end

  def test_midrash_documents_cite_upstream_sectioning_with_flat_category_metadata
    document = conformance_adapter.parse(ref(SIFREI_ZUTA_URN))
    assert_equal %w[Midrash Halakhah], document.metadata["categories"]
    assert_nil document.metadata["facets"], "nothing beyond the shelf prefix — no subshelf facet"
    assert_equal "#{SIFREI_ZUTA_URN}:5.2.1", document.first.urn,
                 "midrash cites its own upstream grain (Chapter/Verse/Paragraph) — never daf"
    ruth = conformance_adapter.parse(ref(RUTH_SMR_URN))
    assert_equal ["Midrash", "Aggadah", "Midrash Rabbah"], ruth.metadata["categories"]
    assert_equal "#{RUTH_SMR_URN}:petichta.1", ruth.first.urn,
                 "the Rabbah default-node quirk: petichta named, the main text cites bare"
  end

  def test_fetch_selects_midrash_shelves_by_named_version_only
    select = Nabu::Adapters::Sefaria.method(:shelf_entry?)
    rabbah = { "title" => "Esther Rabbah", "language" => "Hebrew", "versionTitle" => "Midrash Rabbah -- TE",
               "categories" => ["Midrash", "Aggadah", "Midrash Rabbah"], "json_url" => "https://b/x.json" }
    assert select.call(rabbah)
    refute select.call(rabbah.merge("title" => "Bereshit Rabbah",
                                    "versionTitle" => "Wikisource Bereshit Rabbah")),
           "the wave is the NAMED editions only — an unlisted version never fetches"
    refute select.call(rabbah.merge("categories" => ["Midrash", "Aggadah", "Midrash Rabbah",
                                                     "Commentary", "Etz Yosef"])),
           "the Rabbah Commentary subtree is out of shelf scope"
    refute select.call(rabbah.merge("title" => "Ruth Rabbah (Lerner)", "language" => "English",
                                    "versionTitle" => "Sefaria Community Translation")),
           "the Lerner critical edition duplicates the Ruth Rabbah title — excluded whole"
    assert select.call(rabbah.merge("title" => "Pesikta DeRav Kahana", "categories" => %w[Midrash Aggadah],
                                    "versionTitle" => "Any Named Edition")),
           "wave 3 (P59-5): the flat-bucket classical core is TITLE-allowlisted in — every named " \
           "version, the per-file license gate sifts (the targum stance)"
    halakhah = { "title" => "Sifrei Zuta", "language" => "Hebrew", "versionTitle" => "Leipzig, 1917",
                 "categories" => %w[Midrash Halakhah], "json_url" => "https://b/x.json" }
    assert select.call(halakhah)
    refute select.call(halakhah.merge("title" => "Footnotes on Mekhilta DeRabbi Shimon Ben Yochai",
                                      "versionTitle" => "Mechilta de-Rabbi Simon b. Jochai, " \
                                                        "Dr. D. Hoffman, Frankfurt 1905")),
           "the Footnotes apparatus title shares the named Hoffman versionTitle — excluded by title"
    refute select.call(halakhah.merge("categories" => %w[Midrash Halakhah Commentary])),
           "the Halakhah Commentary subtree is out"
  end

  # --- the P59-5 wave: the flat-Aggadah classical core (queue Q1, ruled) ------

  def test_wave_three_is_title_allowlisted_with_the_seder_olam_subtree
    select = Nabu::Adapters::Sefaria.method(:shelf_entry?)
    flat = { "language" => "Hebrew", "versionTitle" => "Warsaw, 1878",
             "categories" => %w[Midrash Aggadah], "json_url" => "https://b/x.json" }
    ["Midrash Tanchuma", "Pirkei DeRabbi Eliezer", "Tanna DeBei Eliyahu Zuta",
     "Seder Olam Zutta"].each do |title|
      assert select.call(flat.merge("title" => title)), "#{title} is on the ruled allowlist"
    end
    ["Yalkut Shimoni on Torah", "Ein Yaakov", "Otzar Midrashim", "Legends of the Jews",
     "Midrash Sekhel Tov", "Buber footnotes on Midrash Mishlei"].each do |title|
      refute select.call(flat.merge("title" => title)),
             "#{title}: anthology tier / modern authorship / apparatus — deliberately out"
    end
    subtree = flat.merge("title" => "Vilna Gaon on Seder Olam Rabbah",
                         "categories" => ["Midrash", "Aggadah", "Seder Olam Rabbah"])
    assert select.call(subtree),
           "the Seder Olam Rabbah subtree is category-scoped whole — commentaries ride (4 titles)"
    assert_equal "aggadah",
                 Nabu::Adapters::Sefaria.shelf_for(%w[Midrash Aggadah], title: "Midrash Tehillim").id
    assert_equal "seder-olam",
                 Nabu::Adapters::Sefaria.shelf_for(["Midrash", "Aggadah", "Seder Olam Rabbah"],
                                                   title: "Seder Olam Rabbah").id
    assert_nil Nabu::Adapters::Sefaria.shelf_for(%w[Midrash Aggadah], title: "Yalkut Shimoni on Nach"),
               "an off-allowlist flat title has NO shelf — never a fetch, never a parse"
  end

  # --- discovery census (P11-7) ----------------------------------------------

  def test_discovery_skips_census_the_gate
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 5, skips.skipped_by_rule,
                 "1 merged + 1 absent-license + 2 unknown-license (Lenihan, Esther TE) + 1 excluded title"
    assert_predicate skips, :clean?
  end

  def test_a_file_outside_every_shelf_is_a_rule_skip
    with_version({ "categories" => ["Jewish Thought", "Modern"] },
                 fixture: KAUFMANN_FIXTURE, rel: "json/Jewish Thought/Modern/X/Hebrew/V.json") do |dir|
      assert_empty conformance_adapter.discover(dir).to_a,
                   "a licensed file whose categories match no shelf never mints — scope is the " \
                   "shelf table, not whatever lands on disk"
      assert_equal 1, conformance_adapter.discovery_skips(dir).skipped_by_rule
    end
  end

  def test_a_json_tree_with_an_unreadable_file_is_censused_as_unrecognized
    with_version(nil, body: "{not json") do |dir|
      skips = conformance_adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      refute_empty skips.notes
      refute_predicate skips, :clean?
      assert_empty conformance_adapter.discover(dir).to_a
    end
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_selects_named_targum_shelf_entries_only
    select = Nabu::Adapters::Sefaria.method(:shelf_entry?)
    targum = { "title" => "Onkelos Genesis", "language" => "Hebrew", "versionTitle" => "Onkelos Genesis",
               "categories" => %w[Tanakh Targum Onkelos Torah], "json_url" => "https://b/x.json" }
    assert select.call(targum)
    refute select.call(targum.merge("versionTitle" => "merged")), "merged files are never fetched"
    refute select.call(targum.merge("title" => "Tafsir Rasag")), "the Judeo-Arabic tafsir stays out"
    refute select.call(targum.merge("categories" => %w[Tanakh Torah])), "the Tanakh text shelves are not ours"
    refute select.call(targum.merge("json_url" => nil)), "an entry without a json file cannot be fetched"
  end

  def test_fetch_selects_rabbinic_shelves_by_named_version_only
    select = Nabu::Adapters::Sefaria.method(:shelf_entry?)
    mishnah = { "title" => "Mishnah Tamid", "language" => "Hebrew", "versionTitle" => "Torat Emet 357",
                "categories" => ["Mishnah", "Seder Kodashim"], "json_url" => "https://b/x.json" }
    assert select.call(mishnah)
    refute select.call(mishnah.merge("versionTitle" => "The Mishna with Obadiah Bartenura by Rabbi " \
                                                       "Shraga Silverstein")),
           "wave 1 is the NAMED editions only — an unlisted version never fetches"
    refute select.call(mishnah.merge("language" => "English")),
           "the named-version selection is axis-scoped (Torat Emet is a Hebrew-dir edition)"
    refute select.call(mishnah.merge("categories" => ["Mishnah", "Rishonim on Mishnah", "Bartenura"])),
           "commentary subtrees are out of shelf scope"
  end

  # The census the fixture index slice pins: exactly which of its 63 entries
  # the shelf table selects (10 Targum + 21 wave-1 + 15 wave-2). The 17 out:
  # the 9 wave-1 negatives (Berkovits, Tafsir Rasag, 2 merged, Davidson
  # Guides, Vilna-1883-under-Commentary, Bartenura SCT, Venice Yerushalmi,
  # Steinsaltz) + the 8 wave-2 negatives — Footnotes-on-Mekhilta (excluded
  # title sharing the Hoffman versionTitle), Ruth Rabbah (Lerner) SCT
  # (excluded duplicate-edition title), Sifra Venice 1545 (license-unknown
  # upstream — not named, never fetched), "eicha rabba 12" (source-sheet
  # noise, not named), an Esther Rabbah merged sibling, a Rabbah Commentary
  # entry, and a Halakhah Commentary entry. (Pesikta DeRav Kahana, a
  # wave-2 negative here until P59-5, now SELECTS — the wave-3 allowlist.)
  def test_fetch_selection_census_over_the_pinned_index_slice
    index = JSON.parse(File.read(File.join(FIXTURES, "books.json")))
    selected = index.fetch("books").select { |e| Nabu::Adapters::Sefaria.shelf_entry?(e) }
    grouped = selected.group_by { |e| e["categories"].first }.transform_values(&:size)
    assert_equal({ "Tanakh" => 10, "Mishnah" => 7, "Talmud" => 12, "Tosefta" => 2, "Midrash" => 16 },
                 grouped)
    rejected = index.fetch("books").reject { |e| Nabu::Adapters::Sefaria.shelf_entry?(e) }
    assert_equal 16, rejected.size
    assert_includes rejected.map { |e| e["versionTitle"] }, "Venice Edition",
                    "license-unknown Yerushalmi editions are not even fetched — not named"
    assert_includes rejected.map { |e| e["title"] }, "Introductions to the Babylonian Talmud",
                    "the Davidson Guides volume is not a tractate"
    davidson = selected.select { |e| e["versionTitle"].start_with?("William Davidson") }
    assert_equal 4, davidson.size,
                 "the fixture slice's Davidson lane: Tamid en/arc/vocalized + Yerushalmi Shekalim en"
    assert_includes selected.map { |e| e["title"] }, "Pesikta DeRav Kahana",
                    "P59-5 flips the wave-2 boundary: the flat-bucket classical core is " \
                    "title-allowlisted in (wave 3)"
    assert_includes rejected.map { |e| e["versionTitle"] }, "Venice 1545",
                    "Sifra's only Hebrew version says license unknown upstream — known-unknown " \
                    "versions are not even named (the Yerushalmi Venice rule)"
  end

  def test_fetch_lands_index_and_shelf_through_sefaria_fetch
    Dir.mktmpdir do |workdir|
      index = JSON.generate(
        "base_url" => "https://bucket.example.org/sefaria-export",
        "books" => [
          { "title" => "Targum Jonathan on Obadiah", "language" => "Hebrew",
            "versionTitle" => "Mikraot Gedolot", "categories" => ["Tanakh", "Targum", "Targum Jonathan", "Prophets"],
            "json_url" => "https://bucket.example.org/sefaria-export/json/T/Hebrew/Mikraot Gedolot.json" },
          { "title" => "Targum Jonathan on Obadiah", "language" => "Hebrew", "versionTitle" => "merged",
            "categories" => ["Tanakh", "Targum", "Targum Jonathan", "Prophets"],
            "json_url" => "https://bucket.example.org/sefaria-export/json/T/Hebrew/merged.json" }
        ]
      )
      stub_request(:get, "https://index.example.org/books.json")
        .to_return(status: 200, body: index, headers: { "Last-Modified" => "Thu, 02 Jul 2026 07:03:07 GMT" })
      stub_request(:get, "https://bucket.example.org/sefaria-export/json/T/Hebrew/Mikraot%20Gedolot.json")
        .to_return(status: 200, body: File.read(OBADIAH_FIXTURE))

      adapter = conformance_adapter
      adapter.define_singleton_method(:index_url) { "https://index.example.org/books.json" }
      report = adapter.fetch(workdir)

      assert_equal Digest::SHA256.hexdigest(index), report.sha
      assert File.file?(File.join(workdir, "books.json")), "the index rides in canonical"
      assert File.file?(File.join(workdir, "json/T/Hebrew/Mikraot Gedolot.json"))
      refute File.exist?(File.join(workdir, "json/T/Hebrew/merged.json"))
      assert_match(/1 file/, report.notes.to_s)
      assert_equal ["urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"],
                   adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_failure_wraps_as_fetch_error
    Dir.mktmpdir do |workdir|
      stub_request(:get, "https://index.example.org/books.json").to_return(status: 500)
      adapter = conformance_adapter
      adapter.define_singleton_method(:index_url) { "https://index.example.org/books.json" }
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  private

  # A minimal tmp workdir holding ONE version file derived from a real
  # fixture with a single field changed (or raw +body+) — the gate's error
  # paths need shapes upstream does not currently ship.
  def with_version(overrides, body: nil, fixture: OBADIAH_FIXTURE, rel: "json/Tanakh/Targum/T/Hebrew/V.json")
    Dir.mktmpdir do |dir|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      if body
        File.write(path, body)
      else
        data = JSON.parse(File.read(fixture)).merge(overrides)
        File.write(path, JSON.generate(data))
      end
      yield dir
    end
  end
end
