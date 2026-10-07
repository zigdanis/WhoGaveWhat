# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# xcodeproj requires < 4.0; 3.0.9 excludes Ruby >= 3.2. Use the compatible 3.0.8.
gem "CFPropertyList", "3.0.8"
gem "fastlane"
gem "minitest", "~> 5.25"

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
