# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Validity tests for the launchd plist templates under ops/launchd/. Nothing
# here ever calls launchctl (never load/install a job from a test); the
# templates are treated as inert text: substitute the placeholders into a tmp
# copy and check that (a) the result is a valid property list and (b) every
# command it wires up actually exists in this repo.
class LaunchdTemplatesTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  TEMPLATE_DIR = File.join(ROOT, "ops", "launchd")

  # The placeholder convention the templates + docs/ops.md share. Substituted
  # here with real, valid values so the lint/parse checks exercise a plist
  # shaped exactly like the one the owner will install.
  PLACEHOLDERS = {
    "__NABU_ROOT__" => ROOT,
    "__RUBY_BIN_DIR__" => File.dirname(RbConfig.ruby)
  }.freeze

  def templates
    Dir[File.join(TEMPLATE_DIR, "*.plist")]
  end

  def test_templates_are_present
    refute_empty templates, "expected launchd plist templates under ops/launchd/"
  end

  # plutil ships on every macOS box (the suite's platform per CLAUDE.md); on a
  # non-macOS CI runner (ubuntu) it is absent, so skip the lint assertion there
  # rather than fail — the substitution + command-existence checks still run.
  def test_each_template_lints_after_substitution
    skip "plutil unavailable (non-macOS environment)" unless plutil_available?

    templates.each do |path|
      Dir.mktmpdir do |dir|
        copy = File.join(dir, File.basename(path))
        File.write(copy, substitute(File.read(path)))
        assert_plutil_ok(copy, File.basename(path))
      end
    end
  end

  # A stray unsubstituted placeholder would install a broken job silently.
  def test_no_placeholders_survive_substitution
    templates.each do |path|
      substituted = substitute(File.read(path))
      refute_match(/__[A-Z0-9_]+__/, substituted,
                   "#{File.basename(path)}: undocumented placeholder left after substitution")
    end
  end

  # Every `bin/nabu <subcommand>` the plists invoke must be a real CLI command.
  def test_referenced_nabu_commands_exist
    assert File.executable?(File.join(ROOT, "bin", "nabu")), "bin/nabu must exist and be executable"

    valid = Nabu::CLI.all_commands.keys
    templates.each do |path|
      nabu_subcommands(File.read(path)).each do |cmd|
        assert_includes valid, cmd,
                        "#{File.basename(path)} references unknown `bin/nabu #{cmd}`"
      end
    end
  end

  # Every `rake <task>` the plists invoke must be a defined task. Honest source
  # of truth: `rake -T` (network-free, just loads the Rakefile).
  def test_referenced_rake_tasks_exist
    referenced = templates.flat_map { |path| rake_task_refs(File.read(path)) }.uniq
    skip "no rake tasks referenced by the templates" if referenced.empty?

    defined = defined_rake_tasks
    referenced.each do |task|
      assert_includes defined, task, "templates reference unknown `rake #{task}`"
    end
  end

  private

  def substitute(content)
    PLACEHOLDERS.reduce(content) { |acc, (key, value)| acc.gsub(key, value) }
  end

  def plutil_available?
    search = ENV["PATH"].to_s.split(File::PATH_SEPARATOR) + ["/usr/bin"]
    search.any? { |dir| File.executable?(File.join(dir, "plutil")) }
  end

  # plutil -lint prints "<path>: OK" and exits 0 for a valid plist; on a bad one
  # it exits nonzero (Shell::Error), failing this assertion with its message.
  def assert_plutil_ok(path, label)
    output = Nabu::Shell.run("plutil", "-lint", path)
    assert_match(/\bOK\b/, output, "#{label}: plutil -lint did not report OK")
  rescue Nabu::Shell::Error => e
    flunk "#{label}: plutil -lint failed — #{e.stderr.strip}"
  end

  def nabu_subcommands(content)
    content.scan(%r{bin/nabu\s+([a-z_]+)}).flatten.uniq
  end

  def rake_task_refs(content)
    content.scan(/\brake\s+([a-z][\w:]*)/).flatten.uniq
  end

  def defined_rake_tasks
    Nabu::Shell.run("bundle", "exec", "rake", "-T")
               .lines
               .filter_map { |line| line[/^rake\s+(\S+?)(?:\[|\s)/, 1] }
  end
end
