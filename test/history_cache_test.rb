# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class HistoryCacheTest < Minitest::Test
  T = Time.iso8601("2026-11-05T09:00:00+09:00")

  def with_dir(&)
    Dir.mktmpdir(&)
  end

  def counting(value)
    calls = 0
    block = proc do
      calls += 1
      value
    end
    [block, -> { calls }]
  end

  def test_none_always_calls_block
    block, calls = counting(T)
    2.times { Beadview::HistoryCache::NONE.since(repo_path: "/r", id: "a", updated_at: "u1", &block) }

    assert_equal 2, calls.call
  end

  def test_calls_block_once_for_same_updated_at
    with_dir do |dir|
      block, calls = counting(T)
      first = Beadview::HistoryCache.new(dir: dir).since(repo_path: "/r", id: "a", updated_at: "u1", &block)
      second = Beadview::HistoryCache.new(dir: dir).since(repo_path: "/r", id: "a", updated_at: "u1", &block)

      assert_equal 1, calls.call
      assert_equal T, first
      assert_equal T, second
    end
  end

  def test_recomputes_when_updated_at_changes
    with_dir do |dir|
      cache = Beadview::HistoryCache.new(dir: dir)
      block, calls = counting(T)
      cache.since(repo_path: "/r", id: "a", updated_at: "u1", &block)
      cache.since(repo_path: "/r", id: "a", updated_at: "u2", &block)

      assert_equal 2, calls.call
    end
  end

  def test_keys_are_per_repo_and_id
    with_dir do |dir|
      cache = Beadview::HistoryCache.new(dir: dir)
      block, calls = counting(T)
      cache.since(repo_path: "/r1", id: "a", updated_at: "u1", &block)
      cache.since(repo_path: "/r2", id: "a", updated_at: "u1", &block)
      cache.since(repo_path: "/r1", id: "b", updated_at: "u1", &block)

      assert_equal 3, calls.call
    end
  end

  def test_persists_nil
    with_dir do |dir|
      cache = Beadview::HistoryCache.new(dir: dir)
      block, calls = counting(nil)
      2.times { assert_nil cache.since(repo_path: "/r", id: "a", updated_at: "u1", &block) }

      assert_equal 1, calls.call
    end
  end

  def test_ignores_corrupt_file
    with_dir do |dir|
      cache = Beadview::HistoryCache.new(dir: dir)
      cache.since(repo_path: "/r", id: "a", updated_at: "u1") { T }
      Dir[File.join(dir, "*.json")].each { File.write(_1, "{") }

      assert_equal T, cache.since(repo_path: "/r", id: "a", updated_at: "u1") { T }
    end
  end
end
