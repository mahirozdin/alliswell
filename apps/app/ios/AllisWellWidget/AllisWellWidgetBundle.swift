//
//  AllisWellWidgetBundle.swift
//  AllisWellWidget
//
//  The extension's @main. The home-screen and lock-screen widget (OPH-131,
//  OPH-336) and the Live Activity AlarmKit's alarms are presented through
//  (OPH-182). The Control (iOS 18 Control Center) template was removed and can
//  come back as its own task.
//
//  The widget is two structs sharing one kind: `AllisWellWidget` (iOS 16, no
//  settings) and `AllisWellConfigurableWidget` (iOS 17+, a list per widget).
//  A bundle cannot say "one or the other" — no `else` after `#available` — so
//  the first is always listed and steps aside at runtime on 17+ (see its doc
//  comment in AllisWellWidget.swift).
//

import SwiftUI
import WidgetKit

@main
struct AllisWellWidgetBundle: WidgetBundle {
  var body: some Widget {
    AllisWellWidget()
    if #available(iOS 17.0, *) {
      AllisWellConfigurableWidget()
    }
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        AWAlarmLiveActivity()
      }
    #endif
  }
}
