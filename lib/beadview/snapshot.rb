# frozen_string_literal: true

require "time"

module Beadview
  Working = Data.define(:id, :title, :assignee, :since, :prs) do
    def initialize(prs: [], **) = super

    # 書かれた PR がすべて片付き、1つはマージされている。作業は終わっていて、閉じ忘れの疑いがある
    def stale? = prs.any? && prs.all?(&:finished?) && prs.any? { _1.state == :merged }
  end

  Closed = Data.define(:id, :title, :closed_at, :reason, :closer, :guessed, :prs) do
    def initialize(prs: [], **) = super
  end

  RepoView = Data.define(:repo, :working, :closed, :awaiting, :ready_count, :error, :pr_error) do
    def initialize(awaiting: [], pr_error: nil, **) = super
  end

  module Snapshot
    DAY = 86_400

    module_function

    def build(repo:, issues:, ready:, since_by_id:, closers:, now:, days:, prs: {}, pr_error: nil)
      RepoView.new(
        repo: repo,
        working: working(issues, since_by_id, prs),
        closed: closed(issues, closers, prs, now - (days * DAY)),
        awaiting: awaiting(issues, closers, prs),
        ready_count: ready.size,
        error: nil,
        pr_error: pr_error
      )
    end

    def failed(repo:, message:)
      RepoView.new(repo: repo, working: [], closed: [], ready_count: nil, error: message)
    end

    def working(issues, since_by_id, prs)
      issues
        .select { _1["status"] == "in_progress" }
        .map do
          Working.new(id: _1["id"], title: _1["title"], assignee: _1["assignee"], since: since_by_id[_1["id"]],
                      prs: PullRequests.lookup(_1, prs))
        end
    end

    def closed(issues, closers, prs, cutoff)
      closed_items(issues, closers, prs).select { _1.closed_at >= cutoff }
    end

    # 閉じたのに PR がまだ開いている。時期は問わない
    def awaiting(issues, closers, prs)
      closed_items(issues, closers, prs).select { |item| item.prs.any?(&:pending?) }
    end

    def closed_items(issues, closers, prs)
      issues
        .select { _1["status"] == "closed" && _1["closed_at"] }
        .map { closed_item(_1, Time.iso8601(_1["closed_at"]), closers[_1["id"]], PullRequests.lookup(_1, prs)) }
        .sort_by { -_1.closed_at.to_f }
    end

    # events に記録があればそれを、無ければ担当者を推測として使う
    def closed_item(issue, at, recorded, prs)
      Closed.new(id: issue["id"], title: issue["title"], closed_at: at, reason: issue["close_reason"],
                 closer: recorded || issue["assignee"], guessed: recorded.nil?, prs: prs)
    end
  end
end
