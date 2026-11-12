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
tests = project.targets.find { |t| t.name == 'RunnerTests' }
raise 'Runner target not found' unless runner
raise 'AllisWellWidgetExtension target not found' unless widget
raise 'RunnerTests target not found' unless tests

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

# OPH-429 — the occurrence id and fingerprint (NOTIFICATIONS.md 2b.3). Foundation
# only, so the widget extension compiles it too: a native snooze inside the
# widget process names the same alarm Dart would plan.
identity_ref = file_ref(shared_group, 'AWAlarmIdentity.swift')
add_source(runner, identity_ref, 'Shared/AWAlarmIdentity.swift')
add_source(widget, identity_ref, 'Shared/AWAlarmIdentity.swift')

# OPH-430 — the AlarmKit ledger and failure ring (NOTIFICATIONS.md 2b.3 "App
# Group keys"). The alert's intents in AWAlarmShared.swift write the ledger, and
# the widget extension compiles those intents, so both targets need it.
ledger_ref = file_ref(shared_group, 'AWAlarmLedger.swift')
add_source(runner, ledger_ref, 'Shared/AWAlarmLedger.swift')
add_source(widget, ledger_ref, 'Shared/AWAlarmLedger.swift')

# OPH-431 — the native snooze (NOTIFICATIONS.md 2b.3 "Native snooze"): the pure
# core, the snooze target and the AlarmKit ops. The snooze intent in
# AWAlarmShared.swift runs it, and the widget extension compiles that intent.
snooze_ref = file_ref(shared_group, 'AWSnoozeCore.swift')
add_source(runner, snooze_ref, 'Shared/AWSnoozeCore.swift')
add_source(widget, snooze_ref, 'Shared/AWSnoozeCore.swift')

# OPH-451 — the widget snapshot model and the timeline's day choice (#50, v6).
# The widget draws them; Runner compiles them too so RunnerTests can test the
# pure day pick (WidgetDayPickTests). Foundation only.
# OPH-461 — the self-fetch policy (WIDGETS.md 3.2): when the widget may fetch,
# its backoff and reload dates, and the local-or-server choice
# (WidgetFetchPolicyTests). Foundation only.
# OPH-462 — the self-fetch itself: the Keychain read, the one request and the
# server's view in the app's words. Runner compiles it so WidgetFetchPolicyTests
# drives it through a URLProtocol stub. Foundation and Security only.
%w[
  AWSnapshotModel.swift AWWidgetDayPick.swift AWWidgetFetchPolicy.swift AWWidgetFetcher.swift
].each do |name|
  ref = file_ref(shared_group, name)
  add_source(runner, ref, "Shared/#{name}")
  add_source(widget, ref, "Shared/#{name}")
end

# XCTest sources go into the one existing RunnerTests target (hosted in
# Runner.app, `@testable import Runner`); never a second test target.
tests_group = project.main_group['RunnerTests']
raise 'RunnerTests group not found' unless tests_group

%w[
  AlarmIdentityTests.swift AlarmLedgerTests.swift SnoozeCoreTests.swift SnoozeTargetTests.swift
  WidgetDayPickTests.swift WidgetCompletionTests.swift WidgetMoreCountTests.swift
  WidgetFetchPolicyTests.swift
].each do |name|
  add_source(tests, file_ref(tests_group, name), "RunnerTests/#{name}")
end

project.save
puts "saved #{project_path}"
