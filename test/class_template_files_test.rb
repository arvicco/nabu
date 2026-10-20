# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# ClassTemplateFiles (test/support/class_template_files.rb): a per-class
# template directory built once and copied per test. Sound only if every
# copy is independent and complete — pinned here.
class ClassTemplateFilesTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-class-template-files")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def template_class
    Class.new do
      include ClassTemplateFiles

      class << self
        attr_accessor :builds
      end

      def seed(into)
        class_template_files(:tree, into: into) do |dir|
          self.class.builds = (self.class.builds || 0) + 1
          FileUtils.mkdir_p(File.join(dir, "sub", ".hidden"))
          File.write(File.join(dir, "sub", ".hidden", "f.txt"), "seed\n")
          File.write(File.join(dir, "top.txt"), "top\n")
        end
      end
    end
  end

  def test_builds_once_and_copies_the_whole_tree_dotfiles_included
    klass = template_class
    first = klass.new.seed(File.join(@root, "a"))
    second = klass.new.seed(File.join(@root, "b"))

    assert_equal 1, klass.builds
    [first, second].each do |dir|
      assert_equal "seed\n", File.read(File.join(dir, "sub", ".hidden", "f.txt"))
      assert_equal "top\n", File.read(File.join(dir, "top.txt"))
    end
  end

  def test_copies_are_independent_of_each_other_and_of_the_template
    klass = template_class
    first = klass.new.seed(File.join(@root, "a"))
    File.write(File.join(first, "top.txt"), "scribbled\n")
    File.write(File.join(first, "extra.txt"), "x\n")
    second = klass.new.seed(File.join(@root, "b"))

    assert_equal "top\n", File.read(File.join(second, "top.txt"))
    refute File.exist?(File.join(second, "extra.txt"))
  end

  def test_a_failed_build_leaves_no_template_and_is_retried
    klass = Class.new do
      include ClassTemplateFiles

      class << self
        attr_accessor :attempts
      end

      def seed(into)
        class_template_files(:tree, into: into) do |dir|
          self.class.attempts = (self.class.attempts || 0) + 1
          File.write(File.join(dir, "half.txt"), "half\n")
          raise ArgumentError, "boom" if self.class.attempts == 1
        end
      end
    end

    assert_raises(ArgumentError) { klass.new.seed(File.join(@root, "a")) }
    copy = klass.new.seed(File.join(@root, "b"))

    assert_equal 2, klass.attempts
    assert_equal "half\n", File.read(File.join(copy, "half.txt"))
  end
end
