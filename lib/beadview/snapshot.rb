# frozen_string_literal: true

require "time"

module Beadview
  Working = Data.define(:id, :title, :assignee, :since)
  Closed = Data.define(:id, :title, :closed_at, :reason, :closer, :guessed)
  RepoView = Data.define(:repo, :working, :closed, :ready_count, :error)

  module Snapshot
    DAY = 86_400

    module_function

    def build(repo:, issues:, ready:, since_by_id:, closers:, now:, days:)
      RepoView.new(
        repo: repo,
        working: working(issues, since_by_id),
        closed: closed(issues, closers, now - (days * DAY)),
        ready_count: ready.size,
        error: nil
      )
    end

    def failed(repo:, message:)
      RepoView.new(repo: repo, working: [], closed: [], ready_count: nil, error: message)
    end

    def working(issues, since_by_id)
      issues
        .select { _1["status"] == "in_progress" }
        .map { Working.new(id: _1["id"], title: _1["title"], assignee: _1["assignee"], since: since_by_id[_1["id"]]) }
    end

    def closed(issues, closers, cutoff)
      issues
        .select { _1["status"] == "closed" && _1["closed_at"] }
        .map { [_1, Time.iso8601(_1["closed_at"])] }
        .select { |_, at| at >= cutoff }
        .sort_by { |_, at| -at.to_f }
        .map { |issue, at| closed_item(issue, at, closers[issue["id"]]) }
    end

    # events に記録があればそれを、無ければ担当者を推測として使う
    def closed_item(issue, at, recorded)
      Closed.new(id: issue["id"], title: issue["title"], closed_at: at, reason: issue["close_reason"],
                 closer: recorded || issue["assignee"], guessed: recorded.nil?)
    end
  end
end
