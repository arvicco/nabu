# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Kinds (P99-1 — №R-63): the kind-axis config seam. Two files —
# config/kind_classes.yml (the RULED 26-head class list + crosswalks)
# and config/kind_map.yml (per-source folds: exact map, prefix_map,
# range_map, source_kind) — loaded with validation, plus the §4b
# normalization pipeline (strip trailing markers, split composites,
# exact → prefix → range lookup, multi-target, unmapped emission).
class KindsTest < Minitest::Test
  CLASSES = <<~YAML
    version: 1
    classes:
      funerary:
        desc: "Texts for and about the dead."
        subs: [epitaph, mummy-label]
        crosswalk: {lcgft: gf2014026316}
      legal:
        desc: "Law and its instruments."
        subs: [contract, law, court, petition, treaty]
      letter:
        desc: "Correspondence."
      hymn-prayer:
        desc: "Addressing the divine."
      magic:
        desc: "Incantations, curses, amulets."
      divination:
        desc: "Omens and their sciences."
      historiography:
        desc: "Annals, chronicles, king-lists."
      poetry:
        desc: "Verse as verse."
      narrative:
        desc: "Told stories."
        subs: [novel]
      exegesis:
        desc: "Commentary on scripture."
      drama:
        desc: "Text written for performance."
      unknown:
        desc: "Upstream's own 'cannot determine'."
  YAML

  MAP = <<~'YAML'
    split: ["|", ";"]
    strip: ["?"]
    sources:
      edr:
        facet: genre
        map:
          "sepulcralis": funerary/epitaph
          "ignoratur": unknown
      cdli:
        facet: genre
        map:
          "Legal": legal
          "Prayer/Incantation": [hymn-prayer, magic/incantation]
      ebl:
        facet: genre
        prefix_map:
          "CANONICAL/Divination": divination
          "ARCHIVAL/Letter": letter
      tlhdig:
        facet: cth
        range_map:
          "291-298": legal/law
          "531-582": divination
      okhc:
        source_kind: historiography/annals
      kanripo:
        metadata: class
        map:
          "KR2": historiography
      aozora:
        metadata: ndc
        regex_map:
          '\bK?9\d1\b': poetry
          '\bK?9\d3\b': narrative/novel
      dta:
        metadata: subgenre
        map:
          "Drama": drama
      sefaria:
        metadata: categories
        map:
          "Talmud": exegesis
      papyri-ddbdp:
        walk: hgv-keywords
        map:
          "Quittung": legal
  YAML

  def load_kinds(classes: CLASSES, map: MAP)
    Dir.mktmpdir do |dir|
      cpath = File.join(dir, "kind_classes.yml")
      mpath = File.join(dir, "kind_map.yml")
      File.write(cpath, classes)
      File.write(mpath, map)
      return Nabu::Kinds.load(classes_path: cpath, map_path: mpath)
    end
  end

  def kinds = @kinds ||= load_kinds

  # -- loading + validation --------------------------------------------------

  def test_classes_and_sources_load
    assert_includes kinds.class_names, "funerary"
    assert_includes kinds.class_names, "unknown"
    assert_equal %w[epitaph mummy-label], kinds.classes["funerary"].subs
    assert_equal "gf2014026316", kinds.classes["funerary"].crosswalk["lcgft"]
    assert_equal %w[aozora cdli dta ebl edr kanripo okhc papyri-ddbdp sefaria tlhdig],
                 kinds.sources.sort
    assert_equal "genre", kinds.facet_for("edr")
    assert_equal "historiography/annals", kinds.source_kind("okhc")
    assert_nil kinds.source_kind("edr")
  end

  def test_a_map_target_with_an_undeclared_head_is_a_config_error
    bad = MAP.sub("funerary/epitaph", "sepulchral/epitaph")
    error = assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
    assert_match(/sepulchral/, error.message)
    assert_match(/edr/, error.message, "the error names the offending source")
  end

  def test_a_malformed_range_key_is_a_config_error
    bad = MAP.sub('"291-298"', '"291..298"')
    assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
  end

  def test_a_source_rule_without_facet_or_source_kind_is_a_config_error
    bad = MAP.sub(/^\s*facet: cth\n/, "")
    assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
  end

  # -- normalization (§4b) ---------------------------------------------------

  def test_exact_map_and_sub_grain
    assert_equal ["funerary/epitaph"], kinds.normalize("edr", "sepulcralis")
    assert_equal ["unknown"], kinds.normalize("edr", "ignoratur")
  end

  def test_trailing_uncertainty_marker_strips
    assert_equal ["funerary/epitaph"], kinds.normalize("edr", "sepulcralis?")
    assert_equal ["legal"], kinds.normalize("cdli", "Legal ?"),
                 "cdli's space-before-? shape strips to the exact value"
  end

  def test_exact_lookup_falls_back_case_insensitively
    assert_equal ["legal"], kinds.normalize("cdli", "legal"),
                 "cdli carries both 'Administrative' and 'administrative' upstream"
  end

  def test_composites_split_and_multi_target_expands
    assert_equal ["funerary/epitaph", "unknown"],
                 kinds.normalize("edr", "sepulcralis | ignoratur")
    assert_equal ["hymn-prayer", "magic/incantation"],
                 kinds.normalize("cdli", "Prayer/Incantation"),
                 "a ruled split maps one upstream value to two classes"
  end

  def test_prefix_map_matches_path_vocabularies
    assert_equal ["divination"], kinds.normalize("ebl", "CANONICAL/Divination/Celestial")
    assert_equal ["divination"], kinds.normalize("ebl", "CANONICAL/Divination")
    assert_equal ["letter"], kinds.normalize("ebl", "ARCHIVAL/Letter")
  end

  def test_range_map_folds_numeric_facets
    assert_equal ["legal/law"], kinds.normalize("tlhdig", "295")
    assert_equal ["divination"], kinds.normalize("tlhdig", "582")
    assert_equal ["unmapped"], kinds.normalize("tlhdig", "832"),
                 "a CTH number outside every ruled range is honestly unmapped"
  end

  def test_unmapped_fragments_emit_beside_mapped_ones
    assert_equal ["unmapped"], kinds.normalize("edr", "cetera")
    assert_equal ["funerary/epitaph", "unmapped"],
                 kinds.normalize("edr", "sepulcralis; cetera"),
                 "a half-mapped composite keeps the honest bucket"
  end

  def test_duplicate_targets_dedupe
    assert_equal ["funerary/epitaph"],
                 kinds.normalize("edr", "sepulcralis | sepulcralis?")
  end

  def test_unknown_source_normalizes_to_nothing
    assert_empty kinds.normalize("perseus", "anything"),
                 "a source with no rule contributes no rows — its posture speaks instead"
  end

  # -- metadata rules + regex_map (P100-1) -----------------------------------

  def test_metadata_rule_declares_its_fields
    assert_equal ["class"], kinds.rule_for("kanripo").metadata
    assert_equal ["subgenre"], kinds.rule_for("dta").metadata
    assert_nil kinds.facet_for("kanripo"), "a metadata rule is not a facet rule"
    assert_equal ["historiography"], kinds.normalize("kanripo", "KR2"),
                 "normalization is source-agnostic about where the value came from"
  end

  def test_regex_map_collects_every_matching_pattern
    assert_equal ["poetry"], kinds.normalize("aozora", "NDC 911")
    assert_equal ["poetry"], kinds.normalize("aozora", "NDC K921"),
                 "the children's-literature K prefix and any middle digit both ride the pattern"
    assert_equal ["narrative/novel"], kinds.normalize("aozora", "NDC 913")
    assert_equal %w[poetry narrative/novel], kinds.normalize("aozora", "NDC 911 913"),
                 "a value matching several patterns is multi-label"
    assert_equal ["unmapped"], kinds.normalize("aozora", "NDC 596")
  end

  def test_a_rule_must_declare_exactly_one_source_shape
    bad = MAP.sub(/^(\s*)metadata: class\n/) do
      "#{Regexp.last_match(1)}metadata: class\n#{Regexp.last_match(1)}facet: genre\n"
    end
    assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
  end

  def test_walk_rules_declare_a_known_walker
    assert_equal "hgv-keywords", kinds.rule_for("papyri-ddbdp").walk
    bad = MAP.sub("walk: hgv-keywords", "walk: no-such-walker")
    error = assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
    assert_match(/no-such-walker/, error.message)
  end

  def test_a_malformed_regex_is_a_config_error
    bad = MAP.sub('\bK?9\d1\b', "NDC [9")
    assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
  end

  # -- the shipped config ----------------------------------------------------

  def test_the_shipped_config_loads_and_carries_the_ruled_26_heads
    shipped = Nabu::Kinds.load(
      classes_path: File.expand_path("../config/kind_classes.yml", __dir__),
      map_path: File.expand_path("../config/kind_map.yml", __dir__)
    )
    heads = shipped.class_names - ["unknown"]
    assert_equal 26, heads.size, "№R-63 ruled exactly 26 heads + unknown"
    %w[funerary dedicatory honorific building boundary mark royal
       administrative legal letter lexical scholarly school
       scripture exegesis hymn-prayer ritual magic divination
       narrative poetry drama essay diary wisdom historiography].each do |head|
      assert_includes heads, head
    end
    assert_includes shipped.class_names, "unknown"
    assert_operator shipped.sources.size, :>=, 10,
                    "the initial map covers the genre-bearing census sources"
    assert_equal "historiography/annals", shipped.source_kind("okhc")
  end
end
