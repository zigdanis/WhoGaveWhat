require 'tmpdir'
require 'fileutils'
require 'fastlane'
require 'cfpropertylist'

Fastlane.load_actions
fastfile = Fastlane::FastFile.new(File.expand_path('../Fastfile', __dir__))

Dir.mktmpdir('whogavewhat-archive-test-') do |archive|
  app = File.join(archive, 'Products/Applications/WhoGaveWhat.app')
  FileUtils.mkdir_p(app)
  record = { 'version' => '1.0.1', 'build_number' => '10' }
  values = { 'CFBundleIdentifier' => TestflightRelease::APP_ID,
             'CFBundleShortVersionString' => record['version'], 'CFBundleVersion' => record['build_number'],
             'ITSAppUsesNonExemptEncryption' => false }
  write_plist = lambda do |directory, data|
    FileUtils.mkdir_p(directory)
    plist = CFPropertyList::List.new
    plist.value = CFPropertyList.guess(data)
    plist.save(File.join(directory, 'Info.plist'), CFPropertyList::List::FORMAT_BINARY)
  end
  write_plist.call(app, values)
  fastfile.verify_release_archive(archive, record)
  [values.merge('CFBundleVersion' => '11'), values.merge('CFBundleIdentifier' => 'example.OtherApp'),
   values.merge('ITSAppUsesNonExemptEncryption' => true)].each do |invalid|
    write_plist.call(app, invalid)
    begin
      fastfile.verify_release_archive(archive, record)
      raise 'Archive verification accepted incorrect app identity or encryption'
    rescue FastlaneCore::Interface::FastlaneError
      # Expected rejection before upload.
    end
  end
  write_plist.call(app, values)
  write_plist.call(File.join(app, 'PlugIns/Unexpected.appex'), values)
  begin
    fastfile.verify_release_archive(archive, record)
    raise 'Archive verification accepted an unexpected extension'
  rescue FastlaneCore::Interface::FastlaneError
  end
end
puts 'Binary app archive verification checks passed.'
