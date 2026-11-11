# frozen_string_literal: true

require_relative "lib/asobi/version"

Gem::Specification.new do |spec|
  spec.name = "asobi"
  spec.version = Asobi::VERSION
  spec.authors = ["Hayato1031"]
  spec.summary = "Media art in Ruby: objects become pictures, and pictures are objects."
  spec.description = "asobi (play) treats every Ruby object as something that can become a picture, " \
                     "and every picture as an object you can repeat, arrange, combine and set in motion. " \
                     "Run a sketch with plain ruby and it plays live in your browser."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.homepage = "https://github.com/Hayato1031/asobi"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "README.ja.md", "docs/first-sketch.svg", "LICENSE", "DESIGN.md"]
  spec.bindir = "exe"
  spec.executables = ["asobi"]
  spec.require_paths = ["lib"]
end
