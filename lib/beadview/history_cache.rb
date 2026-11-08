# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module Beadview
  # bd history は1件0.25秒かかるので、bead の updated_at が変わったときだけ読み直す。
  # メモリには持たず、毎回ファイルを読み書きする（リポジトリごとに1ファイル）
  class HistoryCache
    def self.default_dir
      File.join(File.expand_path(ENV.fetch("XDG_CACHE_HOME", "~/.cache")), "beadview")
    end

    def initialize(dir: self.class.default_dir)
      @dir = dir
    end

    def since(repo_path:, id:, updated_at:)
      path = file_for(repo_path)
      entries = load(path)
      hit = entries[id]
      return parse(hit["since"]) if hit && hit["updated_at"] == updated_at

      value = yield
      entries[id] = { "updated_at" => updated_at, "since" => value&.iso8601(3) }
      save(path, entries)
      value
    end

    # --no-cache 用。保存せず毎回読む
    NONE = Object.new
    def NONE.since(repo_path:, id:, updated_at:) = yield

    private

    def file_for(repo_path)
      File.join(@dir, "#{Digest::SHA256.hexdigest(repo_path)[0, 16]}.json")
    end

    def load(path)
      data = JSON.parse(File.read(path))
      data.is_a?(Hash) ? data : {}
    rescue SystemCallError, JSON::ParserError
      {}
    end

    # 書けなくても表示は続ける（次回また bd history を読むだけ）
    def save(path, entries)
      FileUtils.mkdir_p(@dir)
      tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.write(tmp, JSON.generate(entries))
      File.rename(tmp, path)
    rescue SystemCallError
      nil
    end

    def parse(value)
      value && Time.iso8601(value)
    end
  end
end
