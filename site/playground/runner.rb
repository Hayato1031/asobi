# ---- the playground's entry point (site/playground/runner.rb) ------------
module Asobi
  # What the web playground calls, once per edit: run the code the way the
  # live view does (Sketch.run resets the random call counter, so an edit
  # never re-scatters) and answer the Reel as a JSON string.
  module Web
    module_function

    def run(source, language)
      Asobi.language = language.to_s == "ja" ? :ja : :en
      JSON.generate(Sketch.run(source.to_s, name: "play.rb"))
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      JSON.generate(Reel.error("#{e.class}: #{e.message}", code: source.to_s))
    end
  end
end
