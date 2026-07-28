#!/usr/bin/env ruby
# OPH-182 — put the AlarmKit sources into the targets that must compile them.
#
# Round 9's lesson in one script: a .swift file sitting in the repo is not a
# compiled file. `AlarmKitBridge.swift` had been written since round 6 and was in
# NO target, so the only lane that can outrun the iOS mute switch never ran once.
#
# Idempotent: running it twice adds nothing twice.
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project_path = ARGV[0] if ARGV[0]
project = Xcodeproj::Project.open(project_path)

runner = project.targets.find { |t| t.name == 'Runner' }
widget = project.targets.find { |t| t.name == 'AllisWellWidgetExtension' }
raise 'Runner target not found' unless runner
raise 'AllisWellWidgetExtension target not found' unless widget

runner_group = project.main_group['Runner']
raise 'Runner group not found' unless runner_group

# A group of its own for the files two targets share, so the double membership is
# visible in the navigator instead of being a surprise in the build log.
shared_group = project.main_group['Shared'] ||
               project.main_group.new_group('Shared', 'Shared')

def file_ref(group, path)
  group.files.find { |f| f.path == path } || group.new_reference(path)
end

def add_source(target, ref, label)
  already = target.source_build_phase.files.any? { |f| f.file_ref == ref }
  if already
    puts "= #{label}: already in #{target.name}"
  else
    target.add_file_references([ref])
    puts "+ #{label} -> #{target.name}"
  end
end

bridge_ref = file_ref(runner_group, 'AlarmKitBridge.swift')
add_source(runner, bridge_ref, 'Runner/AlarmKitBridge.swift')

shared_ref = file_ref(shared_group, 'AWAlarmShared.swift')
add_source(runner, shared_ref, 'Shared/AWAlarmShared.swift')
add_source(widget, shared_ref, 'Shared/AWAlarmShared.swift')

project.save
puts "saved #{project_path}"
