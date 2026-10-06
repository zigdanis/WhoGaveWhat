require 'tmpdir'
require 'fileutils'
require 'fastlane'
require 'xcodeproj'

Dir.mktmpdir('whogavewhat-signing-test-') do |directory|
  original = File.expand_path('../../WhoGaveWhat.xcodeproj', __dir__)
  project_path = File.join(directory, 'WhoGaveWhat.xcodeproj')
  FileUtils.cp_r(original, project_path)
  before = Xcodeproj::Project.open(project_path)
  unchanged = before.targets.flat_map do |target|
    target.build_configurations.filter_map do |configuration|
      next if %w[WhoGaveWhat].include?(target.name) && configuration.name == 'Release'
      [target.name, configuration.name, configuration.build_settings.dup]
    end
  end
  profiles = {
    'pro.ziganshin.WhoGaveWhat' => 'match AppStore pro.ziganshin.WhoGaveWhat WhoGaveWhat CI'
  }
  Fastlane.load_actions
  fastfile = Fastlane::FastFile.new(File.expand_path('../Fastfile', __dir__))
  fastfile.configure_release_signing(project_path, profiles)

  after = Xcodeproj::Project.open(project_path)
  %w[WhoGaveWhat].each do |name|
    target = after.targets.find { |candidate| candidate.name == name }
    settings = target.build_configurations.find { |configuration| configuration.name == 'Release' }.build_settings
    expected = profiles.fetch(settings.fetch('PRODUCT_BUNDLE_IDENTIFIER'))
    raise "#{name} archive profile differs from Match's installed profile" unless settings['PROVISIONING_PROFILE_SPECIFIER'] == expected
    raise "#{name} Release signing must remain manual" unless settings['CODE_SIGN_STYLE'] == 'Manual'
  end
  unchanged.each do |name, configuration_name, settings|
    target = after.targets.find { |candidate| candidate.name == name }
    actual = target.build_configurations.find { |configuration| configuration.name == configuration_name }.build_settings
    raise "Unexpected change to #{name} #{configuration_name}" unless settings == actual
  end
end
puts 'Release signing checks passed.'
