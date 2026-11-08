# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class CLITest < Minitest::Test
  include FixtureHelper

  NOW = Time.iso8601("2026-11-08T12:00:00Z")

  # fixture を返す偽の bd。failing に入れたリポジトリ名では BdError を投げる
  class FakeBd
    attr_reader :history_calls

    def initialize(list:, history:, events:, failing: [])
      @list = list
      @history = history
      @events = events
      @failing = failing
      @history_calls = Queue.new
    end

    def list_all(path)
      raise Beadview::BdError, "database is locked" if @failing.include?(File.basename(path))

      @list
    end

    def ready(_path) = [{}, {}]

    def history(path, id)
      @history_calls << [path, id]
      @history
    end

    def events(_path) = @events
  end

  def setup
    @root = Dir.mktmpdir
    @paths = %w[a b].map do |name|
      File.join(@root, name).tap { FileUtils.mkdir_p(File.join(_1, ".beads")) }
    end
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def fake_bd(failing: [])
    events = fixture("events_tail.txt").lines.filter_map do |line|
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
    FakeBd.new(list: fixture_json("list_all.json"), history: fixture_json("history_d4g.json"),
               events: events, failing: failing)
  end

  def run_cli(argv = [], bd: fake_bd)
    out = StringIO.new
    code = Beadview::CLI.run(argv, bd: bd, repo_paths: @paths, cache: Beadview::HistoryCache::NONE, now: NOW, out: out)
    [code, out.string]
  end

  def test_outputs_all_sections_for_two_repos
    code, out = run_cli

    assert_equal 0, code
    assert_includes out, "── 着手中 "
    assert_includes out, "── 最近閉じたもの（3日以内）"
    assert_includes out, "a 2件 / b 2件"
    assert_equal 2, out.lines.count { _1.include?("資料一覧のフィルタを足す") }
    assert_includes out, "tominocle-codex"
  end

  def test_one_failing_repo_does_not_hide_others
    code, out = run_cli(bd: fake_bd(failing: ["a"]))

    assert_equal 0, code
    assert_match(/^b\s+tw-1/, out)
    assert_includes out, "a: database is locked"
  end

  def test_malformed_time_in_one_repo_does_not_crash
    bad = fixture_json("list_all.json").map { _1["id"] == "tw-2" ? _1.merge("closed_at" => "not-a-time") : _1 }
    bd = fake_bd
    bd.define_singleton_method(:list_all) { |path| File.basename(path) == "a" ? bad : super(path) }
    code, out = run_cli(bd: bd)

    assert_equal 0, code
    assert_match(/^a: /, out)
    assert_match(/^b\s+tw-1/, out)
  end

  def test_unwritable_cache_still_shows_since
    Dir.mktmpdir do |dir|
      blocker = File.join(dir, "file")
      File.write(blocker, "")
      out = StringIO.new
      Beadview::CLI.run([], bd: fake_bd, repo_paths: @paths, cache: Beadview::HistoryCache.new(dir: File.join(blocker, "sub")),
                            now: NOW, out: out)

      refute_includes out.string, "読み込めなかったリポジトリ"
      assert_includes out.string, "日前から"
    end
  end

  def test_all_failing_returns_1
    code, = run_cli(bd: fake_bd(failing: %w[a b]))

    assert_equal 1, code
  end

  def test_history_called_only_for_in_progress
    bd = fake_bd
    run_cli(bd: bd)
    ids = Array.new(bd.history_calls.size) { bd.history_calls.pop }.map(&:last).sort

    assert_equal %w[tw-1 tw-1 tw-3 tw-3], ids
  end

  def test_repo_filter
    _, out = run_cli(["--repo", "b"])

    assert_includes out, "b 2件"
    refute_match(/^a\s/, out)
    refute_includes out, "a 2件"
  end

  def test_json_flag
    _, out = run_cli(["--json", "--days", "5"])
    data = JSON.parse(out)

    assert_equal 5, data["days"]
    assert_equal %w[a b], data["repos"].map { _1["name"] }
  end

  def test_help
    code, out = run_cli(["-h"])

    assert_equal 0, code
    assert_equal "beadview — beads の作業状況を一画面で見る（読み取り専用）", out.lines.first.chomp
  end
end
