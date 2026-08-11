# frozen_string_literal: true

require "test_helper"

# The nabu-data feature census (P50-W1): the registered features, every field
# present and well-shaped. The rail landed first with everything :planned;
# builder packets flip their own feature as each builder lands (P50-W2:
# san/form-lemma, P50-W4: xct/verb-lemma, P52-2: grc/meter). The registry is
# EXPLICIT — no discovery magic — so this test pins the ratified metadata,
# not just the shape.
class DataBuildRegistryTest < Minitest::Test
  EXPECTED_SLUGS = %w[san/form-lemma xct/wylie-fold xct/verb-lemma xct/segmentation
                      zho/hani-fold jpn/aozora-gaiji lat/sabellic-loans grc/meter
                      jpn/kyujitai-fold lzh/kanripo-gaiji sux/value-signs
                      xct/actib-anchors roa-opt/cantigas mul/lect-assignments
                      mul/place-refs mul/places-lpf mul/document-dates
                      mul/char-postings].freeze

  def features
    Nabu::DataBuild::REGISTRY
  end

  def test_registers_exactly_the_expected_features_with_unique_slugs_in_order
    assert_equal EXPECTED_SLUGS, features.map(&:slug)
    assert_equal features.size, features.map(&:slug).uniq.size
  end

  def test_the_builder_status_census
    # The rail landed with every feature :planned; each builder packet flipped
    # exactly its own feature (P50-W2 form-lemma, P50-W3 wylie-fold, P50-W4
    # verb-lemma, P51-W5 segmentation, P52-2/3/4/5 the conversion wave,
    # P53-3 value-signs, P55-4 actib-anchors — landed available, builder and
    # feature together). The full census is available.
    assert_equal EXPECTED_SLUGS, features.select(&:available?).map(&:slug)
    features.select(&:planned?).each { |feature| assert_nil feature.builder }
    features.select(&:available?).each { |feature| refute_nil feature.builder }
  end

  def test_every_field_is_present_and_well_shaped
    features.each do |feature|
      assert_match Nabu::DataBuild::SLUG_PATTERN, feature.slug
      assert feature.slug.start_with?("#{feature.language.id}/"),
             "#{feature.slug}: the slug's language segment must equal the feature's language code"
      refute_empty feature.title
      refute_empty feature.tier
      refute_empty feature.anchoring
      refute_empty feature.rationale
      refute_empty feature.maintenance
      assert_kind_of Array, feature.inputs
      assert_kind_of Array, feature.canonical_cones
      language = feature.language
      [language.id, language.name].each do |value|
        refute_empty value.to_s, "#{feature.slug}: languages.csv statics must be complete"
      end
      if language.iso639p3.nil?
        # ISO 639-3 assigns NO code to Old Galician-Portuguese — roa-opt is
        # the BCP 47 collective-tag convention (roa Romance + opt) Wiktionary
        # and Nabu's catalog already use (D55-a), so the honest ISO static
        # is empty. Any other nil is a missing static.
        assert_equal "roa-opt", language.id,
                     "#{feature.slug}: only roa-opt (no ISO 639-3 code exists) may omit the ISO static"
      else
        refute_empty language.iso639p3, "#{feature.slug}: languages.csv statics must be complete"
      end
      if language.glottocode.nil?
        # Glottolog deliberately assigns no glottocode to ISO 639-3
        # MACROLANGUAGES (verified against the cldf-spine cone 2026-07-29:
        # no languages.csv row carries ISO zho; the nearest node sini1245 is
        # a family, not this tag) or SPECIAL codes (2026-08-11: no row
        # carries ISO mul either — "Multiple languages" names content, not a
        # languoid) — an empty static is honest for exactly those two
        # registered tags. Any other nil is a missing static.
        assert_includes %w[zho mul], language.id,
                        "#{feature.slug}: only the zho macrolanguage and the mul special code " \
                        "may omit a glottocode"
      else
        refute_empty language.glottocode, "#{feature.slug}: languages.csv statics must be complete"
      end
    end
  end

  def test_the_ratified_metadata
    form_lemma = Nabu::DataBuild.feature("san/form-lemma")
    assert form_lemma.available?, "P50-W2 landed the builder"
    assert_equal Nabu::DataBuild::FormLemma, form_lemma.builder
    assert_equal "gold-derived", form_lemma.tier
    assert_equal ["dcs"], form_lemma.inputs
    assert_equal ["dcs"], form_lemma.canonical_cones
    assert_equal "none", form_lemma.anchoring
    assert_equal "san-form-lemma", form_lemma.package_name

    wylie = Nabu::DataBuild.feature("xct/wylie-fold")
    assert_equal "gold", wylie.tier
    assert_empty wylie.inputs, "wylie-fold is own authorship — no source inputs"
    assert_empty wylie.canonical_cones

    verb = Nabu::DataBuild.feature("xct/verb-lemma")
    assert_equal :available, verb.status, "P50-W4: the verb-lemma builder has landed"
    assert_equal Nabu::DataBuild::VerbLemmaBuilder, verb.builder
    assert_equal "gold-derived", verb.tier
    assert_equal ["tibetan-verbs"], verb.inputs
    assert_match(/2,491/, verb.rationale)
    assert_match(%r{deferred behind xct/segmentation}, verb.rationale,
                 "the anchored-layer deferral is stated where the owner reads it")

    segmentation = Nabu::DataBuild.feature("xct/segmentation")
    assert_equal :available, segmentation.status, "P51-W5: the segmentation builder has landed"
    assert_equal Nabu::DataBuild::SegmentationBuilder, segmentation.builder
    assert_equal "silver", segmentation.tier
    assert_equal "passage-urn", segmentation.anchoring
    assert_equal %w[derge-kangyur soas-tibetan], segmentation.inputs
    assert_equal %w[derge-kangyur soas-tibetan], segmentation.canonical_cones

    hani = Nabu::DataBuild.feature("zho/hani-fold")
    assert_equal :available, hani.status, "P52-3: the hani-fold builder has landed"
    assert_equal Nabu::DataBuild::HaniFoldBuilder, hani.builder
    assert_equal "gold-derived", hani.tier,
                 "mechanical resolution of Unihan's declared variants — the verb-lemma parity, " \
                 "not wylie-fold's own-authorship gold"
    assert_equal ["unihan"], hani.inputs, "the source of truth STAYS upstream Unihan (the fold-in audit rule)"
    assert_equal ["unihan"], hani.canonical_cones
    assert_equal "none", hani.anchoring
    assert_match(/refus/, hani.rationale, "the refusal census is the curation — stated where the owner reads")

    gaiji = Nabu::DataBuild.feature("jpn/aozora-gaiji")
    assert_equal :available, gaiji.status, "P52-3: the aozora-gaiji builder has landed"
    assert_equal Nabu::DataBuild::AozoraGaijiBuilder, gaiji.builder
    assert_equal "gold", gaiji.tier, "hand-curated census over open-grant text"
    assert_empty gaiji.inputs, "the checked-in census TSV is the source of truth — the wylie-fold precedent"
    assert_empty gaiji.canonical_cones
    assert_equal "none", gaiji.anchoring

    loans = Nabu::DataBuild.feature("lat/sabellic-loans")
    assert_equal :available, loans.status, "P52-5: builder and feature land together"
    assert_equal Nabu::DataBuild::SabellicLoansBuilder, loans.builder
    assert_equal "gold", loans.tier
    assert_empty loans.inputs, "own curation (config/sabellic_loans.yml) — no canonical inputs"
    assert_empty loans.canonical_cones
    assert_equal "lat-sabellic-loans", loans.package_name
    assert_match(/85 Latin lemmas/, loans.rationale)
    assert_match(/D51-a/, loans.rationale, "the BY-SA ruling is stated where the owner reads it")

    meter = Nabu::DataBuild.feature("grc/meter")
    assert_equal :available, meter.status, "P52-2: the meter builder has landed"
    assert_equal Nabu::DataBuild::MeterBuilder, meter.builder
    assert_equal "gold-derived", meter.tier
    assert_equal "passage-urn", meter.anchoring
    assert_equal %w[hypotactic perseus-greek first1k-greek], meter.inputs,
                 "the anchor corpora are declared inputs — the stale-ingest guard must cover them"
    assert_equal meter.inputs, meter.canonical_cones
    assert_match(/never the CC BY-SA Perseus text/, meter.rationale,
                 "the provenance rule is stated where the owner reads it")

    kyujitai = Nabu::DataBuild.feature("jpn/kyujitai-fold")
    assert_equal :available, kyujitai.status, "P52-4: the kyūjitai-fold builder has landed"
    assert_equal Nabu::DataBuild::KyujitaiFoldBuilder, kyujitai.builder
    assert_equal "gold", kyujitai.tier
    assert_equal "none", kyujitai.anchoring
    assert_equal %w[unihan edrdg], kyujitai.inputs
    assert_equal %w[unihan edrdg], kyujitai.canonical_cones
    assert_match(/rake fold:jpn|Nabu::Jpn/, kyujitai.rationale,
                 "the one-seam-two-consumers relation is stated where the owner reads it")

    gaiji = Nabu::DataBuild.feature("lzh/kanripo-gaiji")
    assert_equal :available, gaiji.status, "P52-4: the kanripo-gaiji builder has landed"
    assert_equal Nabu::DataBuild::KanripoGaijiBuilder, gaiji.builder
    assert_equal "gold", gaiji.tier
    assert_equal "none", gaiji.anchoring
    assert_empty gaiji.inputs, "own curation pinned to the charlist commit the TSV headers record"
    assert_empty gaiji.canonical_cones

    value_signs = Nabu::DataBuild.feature("sux/value-signs")
    assert_equal :available, value_signs.status, "P53-3: the value-signs builder has landed"
    assert_equal Nabu::DataBuild::ValueSignsBuilder, value_signs.builder
    assert_equal "gold", value_signs.tier, "the OSL is the field's hand-curated sign registry"
    assert_equal "none", value_signs.anchoring
    assert_equal ["osl"], value_signs.inputs, "the stale-ingest guard rides the osl cone"
    assert_equal ["osl"], value_signs.canonical_cones
    assert_equal "sux-value-signs", value_signs.package_name
    assert_match(/one row per \(value, sign\) pair/, value_signs.rationale)
    assert_match(/%akk/, value_signs.rationale,
                 "the language-scope call (sux leads, akk rides a qualifier column) is stated " \
                 "where the owner reads it")

    anchors = Nabu::DataBuild.feature("xct/actib-anchors")
    assert_equal :available, anchors.status, "P55-4: builder and feature land together"
    assert_equal Nabu::DataBuild::ActibAnchorsBuilder, anchors.builder
    assert_equal "gold-derived", anchors.tier,
                 "the anchor mapping is deterministic and measured; ACTib's own layers stay " \
                 "labeled automatic upstream"
    assert_equal "urn+sha", anchors.anchoring
    assert_equal %w[derge-kangyur actib], anchors.inputs,
                 "both cones are declared inputs — the stale-ingest guard must cover them"
    assert_equal anchors.inputs, anchors.canonical_cones
    assert_equal "xct-actib-anchors", anchors.package_name
    assert_match(/first re-publication/i, anchors.rationale,
                 "the re-publication milestone is stated where the owner reads it")
    assert_match(/never republished/, anchors.rationale,
                 "the no-content-republication rule is stated where the owner reads it")

    cantigas = Nabu::DataBuild.feature("roa-opt/cantigas")
    assert_equal :available, cantigas.status, "P56-2: builder and feature land together"
    assert_equal Nabu::DataBuild::CantigasBuilder, cantigas.builder
    assert_equal "gold", cantigas.tier,
                 "a faithful structured projection of the granted critical edition"
    assert_equal "urn+sha", cantigas.anchoring
    assert_equal ["cantigas"], cantigas.inputs
    assert_equal ["cantigas"], cantigas.canonical_cones
    assert_equal "roa-opt-cantigas", cantigas.package_name
    assert_match(/first full-corpus re-publication/i, cantigas.rationale,
                 "the milestone is stated where the owner reads it")
    assert_match(/№45-2/, cantigas.rationale,
                 "the written-grant basis is stated where the owner reads it")

    assignments = Nabu::DataBuild.feature("mul/lect-assignments")
    assert_equal :available, assignments.status, "P73-3: builder and feature land together"
    assert_equal Nabu::DataBuild::LectAssignmentsBuilder, assignments.builder
    assert_equal "gold-derived", assignments.tier,
                 "the per-row basis column carries the finer honesty (rule vs date-band)"
    assert_equal "document-urn", assignments.anchoring,
                 "assignments are document-grain — URN, no content hash"
    assert_empty assignments.inputs,
                 "the journal is the source of truth (the aozora posture); the recipe embeds " \
                 "the published-slice digest instead of cone shas"
    assert_empty assignments.canonical_cones
    assert_equal "mul-lect-assignments", assignments.package_name
    assert_match(/nabu-lects/, assignments.rationale,
                 "the public id grammar is cited where the owner reads it")
    assert_match(/censused/, assignments.rationale,
                 "the row-by-row license exclusion is stated where the owner reads it")

    place_refs = Nabu::DataBuild.feature("mul/place-refs")
    assert_equal :available, place_refs.status, "P73-4: builder and feature land together"
    assert_equal Nabu::DataBuild::PlaceRefsBuilder, place_refs.builder
    assert_equal "gold-derived", place_refs.tier
    assert_equal "document-urn", place_refs.anchoring
    assert_equal ["nabu-places"], place_refs.inputs,
                 "the decisions registry is the one declared input — the stale-ingest guard " \
                 "covers its cone"
    assert_equal ["nabu-places"], place_refs.canonical_cones
    assert_equal "mul-place-refs", place_refs.package_name
    assert_match(/Basis/, place_refs.rationale,
                 "the upstream-vs-registry honesty is stated where the owner reads it")

    lpf = Nabu::DataBuild.feature("mul/places-lpf")
    assert_equal :available, lpf.status, "P73-5: builder and feature land together"
    assert_equal Nabu::DataBuild::PlacesLpfBuilder, lpf.builder
    assert_equal "gold-derived", lpf.tier
    assert_equal %w[pleiades trismegistos cigs], lpf.inputs,
                 "titles/coords republish from the index — all three gazetteer cones are " \
                 "load-bearing declared inputs"
    assert_equal lpf.inputs, lpf.canonical_cones
    assert_match(/P69-2/, lpf.rationale,
                 "the GeoNames-rider disposition is recorded where the owner reads it")
    assert_match(/closeMatch/, lpf.rationale,
                 "the no-entity-resolution posture is stated where the owner reads it")

    dates = Nabu::DataBuild.feature("mul/document-dates")
    assert_equal :available, dates.status, "P73-7: builder and feature land together"
    assert_equal Nabu::DataBuild::DocumentDatesBuilder, dates.builder
    assert_equal "gold-derived", dates.tier
    assert_equal "document-urn", dates.anchoring
    assert_empty dates.inputs, "the catalog projection is the source of truth (URN grain)"
    assert_match(/VERBATIM/, dates.rationale,
                 "the raw-string honesty is stated where the owner reads it")
    assert_match(/ODbL/, dates.rationale,
                 "the rundata exclusion is stated where the owner reads it")

    postings = Nabu::DataBuild.feature("mul/char-postings")
    assert_equal :available, postings.status, "P73-8: builder and feature land together"
    assert_equal Nabu::DataBuild::CharPostingsBuilder, postings.builder
    assert_equal "gold-derived", postings.tier
    assert_equal "none", postings.anchoring
    assert_match(/circularity/, postings.rationale,
                 "the Edubba never-re-import guard is stated where the owner reads it")
  end

  def test_language_statics_match_the_glottolog_spine
    # Verified against the owner's canonical/cldf-spine glottolog cone
    # (2026-07-28): sans1269 Sanskrit/san, clas1254 Classical Tibetan/xct;
    # (2026-07-29): anci1242 is the languoid carrying ISO grc (Glottolog's
    # own name is "Ionic-Attic Ancient Greek"; the Name column uses the ISO
    # 639-3 reference name).
    # Also checked: lite1248 Classical Chinese/lzh (P52-4).
    san = Nabu::DataBuild::LANGUAGES.fetch("san")
    assert_equal %w[Sanskrit sans1269 san], [san.name, san.glottocode, san.iso639p3]

    xct = Nabu::DataBuild::LANGUAGES.fetch("xct")
    assert_equal ["Classical Tibetan", "clas1254", "xct"], [xct.name, xct.glottocode, xct.iso639p3]

    # P52-3 statics (cone re-checked 2026-07-29): nucl1643 Japanese/jpn; zho
    # is the ISO 639-3 macrolanguage Glottolog assigns NO glottocode to — the
    # honest static is empty, and it is the same pan-CJK macro tag Nabu's own
    # unihan shelf files under (Adapters::Unihan::LANGUAGE).
    jpn = Nabu::DataBuild::LANGUAGES.fetch("jpn")
    assert_equal %w[Japanese nucl1643 jpn], [jpn.name, jpn.glottocode, jpn.iso639p3]

    zho = Nabu::DataBuild::LANGUAGES.fetch("zho")
    assert_equal ["Chinese", nil, "zho"], [zho.name, zho.glottocode, zho.iso639p3]
    assert_equal Nabu::Adapters::Unihan::LANGUAGE, zho.id

    # Checked 2026-07-29: lati1261 Latin/lat (glottolog/languages.csv).
    lat = Nabu::DataBuild::LANGUAGES.fetch("lat")
    assert_equal %w[Latin lati1261 lat], [lat.name, lat.glottocode, lat.iso639p3]

    grc = Nabu::DataBuild::LANGUAGES.fetch("grc")
    assert_equal ["Ancient Greek", "anci1242", "grc"], [grc.name, grc.glottocode, grc.iso639p3]

    lzh = Nabu::DataBuild::LANGUAGES.fetch("lzh")
    assert_equal ["Classical Chinese", "lite1248", "lzh"], [lzh.name, lzh.glottocode, lzh.iso639p3]

    # Checked 2026-07-29 (P53-3): sume1241 Sumerian/sux (glottolog/
    # languages.csv — level: language, an isolate; the one row carrying
    # ISO sux).
    sux = Nabu::DataBuild::LANGUAGES.fetch("sux")
    assert_equal %w[Sumerian sume1241 sux], [sux.name, sux.glottocode, sux.iso639p3]

    # Checked 2026-08-02 (P56-2): oldp1257 "Old Portuguese" is Glottolog's
    # languoid for the medieval Galician-Portuguese stage (level: dialect
    # under port1283 — Glottolog files historical Romance stages that way,
    # cf. medi1250 Medieval Latin under lati1261). ISO 639-3 has NO code for
    # it: roa-opt is the BCP 47 collective-tag convention (D55-a), so the
    # ISO static is honestly nil.
    roa_opt = Nabu::DataBuild::LANGUAGES.fetch("roa-opt")
    assert_equal ["Old Galician-Portuguese", "oldp1257", nil],
                 [roa_opt.name, roa_opt.glottocode, roa_opt.iso639p3]
    assert_equal Nabu::Adapters::CantigasHtmlParser::LANGUAGE, roa_opt.id

    # Checked 2026-08-11 (P73-0, №R-25): mul is ISO 639-3's SPECIAL code
    # "Multiple languages" (scope S) — it names content, not a languoid, so
    # Glottolog carries no row for it (verified: no languages.csv row in the
    # cldf-spine cone has ISO639P3code mul) and the glottocode is honestly
    # nil. The cross-language corpus-layer datasets (lect-assignments,
    # place-refs, document-dates, places-lpf) file under it.
    mul = Nabu::DataBuild::LANGUAGES.fetch("mul")
    assert_equal ["Multiple languages", nil, "mul"], [mul.name, mul.glottocode, mul.iso639p3]
  end

  # №R-25: the mul/ namespace is real plumbing — a mul-led slug must
  # construct through the same Feature validation every language uses.
  def test_a_mul_slugged_feature_validates
    feature = valid_feature(slug: "mul/test-refs", language: Nabu::DataBuild::LANGUAGES.fetch("mul"))
    assert_equal "mul/test-refs", feature.slug
    assert_equal "mul-test-refs", feature.package_name
  end

  def test_feature_lookup_goes_through_the_features_seam
    assert_equal "san/form-lemma", Nabu::DataBuild.feature("san/form-lemma").slug
    assert_nil Nabu::DataBuild.feature("nope/nope")
  end

  # The D51-a license carve-out (2026-07-29): the allowed set is exactly
  # CC BY / CC BY-SA; NC/ND inputs are disqualifying at intake, so no NC/ND
  # value is ever legal.
  def test_license_defaults_to_cc_by_and_only_the_allowed_set_is_legal
    assert_equal %w[CC-BY-4.0 CC-BY-SA-4.0], Nabu::DataBuild::LICENSES
    assert_equal "CC-BY-4.0", valid_feature.license, "the default is the repo default, CC BY 4.0"
    assert_equal "CC-BY-SA-4.0", valid_feature(license: "CC-BY-SA-4.0").license,
                 "share-alike-derived datasets may publish as BY-SA (owner ruling D51-a)"

    ["CC-BY-NC-4.0", "CC-BY-ND-4.0", "CC0-1.0", "whatever", ""].each do |value|
      error = assert_raises(Nabu::ValidationError, "license #{value.inspect} must be refused") do
        valid_feature(license: value)
      end
      assert_match(/license/, error.message)
    end
  end

  # The shipped license census, per slug. CC BY is the default; the BY-SA
  # entries inherit share-alike from their inputs (the D51-a carve-out:
  # sabellic-loans from Wiktionary's dual grant; kyujitai-fold from
  # KANJIDIC2/EDRDG; kanripo-gaiji from the KR-Gaiji grant — the latter two
  # land with P52-4's merge).
  def test_the_shipped_license_census
    expected = {
      "san/form-lemma" => "CC-BY-4.0", "xct/wylie-fold" => "CC-BY-4.0",
      "xct/verb-lemma" => "CC-BY-4.0", "xct/segmentation" => "CC-BY-4.0",
      "zho/hani-fold" => "CC-BY-4.0", "jpn/aozora-gaiji" => "CC-BY-4.0",
      "lat/sabellic-loans" => "CC-BY-SA-4.0", "grc/meter" => "CC-BY-4.0",
      "jpn/kyujitai-fold" => "CC-BY-SA-4.0", "lzh/kanripo-gaiji" => "CC-BY-SA-4.0",
      "sux/value-signs" => "CC-BY-4.0", "xct/actib-anchors" => "CC-BY-4.0",
      "roa-opt/cantigas" => "CC-BY-4.0",
      # P73-3/P73-4: the №R-24 one-carve-out ruling — the share-alike
      # lanes (edh, aes, ...) ride inside one BY-SA dataset each.
      "mul/lect-assignments" => "CC-BY-SA-4.0",
      "mul/place-refs" => "CC-BY-SA-4.0",
      # P73-5: the TM lane's share-alike inheritance.
      "mul/places-lpf" => "CC-BY-SA-4.0",
      # P73-7: the dating layer's share-alike lanes (edh, tla-hf, aes, ...).
      "mul/document-dates" => "CC-BY-SA-4.0",
      # P73-8: the kanripo lane's share-alike grant.
      "mul/char-postings" => "CC-BY-SA-4.0"
    }
    assert_equal(expected, features.to_h { |feature| [feature.slug, feature.license] })
  end

  def test_feature_construction_refuses_dishonest_values
    assert_raises(Nabu::ValidationError) { valid_feature(slug: "SAN/Form_Lemma") }
    assert_raises(Nabu::ValidationError) { valid_feature(slug: "san") }
    assert_raises(Nabu::ValidationError) { valid_feature(slug: "xct/test-feature") } # language mismatch
    assert_raises(Nabu::ValidationError) { valid_feature(status: :done) }
    assert_raises(Nabu::ValidationError) { valid_feature(status: :available) } # available needs a builder
    assert_raises(Nabu::ValidationError) { valid_feature(builder: Class.new) } # planned must not carry one
    assert_raises(Nabu::ValidationError) { valid_feature(rationale: "") }
    assert_raises(Nabu::ValidationError) { valid_feature(maintenance: " ") }
  end

  private

  def valid_feature(**overrides)
    defaults = {
      slug: "san/test-feature", language: Nabu::DataBuild::LANGUAGES.fetch("san"),
      title: "A test feature", status: :planned, tier: "gold", anchoring: "none",
      inputs: [], canonical_cones: [], rationale: "Because.", maintenance: "Never.", builder: nil
    }
    Nabu::DataBuild::Feature.new(**defaults, **overrides)
  end
end
