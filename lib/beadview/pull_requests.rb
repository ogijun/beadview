# frozen_string_literal: true

require "json"

module Beadview
  class GhError < StandardError; end

  # state は :open / :draft / :merged / :closed（マージされずに閉じた）/ :unknown（PR として見つからない）。
  # unknown は片付いたとも開いているとも言えないので、どちらの判定にも数えない
  PullRequest = Data.define(:number, :state) do
    def finished? = %i[merged closed].include?(state)
    def pending? = %i[open draft].include?(state)
    def known? = state != :unknown
  end

  # bead の文面に書かれた「#123」を、そのリポジトリの PR として読む
  module PullRequests
    FIELDS = %w[title notes close_reason].freeze
    # 「PR#12」は拾い、「GH#2950」は拾わない。\b は「#254を」の「を」を単語の続きとみなすので使わない
    REF = /(?:(?<![\w#])|(?<=PR)|(?<=pr))#(\d+)(?!\d)/
    SLUG = %r{(?:\A|[@/])github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?\z}

    module_function

    def refs(issue)
      FIELDS.flat_map { issue[_1].to_s.scan(REF).flatten }.map(&:to_i).uniq
    end

    def lookup(issue, known)
      refs(issue).map { known.fetch(_1) { |n| PullRequest.new(number: n, state: :unknown) } }
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
