# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Kinds (P99-1 — owner-ruled 2026-09-13): the kind-axis config seam. Two files —
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
      literary:
        desc: "Literature as literature; the bare head is upstream's own unspecified claim."
        subs: [narrative, poetry, drama]
      literary/poetry:
        desc: "Verse as verse."
      literary/narrative:
        desc: "Told stories."
        subs: [novel]
      literary/drama:
        desc: "Text written for performance."
      exegesis:
        desc: "Commentary on scripture."
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
          '\bK?9\d1\b': literary/poetry
          '\bK?9\d3\b': literary/narrative/novel
      dta:
        metadata: subgenre
        map:
          "Drama": literary/drama
      elephantine:
        facet: genre
        map:
          "note": legal
        deliberate:
          "vertical format": "physical layout, not a genre"
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
    assert_equal %w[aozora cdli dta ebl edr elephantine kanripo okhc papyri-ddbdp sefaria tlhdig],
                 kinds.sources.sort
    assert_equal "genre", kinds.facet_for("edr")
    assert_equal "historiography/annals", kinds.source_kind("okhc")
    assert_nil kinds.source_kind("edr")
  end

  # -- the owner-ruled (2026-09-18) tree: slash-keyed sub-classes + head extraction ------------

  def test_slash_keyed_sub_classes_carry_their_own_desc_under_a_declared_head
    assert_includes kinds.class_names, "literary/narrative"
    assert_equal %w[novel], kinds.classes["literary/narrative"].subs
    refute_includes kinds.heads, "literary/narrative", "heads collapse to first segments"
    assert_includes kinds.heads, "literary"
  end

  def test_a_sub_class_without_its_head_is_a_config_error
    bad = CLASSES.sub(/^  literary:\n    desc:[^\n]*\n    subs: \[narrative, poetry, drama\]\n/, "")
    error = assert_raises(Nabu::Kinds::ConfigError) { load_kinds(classes: bad) }
    assert_match(%r{literary/}, error.message)
  end

  def test_a_three_segment_target_validates_against_its_head
    assert_equal ["literary/narrative/novel"], kinds.normalize("aozora", "NDC 913"),
                 "the tree is optionally deeper than two — the head still validates"
  end

  # -- deliberate not-genre declarations (P101) ------------------------

  def test_a_deliberate_value_folds_to_nothing
    assert_empty kinds.normalize("elephantine", "vertical format"),
                 "a reviewed not-genre value is a non-claim, never unmapped noise"
    assert_empty kinds.normalize("elephantine", "Vertical Format"),
                 "deliberate matching folds case like the exact map"
    assert_equal %w[legal], kinds.normalize("elephantine", "note | vertical format"),
                 "a composite keeps its genre fragments and drops the declared one"
  end

  def test_deliberate_declarations_surface_for_the_census
    rows = kinds.deliberate_declarations
    assert_includes rows, ["elephantine", "vertical format", "physical layout, not a genre"]
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
    assert_equal ["literary/poetry"], kinds.normalize("aozora", "NDC 911")
    assert_equal ["literary/poetry"], kinds.normalize("aozora", "NDC K921"),
                 "the children's-literature K prefix and any middle digit both ride the pattern"
    assert_equal ["literary/narrative/novel"], kinds.normalize("aozora", "NDC 913")
    assert_equal %w[literary/poetry literary/narrative/novel],
                 kinds.normalize("aozora", "NDC 911 913"),
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

  # -- open vocabularies: uncovered values mint nothing -----------------------
  #
  # A subject-heading facet (eebo-tcp's LCSH TERMs) is an OPEN vocabulary:
  # tens of thousands of distinct values, overwhelmingly topical. Filing
  # every topical heading as `unmapped` would drown the curation worklist
  # and claim a gap where there is none; `vocabulary: open` declares that
  # an uncovered value folds to NOTHING — and reports it as uncovered so
  # the census can count it (never silent).

  OPEN_MAP = <<~'YAML'
    split: ["|"]
    strip: ["?"]
    sources:
      eebo:
        facet: subject
        vocabulary: open
        regex_map:
          '\ASermons, English\b': hymn-prayer
          '-- Poetry\.?( --|\z)': literary/poetry
        deliberate:
          "Broadsides": "physical format, not a genre"
      edr:
        facet: genre
        map:
          "sepulcralis": funerary/epitaph
  YAML

  def open_kinds = @open_kinds ||= load_kinds(map: OPEN_MAP)

  def test_an_open_vocabulary_folds_uncovered_values_to_nothing
    assert open_kinds.open?("eebo")
    refute open_kinds.open?("edr"), "closed is the default"
    assert_equal ["hymn-prayer"], open_kinds.normalize("eebo", "Sermons, English -- 17th century.")
    assert_equal ["literary/poetry"], open_kinds.normalize("eebo", "Great Britain -- History -- Poetry.")
    assert_empty open_kinds.normalize("eebo", "Great Britain -- Politics and government -- 1660-1688."),
                 "an uncovered topical heading mints nothing — never the unmapped bucket"
  end

  def test_fold_reports_uncovered_fragments_for_the_census
    fold = open_kinds.fold("eebo", "Ireland -- History.")
    assert_empty fold.paths
    assert_equal ["Ireland -- History."], fold.uncovered, "the uncovered value is counted, not dropped"
    mixed = open_kinds.fold("eebo", "Sermons, English | Plague")
    assert_equal ["hymn-prayer"], mixed.paths
    assert_equal ["Plague"], mixed.uncovered
  end

  def test_open_vocabulary_deliberate_values_are_reviewed_not_uncovered
    fold = open_kinds.fold("eebo", "Broadsides")
    assert_empty fold.paths
    assert_empty fold.uncovered, "a declared not-genre value is a reviewed non-claim, not an open-vocabulary miss"
  end

  def test_closed_vocabularies_keep_the_unmapped_bucket_and_report_no_uncovered
    fold = open_kinds.fold("edr", "cetera")
    assert_equal ["unmapped"], fold.paths
    assert_empty fold.uncovered, "a closed vocabulary's miss is the unmapped bucket, already counted"
  end

  def test_fold_of_an_unruled_source_is_empty
    fold = open_kinds.fold("perseus", "anything")
    assert_empty fold.paths
    assert_empty fold.uncovered
  end

  def test_a_class_name_may_not_carry_a_colon
    bad = CLASSES.sub("  unknown:\n", "  \"uncovered:x\":\n    desc: \"shadow\"\n  unknown:\n")
    error = assert_raises(Nabu::Kinds::ConfigError) { load_kinds(classes: bad) }
    assert_match(/colon/, error.message, "the colon is reserved for the uncovered census rows")
  end

  def test_vocabulary_must_be_open_or_closed
    bad = OPEN_MAP.sub("vocabulary: open", "vocabulary: ajar")
    error = assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
    assert_match(/vocabulary/, error.message)
  end

  def test_a_whole_source_declaration_cannot_be_open
    bad = OPEN_MAP.sub("facet: subject\n", "source_kind: literary\n").sub(/^\s+regex_map:\n(.*\n){2}/, "")
                  .sub(/^\s+deliberate:\n.*\n/, "")
    error = assert_raises(Nabu::Kinds::ConfigError) { load_kinds(map: bad) }
    assert_match(/source_kind/, error.message)
  end

  # -- the shipped config ----------------------------------------------------

  def test_the_shipped_config_loads_and_carries_the_ruled_21_heads
    shipped = Nabu::Kinds.load(
      classes_path: File.expand_path("../config/kind_classes.yml", __dir__),
      map_path: File.expand_path("../config/kind_map.yml", __dir__)
    )
    heads = shipped.heads - ["unknown"]
    assert_equal 23, heads.size,
                 "the 26 original heads restructured (owner ruling 2026-09-18): the six literature " \
                 "families live under `literary`; periodical + sermon ruled 2026-10-19 — " \
                 "23 heads + unknown"
    %w[funerary dedicatory honorific building boundary mark royal
       administrative legal letter lexical scholarly school
       scripture exegesis hymn-prayer ritual magic divination
       literary historiography periodical sermon].each do |head|
      assert_includes heads, head
    end
    %w[literary/narrative literary/poetry literary/drama
       literary/essay literary/diary literary/wisdom].each do |sub|
      assert_includes shipped.class_names, sub,
                      "the demoted families keep their names, descs and crosswalks as sub-classes"
    end
    assert_includes shipped.class_names, "unknown"
    assert_operator shipped.sources.size, :>=, 10,
                    "the initial map covers the genre-bearing census sources"
    assert_equal ["literary"], shipped.normalize("cdli", "Literary"),
                 "upstream's own literature catch-all folds to the bare head"
    assert_equal ["administrative/note"], shipped.normalize("elephantine", "note")
    assert_equal ["unknown"], shipped.normalize("cdli", "fake (modern)")
  end

  # P104-1 (the aggressive-mining law): the okhc blanket source_kind graduates to
  # the corpus-field fold — the 1.2M-doc shelf splits into honest kinds.
  def test_shipped_okhc_folds_the_corpus_field
    shipped = shipped_kinds
    assert_nil shipped.source_kind("okhc"), "the blanket declaration retired at P104-1"
    assert_equal %w[corpus], shipped.metadata_for("okhc")
    assert_equal ["literary"], shipped.normalize("okhc", "Korean Literary Collections")
    assert_equal ["historiography/annals"],
                 shipped.normalize("okhc", "The Records of Daily Reflections (Ilseongnok)")
    assert_equal ["historiography"], shipped.normalize("okhc", "History of the Three Kingdoms (Samguk sagi)")
    assert_equal ["administrative"], shipped.normalize("okhc", "Gaksadeungnok")
    assert_equal ["letter"], shipped.normalize("okhc", "AKS Hangeul Letters (한국고문서자료관 / 조선시대 한글편지)")
    assert_empty shipped.normalize("okhc", "GongU Madang"),
                 "a platform label is a reviewed non-claim, never unmapped noise"
    assert_empty shipped.normalize("okhc", "AKS Old Korean Books (옛한글 원문정보)")
  end

  # classical-modern: the 97 works fold by their Siku Quanshu 部類 seat
  # through the SAME heads the held kanripo fold rules (經部 → scripture,
  # 史部 → historiography, the Masters → literary/wisdom, 兵家 →
  # scholarly …); the translation siblings share the book key.
  def test_shipped_classical_modern_folds_the_book_field
    shipped = shipped_kinds
    assert_equal %w[book], shipped.metadata_for("classical-modern")
    assert_equal ["historiography"], shipped.normalize("classical-modern", "史记")
    assert_equal ["historiography/chronicle"], shipped.normalize("classical-modern", "资治通鉴")
    assert_equal ["scripture"], shipped.normalize("classical-modern", "论语")
    assert_equal ["literary/wisdom"], shipped.normalize("classical-modern", "庄子")
    assert_equal ["scholarly"], shipped.normalize("classical-modern", "孙子兵法")
    assert_equal ["scholarly/medicine"], shipped.normalize("classical-modern", "黄帝内经")
    assert_equal ["literary/narrative"], shipped.normalize("classical-modern", "搜神记")
    assert_equal ["legal"], shipped.normalize("classical-modern", "睡虎地秦墓竹简")
    assert_equal ["school"], shipped.normalize("classical-modern", "三字经")
  end

  # P104-1: the ETCSL composition-number taxonomy (c.0–c.6) folds through
  # a frozen prefix map — the Sumerian literary canon's first genre view.
  def test_shipped_etcsl_folds_the_composition_number_blocks
    shipped = shipped_kinds
    assert_equal %w[etcsl_no], shipped.metadata_for("etcsl")
    assert_equal ["administrative/list"], shipped.normalize("etcsl", "0.2.11")
    assert_equal ["literary/narrative/myth"], shipped.normalize("etcsl", "1.8.2.1")
    assert_equal ["historiography"], shipped.normalize("etcsl", "2.1.1"),
                 "the Sumerian King List block is historiography, not royal praise"
    assert_equal ["hymn-prayer/lament"], shipped.normalize("etcsl", "2.2.2")
    assert_equal ["royal"], shipped.normalize("etcsl", "2.4.2.01")
    assert_equal ["letter"], shipped.normalize("etcsl", "3.1.1")
    assert_equal ["hymn-prayer"], shipped.normalize("etcsl", "4.80.1")
    assert_equal ["literary/wisdom"], shipped.normalize("etcsl", "5.3.2")
    assert_equal ["literary/wisdom/proverb"], shipped.normalize("etcsl", "6.1.01")
  end

  # P104-1: the openiti BookSUBJ fold — the subject facet's recurring
  # Arabic library-taxonomy heads through regex rules (multi-label by
  # design); the theology and misc buckets stay deliberately unmapped.
  def test_shipped_openiti_folds_the_book_subjects
    shipped = shipped_kinds
    assert_equal "subject", shipped.facet_for("openiti")
    assert_equal ["literary/poetry"], shipped.normalize("openiti", "جاهلي :: دواوين الشعر العربي")
    assert_equal ["historiography"], shipped.normalize("openiti", "التراجم والطبقات")
    assert_equal ["exegesis"], shipped.normalize("openiti", "علوم القرآن")
    assert_equal ["scripture"], shipped.normalize("openiti", "متون الحديث")
    assert_equal ["legal"], shipped.normalize("openiti", "الفقه الشافعي :: كتب الفقه الإسلامي")
    assert_equal ["literary/wisdom"],
                 shipped.normalize("openiti", "كتب الأخلاق والسلوك :: كتب متفرقة في الأخلاق والسلوك")
    assert_equal ["unmapped"], shipped.normalize("openiti", "العقيدة"),
                 "theology buckets stay deliberately unmapped — the sefaria Kabbalah stance"
  end

  # P104-1: the kanripo KR-Catalog 部類 graduation — the coarse P100-1
  # class rule becomes per-subclass folds fed by the kr-subclass walker
  # ("KR1a 易類" values: code + the catalog's own label).
  def test_shipped_kanripo_folds_the_subclass_taxonomy
    shipped = shipped_kinds
    assert_equal "kr-subclass", shipped.walk_for("kanripo")
    assert_equal ["scripture"], shipped.normalize("kanripo", "KR1a 易類")
    assert_equal ["lexical"], shipped.normalize("kanripo", "KR1j 小學類")
    assert_equal ["historiography/chronicle"], shipped.normalize("kanripo", "KR2b 編年類")
    assert_equal ["administrative"], shipped.normalize("kanripo", "KR2f 詔令奏議類")
    assert_equal %w[scholarly/astronomy scholarly/mathematics],
                 shipped.normalize("kanripo", "KR3f 天文算法類").sort
    assert_equal ["divination"], shipped.normalize("kanripo", "KR3g 術數類")
    assert_equal ["literary/narrative"], shipped.normalize("kanripo", "KR3l 小說家類")
    assert_equal ["literary"], shipped.normalize("kanripo", "KR4d 別集類-宋")
    assert_equal ["scripture"], shipped.normalize("kanripo", "KR5c 洞神部")
    assert_equal ["historiography"], shipped.normalize("kanripo", "KR2a"),
                 "a bare code (label missing from the frozen catalog) folds via the class fallback"
  end

  # P105-6: the fold round over the worklist head (census 2026-09-26,
  # 4,048 unmapped values / 14,695 docs) — one representative pin per
  # extended source; the standing stay-visible rulings (openiti theology
  # buckets, tlhdig 758-829) are untouched.
  def test_shipped_p105_fold_round_covers_the_worklist_head
    shipped = shipped_kinds
    { %w[papyri-ddbdp Befehl] => ["administrative"],
      ["papyri-ddbdp", "Exercice épistolaire"] => ["school"],
      %w[papyri-ddbdp Bittschrift] => ["legal/petition"],
      ["papyri-ddbdp", "Vermessung (?)"] => ["administrative"],
      %w[papyri-ddbdp Liturgie] => ["administrative"],
      ["elephantine", "documentary | contract"] => %w[administrative legal/contract],
      %w[edh prayer] => ["hymn-prayer/prayer"],
      ["edr", "honorarius aut sepulcralis"] => ["unknown"],
      ["edr", "cetera magica"] => ["magic"],
      %w[iip acclamation] => ["honorific"],
      ["iip", "label.weight"] => ["mark/label"],
      %w[isicily unassigned] => ["unknown"],
      ["ogham", "Unable to determine"] => ["unknown"],
      ["oracc", "Seal inscription"] => ["mark/ownership"],
      %w[oracc Hymn-Prayer] => ["hymn-prayer"],
      %w[dta Psychologie] => ["scholarly"],
      %w[dta Erbauungsliteratur] => ["literary/wisdom"],
      ["aozora", "NDC 388"] => ["literary/narrative/tale"],
      ["aozora", "NDC K949"] => ["literary"],
      ["aozora", "NDC 222"] => ["historiography"],
      ["cdli", "Other (see subgenre)"] => ["unknown"] }.each do |(slug, value), want|
      assert_equal want, shipped.normalize(slug, value).sort, "#{slug} #{value.inspect}"
    end
    assert_empty shipped.normalize("papyri-ddbdp", "Datum"),
                 "a bare dating formula is a reviewed non-claim"
    assert_empty shipped.normalize("aozora", "NDC 751"),
                 "applied-arts NDC shelving is a reviewed non-claim"
    assert_empty shipped.normalize("oracc", "Clay tablet inscription"),
                 "an object description is a reviewed non-claim"
  end

  # P116 R4 (owner-ruled 2026-10-10): the Bactrian corpus's own
  # six-genre CONTENTS list folds onto the ruled heads through the genre
  # facet (census 2026-10-10, 123 docs: 70 letters / 32 dated / 8
  # lists / 5 uncertain-date / 5 Buddhist / 3 uncertain-type).
  def test_shipped_titus_bactrian_folds_the_corpus_genres
    shipped = shipped_kinds
    assert_equal "genre", shipped.facet_for("titus-bactrian")
    { "Letters" => ["letter"],
      "Lists and accounts" => ["administrative"],
      "Dated documents" => ["legal"],
      "Documents and fragments of uncertain date" => ["legal"],
      "Buddhist texts" => ["hymn-prayer"],
      "Fragments of documents of uncertain type" => ["unknown"] }.each do |genre, want|
      assert_equal want, shipped.normalize("titus-bactrian", genre), genre
    end
  end

  # Ruled 2026-10-12: the ticha work_type and kdsp genre vocabularies fold
  # onto the ruled heads (census the same day — ticha 93 docs over four
  # values, kdsp 262 ELTeC novels over five), and the same sitting's aozora
  # tail round (917 humor/satire → literary; the folklore trio joins the
  # 382/386 ethnography shape; the recurring subject shelves join the
  # deliberate block).
  def test_shipped_ticha_kdsp_and_the_aozora_tail_round
    shipped = shipped_kinds
    assert_equal "work_type", shipped.facet_for("ticha")
    { "manuscript" => ["legal"], "arte" => ["lexical/grammar"],
      "catecismo" => ["exegesis"], "miscelaneo" => ["unknown"] }.each do |value, want|
      assert_equal want, shipped.normalize("ticha", value), value
    end
    assert_equal "genre", shipped.facet_for("kdsp")
    { "roman" => ["literary/narrative/novel"], "povest" => ["literary/narrative/tale"],
      "novela" => ["literary/narrative/tale"], "črtica" => ["literary/narrative"],
      "drugo" => ["unknown"] }.each do |value, want|
      assert_equal want, shipped.normalize("kdsp", value), value
    end
    assert_equal ["literary"], shipped.normalize("aozora", "NDC 917")
    assert_equal ["scholarly"], shipped.normalize("aozora", "NDC 384")
    assert_empty shipped.normalize("aozora", "NDC 361"),
                 "sociology shelving is a reviewed non-claim"
  end

  # The 2026-10-18 genre-fold round: tamilex's work facet (21 works; the
  # facet carries the devotional canons' sub-work titles and the epics'
  # per-chapter titles, so the fold is prefix rules on the work name),
  # elektire's genre facet (the portal's 23 knjizevna_vrsta term slugs,
  # census 205 works) and eltec-srp as a whole-source novel declaration —
  # the first literary source_kind.
  def test_shipped_tamilex_elektire_and_eltec_srp_folds
    shipped = shipped_kinds
    assert_equal "work", shipped.facet_for("tamilex")
    { "Kuṟuntokai" => ["literary/poetry/love"],
      "Aiṅkuṟunūṟu." => ["literary/poetry/love"],
      "Puṟanāṉūṟu" => ["literary/poetry/praise"],
      "Maturaikkāñci" => ["literary/poetry/praise"],
      "Tirukkuṟaḷ" => ["literary/wisdom"],
      "Tolkāppiyam Collatikāram" => ["lexical/grammar"],
      "Naṉṉūl Eḻuttatikāram 213" => ["lexical/grammar"],
      "Tivākaram" => ["lexical/word-list"],
      "Cilappatikāram. Vañciṉamālai" => ["literary/narrative/epic"],
      "Peruṅkatai 1.33 — mālaip pulampal" => ["literary/narrative/epic"],
      "Tiruvāymoḻi" => ["hymn-prayer/hymn"],
      "Periya Tirumoḻi" => ["hymn-prayer/hymn"],
      "Aṟputat Tiruvvantāti" => ["hymn-prayer/hymn"],
      "Paripāṭal" => ["hymn-prayer/hymn", "literary/poetry"] }.each do |work, want|
      assert_equal want, shipped.normalize("tamilex", work).sort, work
    end
    assert_equal "genre", shipped.facet_for("elektire")
    { "roman" => ["literary/narrative/novel"], "pripovijest" => ["literary/narrative/tale"],
      "zbirka-pjesama" => ["literary/poetry"], "ep" => ["literary/narrative/epic"],
      "komedija" => ["literary/drama"], "pastorala" => ["literary/drama"],
      "putopis" => ["literary/diary/travelogue"], "feljtoni" => ["literary/essay"],
      "pisma" => ["letter/literary"], "basna" => ["literary/narrative/fable"] }.each do |slug, want|
      assert_equal want, shipped.normalize("elektire", slug), slug
    end
    assert_equal "literary/narrative/novel", shipped.source_kind("eltec-srp")
    assert_equal "administrative", shipped.source_kind("damos")
  end

  # Every census value of the round folds to a ruled class (no unmapped
  # remainder): the full elektire slug census and every distinct tamilex
  # work value read from canonical/ on 2026-10-18.
  def test_genre_fold_round_leaves_no_census_value_unmapped
    shipped = shipped_kinds
    %w[zbirka-pjesama roman pripovijest drama zbirka-pripovijesti komedija drama-jednocinka
       spjev pastorala feljtoni poema putopis operni-libreto eseji ep tragedija
       tragikomedija-melodrama bajka prikazanje igrokaz maskereta pisma basna].each do |slug|
      folded = shipped.normalize("elektire", slug)
      refute_empty folded, slug
      refute_includes folded, Nabu::Kinds::UNMAPPED, slug
    end
    ["Akanāṉūṟu", "Naṟṟiṇai", "Kalittokai", "Patiṟṟuppattu", "Neṭunalvāṭai", "Malaipaṭukaṭām",
     "Naṉṉul Eḻuttatikāram", "Tolkāppiyam Eḻuttatikāram", "Puṟapporuḷveṇpāmālai",
     "Tamiḻneṟi Viḷakkam", "Taṇṭiyalaṅkāravurai", "Cilapparikāram. Ūrcūḻvari.", "Peruṅkatai",
     "Periyāḻvār Tirumoḻi", "Nācciyār Tirumoḻi", "Tiruccantaviruttam", "Perumāḷ Tirumoḻi",
     "Iraṇṭān Tiruvantāti", "Mutaṟṟiruvantāti", "Mūṉṟān Tiruvantāti", "Tiruviruttam",
     "Nāṉmukaṉ Tiruvantāti", "Periyatiruvantāti", "Tirumālai", "Tiruppāvai", "Tiruneṭuntāṇṭakam",
     "Tirukkuṟuntāṇṭakam", "Tiruppallāṇṭu", "Kaṇṇinuṇ Ciṟuttāmpu", "Tiruppaḷḷiyeḻucci",
     "Amalaṉ Āti Pirāṉ", "Tiruvāciriyam", "Periya Tirumaṭal", "Ciṟiya Tirumaṭal",
     "Irāmāṉuca Nūṟṟantāti", "Tiruvāymoli", "Tiruvāvmoḻi", "Tiruveḻukūṟṟirukkai", "Tiruvittam",
     "Kayilaipāti Kāḷattipāti Antāti", "Tiruviraṭṭaimaṇimālai",
     "Tiruvalaṅkāṭṭu orāvatu mūtta Tiruppatikam", "Aruḷicceyt Tiru Ātiyulā."].each do |work|
      folded = shipped.normalize("tamilex", work)
      refute_empty folded, work
      refute_includes folded, Nabu::Kinds::UNMAPPED, work
    end
  end

  # GRETIL's genre ladder (the teiHeader keywords term on all 784 files,
  # mined into metadata "genre"): every census value folds to a ruled
  # class or a reviewed non-claim — none lands unmapped.
  GRETIL_LADDER_CENSUS = [
    "Sanskrit -- Religious Literature -- Buddhist", "Sanskrit -- Śāstra -- Philosophy -- Buddhist",
    "Sanskrit -- Poetry -- Kāvya", "Sanskrit -- Śāstra -- Philosophy -- Vedānta",
    "Sanskrit -- Religious Literature -- Śaiva", "Sanskrit -- Śāstra -- Philosophy -- Śaiva",
    "Sanskrit -- Religious Literature -- Vaiṣṇava", "Sanskrit -- Poetry -- Alaṃkāra",
    "Sanskrit -- Śāstra -- Āyurveda", "Sanskrit -- Purāṇa", "Sanskrit -- Śāstra -- Philosophy -- Sāṃkhya",
    "Sanskrit -- Veda -- Upaniṣad", "Sanskrit -- Śāstra -- Jyotiḥśāstra",
    "Sanskrit -- Śāstra -- Dharma -- Smṛti", "Sanskrit -- Śāstra -- Philosophy -- Nyāya",
    "Sanskrit -- Poetry -- Drama", "Sanskrit -- Veda -- Vedāṅga -- Gṛhyasūtra",
    "Sanskrit -- Śāstra -- Philosophy -- Mīmāṃsā", "Sanskrit -- Poetry -- Narrative Literature",
    "Sanskrit -- Poetry -- Subhāṣita", "Sanskrit -- Śāstra -- Grammar",
    "Sanskrit -- Śāstra -- Dharmaśāstra -- Sūtra", "Sanskrit -- Śāstra -- Philosophy -- Yoga",
    "Sanskrit -- Veda -- Saṃhitā", "Sanskrit -- Śāstra -- Kāmaśāstra",
    "Sanskrit -- Śāstra -- Philosophy -- Vaiśeṣika", "Sanskrit -- Poetry -- Chandas",
    "Sanskrit -- Epic -- Mahābhārata", "Sanskrit -- Veda -- Vedāṅga -- Śrautasūtra",
    "Sanskrit -- Veda -- Vedāṅga -- Pariśiṣṭa", "Sanskrit -- Veda -- Brāhmaṇa",
    "Sanskrit -- Śāstra -- Philosophy", "Sanskrit -- Epic -- Rāmāyaṇa",
    "Sanskrit -- Veda -- Vedāṅga -- Prātiśākhya", "Sanskrit -- Poetry -- Historical",
    "Sanskrit -- Śāstra -- Philosophy -- Advaita", "Sanskrit -- Poetry -- Nāṭya",
    "Sanskrit -- Śāstra -- Lexikography", "Sanskrit -- Religious Literature -- Jaina",
    "Sanskirt -- Religious Literature -- Śaiva", "Sanskrit -- Śāstra -- Arthaśāstra",
    "Sanskrit -- Epics -- Rāmāyaṇa", "Sanskrit -- later works -- 20th century",
    "Sanskrit -- Śāstra -- Dharma -- Nibandha", "Sanskrit -- Veda -- Āraṇyaka",
    "Manipravalam -- Vyākhyānas", "Tibetan -- Translation", "Tibetan"
  ].freeze

  def test_shipped_gretil_genre_ladder_fold
    shipped = shipped_kinds
    assert_equal ["genre"], shipped.metadata_for("gretil")
    { "Sanskrit -- Veda -- Upaniṣad" => ["scripture"],
      "Sanskrit -- Religious Literature -- Buddhist" => ["scripture"],
      "Sanskrit -- Śāstra -- Philosophy -- Buddhist" => ["literary/wisdom"],
      "Sanskrit -- Poetry -- Kāvya" => ["literary/poetry"],
      "Sanskrit -- Poetry -- Alaṃkāra" => ["literary/essay/criticism"],
      "Sanskrit -- Śāstra -- Āyurveda" => ["scholarly/medicine"],
      "Sanskrit -- Śāstra -- Dharma -- Smṛti" => ["legal/law"],
      "Sanskrit -- Veda -- Vedāṅga -- Gṛhyasūtra" => ["ritual"],
      "Sanskrit -- Epic -- Mahābhārata" => ["literary/narrative/epic"],
      "Sanskrit -- Śāstra -- Jyotiḥśāstra" => ["divination/astrology", "scholarly/astronomy"],
      "Manipravalam -- Vyākhyānas" => ["exegesis"] }.each do |value, want|
      assert_equal want, shipped.normalize("gretil", value).sort, value
    end
    assert_empty shipped.normalize("gretil", "Tibetan"), "a language shelf is a reviewed non-claim"
    GRETIL_LADDER_CENSUS.each do |value|
      refute_includes shipped.normalize("gretil", value), Nabu::Kinds::UNMAPPED, value
    end
  end

  # The ndl-kotenseki NDC fold (the bib join's ndc facet): the census
  # sample's codes, one class each, the subject-only remainder unmapped.
  def test_ndl_kotenseki_ndc_codes_fold_one_class_each
    shipped = shipped_kinds
    {
      "813.2" => ["lexical"], "221" => ["historiography"], "288.4" => ["historiography"],
      "291.36" => ["scholarly"], "911.12" => ["literary/poetry"], "921" => ["literary/poetry"],
      "913.6" => ["literary/narrative"], "991" => ["literary"], "210.46" => ["historiography"],
      "148" => ["divination"], "322" => ["legal"], "386" => ["scholarly"], "123.83" => ["scripture"],
      "490.9" => ["scholarly/medicine"], "375.9" => ["school"]
    }.each { |code, want| assert_equal want, shipped.normalize("ndl-kotenseki", code), code }
    %w[180 181 150 337.2 701.1 702.1 385 816 901].each do |code|
      assert_equal [Nabu::Kinds::UNMAPPED], shipped.normalize("ndl-kotenseki", code), code
    end
  end

  # eebo-tcp's first kind wave: the LCSH subject facet as an OPEN
  # vocabulary — form headings and form subdivisions fold onto ruled
  # heads; topical, name and about-the-form headings mint nothing.
  EEBO_FOLDS = {
    "Sermons, English -- 17th century." => ["sermon"],
    "Fast-day sermons." => ["sermon"],
    "Sermons, American -- 17th century." => ["sermon"],
    "Funeral sermons -- 17th century." => ["sermon/funeral-sermon"],
    "Church of England -- Sermons." => ["sermon"],
    "Great Britain -- History -- Civil War, 1642-1649 -- Sermons -- Early works to 1800." => ["sermon"],
    "Ballads, English -- 17th century." => ["literary/poetry"],
    "Political ballads and songs -- England -- 17th century." => ["literary/poetry"],
    "Elegiac poetry, English -- 17th century." => ["literary/poetry"],
    "English poetry -- Early modern, 1500-1700." => ["literary/poetry"],
    "Songs, English." => ["literary/poetry"],
    "Charles -- II, -- King of England, 1630-1685 -- Poetry." => ["literary/poetry"],
    "English drama -- Restoration, 1660-1700." => ["literary/drama"],
    "Masques -- Early works to 1800." => ["literary/drama"],
    "Political satire, English -- Early works to 1800." => ["literary"],
    "Prayers -- Early works to 1800." => ["hymn-prayer/prayer"],
    "Church of England -- Prayer-books and devotions." => ["hymn-prayer/prayer"],
    "Hymns, English -- Early works to 1800." => ["hymn-prayer/hymn"],
    "Europe -- History -- 1648-1715 -- Periodicals." => ["periodical"],
    "England -- Proclamations -- Early works to 1800." => ["legal/law"],
    "Proclamations -- Great Britain." => ["legal/law"],
    "Trials (Treason) -- England -- Early works to 1800." => ["legal/court"],
    "Great Britain -- History -- Civil War, 1642-1649 -- Treaties -- Early works to 1800." => ["legal/treaty"],
    "Society of Friends -- Pastoral letters and charges." => ["letter"],
    "Bible. -- N.T. -- Revelation -- Commentaries -- Early works to 1800." => ["exegesis"],
    "Latin language -- Grammar -- Early works to 1800." => ["lexical/grammar"],
    "English language -- Dictionaries -- Early works to 1700." => ["lexical"],
    "Medicine -- Early works to 1800." => ["scholarly/medicine"],
    "Medicine -- Formulae, receipts, prescriptions -- Early works to 1800." =>
      %w[scholarly/medicine scholarly/recipe],
    "Cookery -- Early works to 1800." => ["scholarly/recipe"],
    "Astronomy -- Early works to 1800." => ["scholarly/astronomy"],
    "Geometry -- Early works to 1800." => ["scholarly/mathematics"],
    "Navigation -- Early works to 1800." => ["scholarly"],
    "Astrology -- Early works to 1800." => ["divination/astrology"],
    "Prophecies -- Early works to 1800." => ["divination/oracle"],
    "Great Britain -- Biography." => ["historiography"],
    "Voyages and travels -- Early works to 1800." => ["literary/diary/travelogue"],
    "Fables -- Early works to 1800." => ["literary/narrative/fable"],
    "Proverbs, English." => ["literary/wisdom/proverbs"],
    "Dialogues, English -- Early works to 1800." => ["literary/wisdom/dialogue"],
    "Epitaphs -- England -- Early works to 1800." => ["funerary/epitaph"]
  }.freeze

  # Topical, name, and ABOUT-the-form headings: no rule covers them.
  EEBO_UNCOVERED = [
    "Great Britain -- Politics and government -- 1642-1649.",
    "Broadsides -- England -- London -- 17th century.",
    "Church of England -- Controversial literature.",
    "Sermons -- History and criticism -- England -- 17th century.",
    "Smallwood, Allan, 1608-1686. -- Sermon preached at Carlisle, Aug. 17, 1664.",
    "Prayers -- Law and legislation -- Scotland -- Early works to 1800.",
    "Prayer.",
    "Navigation acts, 1649-1696 -- Early works to 1800.",
    "Medicine -- England -- Controversial literature.",
    "Astrology -- Humor -- Early works to 1800.",
    "Proverbs in the Bible.",
    "Catechisms, English."
  ].freeze

  def test_shipped_eebo_subject_fold_is_an_open_vocabulary
    shipped = shipped_kinds
    assert shipped.open?("eebo-tcp")
    assert_equal "subject", shipped.facet_for("eebo-tcp")
    EEBO_FOLDS.each { |heading, want| assert_equal want, shipped.normalize("eebo-tcp", heading).sort, heading }
    EEBO_UNCOVERED.each do |heading|
      fold = shipped.fold("eebo-tcp", heading)
      assert_empty fold.paths, heading
      assert_equal [heading], fold.uncovered, heading
    end
  end

  def shipped_kinds
    Nabu::Kinds.load(
      classes_path: File.expand_path("../config/kind_classes.yml", __dir__),
      map_path: File.expand_path("../config/kind_map.yml", __dir__)
    )
  end
end
