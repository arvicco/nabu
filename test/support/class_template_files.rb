# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Per-class template DIRECTORIES — the file-backed sibling of
# StoreTestDB#class_template_db. For a test class that rebuilds the same
# on-disk state before every test (a file-backed catalog after a loader
# replay, a seeded upstream git repo): the FIRST call in the class yields a
# private template directory for the block to build into, once; every call
# — the first included — then copies that tree (dotfiles, .git and file
# times included) into +into+, so each test still owns a real, independent
# copy in exactly the state the per-test build would have left it, and
# nothing it writes reaches the template or another test.
#
#   include ClassTemplateFiles
#   class_template_files(:upstream, into: @upstream) { |dir| seed_repo(dir) }
#
# Templates live for the process and are removed after the run. A build
# that raises leaves no template behind (the next test retries it).
module ClassTemplateFiles
  @dirs = []

  class << self
    attr_reader :dirs
  end

  Minitest.after_run { ClassTemplateFiles.dirs.each { |dir| FileUtils.rm_rf(dir) } }

  def class_template_files(name, into:)
    templates = self.class.instance_variable_get(:@class_template_files) ||
                self.class.instance_variable_set(:@class_template_files, {})
    template = templates[name] ||= begin
      dir = Dir.mktmpdir("nabu-class-template")
      built = false
      begin
        yield dir
        built = true
      ensure
        FileUtils.rm_rf(dir) unless built
      end
      ClassTemplateFiles.dirs << dir
      dir
    end
    FileUtils.mkdir_p(into)
    FileUtils.cp_r(File.join(template, "."), into, preserve: true)
    into
  end
end
