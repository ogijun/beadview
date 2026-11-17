# frozen_string_literal: true

require "json"

module Beadview
  class GhError < StandardError; end

  # state は :open / :draft / :merged / :closed（マージされずに閉じた）
  PullRequest = Data.define(:number, :state) do
    def finished? = %i[merged closed].include?(state)
    def pending? = !finished?
  end

  # bead の文面に書かれた「#123」を、そのリポジトリの PR として読む
  module PullRequests
    FIELDS = %w[title notes close_reason].freeze
    # \b は「#254を」の「を」を単語の続きとみなすので使わない
    REF = /(?<![\w#])#(\d+)(?!\d)/
    SLUG = %r{github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?\z}

    module_function

    def refs(issue)
      FIELDS.flat_map { issue[_1].to_s.scan(REF).flatten }.map(&:to_i).uniq
    end

    # 番号が PR として見つかったものだけ。issue 番号や古すぎる PR は黙って落とす
    def lookup(issue, known)
      refs(issue).filter_map { known[_1] }
    end

    def slug(url)
      url.to_s.strip[SLUG, 1]
    end
  end

  # gh を呼ぶ唯一の場所。読むだけ
  class Gh
    LIMIT = 500

    def initialize(runner: Bd::DEFAULT_RUNNER)
      @runner = runner
    end

    # GitHub の origin が無いリポジトリは、PR が無いものとして扱う
    def pulls(repo_path)
      url, _stderr, ok = @runner.call(["git", "-C", repo_path, "remote", "get-url", "origin"])
      slug = ok && PullRequests.slug(url)
      return {} unless slug

      stdout, stderr, ok = call_gh(["gh", "pr", "list", "-R", slug, "--state", "all", "--limit", LIMIT.to_s,
                                    "--json", "number,state,isDraft"])
      raise GhError, stderr.to_s.lines.first.to_s.strip unless ok

      JSON.parse(stdout).to_h { [_1["number"], PullRequest.new(number: _1["number"], state: state(_1))] }
    end

    private

    def call_gh(argv)
      @runner.call(argv)
    rescue Errno::ENOENT
      raise GhError, "gh が見つかりません"
    end

    def state(row)
      return :draft if row["state"] == "OPEN" && row["isDraft"]

      row["state"].downcase.to_sym
    end
  end
end
