# frozen_string_literal: true

require "time"

module Beadview
  module Timeline
    module_function

    # bd history の行（新しい順で届く）から、いま着手中なら「最後に着手中になった時刻」を返す
    def in_progress_since(entries:)
      steps = entries
        .map { [Time.iso8601(_1["CommitDate"]), _1.dig("Issue", "status")] }
        .sort_by(&:first)
      return nil unless steps.last&.last == "in_progress"

      steps.each_cons(2)
        .select { |(_, before), (_, after)| before != "in_progress" && after == "in_progress" }
        .last
        &.last
        &.first
    end

    # events の close 記録から、bead ごとに最後に閉じた人
    def closers(events:)
      events
        .select { _1["op"] == "close" && !_1["actor"].to_s.empty? }
        .sort_by { _1["seq"] }
        .to_h { [_1["issue_id"], _1["actor"]] }
    end
  end
end
