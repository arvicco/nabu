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
        wired: true
        sync_policy: auto
    YAML

    entry = registry["perseus-greek"]
    assert_equal "perseus-greek", entry.slug
    assert_equal "Nabu::Adapters::Perseus", entry.adapter_class_name
    assert entry.wired
    assert_equal "auto", entry.sync_policy
    assert_equal "source", entry.kind, "kind defaults to source"
    assert_predicate entry, :source?
    assert_equal %w[perseus-greek], registry.slugs
    assert_equal 1, registry.size
    refute_predicate registry, :empty?
  end

  def test_defaults_wired_false_and_sync_policy_manual
    registry = load_registry(<<~YAML)
      minimal-src:
        adapter: Some::Adapter
    YAML

    entry = registry["minimal-src"]
    refute entry.wired
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
          wired: true
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
        wired: true
    YAML
    entry = registry["local-language"]
    assert_equal "shelf", entry.kind
    assert_predicate entry, :shelf?
    refute_predicate entry, :source?
  end

  # The P39-0 "module must be wired: false" invariant was RETIRED by the
  # owner's wired-semantics ruling (2026-08-18): wired = the sync link is
  # tested and declared working, for EVERY kind; --all participation is
  # kind + sync_policy's job. A verified module row loads wired: true.
  def test_kind_module_may_be_wired_once_its_channel_is_verified
    registry = load_registry(<<~YAML)
      kr-gaiji:
        adapter: Nabu::Adapters::KrGaiji
        kind: module
        wired: true
        sync_policy: manual
    YAML
    entry = registry["kr-gaiji"]
    assert entry.wired
    assert_predicate entry, :feature_module?
  end

  def test_kind_module_parses_when_disabled
    registry = load_registry(<<~YAML)
      kr-gaiji:
        adapter: Nabu::Adapters::KrGaiji
        kind: module
        wired: false
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
          wired: true
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/adapter/, error.message)
  end

  def test_non_boolean_wired_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          wired: yesplease
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/wired/, error.message)
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

  # -- quickstart tag (P44-r3b) --------------------------------------------

  def test_quickstart_defaults_false_and_parses_true
    registry = load_registry(<<~YAML)
      starter:
        adapter: Some::Adapter
        quickstart: true
      ordinary:
        adapter: Some::Adapter
    YAML
    assert_predicate registry["starter"], :quickstart?
    refute_predicate registry["ordinary"], :quickstart?, "absent quickstart = false"
  end

  def test_quickstart_slugs_lists_tagged_rows_in_order
    registry = load_registry(<<~YAML)
      a:
        adapter: Some::Adapter
        quickstart: true
      b:
        adapter: Some::Adapter
      c:
        adapter: Some::Adapter
        quickstart: true
    YAML
    assert_equal %w[a c], registry.quickstart_slugs
    refute_predicate registry["b"], :quickstart?
  end

  # -- multilingual pack marker (P49-r4) -----------------------------------

  def test_multilingual_defaults_false_and_parses_true
    registry = load_registry(<<~YAML)
      pack:
        adapter: Some::Adapter
        multilingual: true
      mono:
        adapter: Some::Adapter
    YAML
    assert_predicate registry["pack"], :multilingual?
    refute_predicate registry["mono"], :multilingual?, "absent multilingual = false"
  end

  def test_multilingual_rejects_non_boolean
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        pack:
          adapter: Some::Adapter
          multilingual: sometimes
      YAML
    end
    assert_match(/pack.*multilingual must be true or false/, error.message)
  end

  # The registry-level lookup the attribution surfaces read (the blocked?
  # mold): unknown slugs are not multilingual.
  # -- the CORE group (P63 rider, owner ruling 2026-08-09) -------------------

  def test_core_group_parses_and_lists_members_in_order
    registry = load_registry(<<~YAML)
      nabu-lects:
        adapter: Some::Adapter
        group: core
        kind: module
      ordinary:
        adapter: Some::Adapter
      cigs:
        adapter: Some::Adapter
        group: core
        kind: module
    YAML
    assert_equal %w[nabu-lects cigs], registry.core_members
    assert_predicate registry["nabu-lects"], :core?
    refute_predicate registry["ordinary"], :core?, "absent group = no group"
  end

  def test_an_unknown_group_is_refused_loudly
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        x:
          adapter: Some::Adapter
          group: kore
      YAML
    end
    assert_match(/group must be one of core/, error.message)
  end

  def test_the_live_registry_core_group_is_the_three_instruments
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    assert_equal %w[cigs nabu-lects nabu-places], registry.core_members.sort
    registry.core_members.each do |slug|
      assert_predicate registry[slug], :feature_module?,
                       "#{slug}: core members are modules — pre-enabled by nature, no enable dance"
    end
  end

  # -- functional sets (P77 rider, owner ruling 2026-08-13): core/signs/
  # quickstart resolvable wherever --axis takes a name ------------------------

  def functional_sets_registry
    axes = <<~YAML
      classical:
        persona: "The Classicist."
        desc: "test desk"
    YAML
    load_registry_with_axes(axes, <<~YAML)
      nabu-lects:
        adapter: Some::Adapter
        group: core
        kind: module
        axes: [classical]
      starter:
        adapter: Some::Adapter
        quickstart: true
        axes: [classical]
      ordinary:
        adapter: Some::Adapter
        axes: [classical]
    YAML
  end

  def test_functional_sets_are_the_closed_group_vocabulary_plus_quickstart
    assert_equal %w[core signs quickstart], Nabu::SourceRegistry::FUNCTIONAL_SETS
    registry = functional_sets_registry
    assert registry.functional_set?("core")
    assert registry.functional_set?("quickstart")
    refute registry.functional_set?("classical"), "desk axes are not functional sets"
  end

  def test_set_members_resolves_groups_and_the_quickstart_starter_shelf
    registry = functional_sets_registry
    assert_equal %w[nabu-lects], registry.functional_set_members("core")
    assert_equal %w[nabu-lects starter], registry.functional_set_members("quickstart"),
                 "quickstart = core + the quickstart-flagged starters, deduped"
    assert_empty registry.functional_set_members("signs")
  end

  def test_axis_or_set_member_is_the_one_membership_predicate
    registry = functional_sets_registry
    assert registry.axis_or_set_member?("core", "nabu-lects")
    refute registry.axis_or_set_member?("core", "ordinary")
    assert registry.axis_or_set_member?("quickstart", "starter")
    assert registry.axis_or_set_member?("classical", "ordinary"), "desk tags keep working"
    refute registry.axis_or_set_member?("classical", "unknown-slug")
  end

  # -- requires: the dependency chain (P77-r3, owner commission 2026-08-13:
  # "a system where these dependencies are tracked and enabling a source/
  # module that has dependencies enables all chain dependencies") ------------

  def requires_registry
    load_registry(<<~YAML)
      gaz:
        adapter: Some::Adapter
        kind: module
        wired: false
      places:
        adapter: Some::Adapter
        kind: module
        wired: false
        requires: [gaz]
      corpus:
        adapter: Some::Adapter
        requires: [places]
      loner:
        adapter: Some::Adapter
    YAML
  end

  def test_requires_parses_and_defaults_empty
    registry = requires_registry
    assert_equal %w[gaz], registry["places"].requires
    assert_equal %w[places], registry["corpus"].requires
    assert_empty registry["loner"].requires
  end

  def test_requires_closure_is_transitive_and_deduped
    registry = requires_registry
    assert_equal %w[corpus places gaz], registry.requires_closure(%w[corpus]),
                 "enabling corpus pulls the whole chain — the package-manager rule"
    assert_equal %w[loner], registry.requires_closure(%w[loner])
    assert_equal %w[corpus places loner gaz], registry.requires_closure(%w[corpus places loner]),
                 "breadth-first discovery order — named slugs first, then the chain"
  end

  def test_required_by_lists_direct_dependents
    registry = requires_registry
    assert_equal %w[places], registry.required_by("gaz")
    assert_equal %w[corpus], registry.required_by("places")
    assert_empty registry.required_by("corpus")
  end

  def test_requires_must_name_registered_slugs
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        a:
          adapter: Some::Adapter
          requires: [ghost]
      YAML
    end
    assert_match(/"a".*requires unknown source "ghost"/, error.message)
  end

  def test_requires_refuses_cycles_loudly
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        a:
          adapter: Some::Adapter
          requires: [b]
        b:
          adapter: Some::Adapter
          requires: [a]
      YAML
    end
    assert_match(/requires cycle/, error.message)
  end

  def test_requires_refuses_self_reference
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        a:
          adapter: Some::Adapter
          requires: [a]
      YAML
    end
    assert_match(/itself/, error.message)
  end

  def test_the_live_registry_seeds_the_place_layer_chain
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    assert_equal %w[cigs pleiades trismegistos-geo], registry["nabu-places"].requires.sort,
                 "the place-decisions registry resolves refs through all three gazetteer slices"
    assert_equal %w[unikemet], registry["edubba-overlay"].requires,
                 "the didactic overlay joins onto Unikemet sign entries"
    assert_equal %w[perseus-greek first1k-greek], registry["hypotactic"].requires,
                 "№R-31 ruled 2026-08-13: conjunctive over any_of machinery"
    assert_equal %w[perseus-latin], registry["pedecerto"].requires
    assert_equal %w[bridging], registry["bhsa"].requires,
                 "the one parse-time cross-source canonical read (P77-r4)"
  end

  # -- the signs group (P69: `nabu enable signs && nabu sync signs` restores
  # the whole sign/char capability) --------------------------------------------

  def test_group_members_answers_any_registered_group
    registry = load_registry(<<~YAML)
      a:
        adapter: Some::Adapter
        group: signs
      b:
        adapter: Some::Adapter
      c:
        adapter: Some::Adapter
        group: signs
        kind: module
    YAML
    assert_equal %w[a c], registry.group_members("signs")
    assert_empty registry.group_members("core")
  end

  def test_the_live_signs_group_is_the_full_sign_shelf_census
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    # The census pin IS the restore guarantee: a new sign/char shelf must
    # join the group or this pin fires. Modules (osl, unikemet) carry the
    # identity spines; the sources carry the Han card's shelves, the
    # reading lanes, and the Wiktionary sense lane.
    assert_equal %w[babelstone-ids baxter-sagart edrdg edubba-overlay hdic kradfile osl tls
                    tshet-uinh unihan unikemet wiktionary-sux],
                 registry.group_members("signs").sort
    modules = registry.group_members("signs").select { |s| registry[s].feature_module? }
    assert_equal %w[edubba-overlay osl unikemet], modules.sort,
                 "the two identity spines + the didactic overlay are the modules"
  end

  def test_registry_multilingual_lookup_by_slug
    registry = load_registry(<<~YAML)
      pack:
        adapter: Some::Adapter
        multilingual: true
      mono:
        adapter: Some::Adapter
    YAML
    assert registry.multilingual?("pack")
    refute registry.multilingual?("mono")
    refute registry.multilingual?("nope"), "an unknown slug is not multilingual"
  end

  # -- availability (P44-r3a) ----------------------------------------------

  def test_availability_defaults_public
    entry = load_registry(<<~YAML)["minimal-src"]
      minimal-src:
        adapter: Some::Adapter
    YAML
    assert_equal "public", entry.availability, "absent availability = public"
    refute_predicate entry, :blocked?
    assert_predicate entry, :public?
  end

  def test_availability_blocked_parses
    entry = load_registry(<<~YAML)["gated-src"]
      gated-src:
        adapter: Some::Adapter
        availability: blocked
    YAML
    assert_equal "blocked", entry.availability
    assert_predicate entry, :blocked?
    refute_predicate entry, :public?
  end

  def test_unknown_availability_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        gated-src:
          adapter: Some::Adapter
          availability: hidden
      YAML
    end
    assert_match(/gated-src/, error.message)
    assert_match(/availability must be one of public, blocked/, error.message)
  end

  # #public_axis_members / #blocked_axis_members / #blocked? — the seams the
  # public site + docs surfaces read (blocked rows excluded), while
  # #axis_members stays the full list for the CLI/sync scopes.
  def test_public_axis_members_excludes_blocked_while_axis_members_keeps_them
    registry = load_registry_with_axes(TWO_AXES, <<~YAML)
      corph-src:
        adapter: A
        axes: [celtic]
      gated-src:
        adapter: B
        axes: [celtic]
        availability: blocked
    YAML
    assert_equal %w[corph-src gated-src], registry.axis_members("celtic"),
                 "axis_members keeps the full membership (CLI/sync scope)"
    assert_equal %w[corph-src], registry.public_axis_members("celtic"),
                 "public_axis_members drops the blocked row"
    assert_equal %w[gated-src], registry.blocked_axis_members("celtic")
    assert registry.blocked?("gated-src")
    refute registry.blocked?("corph-src")
    refute registry.blocked?("nonexistent"), "unknown slug is not blocked"
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
  # P44-r3c: the shipped starter shelf carries the quickstart tags — a
  # fresh box's default enabled set is exactly the quickstart four.
  def test_shipped_quickstart_tags_are_the_starter_shelf
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    assert_equal %w[iswoc lexica proiel sblgnt], registry.quickstart_slugs.sort
  end

  def test_shipped_registry_mapping_is_valid_and_ratified
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))

    assert_equal %w[classical romance epigraphy slavic germanic celtic italic etym biblical hebrew
                    syriac ethiopic arabic hittite cuneiform egyptian iranian indic buddhist tibetan
                    korean sea sinitic japonic local],
                 registry.axes.names,
                 "the ratified axes, in render order (18 ratified D35 + arabic minted P41-2 with " \
                 "the openiti row + iranian minted P44-r2/D43-d, the Avesta desk between egyptian " \
                 "and indic — the Indo-Iranian pair + romance minted P45-r1, owner ruling " \
                 "2026-07-25, beside classical — the Latin continuum pair + ethiopic minted " \
                 "P46-2/D46-c, owner-ratified 2026-07-26, after syriac — the Oriental-Christian " \
                 "neighborhood + tibetan minted P48-1 with the Derge canon rows, per the " \
                 "owner-ordered P47-s2 survey, after buddhist — its nearest neighbor + korean " \
                 "minted P78-1 with sillok, per the owner-adopted P47-s4 survey, before sinitic " \
                 "— the sinoverse neighborhood + sea minted P92-1 with dharma-khmer, №R-58 " \
                 "ruled (a) 2026-09-01 per the P47-s3 survey, after korean — the Indic " \
                 "cosmopolis's eastern edge beside the sinoverse)"

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
    # The Librarian's five local shelves, and nothing else (P84-1 added
    # the machine-grain local-lemmas shelf).
    assert_equal %w[local-language local-lemmas local-library local-notes local-source],
                 registry.axis_members("local").sort
    # Manifest-verified corrections vs the draft table (see the P35-0 report):
    assert_includes registry["ud"].axes, "sinitic", "UD ships two lzh treebanks (P32-0)"
    assert_includes(registry["ud"].axes, "celtic", "UD ships two sga treebanks")
    assert_includes registry["suttacentral"].axes, "sinitic", "the lzh Agamas (P32-1)"
    assert_equal registry["lexlep"].axes, registry["lexlep-words"].axes,
                 "the two grains of one wiki share their desks"

    # P44-r2 (D43-d): the `iranian` desk. Evidence-ruled membership — the Avesta
    # anchor (blocked, still on etym too) plus the Old Persian lane of oracc/cdli,
    # whole-source and dual-tagged with cuneiform. The blocked anchor drops from
    # the PUBLIC membership; oracc/cdli are the public shelves, in registry order.
    assert_equal %w[etym iranian], registry["titus-avestan"].axes,
                 "the Avesta anchors iranian and keeps etym (its forms feed the comparative shelves)"
    assert_includes registry["oracc"].axes, "iranian", "ORACC's ario = Old Persian Achaemenid trilinguals"
    assert_includes registry["cdli"].axes, "iranian", "CDLI catalogs Old Persian (peo) Achaemenid trilinguals"
    assert_includes registry["oracc"].axes, "cuneiform", "still whole-source on the tablet desk"
    assert_equal %w[oracc cdli perseus-farsilit], registry.public_axis_members("iranian"),
                 "the public iranian shelves, in registry order (the blocked Avesta is not advertised)"
    assert_equal %w[titus-avestan], registry.blocked_axis_members("iranian"),
                 "the grant-gated Avesta rides iranian but is excluded from the public listing"
  end

  # P43-2: the shipped TITUS Avestan row is fetch-gated on the personal grant, and
  # its refusal notice is the on-ramp (terms + whom to ask), never a bare wall.
  def test_shipped_titus_avestan_is_grant_gated_with_the_on_ramp
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["titus-avestan"]

    assert_predicate entry, :grant_required?
    assert_equal "2026-07-23", entry.grant.date
    assert_equal "personal research grant of 2026-07-23", entry.grant.thread
    assert_match(/Gippert/, entry.grant.grantor)
    assert_match(/non-commercial/, entry.grant.terms)

    notice = Nabu::GrantGate.notice(entry)
    assert_match(/titus-avestan: fetch requires a GRANT/, notice)
    assert_match(/request your own:/, notice, "the refusal points at the request scaffold")
    assert_match(/Gippert/, notice)
  end

  # P44-r3a: the fetch right is a PRIVATE personal grant, so the public repo
  # must not advertise the row as a library holding — availability: blocked
  # excludes it from public docs/site/census, and etym's public membership
  # drops it (while the full axis_members list keeps it for CLI/sync scopes).
  def test_shipped_titus_avestan_is_blocked_and_dropped_from_public_etym
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))

    assert_predicate registry["titus-avestan"], :blocked?
    assert registry.blocked?("titus-avestan")
    assert_includes registry.axis_members("etym"), "titus-avestan",
                    "the full membership (CLI/sync scope) still carries it"
    refute_includes registry.public_axis_members("etym"), "titus-avestan",
                    "the PUBLIC etym membership drops the grant-gated row"
    assert_equal %w[titus-avestan titus-osco-umbrian], registry.blocked_axis_members("etym")
  end

  # The manifest's display posture: nc (servable + credited, not hidden) and a
  # verbatim credit line the serving surfaces render (the grant's display duty).
  def test_shipped_titus_avestan_manifest_is_nc_and_credited
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    manifest = registry["titus-avestan"].manifest

    assert_equal "nc", manifest.license_class
    refute_nil manifest.credit
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Gippert/, manifest.credit)
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
        wired: true
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
        wired: true
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

  # -- fetch-grant keys (P42-r1) -------------------------------------------

  def test_grant_absent_by_default
    entry = load_registry(<<~YAML)["src"]
      src:
        adapter: FakeAdapter
        wired: true
    YAML
    refute_predicate entry, :grant_required?
    assert_nil entry.grant
  end

  def test_parses_a_valid_grant_block
    entry = load_registry(<<~YAML)["src"]
      src:
        adapter: FakeAdapter
        wired: true
        grant_required: true
        grant:
          grantor: G. Starostin
          date: "2026-07-15"
          terms: any use, per-base attribution required
          thread: "№1"
          request_hint: write to George Starostin for your own grant
    YAML
    assert_predicate entry, :grant_required?
    assert_equal "G. Starostin", entry.grant.grantor
    assert_equal "2026-07-15", entry.grant.date
    assert_equal "any use, per-base attribution required", entry.grant.terms
    assert_equal "№1", entry.grant.thread
    assert_match(/your own grant/, entry.grant.request_hint)
  end

  def test_grant_required_without_a_block_is_an_error
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        src:
          adapter: FakeAdapter
          wired: true
          grant_required: true
      YAML
    end
    assert_match(/grant_required: true needs a grant: block/, error.message)
  end

  def test_a_grant_block_without_the_flag_is_an_error
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        src:
          adapter: FakeAdapter
          wired: true
          grant:
            grantor: X
            date: "2026-07-15"
            terms: t
            thread: "№1"
            request_hint: ask
      YAML
    end
    assert_match(/grant: block requires grant_required: true/, error.message)
  end

  def test_grant_block_missing_a_field_is_an_error
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        src:
          adapter: FakeAdapter
          wired: true
          grant_required: true
          grant:
            grantor: X
            date: "2026-07-15"
            terms: t
            request_hint: ask
      YAML
    end
    assert_match(/grant\.thread must be a non-empty string/, error.message)
  end

  def test_an_unquoted_date_is_rejected_at_yaml_load
    # A bare 2026-07-15 is a YAML Date, not a String — and the registry's
    # YAML.safe_load refuses the Date class outright, so an unquoted grant date
    # never even reaches the entry validator. Quoting keeps it a String the
    # gate can render verbatim; this proves the guard rail exists.
    assert_raises(Psych::DisallowedClass) do
      load_registry(<<~YAML)
        src:
          adapter: FakeAdapter
          wired: true
          grant_required: true
          grant:
            grantor: X
            date: 2026-07-15
            terms: t
            thread: "№1"
            request_hint: ask
      YAML
    end
  end

  def test_a_non_string_grant_field_is_a_validation_error
    # The belt-and-suspenders: even if a non-String slipped past YAML load
    # (e.g. a numeric thread), grant_field! names the offending key.
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        src:
          adapter: FakeAdapter
          wired: true
          grant_required: true
          grant:
            grantor: X
            date: "2026-07-15"
            terms: t
            thread: 1
            request_hint: ask
      YAML
    end
    assert_match(/grant\.thread must be a non-empty string/, error.message)
  end

  def test_shipped_starling_row_carries_the_grant
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    starling = registry["starling"]
    assert_predicate starling, :grant_required?, "starling arms the grant gate"
    assert_equal "G. Starostin", starling.grant.grantor
    # hdic's license contradiction was owner-resolved (GO, 2026-07-20) — NOT gated.
    refute_predicate registry["hdic"], :grant_required?, "hdic was resolved, not gated"
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
