# frozen_string_literal: true

require "json"
require "open3"

module Beadview
  class BdError < StandardError; end

  # bd を呼ぶ唯一の場所。すべて --readonly で呼び、--json の出力だけを読む。
  class Bd
    DEFAULT_RUNNER = lambda do |argv|
      stdout, stderr, status = Open3.capture3(*argv)
      [stdout, stderr, status.success?]
    end

    def initialize(runner: DEFAULT_RUNNER)
      @runner = runner
    end

    def list_all(repo_path)
      json(repo_path, "list", "--all", "--json", "--limit", "0")
    end

    def ready(repo_path)
      json(repo_path, "ready", "--json", "--limit", "0")
    end

    def history(repo_path, id)
      json(repo_path, "history", id, "--json")
    end

    # journal が無効なときは JSON でない注意書きが混ざるので、読めない行は捨てる。
    # 失敗しても表示を止めるほどのことではないので空にする
    def events(repo_path)
      stdout, _stderr, ok = run(repo_path, "events", "tail")
      return [] unless ok

      utf8(stdout).each_line.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    private

    def json(repo_path, *args)
      stdout, stderr, ok = run(repo_path, *args)
      raise BdError, utf8(stderr).lines.first.to_s.strip unless ok

      JSON.parse(utf8(stdout))
    end

    def run(repo_path, *args)
      @runner.call(["bd", "-C", repo_path, "--readonly", *args])
    end

    # ロケールが UTF-8 でないシェルからでも日本語を読めるように
    def utf8(str)
      str.dup.force_encoding(Encoding::UTF_8)
    end
  end
end
