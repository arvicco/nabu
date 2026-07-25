# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The registry-aware half of the focus profile (P40-f): resolution (names →
# axes/sources/unknown, union + dedupe), the filtered View (shelves always,
# modules --all-only, --all/empty pass-through), write validation, and the
# honesty-line strings.
class FocusTest < Minitest::Test
  # rem + helipad ride germanic; ccmh + lib1 (a shelf) ride slavic; lex rides
  # reference; mod1 is a MODULE tagged germanic (so an axis can drag one in).
  AXES = <<~YAML
    germanic:
      persona: "The Germanicist."
      desc: "Old Germanic."
    slavic:
      persona: "The Slavicist."
      desc: "OCS and kin."
    reference:
      persona: "The Lexicographer."
      desc: "Dictionaries."
  YAML

  SOURCES = <<~YAML
    rem:
      adapter: Nabu::Adapters::UniversalDependencies
      wired: true
      sync_policy: manual
      axes: [germanic]
    helipad:
      adapter: Nabu::Adapters::UniversalDependencies
      wired: true
      sync_policy: manual
      axes: [germanic]
    ccmh:
      adapter: Nabu::Adapters::UniversalDependencies
      wired: true
      sync_policy: manual
      axes: [slavic]
    lex:
      adapter: Nabu::Adapters::UniversalDependencies
      wired: true
      sync_policy: frozen
      axes: [reference]
    lib1:
      adapter: Nabu::Adapters::UniversalDependencies
      wired: true
      kind: shelf
      axes: [slavic]
    mod1:
      adapter: Nabu::Adapters::UniversalDependencies
      wired: false
      kind: module
      axes: [germanic]
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "axes.yml"), AXES)
    path = File.join(@dir, "sources.yml")
    File.write(path, SOURCES)
    @registry = Nabu::SourceRegistry.load(path)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def profile(*names) = Nabu::Profile.new(names)

  # -- resolution -------------------------------------------------------------

  def test_resolution_splits_axes_sources_and_unknowns
    res = Nabu::Focus.resolve(profile("germanic", "ccmh", "bogus"), @registry)
    assert_equal %w[germanic], res.axes
    assert_equal %w[ccmh], res.sources
    assert_equal %w[bogus], res.unknown
  end

  def test_resolution_unions_axis_members_with_named_sources
    # germanic → rem, helipad, mod1 ; plus the named source ccmh.
    res = Nabu::Focus.resolve(profile("germanic", "ccmh"), @registry)
    assert_equal %w[rem helipad mod1 ccmh lib1].sort, res.slugs.sort,
                 "axis members + named sources + shelves (implicitly always enabled)"
  end

  def test_resolution_dedupes_axis_source_overlap
    # rem is a germanic member AND named explicitly — it appears once.
    res = Nabu::Focus.resolve(profile("germanic", "rem"), @registry)
    assert_equal res.slugs.uniq, res.slugs
    assert_equal 1, res.slugs.count("rem")
  end

  # -- the view ---------------------------------------------------------------

  def test_active_view_shows_enabled_rows_with_shelves_always
    view = Nabu::Focus.view(profile: profile("germanic"), registry: @registry, all: false)
    assert_predicate view, :active?
    shown = view.registry.slugs.sort
    assert_includes shown, "rem",  "an enabled source shows"
    assert_includes shown, "lib1", "a shelf always shows (owner's own), even off-axis"
    assert_includes shown, "mod1",
                    "a module enabled via its desk shows like any member (owner ruling 2026-07-24 — " \
                    "the P40-f modules-only-under---all rule died with the enablement promotion)"
    refute_includes shown, "ccmh", "a non-enabled source is hidden"
  end

  def test_all_flag_is_the_pass_through
    view = Nabu::Focus.view(profile: profile("germanic"), registry: @registry, all: true)
    refute_predicate view, :active?
    assert_equal @registry.slugs.sort, view.registry.slugs.sort
    assert_equal 0, view.registry_hidden
  end

  # P44-r3b: an empty enabled set is no longer the pass-through — the profile IS
  # the box's enabled set, so an empty one shows only the owner's shelves (a
  # source shows iff enabled; --all is the only pass-through).
  def test_empty_enabled_set_shows_only_shelves
    view = Nabu::Focus.view(profile: profile, registry: @registry, all: false)
    assert_predicate view, :active?
    assert_equal %w[lib1], view.registry.slugs, "only the shelf shows; no source is enabled"
    refute view.visible?("rem"), "a non-enabled source is hidden"
  end

  def test_registry_hidden_counts_the_rows_all_would_reveal
    view = Nabu::Focus.view(profile: profile("germanic"), registry: @registry, all: false)
    # 6 rows total; shown = rem, helipad, mod1 (module on the enabled axis),
    # lib1 (shelf). Hidden = ccmh, lex.
    assert_equal 4, view.registry.size
    assert_equal 2, view.registry_hidden
  end

  # P44-i2 (owner report 2026-07-24: "which one source is 'not enabled'? How
  # am I supposed to guess it?") — the hidden rows are nameable, not just
  # countable, so a small gap prints its slugs.
  def test_registry_hidden_slugs_names_the_rows_all_would_reveal
    view = Nabu::Focus.view(profile: profile("germanic"), registry: @registry, all: false)
    assert_equal %w[ccmh lex], view.registry_hidden_slugs.sort
  end

  def test_filtered_registry_keeps_axes_for_grouping
    view = Nabu::Focus.view(profile: profile("germanic"), registry: @registry, all: false)
    assert_equal @registry.axes.names, view.registry.axes.names
  end

  # -- write validation -------------------------------------------------------

  def test_validate_names_passes_known_axes_and_slugs
    assert_equal %w[germanic rem], Nabu::Focus.validate_names!(%w[germanic rem], @registry)
  end

  def test_validate_names_refuses_an_unknown_name_with_a_near_miss
    error = assert_raises(Nabu::Focus::UnknownName) do
      Nabu::Focus.validate_names!(%w[germnic], @registry)
    end
    assert_match(/unknown name "germnic"/, error.message)
    assert_match(/did you mean germanic/, error.message)
  end

  def test_validate_names_falls_back_to_the_known_set_when_nothing_is_close
    error = assert_raises(Nabu::Focus::UnknownName) do
      Nabu::Focus.validate_names!(%w[zzzzzz], @registry)
    end
    assert_match(%r{known axes/sources:}, error.message)
    assert_match(/germanic/, error.message)
  end

  # -- honesty lines ----------------------------------------------------------

  def test_empty_state_line_names_the_enable_on_ramp
    assert_match(/no sources enabled/, Nabu::Focus.empty_state_line)
    assert_match(/nabu enable/, Nabu::Focus.empty_state_line)
  end

  # P44-i2: a small gap is NAMED — a bare count is a guessing game (owner
  # report 2026-07-24), while the enabled rows are still never re-dumped.
  def test_footer_line_names_a_small_gap
    assert_equal "enabled: 2 entries — not enabled: ccmh, lex (--all shows them)",
                 Nabu::Focus.footer_line(%w[germanic rem], %w[ccmh lex])
  end

  def test_footer_line_singular_and_zero_suppressed
    assert_equal "enabled: 1 entry — not enabled: lila (--all shows it)",
                 Nabu::Focus.footer_line(%w[germanic], %w[lila])
    assert_equal "enabled: 1 entry (nabu enable <axis|source> to add)", Nabu::Focus.footer_line(%w[germanic], [])
  end

  # Beyond the name cap the count summary stands (a fresh box hides ~90
  # sources — naming them all IS the name dump the owner refused).
  def test_footer_line_falls_back_to_a_count_beyond_the_name_cap
    hidden = (1..7).map { |i| "s#{i}" }
    assert_equal "enabled: 2 entries — 7 sources not enabled (--all shows them)",
                 Nabu::Focus.footer_line(%w[germanic rem], hidden)
  end

  def test_drift_line_names_the_ignored_entries
    line = Nabu::Focus.drift_line(%w[bogus typo])
    assert_match(/ignoring bogus, typo/, line)
    assert_match(/registry drift/, line)
  end

  # P44-r3b: an AXIS enables its PUBLIC members only — a blocked (grant-gated)
  # member never joins the enabled set implicitly; a blocked source named BY
  # SLUG does.
  def test_axis_expansion_excludes_blocked_members_but_a_named_slug_includes
    dir = Dir.mktmpdir
    File.write(File.join(dir, "axes.yml"), AXES)
    File.write(File.join(dir, "sources.yml"), <<~YAML)
      rem:
        adapter: Nabu::Adapters::UniversalDependencies
        wired: true
        sync_policy: manual
        axes: [germanic]
      secret:
        adapter: Nabu::Adapters::UniversalDependencies
        wired: true
        sync_policy: manual
        axes: [germanic]
        availability: blocked
    YAML
    registry = Nabu::SourceRegistry.load(File.join(dir, "sources.yml"))
    by_axis = Nabu::Focus.resolve(Nabu::Profile.new(%w[germanic]), registry)
    refute_includes by_axis.slugs, "secret", "an axis never drags a blocked member in"
    assert_includes by_axis.slugs, "rem"
    by_slug = Nabu::Focus.resolve(Nabu::Profile.new(%w[secret]), registry)
    assert_includes by_slug.slugs, "secret", "a blocked source named by slug is enabled"
  ensure
    FileUtils.remove_entry(dir)
  end
end
