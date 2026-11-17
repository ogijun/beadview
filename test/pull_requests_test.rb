# frozen_string_literal: true

require_relative "test_helper"

class PullRequestsTest < Minitest::Test
  include FixtureHelper

  PR = Beadview::PullRequest

  def test_refs_in_order_of_appearance_without_duplicates
    issue = { "title" => "PR #3 を見直す", "notes" => "#261 を作成。#258/#254を置換する。#3",
              "close_reason" => "PR #27 ready" }

    assert_equal [3, 261, 258, 254, 27], Beadview::PullRequests.refs(issue)
  end

  # GH#2950 のような他所の番号や、色コードの類は拾わない
  def test_refs_ignore_hash_glued_to_a_word
    assert_empty Beadview::PullRequests.refs({ "title" => "GH#2950 と abc#12", "notes" => nil })
  end

  def test_lookup_keeps_only_known_numbers_in_ref_order
    known = { 261 => PR.new(number: 261, state: :merged), 254 => PR.new(number: 254, state: :closed) }
    issue = { "notes" => "#261 #999 #254" }

    assert_equal [261, 254], Beadview::PullRequests.lookup(issue, known).map(&:number)
  end

  def test_slug_from_remote_urls
    %w[git@github.com:ogijun/team_wiki.git https://github.com/ogijun/team_wiki
       https://github.com/ogijun/team_wiki.git ssh://git@github.com/ogijun/team_wiki.git].each do |url|
      assert_equal "ogijun/team_wiki", Beadview::PullRequests.slug(url), url
    end
    assert_nil Beadview::PullRequests.slug("git@gitlab.com:ogijun/x.git")
  end

  def test_gh_fetches_states_for_the_origin_repo
    calls = []
    runner = lambda do |argv|
      calls << argv
      next ["git@github.com:ogijun/team_wiki.git\n", "", true] if argv.first == "git"

      [JSON.generate([{ "number" => 261, "state" => "MERGED", "isDraft" => false },
                      { "number" => 247, "state" => "OPEN", "isDraft" => true },
                      { "number" => 250, "state" => "OPEN", "isDraft" => false },
                      { "number" => 254, "state" => "CLOSED", "isDraft" => false }]), "", true]
    end
    prs = Beadview::Gh.new(runner: runner).pulls("/r/team_wiki")

    assert_equal({ 261 => :merged, 247 => :draft, 250 => :open, 254 => :closed }, prs.transform_values(&:state))
    assert_equal ["git", "-C", "/r/team_wiki", "remote", "get-url", "origin"], calls[0]
    assert_equal %w[gh pr list -R ogijun/team_wiki --state all], calls[1].first(7)
  end

  def test_gh_failure_raises_gh_error
    runner = lambda do |argv|
      argv.first == "git" ? ["git@github.com:o/r.git\n", "", true] : ["", "HTTP 401: Bad credentials\nmore", false]
    end

    error = assert_raises(Beadview::GhError) { Beadview::Gh.new(runner: runner).pulls("/r/x") }
    assert_equal "HTTP 401: Bad credentials", error.message
  end

  def test_gh_without_github_origin_returns_empty
    runner = ->(_argv) { ["", "error: No such remote 'origin'", false] }

    assert_empty Beadview::Gh.new(runner: runner).pulls("/r/x")
  end

  def test_missing_gh_raises_gh_error
    runner = lambda do |argv|
      raise Errno::ENOENT, "gh" if argv.first == "gh"

      ["git@github.com:o/r.git\n", "", true]
    end

    assert_raises(Beadview::GhError) { Beadview::Gh.new(runner: runner).pulls("/r/x") }
  end
end
