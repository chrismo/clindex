# frozen_string_literal: true

require 'bundler/gem_tasks'
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "src"
  t.test_files = FileList['test/**/*test.rb']
end

task default: :test

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: :rubocop
