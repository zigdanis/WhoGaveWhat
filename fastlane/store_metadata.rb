# Pure helpers for the `store_metadata` lane: validation and the private App Review contact mapping.
module StoreMetadata
  VERSION_PATTERN = /\A\d+\.\d+(\.\d+)?\z/
  # BETA_REVIEW_INFO keys (see TestflightRelease#review_info) mapped to deliver's app_review_information keys.
  REVIEW_CONTACT_FIELDS = {
    'contact_first_name' => :first_name,
    'contact_last_name' => :last_name,
    'contact_email' => :email_address,
    'contact_phone' => :phone_number
  }.freeze

  def self.validate_version(value)
    version = value.to_s.strip
    raise 'Set STORE_VERSION to the App Store version, for example 1.0 or 1.0.1' unless version.match?(VERSION_PATTERN)
    version
  end

  # The screenshots folder, or nil when none was requested. It holds one folder per store language.
  def self.screenshots_path(value)
    path = value.to_s.strip
    return nil if path.empty?
    raise "Screenshots folder #{path} has no language folders" unless File.directory?(path) && !Dir.children(path).empty?
    File.expand_path(path)
  end

  # Contact details come from the private secret, never from the repository; only the notes may live in
  # fastlane/metadata/review_information/notes.txt and win over a notes entry in the secret.
  def self.review_information(info, notes_path)
    missing = REVIEW_CONTACT_FIELDS.keys.select { |key| info[key].to_s.strip.empty? }
    unless missing.empty?
      raise "Missing App Review contact fields: #{missing.join(', ')}; supply BETA_REVIEW_INFO as an encrypted JSON secret"
    end
    result = REVIEW_CONTACT_FIELDS.to_h { |key, option| [option, info.fetch(key).strip] }
    notes = File.file?(notes_path) ? File.read(notes_path).strip : info['notes'].to_s.strip
    result[:notes] = notes unless notes.empty?
    result.merge(demo_required: false)
  end
end
