#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint alliswell_docref.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'alliswell_docref'
  s.version          = '0.0.1'
  s.summary          = 'External document handles (ADR-0030).'
  s.description      = <<-DESC
External document handles (ADR-0030).
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'alliswell_docref/Sources/alliswell_docref/**/*'
  s.dependency 'Flutter'
  # 15.0, matching the app (ios/Podfile). Not eventkit's 13.0: this plugin uses
  # UniformTypeIdentifiers and `UIDocumentPickerViewController(
  # forOpeningContentTypes:asCopy:)`, both iOS 14+, and the 13.0 it was copied
  # with failed to compile with exactly that message.
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'alliswell_docref_privacy' => ['alliswell_docref/Sources/alliswell_docref/PrivacyInfo.xcprivacy']}
end
