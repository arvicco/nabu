# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Run RuboCop"
task :lint do
  sh "rubocop"
end

namespace :lint do
  desc "Run RuboCop with safe autocorrections"
  task :fix do
    sh "rubocop -a"
  end
end

task default: :test
