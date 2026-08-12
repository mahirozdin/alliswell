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

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'alliswell_docref_privacy' => ['alliswell_docref/Sources/alliswell_docref/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
