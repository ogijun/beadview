# frozen_string_literal: true

require "json"
require "time"

module Beadview
  module Render
    # East Asian Width が W/F の主な範囲。文字種（script）で見ると ・ ー が漏れ、半角カナが入ってしまう
    WIDE = /[\u{1100}-\u{115F}\u{2E80}-\u{303E}\u{3041}-\u{33FF}\u{3400}-\u{4DBF}\u{4E00}-\u{9FFF}\u{A960}-\u{A97F}\u{AC00}-\u{D7A3}\u{F900}-\u{FAFF}\u{FE30}-\u{FE4F}\u{FF00}-\u{FF60}\u{FFE0}-\u{FFE6}\u{1F300}-\u{1F64F}\u{1F900}-\u{1F9FF}\u{20000}-\u{3FFFD}]/
    HEADING_WIDTH = 50
    TITLE_WIDTH = 30
    REASON_WIDTH = 80
    NONE = "（なし）"

    module_function

    # pr: false のときは PR を調べていないので、「マージ待ち（なし）」と言い切らずに区分ごと出さない
    def text(views:, now:, days:, pr: true)
      ok = views.reject(&:error)
      failed = views.select(&:error)
      sections = [
        [heading("── 着手中 "), working_lines(ok, now)],
        ([heading("── マージ待ち（閉じたが PR が開いている）"), awaiting_lines(ok)] if pr),
        [heading("── 最近閉じたもの（#{days}日以内）"), closed_lines(ok, now)],
        [heading("── 着手できるもの "), ready_lines(ok)]
      ].compact
      sections << [heading("── 読み込めなかったリポジトリ "), failed.map { "#{_1.repo.name}: #{_1.error}" }] if failed.any?
      pr_failed = ok.select(&:pr_error)
      sections << [heading("── PR の状態を取れなかったリポジトリ "), pr_failed.map { "#{_1.repo.name}: #{_1.pr_error}" }] if pr_failed.any?
      sections.map { |head, lines| [head, *(lines.empty? ? [NONE] : lines)].join("\n") }.join("\n\n") + "\n"
    end

    def json(views:, now:, days:)
      JSON.pretty_generate(
        "generated_at" => now.iso8601,
        "days" => days,
        "repos" => views.map { repo_hash(_1) }
      )
    end

    def width(str)
      str.each_char.sum { WIDE.match?(_1) ? 2 : 1 }
    end

    def ago(time, now)
      sec = now - time
      return "たった今から" if sec < 60
      return "#{(sec / 60).floor}分前から" if sec < 3600
      return "#{(sec / 3600).floor}時間前から" if sec < 86_400

      "#{(sec / 86_400).floor}日前から"
    end

    def heading(label)
      label + ("─" * [HEADING_WIDTH - width(label), 0].max)
    end

    def working_lines(views, now)
      rows = views.flat_map do |v|
        v.working.map do
          [v.repo.name, _1.id, truncate(_1.title.to_s, TITLE_WIDTH), _1.assignee || "?", _1.since ? ago(_1.since, now) : "—",
           [("閉じ忘れ?" if _1.stale?), prs_label(_1.prs)].compact.join(" ")]
        end
      end
      table(rows)
    end

    # 片付いた PR は出さない。ここで見たいのは「どこで止まっているか」
    def awaiting_lines(views)
      rows = views.flat_map do |v|
        v.awaiting.map { [v.repo.name, _1.id, truncate(_1.title.to_s, TITLE_WIDTH), prs_label(_1.prs.select(&:pending?))] }
      end
      table(rows)
    end

    def prs_label(prs)
      prs.select(&:known?).map { "##{_1.number} #{_1.state}" }.join(" · ")
    end

    def closed_lines(views, now)
      items = views.flat_map { |v| v.closed.map { [v.repo.name, _1] } }.sort_by { |_, c| -c.closed_at.to_f }
      rows = items.map do |name, c|
        ["#{c.closed_at.getlocal(now.utc_offset).strftime('%m/%d')} #{name}", c.id, truncate(c.title.to_s, TITLE_WIDTH), closer(c),
         prs_label(c.prs)]
      end
      table(rows).zip(items).flat_map do |line, (_, c)|
        reason = c.reason.to_s.gsub(/\s*\R\s*/, " ").strip
        reason.empty? ? [line] : [line, "      → #{truncate(reason, REASON_WIDTH)}"]
      end
    end

    def ready_lines(views)
      views.empty? ? [] : [views.map { "#{_1.repo.name} #{_1.ready_count}件" }.join(" / ")]
    end

    def closer(item)
      return item.closer.to_s unless item.guessed

      "#{item.closer}?"
    end

    # 最後の列以外を表示幅でそろえる。最後の列が空なら行末の空白は残さない
    def table(rows)
      return [] if rows.empty?

      widths = rows.transpose[0...-1].map { |col| col.map { width(_1) }.max }
      rows.map do |row|
        cells = row[0...-1].each_with_index.map { |cell, i| pad(cell, widths[i]) }
        (cells << row.last).join("  ").rstrip
      end
    end

    def pad(str, to) = str + (" " * (to - width(str)))

    def truncate(str, max)
      return str if width(str) <= max

      out = +""
      str.each_char do |ch|
        break if width(out) + width(ch) > max - 1

        out << ch
      end
      "#{out}…"
    end

    def repo_hash(view)
      {
        "name" => view.repo.name,
        "error" => view.error,
        "ready_count" => view.ready_count,
        "pr_error" => view.pr_error,
        "working" => view.working.map do
          { "id" => _1.id, "title" => _1.title, "assignee" => _1.assignee, "since" => _1.since&.iso8601,
            "prs" => prs_hash(_1.prs), "stale" => _1.stale? }
        end,
        "awaiting" => view.awaiting.map { closed_hash(_1) },
        "closed" => view.closed.map { closed_hash(_1) }
      }
    end

    def closed_hash(item)
      { "id" => item.id, "title" => item.title, "closed_at" => item.closed_at.iso8601, "reason" => item.reason,
        "closer" => item.closer, "guessed" => item.guessed, "prs" => prs_hash(item.prs) }
    end

    def prs_hash(prs) = prs.map { { "number" => _1.number, "state" => _1.state.to_s } }
  end
end
