# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "beadview"
  spec.version = "0.1.0"
  spec.summary = "beads の作業状況を一画面で見る（読み取り専用）"
  spec.authors = ["Junya Ogino"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "exe/*"]
  spec.bindir = "exe"
  spec.executables = ["beadview"]
end
