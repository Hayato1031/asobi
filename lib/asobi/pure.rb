# frozen_string_literal: true

# The core of asobi, without touching Ruby itself: no to_art on Integer,
# no shape words on Object. Write Asobi.circle(...) and Asobi.art(8).
require_relative "version"
require_relative "messages"
require_relative "geometry"
require_relative "color"
require_relative "random"
require_relative "shapes"
require_relative "art"
require_relative "nodes"
require_relative "many"
require_relative "svg"

# Parts that live in their own files: pictures in motion, and the reel a
# browser plays. Neither touches Ruby's own classes.
%w[motion reel].each do |part|
  path = File.join(__dir__, "#{part}.rb")
  require path if File.exist?(path)
end
