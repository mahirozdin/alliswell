#!/usr/bin/env ruby
# frozen_string_literal: true

# OPH-335 — adds the macOS widget extension target (`AllisWellWidgetMac`) to
# Runner.xcodeproj, so nobody edits the pbxproj by hand (the
# flutter_launcher_icons lesson: a tool that rewrites project.pbxproj without
# being read afterwards is how an iOS project got corrupted once already).
#
#   cd apps/app/macos && ruby scripts/add_widget_extension.rb
#   ruby scripts/add_widget_extension.rb path/to/Runner.xcodeproj   # a copy
#
# IDEMPOTENT and CONVERGING: a second run finds the target and changes nothing
# — measured, the pbxproj checksum is identical after it. A target an older
# version of this script created gets the shared sources it lacks (OPH-451
# moved the snapshot model out of AllisWellWidget.swift; a pre-OPH-451 target
# would no longer compile), and nothing else about it is touched.
#
# What it does NOT do, on purpose: sign. The extension has its own bundle id
# (`com.alliswell.alliswell.AllisWellWidget`) and the only Mac profile on the
# team covers the app's id alone, so the first build needs Xcode's automatic
# signing to register the id with the account — a step that belongs to the
# account holder, not a script. `macos/AllisWellWidgetMac/SETUP.md` is that
# step, and until it is taken `flutter build macos` would fail on the missing
# profile. That is why this script is kept, and not applied, in the repo.
#
# Uses the `xcodeproj` gem CocoaPods already brings along.

require 'xcodeproj'

TARGET = 'AllisWellWidgetMac'
BUNDLE_ID = 'com.alliswell.alliswell.AllisWellWidget'
TEAM = 'WWRZ5CG3DW'
# Sonoma: the iOS source this target shares is written against iOS 17-era
# SwiftUI (foregroundStyle, containerBackground, Button(intent:)), and
# interactive widgets begin at macOS 14 anyway. The APP keeps macOS 11; on an
# older Mac the widget simply is not offered.
DEPLOYMENT = '14.0'

# Every file the widget compiles from the iOS tree. The widget itself is the
# iOS source — one set of views, one grouping. Only the @main bundle differs
# (the iOS one also carries the AlarmKit Live Activity, which does not exist on
# a Mac).
# - AWAlarmShared.swift: the queue the complete intent writes into
#   (AWAlarmActionQueue). Its AlarmKit intents are compiled out on macOS
#   (`#if canImport(AppIntents) && os(iOS)`).
# - OPH-451: the snapshot model and the timeline's day choice moved out of
#   AllisWellWidget.swift into ios/Shared (Runner compiles them for
#   RunnerTests); without them the widget source loses its types.
# - OPH-461: the self-fetch policy. The Mac widget does not fetch (iOS only,
#   WIDGETS.md 3.2); it compiles the shared set whole, so a shared type the
#   widget source names never goes missing here.
# - OPH-462: the self-fetch itself. Only its queue helper runs on a Mac (the
#   widget's read of queued completions); the fetch is compiled out there.
SHARED_GROUP = 'AllisWellWidgetShared (ios)'
SHARED_SOURCES = %w[
  AllisWellWidget/AllisWellWidget.swift
  Shared/AWAlarmShared.swift
  Shared/AWSnapshotModel.swift
  Shared/AWWidgetDayPick.swift
  Shared/AWWidgetFetchPolicy.swift
  Shared/AWWidgetFetcher.swift
].freeze

project_path = ARGV[0] || File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

def shared_group(project)
  project.main_group.groups.find { |g| g.display_name == SHARED_GROUP } ||
    project.main_group.new_group(SHARED_GROUP, '../ios')
end

def file_ref(group, path)
  group.files.find { |f| f.path == path } || group.new_reference(path)
end

# Adds each of [refs] the target does not compile yet; the number added.
def add_sources(target, refs)
  missing = refs.reject { |ref| target.source_build_phase.files.any? { |f| f.file_ref == ref } }
  target.add_file_references(missing) unless missing.empty?
  missing.size
end

existing = project.targets.find { |t| t.name == TARGET }
if existing
  shared = shared_group(project)
  added = add_sources(existing, SHARED_SOURCES.map { |path| file_ref(shared, path) })
  if added.zero?
    puts "#{TARGET}: already present in #{project_path} — nothing to do"
  else
    project.save
    puts "#{TARGET}: already present; added #{added} shared source(s) in #{project_path}"
  end
  exit 0
end

runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

ext = project.new_target(:app_extension, TARGET, :osx, DEPLOYMENT, nil, :swift)

own = project.main_group.new_group(TARGET, TARGET)
bundle_ref = own.new_reference('AllisWellWidgetMacBundle.swift')
own.new_reference('Info.plist')
own.new_reference("#{TARGET}.entitlements")
own.new_reference('SETUP.md')

shared = shared_group(project)
add_sources(ext, [bundle_ref] + SHARED_SOURCES.map { |path| file_ref(shared, path) })

ext.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{TARGET}/Info.plist"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{TARGET}/#{TARGET}.entitlements"
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  settings['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT
  settings['SWIFT_VERSION'] = '5.0'
  settings['SKIP_INSTALL'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/../Frameworks',
    '@executable_path/../../../../Frameworks',
  ]
  # The app's own numbers (Flutter-Generated.xcconfig, inherited from the
  # project-level configuration): an extension whose version differs from its
  # host's is one the store — and some macOS versions — refuse to load.
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
end

# Embed the .appex in the app (Contents/PlugIns), as the iOS project does.
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
        runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
build_file = embed.add_file_reference(ext.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy CodeSignOnCopy] }
runner.add_dependency(ext)

project.save
puts "#{TARGET}: added to #{project_path}"
