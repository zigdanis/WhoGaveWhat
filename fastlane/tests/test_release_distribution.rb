require 'pilot'
require 'fastlane'
require_relative '../testflight_release'

Fastlane.load_actions
fastfile = Fastlane::FastFile.new(File.expand_path('../Fastfile', __dir__))
fastfile.validate_release_notes('en-US' => "What's New\n• Photo saving fixed.", 'ru' => 'Что нового: сохранение фото исправлено.')
['New photo controls 🌱', 'Test children < 3'].each do |text|
  begin
    fastfile.validate_release_notes('en-US' => text)
    raise 'Notes accepted text that pinned Pilot silently changes'
  rescue FastlaneCore::Interface::FastlaneError => error
    raise unless error.message.include?('Fastlane would alter them')
  end
end

release = TestflightRelease.new('GITHUB_REPOSITORY' => 'example/WhoGaveWhat', 'GITHUB_RUN_ID' => '100')
release.instance_variable_set(:@app, { 'id' => 'app' })
release.instance_variable_set(:@group, { 'id' => 'group', 'attributes' => { 'name' => 'External', 'isInternalGroup' => false } })
release.record.merge!('version' => '2.1.4', 'build_number' => '26', 'notes' => {})

options = FastlaneCore::Configuration.create(Pilot::Options.available_options, release.pilot_options)
manager = Pilot::Manager.new
manager.instance_variable_set(:@config, options)
raise 'Distribution must resolve iOS without an IPA or interactive input' unless manager.fetch_app_platform == 'ios'

puts 'Noninteractive distribution platform check passed.'

# Exercise pinned Pilot's real name-based selection, not a copy of its predicate.
class FakePilotBuild
  attr_reader :assigned_groups, :review_submitted

  def initialize(groups)
    @groups = groups
    @assigned_groups = []
  end

  def app_version = '1.0.1'
  def version = '10'
  def uses_non_exempt_encryption = false
  def ready_for_beta_submission? = true
  def post_beta_app_review_submission = @review_submitted = true
  def app = self
  def get_beta_groups = @groups
  def add_beta_groups(beta_groups:) = @assigned_groups.concat(beta_groups)
end

selected = Struct.new(:id, :name).new('group', 'WhoGaveWhat testers')
unrelated = Struct.new(:id, :name).new('other', 'Other testers')
[[false, false], [true, false], [true, true]].each do |internal, all_builds|
  release.instance_variable_set(:@group, {
    'id' => selected.id,
    'attributes' => { 'name' => selected.name, 'isInternalGroup' => internal, 'hasAccessToAllBuilds' => all_builds }
  })
  build = FakePilotBuild.new([unrelated, selected])
  options = release.pilot_options
  Pilot::BuildManager.new.send(:distribute_build, build, options)
  expected = internal && all_builds ? [] : [selected]
  unless build.assigned_groups == expected
    raise "Pinned Pilot did not assign the intended group (internal=#{internal}, all_builds=#{all_builds})"
  end
  raise 'All-builds internal access must not manually select groups' if internal && all_builds && options[:groups]
  raise 'External group must submit beta review' unless internal || build.review_submitted
end
puts 'Pinned Pilot group assignment contract checks passed.'
