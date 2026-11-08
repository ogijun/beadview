# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class ReposTest < Minitest::Test
  include FixtureHelper

  def with_tree
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      yield root
    end
  end

  def test_keeps_only_dirs_with_beads
    with_tree do |root|
      FileUtils.mkdir_p(File.join(root, "a/.beads"))
      FileUtils.mkdir_p(File.join(root, "b"))
      repos = Beadview::Repos.from_paths(paths: [File.join(root, "b"), File.join(root, "a")])

      assert_equal [Beadview::Repo.new(name: "a", path: File.join(root, "a"))], repos
    end
  end

  def test_dedupes_symlinked_paths
    with_tree do |root|
      FileUtils.mkdir_p(File.join(root, "a/.beads"))
      File.symlink(File.join(root, "a"), File.join(root, "link"))
      repos = Beadview::Repos.from_paths(paths: [File.join(root, "a"), File.join(root, "link")])

      assert_equal ["a"], repos.map(&:name)
    end
  end

  def test_ignores_beads_file_not_dir
    with_tree do |root|
      FileUtils.mkdir_p(File.join(root, "c"))
      File.write(File.join(root, "c/.beads"), "")

      assert_empty Beadview::Repos.from_paths(paths: [File.join(root, "c")])
    end
  end

  def test_sorted_by_name
    with_tree do |root|
      %w[zeta alpha].each { FileUtils.mkdir_p(File.join(root, _1, ".beads")) }
      repos = Beadview::Repos.from_paths(paths: %w[zeta alpha].map { File.join(root, _1) })

      assert_equal %w[alpha zeta], repos.map(&:name)
    end
  end

  def test_ghq_paths_splits_lines
    runner, calls = recording_runner(stdout: "/x/a\n/x/b\n")

    assert_equal ["/x/a", "/x/b"], Beadview::Repos.ghq_paths(runner: runner)
    assert_equal [["ghq", "list", "-p"]], calls
  end
end
