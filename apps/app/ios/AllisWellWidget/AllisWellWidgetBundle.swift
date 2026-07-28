//
//  AllisWellWidgetBundle.swift
//  AllisWellWidget
//
//  The extension's @main. Two members: the home-screen widget (OPH-131) and the
//  Live Activity AlarmKit's alarms are presented through (OPH-182). The Control
//  (iOS 18 Control Center) template was removed and can come back as its own
//  task.
//

import SwiftUI
import WidgetKit

@main
struct AllisWellWidgetBundle: WidgetBundle {
  var body: some Widget {
    AllisWellWidget()
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        AWAlarmLiveActivity()
      }
    #endif
  }
}
