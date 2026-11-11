# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

task default: :test

desc "Build the website (docs + playground) from site/ into _site/"
task :site do
  ruby "-Ilib", "site/build.rb", "--out", "_site"
end
