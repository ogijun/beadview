# frozen_string_literal: true

require_relative "test_helper"

class RenderTest < Minitest::Test
  NOW = Time.new(2026, 11, 8, 21, 0, 0, "+09:00")
  TW = Beadview::Repo.new(name: "team_wiki", path: "/r/team_wiki")
  RA = Beadview::Repo.new(name: "reserve_app", path: "/r/reserve_app")

  def view(repo: TW, working: [], closed: [], awaiting: [], ready_count: 0, error: nil, pr_error: nil)
    Beadview::RepoView.new(repo: repo, working: working, closed: closed, awaiting: awaiting, ready_count: ready_count,
                           error: error, pr_error: pr_error)
  end

  def working(id, title: "t", assignee: "a-claude", since: NOW - 3600, prs: [])
    Beadview::Working.new(id: id, title: title, assignee: assignee, since: since, prs: prs)
  end

  def closed(id, closer: "a-codex", guessed: false, reason: nil, at: NOW - 7200, prs: [])
    Beadview::Closed.new(id: id, title: "t", closed_at: at, reason: reason, closer: closer, guessed: guessed, prs: prs)
  end

  def text(views, days: 3) = Beadview::Render.text(views: views, now: NOW, days: days)

  def test_width_counts_fullwidth_as_two
    assert_equal 5, Beadview::Render.width("資料a")
  end

  # 実データで列がずれた文字。・ー は Katakana ではなく Common に属する
  def test_width_of_common_cjk_marks_and_halfwidth_kana
    assert_equal 4, Beadview::Render.width("・ー")
    assert_equal 6, Beadview::Render.width("（、）")
    assert_equal 2, Beadview::Render.width("ｶﾅ")
    assert_equal 2, Beadview::Render.width("한")
  end

  def test_ago_buckets
    assert_equal "たった今から", Beadview::Render.ago(NOW - 30, NOW)
    assert_equal "15分前から", Beadview::Render.ago(NOW - (15 * 60), NOW)
    assert_equal "2時間前から", Beadview::Render.ago(NOW - (2 * 3600), NOW)
    assert_equal "3日前から", Beadview::Render.ago(NOW - (3 * 86_400), NOW)
  end

  def test_text_has_three_headings_with_days
    out = text([view])

    assert_includes out, "── 着手中 "
    assert_includes out, "── 最近閉じたもの（3日以内）"
    assert_includes out, "── 着手できるもの "
    out.lines.grep(/\A── /).each { assert_equal 50, Beadview::Render.width(_1.chomp) }
  end

  def test_long_japanese_title_truncated_and_aligned
    long = "資料一覧のフィルタを足して検索結果を絞り込めるようにする"
    out = text([view(working: [working("tw-1", title: long, assignee: "x-codex"),
                               working("tw-22", title: "短い", assignee: "y-claude")])])
    rows = out.lines.select { _1.include?("x-codex") || _1.include?("y-claude") }

    assert_equal 2, rows.size
    assert_includes rows[0], "…"
    starts = rows.map { |r| Beadview::Render.width(r[0, r.index(/[xy]-c/)]) }
    assert_equal starts[0], starts[1]
    title_part = rows[0][/資料.*…/]
    assert_includes 29..30, Beadview::Render.width(title_part)
  end

  def test_missing_since_shows_dash
    out = text([view(working: [working("tw-3", assignee: nil, since: nil)])])
    row = out.lines.find { _1.include?("tw-3") }

    assert_match(/\?\s+—$/, row.chomp)
  end

  def test_guessed_closer_has_question_mark
    out = text([view(closed: [closed("tw-2", closer: "y-codex", guessed: true), closed("tw-4", closer: nil, guessed: true),
                              closed("tw-5", closer: "z-claude")])])

    assert_match(/y-codex\?$/, out.lines.find { _1.include?("tw-2") }.chomp)
    assert_match(/\s\?$/, out.lines.find { _1.include?("tw-4") }.chomp)
    assert_match(/z-claude$/, out.lines.find { _1.include?("tw-5") }.chomp)
  end

  def test_reason_on_next_line
    out = text([view(closed: [closed("tw-2", reason: "PR #10 でマージ。\nテスト済み")])])
    lines = out.lines.map(&:chomp)
    i = lines.index { _1.include?("tw-2") }

    assert_match(%r{\A11/08 team_wiki}, lines[i])
    assert_equal "      → PR #10 でマージ。 テスト済み", lines[i + 1]
  end

  def test_empty_section_shows_nashi
    out = text([view(ready_count: 0)])

    assert_equal 3, out.scan("（なし）").size
  end

  def pr(number, state) = Beadview::PullRequest.new(number: number, state: state)

  def test_working_row_ends_with_pr_states_and_flags_forgotten_close
    out = text([view(working: [working("tw-1", prs: [pr(261, :merged), pr(254, :closed)]),
                               working("tw-2", prs: [pr(247, :draft)])])])

    assert_match(/前から  閉じ忘れ\? #261 merged · #254 closed$/, out.lines.find { _1.include?("tw-1") }.chomp)
    assert_match(/から  #247 draft$/, out.lines.find { _1.include?("tw-2") }.chomp)
  end

  def test_awaiting_section_sits_between_working_and_closed
    out = text([view(awaiting: [closed("tw-9", prs: [pr(261, :merged), pr(247, :open)])])])
    heads = out.lines.grep(/\A── /).map(&:chomp)
    row = out.lines.find { _1.include?("tw-9") }.chomp

    assert_equal ["── 着手中 ", "── マージ待ち（閉じたが PR が開いている）", "── 最近閉じたもの（3日以内）"],
                 heads.first(3).map { _1.sub(/─+\z/, "") }
    assert_match(/\Ateam_wiki\s+tw-9\s+t\s+#247 open$/, row, "片付いた PR は出さない")
  end

  def test_unknown_prs_are_not_printed
    out = text([view(working: [working("tw-1", prs: [pr(3, :unknown), pr(27, :open)])])])

    assert_match(/から  #27 open$/, out.lines.find { _1.include?("tw-1") }.chomp)
  end

  def test_closed_row_shows_prs_after_closer
    out = text([view(closed: [closed("tw-2", closer: "y-codex", prs: [pr(67, :merged)])])])

    assert_match(/y-codex  #67 merged$/, out.lines.find { _1.include?("tw-2") }.chomp)
  end

  def test_pr_error_listed_without_hiding_repo
    out = text([view(ready_count: 2, pr_error: "gh が見つかりません")])

    assert_includes out, "team_wiki 2件"
    assert_includes out, "── PR の状態を取れなかったリポジトリ "
    assert_includes out, "team_wiki: gh が見つかりません"
  end

  def test_json_has_prs_stale_and_awaiting
    views = [view(working: [working("tw-1", prs: [pr(261, :merged)])],
                  awaiting: [closed("tw-9", prs: [pr(247, :open)])], pr_error: "x")]
    repo = JSON.parse(Beadview::Render.json(views: views, now: NOW, days: 3))["repos"][0]

    assert_equal [{ "number" => 261, "state" => "merged" }], repo["working"][0]["prs"]
    assert_equal true, repo["working"][0]["stale"]
    assert_equal "tw-9", repo["awaiting"][0]["id"]
    assert_equal "open", repo["awaiting"][0]["prs"][0]["state"]
    assert_equal "x", repo["pr_error"]
  end

  def test_error_repo_listed_and_excluded_from_ready
    out = text([view(ready_count: 2), view(repo: RA, ready_count: nil, error: "database is locked")])

    assert_includes out, "team_wiki 2件"
    refute_includes out, "reserve_app 0件"
    refute_match(/reserve_app \d+件/, out)
    assert_includes out, "── 読み込めなかったリポジトリ "
    assert_includes out, "reserve_app: database is locked"
  end

  def test_json_roundtrip
    views = [view(working: [working("tw-1")], closed: [closed("tw-2", guessed: true)], ready_count: 1),
             view(repo: RA, ready_count: nil, error: "boom")]
    data = JSON.parse(Beadview::Render.json(views: views, now: NOW, days: 3))

    assert_equal 2, data["repos"].size
    assert_equal 3, data["days"]
    assert_equal "tw-1", data["repos"][0]["working"][0]["id"]
    assert_equal (NOW - 3600).iso8601, data["repos"][0]["working"][0]["since"]
    assert_equal true, data["repos"][0]["closed"][0]["guessed"]
    assert_equal "boom", data["repos"][1]["error"]
  end
end
