# frozen_string_literal: true

require_relative "test_helper"

class SnapshotTest < Minitest::Test
  include FixtureHelper

  NOW = Time.iso8601("2026-11-08T12:00:00Z")
  REPO = Beadview::Repo.new(name: "team_wiki", path: "/r/team_wiki")

  def build(issues: fixture_json("list_all.json"), closers: {}, since_by_id: {}, days: 3, ready: [{}, {}],
            prs: {}, pr_error: nil)
    Beadview::Snapshot.build(repo: REPO, issues: issues, ready: ready, since_by_id: since_by_id,
                             closers: closers, now: NOW, days: days, prs: prs, pr_error: pr_error)
  end

  def closed_issue(id, closed_at, assignee: nil)
    { "id" => id, "title" => id, "status" => "closed", "assignee" => assignee,
      "closed_at" => closed_at, "close_reason" => "done" }
  end

  def test_working_lists_in_progress_with_since
    since = Time.iso8601("2026-11-05T00:00:00Z")
    view = build(since_by_id: { "tw-1" => since })

    assert_equal %w[tw-1 tw-3], view.working.map(&:id)
    assert_equal since, view.working.first.since
    assert_nil view.working.last.since
    assert_equal "資料一覧のフィルタを足す", view.working.first.title
  end

  def test_closed_within_days_sorted_desc
    issues = [
      closed_issue("old", "2026-11-04T11:59:59Z"),
      closed_issue("edge", "2026-11-05T12:00:00Z"),
      closed_issue("new", "2026-11-08T08:00:00Z")
    ]
    view = build(issues: issues)

    assert_equal %w[new edge], view.closed.map(&:id)
    assert_equal Time.iso8601("2026-11-08T08:00:00Z"), view.closed.first.closed_at
    assert_equal "done", view.closed.first.reason
  end

  def test_closed_without_closed_at_is_excluded
    refute_includes build.closed.map(&:id), "tw-4"
  end

  def test_closer_prefers_events_then_guesses_assignee
    issues = [closed_issue("a", "2026-11-08T00:00:00Z", assignee: "x-claude"),
              closed_issue("b", "2026-11-08T01:00:00Z", assignee: "y-codex")]
    view = build(issues: issues, closers: { "a" => "z-codex" })
    by_id = view.closed.to_h { [_1.id, _1] }

    assert_equal ["z-codex", false], [by_id["a"].closer, by_id["a"].guessed]
    assert_equal ["y-codex", true], [by_id["b"].closer, by_id["b"].guessed]
  end

  def test_nil_assignee_kept_as_nil
    view = build(issues: [closed_issue("c", "2026-11-08T00:00:00Z")])

    assert_nil view.working.find { _1.id == "tw-3" }
    assert_equal [nil, true], [view.closed.first.closer, view.closed.first.guessed]
    assert_nil build.working.find { _1.id == "tw-3" }.assignee
  end

  def test_ready_count_and_no_error
    view = build

    assert_equal 2, view.ready_count
    assert_nil view.error
    assert_equal REPO, view.repo
  end

  def pr(number, state) = Beadview::PullRequest.new(number: number, state: state)

  def test_working_carries_pr_states_and_flags_forgotten_close
    issues = [
      { "id" => "done", "title" => "t", "status" => "in_progress", "notes" => "PR #261 作成。#254 を置換" },
      { "id" => "wip", "title" => "t", "status" => "in_progress", "notes" => "PR #247 draft" },
      { "id" => "dropped", "title" => "t", "status" => "in_progress", "notes" => "#254 は閉じた" },
      { "id" => "none", "title" => "t", "status" => "in_progress" }
    ]
    prs = { 261 => pr(261, :merged), 254 => pr(254, :closed), 247 => pr(247, :draft) }
    by_id = build(issues: issues, prs: prs).working.to_h { [_1.id, _1] }

    assert_equal [261, 254], by_id["done"].prs.map(&:number)
    assert_predicate by_id["done"], :stale?
    refute_predicate by_id["wip"], :stale?
    refute_predicate by_id["dropped"], :stale?, "マージされずに閉じただけなら、作業が終わったとは言えない"
    refute_predicate by_id["none"], :stale?
  end

  def test_unknown_pr_blocks_forgotten_close
    issues = [{ "id" => "w", "title" => "t", "status" => "in_progress", "notes" => "#100 の続き。#620 はマージ済み" }]
    view = build(issues: issues, prs: { 620 => pr(620, :merged) })

    refute_predicate view.working.first, :stale?
  end

  # 閉じた時期を問わず、PR がまだ開いているものを拾う
  def test_awaiting_lists_closed_beads_with_pending_pr
    issues = [
      closed_issue("old-open", "2026-10-01T00:00:00Z").merge("close_reason" => "PR #247 ready"),
      closed_issue("merged", "2026-11-08T00:00:00Z").merge("close_reason" => "PR #261 merged"),
      closed_issue("new-open", "2026-11-08T01:00:00Z").merge("notes" => "#250")
    ]
    prs = { 247 => pr(247, :draft), 261 => pr(261, :merged), 250 => pr(250, :open) }
    view = build(issues: issues, prs: prs)

    assert_equal %w[new-open old-open], view.awaiting.map(&:id)
    assert_equal [250], view.awaiting.first.prs.map(&:number)
    assert_equal [261], view.closed.find { _1.id == "merged" }.prs.map(&:number)
  end

  def test_pr_error_is_kept_without_failing_the_repo
    view = build(pr_error: "gh が見つかりません")

    assert_equal "gh が見つかりません", view.pr_error
    assert_nil view.error
    assert_empty view.awaiting
  end

  def test_failed_has_error_and_no_counts
    view = Beadview::Snapshot.failed(repo: REPO, message: "database is locked")

    assert_equal "database is locked", view.error
    assert_nil view.ready_count
    assert_empty view.working
    assert_empty view.closed
  end
end
