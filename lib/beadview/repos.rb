# frozen_string_literal: true

module Beadview
  Repo = Data.define(:name, :path)

  module Repos
    module_function

    # .beads/ ディレクトリを持つものだけ。symlink 経由の重複は realpath で除く
    def from_paths(paths:)
      paths
        .select { File.directory?(File.join(_1, ".beads")) }
        .map { File.realpath(_1) }
        .uniq
        .map { Repo.new(name: File.basename(_1), path: _1) }
        .sort_by(&:name)
    end

    def ghq_paths(runner:)
      stdout, _stderr, ok = runner.call(["ghq", "list", "-p"])
      return [] unless ok

      stdout.lines.map(&:strip).reject(&:empty?)
    end
  end
end
