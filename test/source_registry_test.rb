# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class SourceRegistryTest < Minitest::Test
  include StoreTestDB

  # A resolvable adapter for the lazy-resolution and sync_source! paths. Named
  # at the top level so "FakeAdapter" resolves via Object.const_get.
  class FakeAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "fake-src", name: "Fake Source", license: "CC BY 4.0",
      license_class: "attribution", upstream_url: "https://example.invalid/fake",
      parser_family: "plaintext"
    )

    def self.manifest
      MANIFEST
    end
  end

  # -- parsing -------------------------------------------------------------

  def test_parses_entry_with_all_fields
    registry = load_registry(<<~YAML)
      perseus-greek:
        adapter: Nabu::Adapters::Perseus
        enabled: true
        sync_policy: auto
    YAML

    entry = registry["perseus-greek"]
    assert_equal "perseus-greek", entry.slug
    assert_equal "Nabu::Adapters::Perseus", entry.adapter_class_name
    assert entry.enabled
    assert_equal "auto", entry.sync_policy
    assert_equal "source", entry.kind, "kind defaults to source"
    assert_predicate entry, :source?
    assert_equal %w[perseus-greek], registry.slugs
    assert_equal 1, registry.size
    refute_predicate registry, :empty?
  end

  def test_defaults_enabled_false_and_sync_policy_manual
    registry = load_registry(<<~YAML)
      minimal-src:
        adapter: Some::Adapter
    YAML

    entry = registry["minimal-src"]
    refute entry.enabled
    assert_equal "manual", entry.sync_policy
  end

  def test_each_source_yields_every_entry
    registry = load_registry(<<~YAML)
      a-src:
        adapter: A
      b-src:
        adapter: B
    YAML

    assert_equal %w[a-src b-src], registry.each_source.map(&:slug).sort
  end

  # -- empty / missing -----------------------------------------------------

  def test_missing_file_is_empty_valid_registry
    Dir.mktmpdir do |dir|
      registry = Nabu::SourceRegistry.load(File.join(dir, "does-not-exist.yml"))
      assert_predicate registry, :empty?
      assert_equal 0, registry.size
    end
  end

  def test_comments_only_file_is_empty_valid_registry
    registry = load_registry("# only comments here\n")
    assert_predicate registry, :empty?
  end

  # -- validation ----------------------------------------------------------

  def test_bad_slug_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        Bad Slug:
          adapter: A
      YAML
    end
    assert_match(/Bad Slug/, error.message)
    assert_match(/slug/, error.message)
  end

  # P39-0: the `local` sync_policy is GONE — a no-upstream shelf is kind: shelf,
  # which implies the local fetch strategy and declares no sync_policy.
  def test_sync_policy_local_is_rejected
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        local-language:
          adapter: Nabu::Adapters::LocalLanguage
          kind: shelf
          enabled: true
          sync_policy: local
      YAML
    end
    assert_match(/local-language/, error.message)
    assert_match(/local fetch strategy|drop sync_policy/, error.message)
  end

  # P39-0: kind: shelf parses, reads shelf?, and (with no sync_policy) the
  # internal default is manual — never rendered or swept for a shelf.
  def test_kind_shelf_parses_and_forbids_sync_policy
    registry = load_registry(<<~YAML)
      local-language:
        adapter: Nabu::Adapters::LocalLanguage
        kind: shelf
        enabled: true
    YAML
    entry = registry["local-language"]
    assert_equal "shelf", entry.kind
    assert_predicate entry, :shelf?
    refute_predicate entry, :source?
  end

  # P39-0: a kind: module mints no catalog rows, so it MUST be enabled: false.
  def test_kind_module_must_be_disabled
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        kr-gaiji:
          adapter: Nabu::Adapters::KrGaiji
          kind: module
          enabled: true
          sync_policy: manual
      YAML
    end
    assert_match(/kr-gaiji/, error.message)
    assert_match(/module.*enabled: false|mints no catalog rows/, error.message)
  end

  def test_kind_module_parses_when_disabled
    registry = load_registry(<<~YAML)
      kr-gaiji:
        adapter: Nabu::Adapters::KrGaiji
        kind: module
        enabled: false
        sync_policy: manual
    YAML
    entry = registry["kr-gaiji"]
    assert_equal "module", entry.kind
    assert_predicate entry, :feature_module?
  end

  def test_unknown_kind_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          kind: widget
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/kind must be one of/, error.message)
  end

  def test_bad_sync_policy_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          sync_policy: weekly
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/sync_policy/, error.message)
  end

  def test_non_hash_entry_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src: just-a-string
      YAML
    end
    assert_match(/my-src/, error.message)
  end

  def test_missing_adapter_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          enabled: true
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/adapter/, error.message)
  end

  def test_non_boolean_enabled_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          enabled: yesplease
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/enabled/, error.message)
  end

  def test_top_level_non_mapping_raises
    assert_raises(Nabu::ValidationError) do
      load_registry("- just\n- a\n- list\n")
    end
  end

  # -- translations flag (P7-4) ---------------------------------------------

  def test_translations_defaults_false
    entry = load_registry(<<~YAML)["minimal-src"]
      minimal-src:
        adapter: Some::Adapter
    YAML
    refute entry.translations
  end

  def test_translations_flag_parses_true
    entry = load_registry(<<~YAML)["perseus-greek"]
      perseus-greek:
        adapter: Nabu::Adapters::Perseus
        translations: true
    YAML
    assert entry.translations
  end

  def test_non_boolean_translations_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          translations: sure
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/translations/, error.message)
  end

  # -- license_watch (P16-5) -------------------------------------------------

  def test_license_watch_defaults_nil
    entry = load_registry(<<~YAML)["minimal-src"]
      minimal-src:
        adapter: Some::Adapter
    YAML
    assert_nil entry.license_watch
  end

  def test_license_watch_parses_an_https_url
    entry = load_registry(<<~YAML)["ccmh"]
      ccmh:
        adapter: Nabu::Adapters::Ccmh
        license_watch: https://www.kielipankki.fi/download/ccmh-src/README.txt
    YAML
    assert_equal "https://www.kielipankki.fi/download/ccmh-src/README.txt", entry.license_watch
  end

  def test_non_url_license_watch_raises_naming_the_slug
    ["yes", true, 42, "ftp://x.example/f", ""].each do |bad|
      error = assert_raises(Nabu::ValidationError, "#{bad.inspect} must be rejected") do
        load_registry(<<~YAML)
          my-src:
            adapter: A
            license_watch: #{bad.inspect}
        YAML
      end
      assert_match(/my-src/, error.message)
      assert_match(/license_watch/, error.message)
    end
  end

  # -- fuzzy_index flag (P16-4) ----------------------------------------------

  def test_fuzzy_index_defaults_false_and_fuzzy_slugs_lists_only_flagged
    registry = load_registry(<<~YAML)
      literary-src:
        adapter: A
      papyri-src:
        adapter: B
        fuzzy_index: true
      tablets-src:
        adapter: C
        fuzzy_index: true
    YAML
    refute registry["literary-src"].fuzzy_index
    assert registry["papyri-src"].fuzzy_index
    assert_equal %w[papyri-src tablets-src], registry.fuzzy_slugs
  end

  def test_non_boolean_fuzzy_index_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          fuzzy_index: documentary
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/fuzzy_index/, error.message)
  end

  # -- lemma_tier (P26-0) ----------------------------------------------------
  # ABSENT = gold: every existing registry entry keeps gold semantics with
  # zero churn; a source whose lemmatization is AUTOMATIC declares
  # `lemma_tier: silver` and its rows are labeled all the way to the render.

  def test_lemma_tier_defaults_gold_and_lemma_tiers_maps_only_non_gold
    registry = load_registry(<<~YAML)
      treebank-src:
        adapter: A
      diorisis-src:
        adapter: B
        lemma_tier: silver
      explicit-gold-src:
        adapter: C
        lemma_tier: gold
    YAML
    assert_equal "gold", registry["treebank-src"].lemma_tier
    assert_equal "silver", registry["diorisis-src"].lemma_tier
    assert_equal "gold", registry["explicit-gold-src"].lemma_tier
    assert_equal({ "diorisis-src" => "silver" }, registry.lemma_tiers,
                 "absent-is-gold is the wire format: only non-gold sources are mapped")
  end

  # P34-3: the third tier. "equivalence" is scholar-curated cross-language
  # equivalence (CEIPoM's Classical-Latin-equivalent column) — a DIFFERENT
  # honesty from silver (upstream-automatic), so it is its own label, never
  # folded into either existing tier.
  def test_lemma_tier_equivalence_accepted_and_mapped_as_non_gold
    registry = load_registry(<<~YAML)
      ceipom-src:
        adapter: A
        lemma_tier: equivalence
    YAML
    assert_equal "equivalence", registry["ceipom-src"].lemma_tier
    assert_equal({ "ceipom-src" => "equivalence" }, registry.lemma_tiers,
                 "equivalence rides the same non-gold wire format as silver")
  end

  def test_unknown_lemma_tier_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          lemma_tier: bronze
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/lemma_tier/, error.message)
  end

  # -- build_adapter ---------------------------------------------------------

  def test_build_adapter_with_flag_off_is_plain_no_arg_construction
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
    YAML
    assert_instance_of FakeAdapter, entry.build_adapter
  end

  def test_build_adapter_passes_translations_to_a_supporting_adapter
    entry = load_registry(<<~YAML)["perseus-greek"]
      perseus-greek:
        adapter: Nabu::Adapters::Perseus
        translations: true
    YAML

    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-eng2.xml"))
      refs = entry.build_adapter.discover(dir).to_a
      assert_equal %w[urn:cts:greekLit:tlg9999.tlg001.perseus-eng2
                      urn:cts:greekLit:tlg9999.tlg001.perseus-grc2], refs.map(&:id)
    end
  end

  def test_build_adapter_translations_on_an_unsupporting_adapter_raises
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
        translations: true
    YAML

    error = assert_raises(Nabu::ValidationError) { entry.build_adapter }
    assert_match(/fake-src/, error.message)
    assert_match(/translations/, error.message)
    assert_match(/FakeAdapter/, error.message)
  end

  # -- classes list (P33-0, the many-repo scope) ----------------------------

  def test_classes_defaults_nil
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
    YAML
    assert_nil entry.classes
  end

  def test_classes_parses_a_list_of_strings
    entry = load_registry(<<~YAML)["kanripo"]
      kanripo:
        adapter: Nabu::Adapters::Kanripo
        classes: [KR1, KR3, KR4]
    YAML
    assert_equal %w[KR1 KR3 KR4], entry.classes
  end

  def test_non_list_classes_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        kanripo:
          adapter: Nabu::Adapters::Kanripo
          classes: KR1
      YAML
    end
    assert_match(/kanripo/, error.message)
    assert_match(/classes/, error.message)
  end

  def test_empty_or_non_string_classes_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        kanripo:
          adapter: Nabu::Adapters::Kanripo
          classes: []
      YAML
    end
    assert_match(/classes/, error.message)

    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        kanripo:
          adapter: Nabu::Adapters::Kanripo
          classes: [1, 2]
      YAML
    end
    assert_match(/classes/, error.message)
  end

  # -- siblings (P34-0: the --parallel work-pattern seam) -------------------

  def test_siblings_defaults_nil
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
    YAML
    assert_nil entry.siblings
  end

  def test_siblings_parses_a_list_of_tail_patterns
    entry = load_registry(<<~YAML)["itant"]
      itant:
        adapter: Nabu::Adapters::Itant
        siblings: ["-(eng|ita|dipl)"]
    YAML
    assert_equal ["-(eng|ita|dipl)"], entry.siblings
  end

  def test_siblings_parses_the_cts_marker
    entry = load_registry(<<~YAML)["perseus-greek"]
      perseus-greek:
        adapter: Nabu::Adapters::Perseus
        siblings: cts
    YAML
    assert_equal "cts", entry.siblings
  end

  def test_non_cts_scalar_siblings_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        damaskini:
          adapter: Nabu::Adapters::Damaskini
          siblings: "-en"
      YAML
    end
    assert_match(/damaskini/, error.message)
    assert_match(/siblings/, error.message)
  end

  def test_empty_or_tailless_siblings_list_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        damaskini:
          adapter: Nabu::Adapters::Damaskini
          siblings: []
      YAML
    end
    assert_match(/siblings/, error.message)

    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        damaskini:
          adapter: Nabu::Adapters::Damaskini
          siblings: ["en"]
      YAML
    end
    assert_match(/siblings/, error.message)
    assert_match(/"en"/, error.message)
  end

  def test_unparseable_sibling_tail_regex_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        damaskini:
          adapter: Nabu::Adapters::Damaskini
          siblings: ["-(en"]
      YAML
    end
    assert_match(/damaskini/, error.message)
    assert_match(/siblings/, error.message)
  end

  def test_build_adapter_passes_classes_to_a_supporting_adapter
    entry = load_registry(<<~YAML)["kanripo"]
      kanripo:
        adapter: Nabu::Adapters::Kanripo
        classes: [KR1]
    YAML

    adapter = entry.build_adapter
    assert_instance_of Nabu::Adapters::Kanripo, adapter
    assert_equal ["KR1"], adapter.classes
  end

  def test_build_adapter_classes_on_an_unsupporting_adapter_raises
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
        classes: [KR1]
    YAML

    error = assert_raises(Nabu::ValidationError) { entry.build_adapter }
    assert_match(/fake-src/, error.message)
    assert_match(/classes/, error.message)
  end

  # -- research axes (P35-0: the axes registry seam) ------------------------
  # Definitions live in config/axes.yml (AxisRegistryTest); membership is a
  # list-valued `axes:` key on every source row. Three load-time invariants:
  # every source declares >= 1 axis (once definitions exist), every declared
  # axis exists in the definitions, and axis names NEVER collide with source
  # slugs — the resolution guarantee for the future `nabu sync <axis>` /
  # `list --axis` surfaces (P35-1/2).

  TWO_AXES = <<~YAML
    classical:
      persona: "The Classicist."
      desc: "Greco-Roman letters."
    celtic:
      persona: "The Celticist."
      desc: "From Lepontic stones to the glossators."
  YAML

  def test_axes_default_empty_when_no_definitions_file
    entry = load_registry(<<~YAML)["minimal-src"]
      minimal-src:
        adapter: Some::Adapter
    YAML
    assert_equal [], entry.axes, "bootstrap/test mode: no axes.yml, no axes required"
  end

  def test_axes_parse_from_the_sibling_definitions_file
    registry = load_registry_with_axes(TWO_AXES, <<~YAML)
      corph-src:
        adapter: A
        axes: [celtic]
      lexica-src:
        adapter: B
        axes: [classical, celtic]
    YAML
    assert_equal %w[celtic], registry["corph-src"].axes
    assert_equal %w[classical celtic], registry["lexica-src"].axes
    assert_equal %w[classical celtic], registry.axes.names, "the definitions ride the registry"
  end

  def test_axis_members_lists_slugs_in_registration_order
    registry = load_registry_with_axes(TWO_AXES, <<~YAML)
      corph-src:
        adapter: A
        axes: [celtic]
      lexica-src:
        adapter: B
        axes: [classical, celtic]
    YAML
    assert_equal %w[corph-src lexica-src], registry.axis_members("celtic")
    assert_equal %w[lexica-src], registry.axis_members("classical")
    assert_equal [], registry.axis_members("nonexistent")
  end

  def test_source_without_axes_raises_once_definitions_exist
    error = assert_raises(Nabu::ValidationError) do
      load_registry_with_axes(TWO_AXES, <<~YAML)
        bare-src:
          adapter: A
      YAML
    end
    assert_match(/bare-src/, error.message)
    assert_match(/at least one/, error.message)
  end

  def test_empty_or_non_list_axes_raises_naming_the_slug
    ["axes: []", "axes: classical", "axes: [1]"].each do |bad|
      error = assert_raises(Nabu::ValidationError, "#{bad.inspect} must be rejected") do
        load_registry_with_axes(TWO_AXES, <<~YAML)
          my-src:
            adapter: A
            #{bad}
        YAML
      end
      assert_match(/my-src/, error.message)
      assert_match(/axes/, error.message)
    end
  end

  def test_duplicate_axes_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry_with_axes(TWO_AXES, <<~YAML)
        my-src:
          adapter: A
          axes: [celtic, celtic]
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/duplicate/, error.message)
  end

  def test_unknown_axis_raises_naming_slug_and_axis
    error = assert_raises(Nabu::ValidationError) do
      load_registry_with_axes(TWO_AXES, <<~YAML)
        my-src:
          adapter: A
          axes: [classical, sinitic]
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/sinitic/, error.message)
    assert_match(/unknown axis/, error.message)
  end

  def test_axis_name_colliding_with_a_source_slug_is_a_load_error
    error = assert_raises(Nabu::ValidationError) do
      load_registry_with_axes(TWO_AXES, <<~YAML)
        celtic:
          adapter: A
          axes: [classical]
      YAML
    end
    assert_match(/celtic/, error.message)
    assert_match(/collide/, error.message)
  end

  # The shipped registry: the owner-ratified 18-axis set over all 80 sources.
  # Loading the REAL config enforces all three invariants on the real mapping;
  # the pins below freeze the ratified structure (definitions order, the D35-d
  # dual-tagging ruling, the whole-source memberships).
  def test_shipped_registry_mapping_is_valid_and_ratified
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))

    assert_equal %w[classical epigraphy slavic germanic celtic italic etym biblical hebrew
                    syriac arabic hittite cuneiform egyptian indic buddhist sinitic japonic local],
                 registry.axes.names,
                 "the ratified axes, in render order (18 ratified D35 + arabic, minted P41-2 " \
                 "with the openiti row — registry validation requires the definition; " \
                 "the axis build-out is P41-4)"

    registry.each_source do |entry|
      refute_empty entry.axes, "#{entry.slug} must declare at least one research axis"
    end
    registry.axes.names.each do |axis|
      refute_empty registry.axis_members(axis), "axis #{axis} must have at least one member"
      assert registry.axes[axis].persona.start_with?("The "),
             "axis #{axis}: persona is first-class render data (the hat, house voice)"
    end

    # D35-d: tlhdig rides BOTH cuneiform AND hittite — dual-tagging over folding.
    assert_includes registry["tlhdig"].axes, "cuneiform"
    assert_includes registry["tlhdig"].axes, "hittite"
    # The hebrew/biblical coexistence is BY DESIGN (D35-a): cross-language hat + language desk.
    assert_equal %w[biblical hebrew], registry["oshb"].axes.sort
    assert_equal %w[biblical hebrew], registry["bridging"].axes.sort, "the feature module rides its host's desks"
    # The Librarian's four local shelves, and nothing else.
    assert_equal %w[local-language local-library local-notes local-source],
                 registry.axis_members("local").sort
    # Manifest-verified corrections vs the draft table (see the P35-0 report):
    assert_includes registry["ud"].axes, "sinitic", "UD ships two lzh treebanks (P32-0)"
    assert_includes(registry["ud"].axes, "celtic", "UD ships two sga treebanks")
    assert_includes registry["suttacentral"].axes, "sinitic", "the lzh Agamas (P32-1)"
    assert_equal registry["lexlep"].axes, registry["lexlep-words"].axes,
                 "the two grains of one wiki share their desks"
  end

  # -- lazy adapter resolution --------------------------------------------

  def test_unknown_adapter_class_is_lazy
    # Loading succeeds even though the class does not exist...
    registry = load_registry(<<~YAML)
      ghost-src:
        adapter: Nabu::Adapters::DoesNotExist
    YAML
    entry = registry["ghost-src"]

    # ...the error only surfaces on resolution, and names class + source.
    error = assert_raises(Nabu::ValidationError) { entry.adapter_class }
    assert_match(/unknown adapter class/, error.message)
    assert_match(/Nabu::Adapters::DoesNotExist/, error.message)
    assert_match(/ghost-src/, error.message)
  end

  def test_adapter_class_and_manifest_resolve_for_real_adapter
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
    YAML

    assert_equal FakeAdapter, entry.adapter_class
    assert_equal "Fake Source", entry.manifest.name
  end

  # -- sync_source! --------------------------------------------------------

  def test_sync_source_creates_row_from_manifest
    db = store_test_db
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
        enabled: true
    YAML

    source = entry.sync_source!(db)
    assert_equal "fake-src", source.slug
    assert_equal "Fake Source", source.name
    assert_equal "SourceRegistryTest::FakeAdapter", source.adapter_class
    assert_equal "CC BY 4.0", source.license
    assert_equal "attribution", source.license_class
    assert_equal "https://example.invalid/fake", source.upstream_url
    assert source.enabled, "enabled seeds from the registry entry on create"
  end

  # Spec REVISED 2026-07-04 (owner sign-off workflow): the registry yaml is
  # authoritative for `enabled` — the owner flips it there with a sign-off
  # comment, and `sync --all` already reads the yaml. The db mirrors it on
  # every reconcile (the original "db owns enabled" split left status showing
  # stale rows forever). Sync history (last_sync_*) stays db-owned.
  def test_sync_source_reconciles_enabled_from_registry_preserving_history
    db = store_test_db
    Nabu::Store::Source.create(
      slug: "fake-src", name: "STALE NAME", adapter_class: "Stale",
      license_class: "restricted", enabled: false, last_sync_sha: "deadbeef"
    )
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
        enabled: true
    YAML

    source = entry.sync_source!(db)
    # metadata refreshed from the manifest...
    assert_equal "Fake Source", source.name
    assert_equal "attribution", source.license_class
    # ...enabled reconciled from the registry (the owner's flip lands)...
    assert source.enabled, "a registry enabled flip must reach the db row"
    # ...sync history (db-owned) preserved.
    assert_equal "deadbeef", source.last_sync_sha
    assert_equal 1, Nabu::Store::Source.count
  end

  private

  def load_registry(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sources.yml")
      File.write(path, yaml)
      return Nabu::SourceRegistry.load(path)
    end
  end

  # P35-0: axes.yml is the sources.yml SIBLING — writing both into one tmpdir
  # exercises the default wiring (no explicit axes_path at any call site).
  def load_registry_with_axes(axes_yaml, sources_yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "axes.yml"), axes_yaml)
      path = File.join(dir, "sources.yml")
      File.write(path, sources_yaml)
      return Nabu::SourceRegistry.load(path)
    end
  end
end
