# frozen_string_literal: true

require "test_helper"
require "prism"
require "stringio"

# The --verbose explanation registry (Nabu::Ops::StageGuide): one
# library-reader sentence per composite-command stage and one intro per
# composite command, rendered green on the progress channel through the
# house color seam. The guards below pin the registry to the REAL stage
# call sites, both ways — a new stage cannot ship silent, a renamed one
# cannot leave its explanation orphaned.
class StageGuideTest < Minitest::Test
  LIB = File.expand_path("../../lib/nabu", __dir__)

  # The composite-command orchestrators whose every stage must explain
  # itself. (Sub-steps inside a registered stage — the indexer's merge
  # chunks, the links unit lines — are narrated by their parent stage.)
  GUARDED = %w[
    rebuild.rb incremental_rebuild.rb ops/builder_refresh.rb sync_runner.rb store/lect_facets.rb
  ].freeze

  # Files whose stage labels may satisfy a registry entry (the reverse,
  # orphan guard) without being guarded themselves.
  SAMPLED = (GUARDED + %w[store/indexer.rb]).freeze

  # Non-literal stage arguments the guard accepts, each with what it
  # carries: a replayed source's slug (explained by the source-replay
  # entry), timed_stage's own pass-through parameter (its callers' label
  # literals are checked), and the indexer reconcile note (a sub-step of
  # the fulltext stage, named by the indexer itself).
  DYNAMIC = { "entry.slug" => :source_replay, "label" => nil, "stage_note" => nil }.freeze

  SLUG = "corpus"

  def test_every_registered_stage_and_command_carries_an_explanation
    refute_empty Nabu::Ops::StageGuide.stages
    Nabu::Ops::StageGuide.stages.each do |entry|
      assert_kind_of Symbol, entry.key
      refute_empty entry.text.strip, "stage #{entry.key} ships without an explanation"
    end
    refute_empty Nabu::Ops::StageGuide.commands
    Nabu::Ops::StageGuide.commands.each do |key, text|
      refute_empty text.strip, "command #{key} ships without an intro"
    end
  end

  def test_registration_refuses_a_blank_explanation_or_a_duplicate_key
    assert_raises(ArgumentError) { Nabu::Ops::StageGuide.stage(:blank_probe, "x", "  ") }
    assert_raises(ArgumentError) { Nabu::Ops::StageGuide.stage(:timeline, "timeline", "dup") }
    assert_raises(ArgumentError) { Nabu::Ops::StageGuide.command(:rebuild, "dup") }
  end

  def test_every_stage_call_in_the_orchestrators_resolves_to_an_explanation
    samples(GUARDED).each do |file, line, label, dynamic|
      if dynamic
        assert DYNAMIC.key?(dynamic), "#{file}:#{line} passes a non-literal stage label (#{dynamic}) — " \
                                      "give it a literal label and a StageGuide entry"
        next
      end
      entry = Nabu::Ops::StageGuide.lookup(label, sources: [SLUG])
      refute_nil entry, "#{file}:#{line} stage #{label.inspect} has no StageGuide explanation — " \
                        "register one in lib/nabu/ops/stage_guide.rb"
    end
  end

  def test_no_registered_stage_is_orphaned_from_its_call_sites
    labels = samples(SAMPLED).filter_map { |_f, _l, label, dynamic| dynamic ? DYNAMIC[dynamic] : label }
    Nabu::Ops::StageGuide.stages.each do |entry|
      hit = labels.any? do |label|
        label.is_a?(Symbol) ? label == entry.key : Nabu::Ops::StageGuide.lookup(label, sources: [SLUG]) == entry
      end
      assert hit, "StageGuide entry #{entry.key} matches no stage call site — renamed or removed stage?"
    end
  end

  def test_lookup_matches_exact_labels_patterns_and_source_slugs
    assert_equal :timeline, Nabu::Ops::StageGuide.lookup("timeline").key
    assert_equal :sync_fetch, Nabu::Ops::StageGuide.lookup("fetch: perseus-greek").key
    assert_equal :source_replay, Nabu::Ops::StageGuide.lookup("perseus-greek", sources: ["perseus-greek"]).key
    assert_nil Nabu::Ops::StageGuide.lookup("perseus-greek"), "a bare slug is a replay only when it IS a source"
    assert_nil Nabu::Ops::StageGuide.lookup("fts merge: fts — chunk 3"), "sub-steps stay unexplained"
  end

  def test_narrator_explains_each_stage_once_and_paints_only_when_color_is_on
    io = StringIO.new
    narrator = Nabu::Ops::StageGuide::Narrator.new(io: io, color: false, sources: %w[a b])
    %w[a b timeline timeline facets].each { |label| narrator.call(label) }
    narrator.call("not a stage")
    lines = io.string.lines
    assert_equal 3, lines.size, "source replay once, timeline once, facets once: #{lines.inspect}"
    assert_includes io.string, Nabu::Ops::StageGuide.fetch(:timeline).text
    refute_match(/\e\[/, io.string, "colorless output carries no ANSI codes")

    painted = StringIO.new
    Nabu::Ops::StageGuide::Narrator.new(io: painted, color: true).call("timeline")
    assert_match(/\A\s*\e\[32m.*#{Regexp.escape(Nabu::Ops::StageGuide.fetch(:timeline).text)}.*\e\[0m\n\z/,
                 painted.string)
  end

  def test_narrator_intro_prints_the_command_explanation_and_runs_the_before_hook
    io = StringIO.new
    calls = 0
    narrator = Nabu::Ops::StageGuide::Narrator.new(io: io, color: false, before: -> { calls += 1 })
    narrator.intro(:rebuild)
    narrator.call("timeline")
    assert_includes io.string, Nabu::Ops::StageGuide.intro(:rebuild)
    assert_equal 2, calls, "the before hook (close the open stage line) runs ahead of every explanation"
  end

  def test_narrator_color_default_follows_the_display_seam
    with_env("NO_COLOR" => "1", "NABU_COLOR" => "1") do
      refute_predicate Nabu::Ops::StageGuide::Narrator.new(io: StringIO.new), :color?
    end
    with_env("NO_COLOR" => nil, "NABU_COLOR" => "1") do
      assert_predicate Nabu::Ops::StageGuide::Narrator.new(io: StringIO.new), :color?
    end
  end

  def test_progress_reporter_explains_before_announcing_and_costs_nothing_when_off
    seen = []
    reporter = Nabu::ProgressReporter.new(on_explain: ->(label) { seen << [:explain, label] },
                                          on_stage: ->(label, _eta) { seen << [:stage, label] })
    reporter.stage("timeline")
    reporter.explain("post-load lanes: x")
    assert_equal [[:explain, "timeline"], [:stage, "timeline"], [:explain, "post-load lanes: x"]], seen

    quiet = Nabu::ProgressReporter.new(on_stage: ->(_l, _e) {})
    assert_nil quiet.explain("timeline")
    quiet.stage("timeline") # no on_explain: nothing resolves, nothing raises
  end

  private

  # [file, line, label-or-nil, dynamic-source-or-nil] for every progress
  # stage/explain call (and timed_stage label) in +files+.
  def samples(files)
    files.flat_map do |rel|
      path = File.join(LIB, rel)
      collect(Prism.parse(File.read(path)).value, rel)
    end
  end

  def collect(node, rel, out = [])
    return out unless node.is_a?(Prism::Node)

    if node.is_a?(Prism::CallNode)
      arg = label_argument(node)
      out << [rel, node.location.start_line, *evaluate(arg)] if arg
    end
    node.compact_child_nodes.each { |child| collect(child, rel, out) }
    out
  end

  def label_argument(call)
    args = call.arguments&.arguments || []
    case call.name
    when :stage, :explain then call.receiver && args.first
    when :timed_stage then args[2]
    when :timed_sync_stage then args[3]
    end
  end

  def evaluate(arg)
    case arg
    when Prism::StringNode then [arg.unescaped, nil]
    when Prism::InterpolatedStringNode then [flatten(arg), nil]
    else [nil, arg.slice]
    end
  end

  def flatten(node)
    node.parts.map do |part|
      case part
      when Prism::StringNode then part.unescaped
      when Prism::InterpolatedStringNode then flatten(part)
      else SLUG
      end
    end.join
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
