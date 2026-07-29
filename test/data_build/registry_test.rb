# frozen_string_literal: true

require "test_helper"

# The nabu-data feature census (P50-W1): six registered features, every field
# present and well-shaped. The rail landed first with everything :planned;
# builder packets flip their own feature as each builder lands (P50-W2:
# san/form-lemma, P50-W4: xct/verb-lemma, P52-4: the two BY-SA fold-ins).
# The registry is EXPLICIT — no discovery magic — so this test pins the
# ratified metadata, not just the shape.
class DataBuildRegistryTest < Minitest::Test
  EXPECTED_SLUGS = %w[san/form-lemma xct/wylie-fold xct/verb-lemma xct/segmentation
                      jpn/kyujitai-fold lzh/kanripo-gaiji].freeze

  def features
    Nabu::DataBuild::REGISTRY
  end

  def test_registers_exactly_the_six_features_with_unique_slugs_in_order
    assert_equal EXPECTED_SLUGS, features.map(&:slug)
    assert_equal features.size, features.map(&:slug).uniq.size
  end

  def test_the_builder_status_census
    # The rail landed with every feature :planned; each builder packet flipped
    # exactly its own feature (P50-W2 form-lemma, P50-W3 wylie-fold, P50-W4
    # verb-lemma, P51-W5 segmentation, P52-4 kyujitai-fold + kanripo-gaiji).
    # The full census is available.
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
      [language.id, language.name, language.glottocode, language.iso639p3].each do |value|
        refute_empty value.to_s, "#{feature.slug}: languages.csv statics must be complete"
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
  end

  def test_language_statics_match_the_glottolog_spine
    # Verified against the owner's canonical/cldf-spine glottolog cone
    # (2026-07-28): sans1269 Sanskrit/san, clas1254 Classical Tibetan/xct;
    # (2026-07-29): nucl1643 Japanese/jpn, lite1248 Classical Chinese/lzh.
    san = Nabu::DataBuild::LANGUAGES.fetch("san")
    assert_equal %w[Sanskrit sans1269 san], [san.name, san.glottocode, san.iso639p3]

    xct = Nabu::DataBuild::LANGUAGES.fetch("xct")
    assert_equal ["Classical Tibetan", "clas1254", "xct"], [xct.name, xct.glottocode, xct.iso639p3]

    jpn = Nabu::DataBuild::LANGUAGES.fetch("jpn")
    assert_equal %w[Japanese nucl1643 jpn], [jpn.name, jpn.glottocode, jpn.iso639p3]

    lzh = Nabu::DataBuild::LANGUAGES.fetch("lzh")
    assert_equal ["Classical Chinese", "lite1248", "lzh"], [lzh.name, lzh.glottocode, lzh.iso639p3]
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

  # The per-feature license census (D51-a): the four legacy features stay the
  # repo-default CC BY; the two P52-4 fold-ins are BY-SA — kyujitai-fold's
  # load-bearing KANJIDIC2 lane is EDRDG share-alike, kanripo-gaiji is curated
  # from the BY-SA KR-Gaiji charlist.
  def test_the_per_feature_license_census
    expected = {
      "san/form-lemma" => "CC-BY-4.0",
      "xct/wylie-fold" => "CC-BY-4.0",
      "xct/verb-lemma" => "CC-BY-4.0",
      "xct/segmentation" => "CC-BY-4.0",
      "jpn/kyujitai-fold" => "CC-BY-SA-4.0",
      "lzh/kanripo-gaiji" => "CC-BY-SA-4.0"
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
