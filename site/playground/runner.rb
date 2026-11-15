# ---- the playground's entry point (site/playground/runner.rb) ------------
module Asobi
  # What the web playground calls, once per edit: run the code the way the
  # live view does (Sketch.run resets the random call counter, so an edit
  # never re-scatters) and answer the Reel as a JSON string.
  #
  # In one step:   run(source, language)       the whole Reel
  # In two steps:  start(source, language)     the first Reel: for a motion a
  #                                            quick preview ("pending": true)
  #                finish                      the whole Reel of that motion
  #             or finish_some(seconds)        the same, a slice of about that
  #                                            many seconds at a time: nil until
  #                                            the whole Reel is ready
  #                drop                        give up the half-made whole Reel
  # Between the steps the page can stop when a newer edit is waiting.
  #
  # The playground has no files. It has one song: the loop the site ships
  # as assets/beat.wav (a copy of examples/reactions/beat.wav), so
  # play "beat.wav" plays that; any other name is a teaching error.
  # The id is the file's own (Song id: SHA-256, first 12 characters), so the
  # song goes on while the code changes; site/build.rb checks it.
  # The src is from the site's root; the page puts its own root in front.
  Sketch.playground = {
    "beat.wav" => Song.new(path: "beat.wav", id: "3ff79180f05b", src: "assets/beat.wav")
  }.freeze

  module Web
    module_function

    def run(source, language)
      Asobi.language = language.to_s == "ja" ? :ja : :en
      safely(source) { Sketch.run(source.to_s, name: "play.rb") }
    end

    def start(source, language)
      Asobi.language = language.to_s == "ja" ? :ja : :en
      safely(source) { Sketch.run(source.to_s, name: "play.rb", preview: true) }
    end

    # Did start leave a motion for finish?
    def waiting? = Sketch.waiting?

    # nil when start already answered the whole Reel.
    def finish
      whole = Sketch.finish
      whole && JSON.generate(whole)
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      JSON.generate(Reel.error("#{e.class}: #{e.message}"))
    end

    # One slice of finish: the whole Reel as JSON once it is ready, nil
    # while it is not (waiting? stays true), nil when nothing is waiting.
    def finish_some(seconds)
      whole = Sketch.finish_some(seconds.to_f)
      whole && JSON.generate(whole)
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      Sketch.forget # nothing half-made is left behind
      JSON.generate(Reel.error("#{e.class}: #{e.message}"))
    end

    # A newer edit came: forget the motion waiting for finish.
    def drop = Sketch.forget

    def safely(source)
      JSON.generate(yield)
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      JSON.generate(Reel.error("#{e.class}: #{e.message}", code: source.to_s))
    end
  end
end
