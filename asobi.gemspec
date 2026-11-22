# frozen_string_literal: true

require_relative "lib/asobi/version"

Gem::Specification.new do |spec|
  spec.name = "asobi"
  spec.version = Asobi::VERSION
  spec.authors = ["Hayato1031"]
  spec.summary = "Make SVG pictures and looping animations with Ruby objects, and let them react to clicks and sound."
  spec.description = "asobi (Japanese for 'play') is a Ruby library for making pictures and looping animations. " \
                     "A picture is a Ruby object: repeat a petal eight times, arrange the petals into a flower, and spin the whole flower. " \
                     "Give your own objects a visual form by defining to_art. " \
                     "Let a motion react to a click, the pointer, a key, the microphone or a song, " \
                     "and make notes and drum sounds, for live coding and VJ sets. " \
                     "Run the asobi command to see your sketch update in the browser as you edit. " \
                     "Export a still as SVG, or an animation as a standalone HTML file that still reacts and carries its song."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.homepage = "https://asobi.myura.me/"
  spec.metadata["documentation_uri"] = "https://asobi.myura.me/reference"
  spec.metadata["source_code_uri"] = "https://github.com/Hayato1031/asobi"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Hayato1031/asobi/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["changelog_uri"] = "https://github.com/Hayato1031/asobi/blob/v#{spec.version}/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "README.ja.md", "CHANGELOG.md", "LICENSE", "DESIGN.md"]
  spec.bindir = "exe"
  spec.executables = ["asobi"]
  spec.require_paths = ["lib"]
end
