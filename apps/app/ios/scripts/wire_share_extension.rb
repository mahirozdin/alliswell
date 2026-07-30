#!/usr/bin/env ruby
# OPH-225 (ADR-0023) — wire the AllisWell Share Extension into the Xcode project.
#
# Second pbxproj deviation after the widget (ADR-0010): a share-services app
# extension so "Share to AllisWell" works from any app. Kept in a script (not a
# hand-edited pbxproj) for the same reason the widget was — the mutation is
# reviewable, and idempotent: running it twice adds nothing twice.
#
# Run on a Mac with the xcodeproj gem, THEN `pod install`, THEN build once to
# verify (this is the device-tour step; see ios/AllisWellShare/SETUP.md):
#   ruby ios/scripts/wire_share_extension.rb
#
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project_path = ARGV[0] if ARGV[0]
project = Xcodeproj::Project.open(project_path)

EXT_NAME = 'AllisWellShare'
HOST_BUNDLE = 'com.alliswell.alliswell'
EXT_BUNDLE = "#{HOST_BUNDLE}.#{EXT_NAME}"
GROUP_ID = 'group.com.alliswell.alliswell'

runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

# 1) The extension target (idempotent).
ext = project.targets.find { |t| t.name == EXT_NAME }
if ext.nil?
  ext = project.new_target(:app_extension, EXT_NAME, :ios, '14.0')
  puts "+ target #{EXT_NAME}"
else
  puts "= target #{EXT_NAME}: exists"
end

# 2) Source group + files.
group = project.main_group[EXT_NAME] || project.main_group.new_group(EXT_NAME, EXT_NAME)
def ref(group, path)
  group.files.find { |f| f.path == path } || group.new_reference(path)
end
src_ref = ref(group, 'ShareViewController.swift')
unless ext.source_build_phase.files.any? { |f| f.file_ref == src_ref }
  ext.add_file_references([src_ref])
  puts "+ ShareViewController.swift -> #{EXT_NAME}"
end
# Info.plist + entitlements only need to exist in the group (referenced by
# build settings below), not compiled.
ref(group, 'Info.plist')
ref(group, 'AllisWellShare.entitlements')

# 3) Build settings on every configuration.
ext.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/AllisWellShare.entitlements"
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  s['SWIFT_VERSION'] = '5.0'
  s['CUSTOM_GROUP_ID'] = GROUP_ID
  s['SKIP_INSTALL'] = 'YES'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
end

# 4) Embed the extension into Runner (Embed App Extensions copy-files phase).
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
if embed.nil?
  embed = runner.new_copy_files_build_phase('Embed App Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins # dstSubfolderSpec = 13
  puts '+ Embed App Extensions phase'
end
product = ext.product_reference
unless embed.files.any? { |f| f.file_ref == product }
  build_file = embed.add_file_reference(product)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "+ embed #{EXT_NAME}.appex"
end

# 5) Runner depends on the extension so it builds first.
unless runner.dependencies.any? { |d| d.target == ext }
  runner.add_dependency(ext)
  puts "+ Runner depends on #{EXT_NAME}"
end

project.save
puts "saved #{project_path}"
puts 'NEXT: add the Podfile target block (see SETUP.md), then `pod install`.'
