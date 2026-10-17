#!/usr/bin/env ruby
# OPH-376 (ADR-0057) — put the Siri / Shortcuts sources into the app targets.
#
# `ios/Shared/AWAppShortcuts.swift` and its strings (en, tr) must be compiled
# into the iOS Runner AND the macOS Runner — and into no widget extension: an
# AppShortcutsProvider belongs to the app only. A .swift file sitting in the
# repo is not a compiled file (LESSONS ios-native), hence this script.
#
# Idempotent: running it twice adds nothing twice.
#
#   ruby apps/app/ios/scripts/wire_app_shortcuts.rb
require 'xcodeproj'

APP_DIR = File.expand_path('../..', __dir__)
SWIFT = 'AWAppShortcuts.swift'
STRINGS = %w[AppShortcuts.strings Localizable.strings].freeze
LANGS = %w[en tr].freeze

def file_ref(group, path)
  group.files.find { |f| f.path == path } || group.new_reference(path)
end

def add_source(target, ref)
  if target.source_build_phase.files.any? { |f| f.file_ref == ref }
    puts "= #{ref.path}: already in #{target.name} Sources"
  else
    target.source_build_phase.add_file_reference(ref)
    puts "+ #{ref.path} -> #{target.name} Sources"
  end
end

# A variant group `<name>` holding `en.lproj/<name>` and `tr.lproj/<name>`.
def variant_group(group, name)
  variant = group.children.find do |c|
    c.isa == 'PBXVariantGroup' && c.name == name
  end
  variant ||= begin
    v = group.project.new(Xcodeproj::Project::Object::PBXVariantGroup)
    v.name = name
    v.source_tree = '<group>'
    group.children << v
    v
  end
  LANGS.each do |lang|
    path = "#{lang}.lproj/#{name}"
    next if variant.files.any? { |f| f.path == path }

    ref = group.project.new(Xcodeproj::Project::Object::PBXFileReference)
    ref.name = lang
    ref.path = path
    ref.source_tree = '<group>'
    ref.last_known_file_type = 'text.plist.strings'
    variant.children << ref
  end
  variant
end

def add_resource(target, ref)
  if target.resources_build_phase.files.any? { |f| f.file_ref == ref }
    puts "= #{ref.name}: already in #{target.name} Resources"
  else
    target.resources_build_phase.add_file_reference(ref)
    puts "+ #{ref.name} -> #{target.name} Resources"
  end
end

def add_region(project, region)
  regions = project.root_object.known_regions
  return if regions.include?(region)

  regions << region
  puts "+ knownRegions #{region}"
end

def wire(project_path, group_name, group_path)
  project = Xcodeproj::Project.open(project_path)
  runner = project.targets.find { |t| t.name == 'Runner' }
  raise "Runner target not found in #{project_path}" unless runner

  group = project.main_group.children.find do |c|
    c.respond_to?(:display_name) && c.display_name == group_name
  end
  group ||= project.main_group.new_group(group_name, group_path)

  add_source(runner, file_ref(group, SWIFT))
  STRINGS.each { |name| add_resource(runner, variant_group(group, name)) }
  LANGS.each { |lang| add_region(project, lang) }

  project.save
  puts "saved #{project_path}"
end

# iOS: the existing `Shared` group (wire_alarmkit.rb made it, path `Shared`).
wire(File.join(APP_DIR, 'ios/Runner.xcodeproj'), 'Shared', 'Shared')
# macOS: the same files, reached through `../ios/Shared`.
wire(File.join(APP_DIR, 'macos/Runner.xcodeproj'), 'AppShortcutsShared (ios)', '../ios/Shared')
