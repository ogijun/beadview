# frozen_string_literal: true

require_relative "test_helper"

class TimelineTest < Minitest::Test
  include FixtureHelper

  def entry(date, status)
    { "CommitDate" => date, "Committer" => "root", "Issue" => { "status" => status } }
  end

  def test_since_is_latest_transition_into_in_progress
    since = Beadview::Timeline.in_progress_since(entries: fixture_json("history_d4g.json"))

    assert_equal Time.iso8601("2026-11-05T09:00:00.000+09:00"), since
  end

  def test_since_handles_newest_first_input
    entries = fixture_json("history_d4g.json")

    assert_equal Beadview::Timeline.in_progress_since(entries: entries),
                 Beadview::Timeline.in_progress_since(entries: entries.reverse)
  end

  def test_since_nil_when_not_in_progress_now
    entries = [entry("2026-11-01T00:00:00Z", "in_progress"), entry("2026-11-02T00:00:00Z", "closed")]

    assert_nil Beadview::Timeline.in_progress_since(entries: entries)
  end

  def test_since_nil_when_no_transition
    entries = [entry("2026-11-01T00:00:00Z", "in_progress"), entry("2026-11-02T00:00:00Z", "in_progress")]

    assert_nil Beadview::Timeline.in_progress_since(entries: entries)
  end

  def test_since_nil_for_empty_history
    assert_nil Beadview::Timeline.in_progress_since(entries: [])
  end

  def test_closers_uses_last_close_with_actor
    events = [
      { "seq" => 3, "op" => "close", "issue_id" => "tw-2", "actor" => "first" },
      { "seq" => 5, "op" => "close", "issue_id" => "tw-2", "actor" => "second" },
      { "seq" => 4, "op" => "update", "issue_id" => "tw-2", "actor" => "editor" },
      { "seq" => 6, "op" => "close", "issue_id" => "tw-9", "actor" => "" },
      { "seq" => 7, "op" => "close", "issue_id" => "tw-8" }
    ]

    assert_equal({ "tw-2" => "second" }, Beadview::Timeline.closers(events: events))
  end
end
