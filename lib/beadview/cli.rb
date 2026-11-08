# frozen_string_literal: true

require "optparse"

module Beadview
  module CLI
    BANNER = "beadview — beads の作業状況を一画面で見る（読み取り専用）"
    # リポジトリ1つが読めなくても、ほかの表示は止めない
    REPO_ERRORS = [BdError, JSON::ParserError, SystemCallError, ArgumentError].freeze

    module_function

    def run(argv, bd: Bd.new, repo_paths: nil, cache: HistoryCache.new, now: Time.now, out: $stdout)
      opts = parse(argv)
      return usage(out, opts[:help]) if opts[:help]

      cache = HistoryCache::NONE if opts[:no_cache]
      paths = repo_paths || Repos.ghq_paths(runner: Bd::DEFAULT_RUNNER)
      repos = Repos.from_paths(paths: paths)
      repos = repos.select { opts[:repos].include?(_1.name) } if opts[:repos].any?

      views = repos.map { |repo| Thread.new { view_for(repo, bd: bd, cache: cache, now: now, days: opts[:days]) } }.map(&:value)
      out.write(opts[:json] ? Render.json(views: views, now: now, days: opts[:days]) + "\n" : Render.text(views: views, now: now, days: opts[:days]))
      views.any? && views.all?(&:error) ? 1 : 0
    rescue OptionParser::ParseError => e
      out.puts e.message
      2
    end

    def view_for(repo, bd:, cache:, now:, days:)
      issues = bd.list_all(repo.path)
      since_by_id = issues.select { _1["status"] == "in_progress" }.to_h do |issue|
        since = cache.since(repo_path: repo.path, id: issue["id"], updated_at: issue["updated_at"]) do
          Timeline.in_progress_since(entries: bd.history(repo.path, issue["id"]))
        end
        [issue["id"], since]
      end
      Snapshot.build(repo: repo, issues: issues, ready: bd.ready(repo.path), since_by_id: since_by_id,
                     closers: Timeline.closers(events: bd.events(repo.path)), now: now, days: days)
    rescue *REPO_ERRORS => e
      Snapshot.failed(repo: repo, message: e.message.lines.first.to_s.strip)
    end

    def parse(argv)
      opts = { days: 3, repos: [], json: false, no_cache: false, help: nil }
      parser = OptionParser.new do |o|
        o.banner = "#{BANNER}\n\nusage: beadview [options]"
        o.on("--days N", Integer, "最近閉じたものを何日さかのぼるか（既定 3）") { opts[:days] = _1 }
        o.on("--repo NAME", "リポジトリ名で絞る（複数可）") { opts[:repos] << _1 }
        o.on("--json", "JSON で出す") { opts[:json] = true }
        o.on("--no-cache", "bd history のキャッシュを使わない") { opts[:no_cache] = true }
        o.on("-h", "--help", "このヘルプ") { opts[:help] = o.help }
      end
      parser.parse(argv)
      opts
    end

    def usage(out, text)
      out.puts text
      0
    end
  end
end
