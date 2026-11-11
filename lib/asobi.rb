# frozen_string_literal: true

# Everything: the core, to_art on Ruby's own objects, and the shape words
# available everywhere.
require_relative "asobi/pure"
require_relative "asobi/core_ext"
require_relative "asobi/top_level"

%w[motion reel sketch].each do |part|
  path = File.join(__dir__, "asobi", "#{part}.rb")
  require path if File.exist?(path)
end
