#!/usr/bin/env ruby
# frozen_string_literal: true

# add_widget_extension.rb, run against copies of Runner.xcodeproj:
#
#   ruby apps/app/macos/scripts/add_widget_extension_test.rb
#
# The script is kept, not applied, in the repo, so nothing else would notice
# when a project set up by an older version of it stops converging: a widget
# target created before OPH-451 compiles AllisWellWidget.swift without the
# snapshot model it now reads, and a re-run must add what it lacks.
#
# Needs the `xcodeproj` gem CocoaPods brings along (as the script does) and
# nothing else: a newer Ruby ships no test framework by default, so the few
# assertions below are plain Ruby. Exit status 0 = every case passed.

require 'fileutils'
require 'open3'
require 'tmpdir'
require 'xcodeproj'

class AddWidgetExtensionTest
  class Failure < StandardError; end

  def assert(ok, message = 'assertion failed')
    raise Failure, message unless ok
  end

  def assert_equal(expected, actual, message = nil)
    return if expected == actual

    raise Failure, "#{message || 'not equal'}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def refute_nil(value, message)
    raise Failure, message if value.nil?
  end

  SCRIPT = File.expand_path('add_widget_extension.rb', __dir__)
  PROJECT = File.expand_path('../Runner.xcodeproj', __dir__)
  TARGET = 'AllisWellWidgetMac'
  EXPECTED = %w[
    AllisWellWidgetMacBundle.swift
    AllisWellWidget.swift
    AWAlarmShared.swift
    AWSnapshotModel.swift
    AWWidgetDayPick.swift
    AWWidgetFetchPolicy.swift
  ].freeze

  def setup
    @dir = Dir.mktmpdir('aw-widget-mac')
    @copy = File.join(@dir, 'Runner.xcodeproj')
    FileUtils.cp_r(PROJECT, @copy)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def run_script
    out, status = Open3.capture2e('ruby', SCRIPT, @copy)
    assert status.success?, out
    out
  end

  def sources
    project = Xcodeproj::Project.open(@copy)
    target = project.targets.find { |t| t.name == TARGET }
    refute_nil target, "#{TARGET} exists"
    target.source_build_phase.files.map { |f| f.file_ref.path.split('/').last }
  end

  def pbxproj
    File.read(File.join(@copy, 'project.pbxproj'))
  end

  def test_a_fresh_project_gets_the_target_with_every_shared_source
    run_script
    assert_equal EXPECTED.sort, sources.sort
  end

  def test_a_second_run_changes_nothing
    run_script
    before = pbxproj
    run_script
    assert_equal before, pbxproj
  end

  # The target as the script before OPH-451 left it: the bundle, the widget
  # and the queue, no snapshot model and no day pick.
  def test_a_target_from_the_previous_script_gains_the_missing_shared_sources
    project = Xcodeproj::Project.open(@copy)
    ext = project.new_target(:app_extension, TARGET, :osx, '14.0', nil, :swift)
    own = project.main_group.new_group(TARGET, TARGET)
    bundle = own.new_reference('AllisWellWidgetMacBundle.swift')
    shared = project.main_group.new_group('AllisWellWidgetShared (ios)', '../ios')
    widget = shared.new_reference('AllisWellWidget/AllisWellWidget.swift')
    queue = shared.new_reference('Shared/AWAlarmShared.swift')
    ext.add_file_references([bundle, widget, queue])
    project.save

    run_script

    assert_equal EXPECTED.sort, sources.sort
    reopened = Xcodeproj::Project.open(@copy)
    groups = reopened.main_group.groups.select { |g| g.display_name == 'AllisWellWidgetShared (ios)' }
    assert_equal 1, groups.size, 'the shared group is reused, not duplicated'
    paths = groups.first.files.map(&:path)
    assert_equal paths.uniq, paths, 'no file reference is added twice'

    before = pbxproj
    run_script
    assert_equal before, pbxproj, 'converged: a further run changes nothing'
  end
end

failed = 0
cases = AddWidgetExtensionTest.instance_methods(false).grep(/^test_/).sort
cases.each do |name|
  test = AddWidgetExtensionTest.new
  test.setup
  begin
    test.public_send(name)
    puts "ok   #{name}"
  rescue AddWidgetExtensionTest::Failure => e
    failed += 1
    puts "FAIL #{name}: #{e.message}"
  ensure
    test.teardown
  end
end
puts "#{cases.size - failed}/#{cases.size} passed"
exit(failed.zero? ? 0 : 1)
