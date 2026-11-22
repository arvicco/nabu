# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "stringio"
require "nabu/ops/worktree_prep"

module Ops
  # Nabu::Ops::WorktreePrep — `rake worktree:prepare`. A fresh lane
  # worktree carries no local/ (it is gitignored), so the StrictSkips gate
  # never binds there and restricted-source tests skip silently: the lane
  # reports green on a suite the main checkout would fail. The task links
  # the main checkout's instance folders in so the lane runs the SAME
  # strict suite.
  class WorktreePrepTest < Minitest::Test
    W = Nabu::Ops::WorktreePrep

    def git!(dir, *)
      out, err, status = Open3.capture3({ "TZ" => "UTC" }, "git", "-C", dir, "-c", "user.name=t",
                                        "-c", "user.email=1+t@users.noreply.github.com",
                                        "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *)
      assert status.success?, out + err
      out
    end

    # A scratch main checkout with the three instance folders populated,
    # plus one linked worktree beside it.
    def with_main_and_lane
      Dir.mktmpdir("wtprep") do |dir|
        main = File.join(dir, "main")
        FileUtils.mkdir_p(main)
        git!(main, "init", "-q", "-b", "main")
        File.write(File.join(main, "README"), "x\n")
        git!(main, "add", "-A")
        git!(main, "commit", "-q", "-m", "Seed")
        W::LINKED.each do |name|
          FileUtils.mkdir_p(File.join(main, "local", name))
          File.write(File.join(main, "local", name, "marker"), name)
        end
        lane = File.join(dir, "lane")
        git!(main, "worktree", "add", "-q", "-b", "lane", lane)
        yield File.realpath(main), File.realpath(lane)
      end
    end

    def test_a_lane_gets_the_three_instance_folders_linked_from_the_main_checkout
      with_main_and_lane do |main, lane|
        refute File.exist?(File.join(lane, "local")), "precondition: a fresh worktree has no local/"
        states = W.new(root: lane, out: StringIO.new).prepare!
        assert_equal({ "fixtures" => :linked, "shelves" => :linked, "config" => :linked }, states)
        W::LINKED.each do |name|
          link = File.join(lane, "local", name)
          assert File.symlink?(link), "#{name} must be a symlink"
          assert_equal File.join(main, "local", name), File.readlink(link)
          assert_equal name, File.read(File.join(link, "marker"))
        end
      end
    end

    def test_a_rerun_is_an_announced_skip
      with_main_and_lane do |_main, lane|
        W.new(root: lane, out: StringIO.new).prepare!
        out = StringIO.new
        again = W.new(root: lane, out: out).prepare!
        assert_equal(%i[present present present], again.values)
        assert_match(/present, skipped/, out.string)
      end
    end

    def test_the_main_checkout_itself_is_a_safe_noop
      with_main_and_lane do |main, _lane|
        before = Dir.children(File.join(main, "local")).sort
        out = StringIO.new
        assert_equal :main_checkout, W.new(root: main, out: out).prepare!
        assert_match(/main checkout.*nothing to do/i, out.string)
        assert_equal before, Dir.children(File.join(main, "local")).sort
        W::LINKED.each { |name| refute File.symlink?(File.join(main, "local", name)) }
      end
    end

    def test_a_real_folder_already_in_the_lane_is_never_replaced
      with_main_and_lane do |_main, lane|
        own = File.join(lane, "local", "shelves")
        FileUtils.mkdir_p(own)
        File.write(File.join(own, "mine"), "keep")
        out = StringIO.new
        states = W.new(root: lane, out: out).prepare!
        assert_equal :foreign, states["shelves"]
        assert_equal :linked, states["fixtures"]
        assert_equal "keep", File.read(File.join(own, "mine"))
        assert_match(/not replaced/, out.string)
      end
    end

    def test_an_absent_main_folder_is_reported_not_dangled
      with_main_and_lane do |main, lane|
        FileUtils.rm_rf(File.join(main, "local", "config"))
        states = W.new(root: lane, out: StringIO.new).prepare!
        assert_equal :missing_source, states["config"]
        refute File.symlink?(File.join(lane, "local", "config"))
      end
    end

    def test_the_main_checkout_resolves_from_git_never_a_hardcoded_path
      with_main_and_lane do |main, lane|
        assert_equal main, File.realpath(W.new(root: lane, out: StringIO.new).main_root)
        assert_equal main, File.realpath(W.new(root: main, out: StringIO.new).main_root)
      end
    end
  end
end
