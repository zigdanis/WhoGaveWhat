require 'tmpdir'
require 'fileutils'
require 'fastlane'
require 'xcodeproj'

Fastlane.load_actions
fastfile = Fastlane::FastFile.new(File.expand_path('../Fastfile', __dir__))
Dir.mktmpdir('whogavewhat-source-test-') do |directory|
  source = File.expand_path('../../WhoGaveWhat.xcodeproj', __dir__)
  project_path = File.join(directory, 'WhoGaveWhat.xcodeproj')
  FileUtils.cp_r(source, project_path)
  settings = fastfile.validate_release_source(project_path)
  unless settings.values_at('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION').all? { |value| value.match?(/\A\d+(?:\.\d+){0,2}\z/) }
    raise 'Project build/version were not discovered as numeric values'
  end
  project = Xcodeproj::Project.open(project_path)
  app = project.targets.find { |target| target.name == 'WhoGaveWhat' }
  release = app.build_configurations.find { |configuration| configuration.name == 'Release' }
  release.build_settings['INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'] = 'YES'
  project.save
  begin
    fastfile.validate_release_source(project_path)
    raise 'Source validation accepted an unreviewed encryption change'
  rescue FastlaneCore::Interface::FastlaneError
  end
end
puts 'Generated app Info.plist source checks passed.'

previous = ENV['ALLOW_NATIVE_RELEASE_BUILD']
begin
  ENV.delete('ALLOW_NATIVE_RELEASE_BUILD')
  begin
    fastfile.validate_native_release_build
    raise 'Native release build accepted missing authorization'
  rescue FastlaneCore::Interface::FastlaneError => error
    raise unless error.message.include?('explicit authorization')
  end
  ENV['ALLOW_NATIVE_RELEASE_BUILD'] = 'true'
  fastfile.validate_native_release_build
ensure
  previous ? ENV['ALLOW_NATIVE_RELEASE_BUILD'] = previous : ENV.delete('ALLOW_NATIVE_RELEASE_BUILD')
end
puts 'Native release exception authorization checks passed.'
