# frozen_string_literal: true

require_relative "test_helper"

class BdTest < Minitest::Test
  include FixtureHelper

  def test_list_all_passes_readonly_and_directory
    runner, calls = recording_runner(stdout: fixture("list_all.json"))
    issues = Beadview::Bd.new(runner: runner).list_all("/r")

    assert_equal [["bd", "-C", "/r", "--readonly", "list", "--all", "--json", "--limit", "0"]], calls
    assert_equal 5, issues.size
    assert_equal "tw-1", issues.first["id"]
  end

  def test_ready_passes_readonly
    runner, calls = recording_runner(stdout: "[]")
    Beadview::Bd.new(runner: runner).ready("/r")

    # 既定の --limit は 100 で、超えると黙って切られる
    assert_equal [["bd", "-C", "/r", "--readonly", "ready", "--json", "--limit", "0"]], calls
  end

  def test_history_parses_array
    runner, calls = recording_runner(stdout: fixture("history_d4g.json"))
    entries = Beadview::Bd.new(runner: runner).history("/r", "tw-1")

    assert_equal [["bd", "-C", "/r", "--readonly", "history", "tw-1", "--json"]], calls
    assert_equal 6, entries.size
  end

  def test_failure_raises_bd_error
    runner, = recording_runner(stderr: "Error: database is locked\nmore", success: false)
    error = assert_raises(Beadview::BdError) { Beadview::Bd.new(runner: runner).list_all("/r") }

    assert_includes error.message, "database is locked"
    refute_includes error.message, "more"
  end

  def test_events_skips_non_json_lines
    runner, calls = recording_runner(stdout: fixture("events_tail.txt"))
    events = Beadview::Bd.new(runner: runner).events("/r")

    assert_equal [["bd", "-C", "/r", "--readonly", "events", "tail"]], calls
    assert_equal 3, events.size
    assert events.all? { _1.key?("op") }
  end

  def test_events_failure_returns_empty
    runner, = recording_runner(stderr: "boom", success: false)

    assert_equal [], Beadview::Bd.new(runner: runner).events("/r")
  end

  # ロケールが UTF-8 でないシェル（エージェントの Bash 等）では bd の出力が
  # US-ASCII / BINARY として届く。日本語を含んでいても読めること
  def test_parses_utf8_output_delivered_as_binary
    runner, = recording_runner(stdout: fixture("list_all.json").dup.force_encoding(Encoding::BINARY))
    issues = Beadview::Bd.new(runner: runner).list_all("/r")

    assert_equal "資料一覧のフィルタを足す", issues.first["title"]
    assert_equal Encoding::UTF_8, issues.first["title"].encoding
  end
end
