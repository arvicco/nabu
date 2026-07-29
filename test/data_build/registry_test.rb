# frozen_string_literal: true

require "test_helper"

# The nabu-data feature census (P50-W1): seven registered features, every field
# present and well-shaped. The rail landed first with everything :planned;
# builder packets flip their own feature as each builder lands (P50-W2:
# san/form-lemma, P50-W4: xct/verb-lemma, P52-3: zho/hani-fold +
# jpn/aozora-gaiji). The registry is EXPLICIT — no discovery magic — so this
# test pins the ratified metadata, not just the shape.
class DataBuildRegistryTest < Minitest::Test
  EXPECTED_SLUGS = %w[san/form-lemma xct/wylie-fold xct/verb-lemma xct/segmentation
                      zho/hani-fold jpn/aozora-gaiji
                      lat/sabellic-loans].freeze

  def features
    Nabu::DataBuild::REGISTRY
  end

  def test_registers_exactly_the_seven_features_with_unique_slugs_in_order
    assert_equal EXPECTED_SLUGS, features.map(&:slug)
    assert_equal features.size, features.map(&:slug).uniq.size
  end

  def test_the_builder_status_census
    # The rail landed with every feature :planned; each builder packet flipped
    # exactly its own feature (P50-W2 form-lemma, P50-W3 wylie-fold, P50-W4
    # verb-lemma, P51-W5 segmentation, P52-5 sabellic-loans landing available
    # with its builder in one packet). The full census is available.
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
      [language.id, language.name, language.iso639p3].each do |value|
        refute_empty value.to_s, "#{feature.slug}: languages.csv statics must be complete"
      end
      if language.glottocode.nil?
        # Glottolog deliberately assigns no glottocode to ISO 639-3
        # MACROLANGUAGES (verified against the cldf-spine cone 2026-07-29:
        # no languages.csv row carries ISO zho; the nearest node sini1245 is
        # a family, not this tag) — an empty static is honest there, and zho
        # is the one registered macro tag. Any other nil is a missing static.
        assert_equal "zho", language.id,
                     "#{feature.slug}: only the zho macrolanguage may omit a glottocode"
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
  end

  def test_language_statics_match_the_glottolog_spine
    # Verified against the owner's canonical/cldf-spine glottolog cone
    # (2026-07-28): sans1269 Sanskrit/san, clas1254 Classical Tibetan/xct.
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

  # The shipped license census, per slug: the P50/P51 features are CC BY;
  # lat/sabellic-loans derives from Wiktionary's share-alike dual grant and
  # publishes as BY-SA (the D51-a carve-out in action).
  def test_the_shipped_license_census
    expected = {
      "san/form-lemma" => "CC-BY-4.0", "xct/wylie-fold" => "CC-BY-4.0",
      "xct/verb-lemma" => "CC-BY-4.0", "xct/segmentation" => "CC-BY-4.0",
      "lat/sabellic-loans" => "CC-BY-SA-4.0"
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
