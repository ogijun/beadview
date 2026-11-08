# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "beadview"
require "minitest/autorun"

module FixtureHelper
  DIR = File.expand_path("fixtures", __dir__)

  def fixture(name)
    File.read(File.join(DIR, name), encoding: "UTF-8")
  end

  def fixture_json(name)
    JSON.parse(fixture(name))
  end

  # bd を呼ぶ代わりに、受け取った argv を記録して決まった出力を返す
  def recording_runner(stdout: "", stderr: "", success: true)
    calls = []
    runner = lambda do |argv|
      calls << argv
      [stdout, stderr, success]
    end
    [runner, calls]
  end
end
