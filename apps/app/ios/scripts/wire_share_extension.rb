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
  ext = project.new_target(:app_extension, EXT_NAME, :ios, '15.0')
  puts "+ target #{EXT_NAME}"
else
  puts "= target #{EXT_NAME}: exists"
end

# 2) Source group + files.
group = project.main_group[EXT_NAME] || project.main_group.new_group(EXT_NAME, EXT_NAME)
def ref(group, path)
  group.files.find { |f| f.path == path } || group.new_reference(path)
end
%w[ShareViewController.swift ShareNotifier.swift].each do |name|
  src_ref = ref(group, name)
  if ext.source_build_phase.files.any? { |f| f.file_ref == src_ref }
    puts "= #{name}: already in #{EXT_NAME}"
  else
    ext.add_file_references([src_ref])
    puts "+ #{name} -> #{EXT_NAME}"
  end
end

# 2b) The Runner half of the same feature (OPH-242, ADR-0029). The extension
# writes the App Group and stops there — an appex cannot open its host app on
# iOS 18+ — so the app needs the channel that reads that mailbox. Wired here
# rather than in wire_alarmkit.rb because it is share plumbing, and left out of
# neither: a .swift file in the repo that is in no target compiles nowhere,
# which is the exact lesson wire_alarmkit.rb was written to record.
runner_group = project.main_group['Runner']
raise 'Runner group not found' unless runner_group
inbox_ref = ref(runner_group, 'ShareInboxBridge.swift')
if runner.source_build_phase.files.any? { |f| f.file_ref == inbox_ref }
  puts '= ShareInboxBridge.swift: already in Runner'
else
  runner.add_file_references([inbox_ref])
  puts '+ ShareInboxBridge.swift -> Runner'
end
# Info.plist + entitlements only need to exist in the group (referenced by
# build settings below), not compiled.
ref(group, 'Info.plist')
ref(group, 'AllisWellShare.entitlements')

# 3) Base configurations. Without these, MARKETING_VERSION below resolves to
# EMPTY and App Store validation rejects the upload ("extension version must
# match the app") — the exact trap Flutter/AllisWellWidget.xcconfig documents.
# Each file includes BOTH the CocoaPods xcconfig (this extension links
# receive_sharing_intent, unlike the widget) and Generated.xcconfig.
flutter_group = project.main_group['Flutter'] ||
                project.main_group.new_group('Flutter', 'Flutter')

# The 'Flutter' group is VIRTUAL (name only, no path), so a reference inside it
# must carry the full relative path or Xcode looks for the file next to the
# .xcodeproj and fails with "Unable to open base configuration reference file".
# AllisWellWidget.xcconfig stores `path = Flutter/…` for exactly this reason;
# mirror it.
def xcconfig_ref(group, name)
  path = "Flutter/#{name}"
  existing = group.files.find { |f| f.path == path }
  return existing if existing
  ref = group.new_reference(path)
  ref.name = name
  ref
end

ext.build_configurations.each do |config|
  file = "AllisWellShare#{config.name}.xcconfig" # Debug / Release / Profile
  config.base_configuration_reference = xcconfig_ref(flutter_group, file)
end

# 4) Build settings on every configuration.
ext.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/AllisWellShare.entitlements"
  # 15.0, not 14.0: receive_sharing_intent 1.8.1 raised its own minimum, and a
  # lower target here fails the build with "Compiling for iOS 14.0, but module
  # 'receive_sharing_intent' has a minimum deployment target of iOS 15.0"
  # (OPH-242, measured). The Podfile has said `platform :ios, '15.0'` all along,
  # so this only ever agreed with the app by accident.
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['SWIFT_VERSION'] = '5.0'
  s['CUSTOM_GROUP_ID'] = GROUP_ID
  s['SKIP_INSTALL'] = 'YES'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  # Single source of truth: pubspec.yaml, via Generated.xcconfig.
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
end

# 5) Embed the extension into Runner. REUSE the existing PlugIns copy phase —
# the widget already has one ("Embed Foundation Extensions", Xcode 15+ naming)
# and it sits BEFORE Flutter's "Thin Binary" script phase. Appending a second,
# separate phase puts it AFTER Thin Binary, which reads the whole Runner.app
# tree (PlugIns included) and Xcode then fails with "Cycle inside Runner".
embed = runner.copy_files_build_phases.find do |p|
  p.symbol_dst_subfolder_spec == :plug_ins
end
if embed.nil?
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins # dstSubfolderSpec = 13
  thin = runner.build_phases.find do |p|
    p.respond_to?(:name) && p.name == 'Thin Binary'
  end
  if thin
    runner.build_phases.delete(embed)
    runner.build_phases.insert(runner.build_phases.index(thin), embed)
  end
  puts '+ Embed Foundation Extensions phase (before Thin Binary)'
else
  puts "= embed phase: reusing #{embed.name.inspect}"
end
product = ext.product_reference
unless embed.files.any? { |f| f.file_ref == product }
  build_file = embed.add_file_reference(product)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "+ embed #{EXT_NAME}.appex"
end

# 6) Runner depends on the extension so it builds first.
unless runner.dependencies.any? { |d| d.target == ext }
  runner.add_dependency(ext)
  puts "+ Runner depends on #{EXT_NAME}"
end

project.save
puts "saved #{project_path}"
puts 'NEXT: add the Podfile target block (see SETUP.md), then `pod install`.'
