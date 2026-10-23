require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../store_metadata'

class StoreMetadataTest < Minitest::Test
  CONTACT = { 'contact_first_name' => 'Ada', 'contact_last_name' => 'Lovelace',
              'contact_email' => 'ada@example.com', 'contact_phone' => '+10000000000' }.freeze

  def test_accepts_two_and_three_part_versions
    assert_equal '1.0', StoreMetadata.validate_version('1.0')
    assert_equal '1.2.10', StoreMetadata.validate_version(" 1.2.10\n")
  end

  def test_rejects_other_versions
    ['', nil, '1', '1.', '1.0.0.0', 'v1.0', '1.0-beta', "1.0\nx", '1.a'].each do |value|
      assert_raises(RuntimeError, value.inspect) { StoreMetadata.validate_version(value) }
    end
  end

  def test_no_screenshots_folder_means_none_requested
    assert_nil StoreMetadata.screenshots_path(nil)
    assert_nil StoreMetadata.screenshots_path('  ')
  end

  def test_screenshots_folder_needs_language_folders
    Dir.mktmpdir do |directory|
      assert_raises(RuntimeError) { StoreMetadata.screenshots_path(File.join(directory, 'missing')) }
      assert_raises(RuntimeError) { StoreMetadata.screenshots_path(directory) }
      Dir.mkdir(File.join(directory, 'en-US'))
      assert_equal File.expand_path(directory), StoreMetadata.screenshots_path(directory)
    end
  end

  def test_maps_the_private_contact_to_deliver_keys
    Dir.mktmpdir do |directory|
      info = StoreMetadata.review_information(CONTACT, File.join(directory, 'notes.txt'))
      assert_equal({ first_name: 'Ada', last_name: 'Lovelace', email_address: 'ada@example.com',
                     phone_number: '+10000000000' }, info)
    end
  end

  def test_notes_file_wins_over_the_secret_notes
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'notes.txt')
      assert_equal 'From secret', StoreMetadata.review_information(CONTACT.merge('notes' => 'From secret'), path)[:notes]
      File.write(path, "From file\n")
      assert_equal 'From file', StoreMetadata.review_information(CONTACT.merge('notes' => 'From secret'), path)[:notes]
    end
  end

  def test_missing_contact_fields_are_named_without_values
    error = assert_raises(RuntimeError) do
      StoreMetadata.review_information(CONTACT.merge('contact_email' => ' ').reject { |key, _| key == 'contact_phone' }, '/nonexistent')
    end
    assert_includes error.message, 'contact_email, contact_phone'
    refute_includes error.message, 'ada@example.com'
  end

  def test_without_a_contact_the_review_section_is_left_alone
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'notes.txt')
      File.write(path, "From file\n")
      assert_nil StoreMetadata.review_information({}, path)
      assert_nil StoreMetadata.review_information({ 'contact_email' => ' ', 'notes' => 'From secret' }, path)
    end
  end

  def test_metadata_copy_drops_only_the_review_section
    Dir.mktmpdir do |directory|
      source = File.join(directory, 'metadata')
      FileUtils.mkdir_p([File.join(source, 'en-US'), File.join(source, 'review_information')])
      File.write(File.join(source, 'en-US', 'subtitle.txt'), 'Gift tracker')
      File.write(File.join(source, 'copyright.txt'), '2026')
      File.write(File.join(source, 'review_information', 'notes.txt'), 'Notes')

      copy = StoreMetadata.metadata_without_review_information(source, directory)

      refute_equal source, copy
      assert_equal 'Gift tracker', File.read(File.join(copy, 'en-US', 'subtitle.txt'))
      assert File.file?(File.join(copy, 'copyright.txt'))
      refute File.exist?(File.join(copy, 'review_information'))
      assert File.file?(File.join(source, 'review_information', 'notes.txt'))
    end
  end
end
