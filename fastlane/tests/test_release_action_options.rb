require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'fastlane'
require 'match'
require 'gym'
require 'pilot'
require_relative '../testflight_release'

Fastlane.load_actions

class ReleaseActionOptionsTest < Minitest::Test
  class Coordinator < TestflightRelease
    attr_reader :record, :app

    def initialize
      @record = { 'version' => '1.0.1', 'build_number' => '10',
                  'notes' => { 'en-US' => 'Check gift history.', 'ru' => 'Проверьте историю подарков.' },
                  'phase' => 'available' }
      @app = { 'id' => 'fixture-app' }
      @group = { 'id' => 'fixture-group', 'attributes' => { 'name' => 'Fixture', 'isInternalGroup' => true, 'hasAccessToAllBuilds' => true } }
    end

    def requested_notes = record['notes']
    def preflight!(configure:) = nil
    def prepare! = nil
    def upload_needed? = true
    def begin_upload! = nil
    def uploaded! = nil
    def wait_for_processing! = nil
    def verify_notes! = nil
    def verify_distribution! = nil
    def write_report = nil

  end

  def test_actual_release_action_options_are_supported_by_pinned_fastlane
    original_environment = ENV.to_h
    original_context = Fastlane::Actions.lane_context.dup
    calls = []
    Dir.mktmpdir('whogavewhat-action-options-') do |directory|
      FileUtils.cp_r(File.expand_path('../../WhoGaveWhat.xcodeproj', __dir__), directory)
      key = File.join(directory, 'fixture-signing-key')
      File.write(key, 'nonsecret fixture')
      ENV.update('GITHUB_ACTIONS' => 'true', 'RELEASE_SOURCE_DIR' => directory, 'RELEASE_TEMP' => directory,
                 'ASC_KEY_ID' => 'fixture', 'ASC_ISSUER_ID' => 'fixture', 'ASC_KEY_PATH' => key,
                 'APPLE_TEAM_ID' => 'TESTTEAM01', 'MATCH_GIT_PRIVATE_KEY_PATH' => key,
                 'MATCH_GIT_URL' => 'git@github.com:example/fixture-signing.git',
                 'ALLOW_NATIVE_RELEASE_BUILD' => 'true', 'RESUME_RUN_ID' => '')
      coordinator = Coordinator.new
      fastfile = Fastlane::FastFile.new(File.expand_path('../Fastfile', __dir__))
      actions = {
        app_store_connect_api_key: Fastlane::Actions::AppStoreConnectApiKeyAction,
        create_keychain: Fastlane::Actions::CreateKeychainAction,
        match: Fastlane::Actions::MatchAction,
        update_code_signing_settings: Fastlane::Actions::UpdateCodeSigningSettingsAction,
        gym: Fastlane::Actions::GymAction,
        pilot: Fastlane::Actions::PilotAction,
        delete_keychain: Fastlane::Actions::DeleteKeychainAction
      }
      actions.each do |name, action|
        fastfile.define_singleton_method(name) do |**options|
          # Run Fastlane's real validation, but never its native/API action body.
          FastlaneCore::Configuration.create(action.available_options, options)
          calls << [name, options]
          if name == :match
            Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING] = {
              TestflightRelease::APP_ID => 'match AppStore pro.ziganshin.WhoGaveWhat'
            }
          elsif name == :create_keychain
            File.write(options.fetch(:path), 'nonsecret fixture')
          elsif name == :gym
            File.write(File.join(options.fetch(:output_directory), options.fetch(:output_name)), 'nonsecret fixture')
          elsif name == :app_store_connect_api_key
            { key_id: 'fixture', issuer_id: 'fixture', key: 'nonsecret fixture' }
          end
        end
      end
      fastfile.define_singleton_method(:verify_release_archive) { |*| }
      TestflightRelease.stub(:new, coordinator) { fastfile.run_release(upload: true) }
      assert_equal [:app_store_connect_api_key, :create_keychain, :match, :update_code_signing_settings,
                    :gym, :pilot, :delete_keychain, :pilot], calls.map(&:first)
      match_options = calls.find { |name, _| name == :match }.last
      assert_equal false, match_options[:readonly]
      assert_equal true, match_options[:generate_apple_certs]
      assert_equal [TestflightRelease::APP_ID], match_options[:app_identifier]
      assert_equal File.join(directory, 'signing.keychain'), match_options[:keychain_name]
      assert_equal directory, calls.find { |name, _| name == :gym }.last[:output_directory]
    end
  ensure
    ENV.replace(original_environment)
    Fastlane::Actions.lane_context.replace(original_context)
  end
end
