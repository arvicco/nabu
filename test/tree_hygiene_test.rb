# frozen_string_literal: true

require "test_helper"
require "psych"

# Integration invariants over the tracked tree — each anchored to a named
# class of past defect that no unit test could see, and each cheap (the
# whole file runs in well under a second). The commit-time half of the
# first one is the pre-commit hook (Nabu::Ops::GitHooks); this is the
# backstop for whatever lands without it (a hookless worktree, a
# --no-verify).
class TreeHygieneTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Anchor: hand-resolved merge conflicts (the phase-gate pick sequences)
  # left marker lines behind; an orphan ======= survived a sweep that only
  # looked for the opening marker. All three strings, line-anchored, over
  # every tracked file but upstream fixture bytes.
  def test_no_conflict_markers_in_tracked_files
    hits = git("grep", "-n", "-I", "-E", "^(<{7}( |$)|={7}[[:space:]]*$|>{7}( |$))", allow_empty: true)
           .split("\n").grep_v(Nabu::Ops::GitHooks::MARKER_EXEMPT)
    assert_empty hits, "conflict markers committed:\n  #{hits.first(20).join("\n  ")}"
  end

  # Anchor: a registry slug entered twice in config/sources.yml — YAML
  # silently keeps the LATER mapping, so the first entry was shadowed with
  # no error and no merge conflict ever raised. Every config YAML, every
  # mapping level.
  def test_no_duplicate_keys_in_config_yaml
    duplicates = Dir[File.join(ROOT, "config", "**", "*.{yml,yaml}")].flat_map do |path|
      duplicate_keys(Psych.parse_file(path)).map { |line, key| "#{rel(path)}:#{line}: #{key}" }
    end
    assert_empty duplicates, "duplicate YAML keys (the later silently wins):\n  #{duplicates.join("\n  ")}"
  end

  # Gaps a past renumbering deliberately left (number => reason). Empty:
  # the sequence has never had one.
  DECLARED_MIGRATION_GAPS = {}.freeze

  # Anchor: two lanes each minted the same next migration number; the
  # collision surfaced only because one lane happened to flag it (the fix
  # was a renumber). Unique, and gapless unless a gap is declared above.
  def test_migration_numbers_are_unique_and_gapless_or_declared
    numbers = Dir[File.join(ROOT, "db", "migrate", "*.rb")].map { |path| File.basename(path)[/\A\d+/].to_i }
    collisions = numbers.tally.select { |_, count| count > 1 }.keys
    assert_empty collisions, "migration numbers minted twice: #{collisions.sort.inspect}"
    gaps = (1..numbers.max).to_a - numbers - DECLARED_MIGRATION_GAPS.keys
    assert_empty gaps, "undeclared migration-number gaps: #{gaps.inspect} — renumber, or declare the gap"
    stale = DECLARED_MIGRATION_GAPS.keys & numbers
    assert_empty stale, "declared gaps that are no longer gaps: #{stale.inspect}"
  end

  # Anchor: test methods defined below a class-body `private` are private
  # instance methods, which Minitest never collects — a whole block of
  # guards ran green for phases while running nothing. A dead guard is
  # worse than none.
  def test_no_test_methods_below_a_private_marker
    dead = Dir[File.join(ROOT, "test", "**", "*_test.rb")].flat_map { |path| private_tests(path) }
    assert_empty dead, "test methods Minitest never runs (below `private`):\n  #{dead.join("\n  ")}"
  end

  # The scanners must bite on the shapes they exist for.
  def test_the_scanners_bite
    yaml = Psych.parse("a: 1\nb:\n  c: 1\n  c: 2\na: 3\n")
    assert_equal [[4, "c"], [5, "a"]], duplicate_keys(yaml).sort

    Dir.mktmpdir do |dir|
      path = File.join(dir, "x_test.rb")
      File.write(path, "class X\n  def test_a; end\n\n  private\n\n  def helper; end\n\n  " \
                       "def test_dead; end\nend\nclass Y\n  def test_b; end\nend\n")
      assert_equal ["#{path}:8: test_dead"], private_tests(path)
    end
  end

  private

  def duplicate_keys(node, found = [])
    case node
    when Psych::Nodes::Mapping
      seen = {}
      node.children.each_slice(2) do |key, value|
        if key.is_a?(Psych::Nodes::Scalar) && key.value != "<<"
          found << [key.start_line + 1, key.value] if seen[key.value]
          seen[key.value] = true
        end
        duplicate_keys(value, found)
      end
    when Psych::Nodes::Node
      node.children&.each { |child| duplicate_keys(child, found) }
    end
    found
  end

  # Lexical: a `private` at some indent opens a private run that a `public`
  # at the same indent, or any end/class/module at a shallower indent,
  # closes; a `def test_` at the run's indent inside it is dead.
  def private_tests(path)
    dead = []
    indent = nil
    File.foreach(path).with_index(1) do |line, number|
      if (marker = line.match(/\A(\s*)(private|public)\s*(?:#.*)?\z/))
        indent = marker[2] == "private" ? marker[1].size : nil if indent.nil? || marker[1].size == indent
        next
      end
      next unless indent

      closer = line.match(/\A(\s*)(?:end|class|module)\b/)
      indent = nil if closer && closer[1].size < indent
      definition = line.match(/\A(\s*)def (test_\w+)/)
      dead << "#{rel(path)}:#{number}: #{definition[2]}" if indent && definition && definition[1].size == indent
    end
    dead
  end

  def rel(path) = path.delete_prefix("#{ROOT}/")

  def git(*, allow_empty: false)
    Nabu::Shell.run("git", "-C", ROOT, *)
  rescue Nabu::Shell::Error => e
    # git grep exits 1 on "no match" — the clean result.
    return "" if allow_empty && e.status == 1

    skip "no git checkout — the guard runs where the tree is tracked" unless File.exist?(File.join(ROOT, ".git"))
    raise
  end
end
