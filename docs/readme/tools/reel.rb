# Runs a sketch and writes its reel (every frame as SVG) to a JSON file.
#
#   ruby docs/readme/tools/reel.rb examples/showcase/hanabi.rb /tmp/hanabi.json
#   node docs/readme/tools/gif.mjs /tmp/hanabi.json docs/readme/media/hanabi.gif 760 422 20
#
# gif.mjs draws each frame in headless Chrome and hands the PNGs to ffmpeg.
# Give it a .png name (and a frame number last) for one still picture.
# COLORS=64 and DITHER=none in the environment make a smaller file.
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
ENV["ASOBI_LIVE"] = "0"
require "asobi"
require "json"

sketch, out = ARGV
abort "usage: ruby reel.rb SKETCH.rb OUT.json" unless sketch && out

reel = Asobi::Sketch.evaluate(File.expand_path(sketch))
abort reel["error"] if reel["error"]
reel["code"] = nil
json = JSON.generate(reel)
File.write(out, json)
warn "#{sketch}: #{reel["frames"].size} frames at #{reel["fps"]} fps, #{json.bytesize / 1000} KB"
