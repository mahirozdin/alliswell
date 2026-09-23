//
//  AllisWellWidgetMacBundle.swift
//  AllisWellWidgetMac
//
//  OPH-335: the macOS extension's @main. The widget itself is the iOS source
//  (ios/AllisWellWidget/AllisWellWidget.swift), compiled into this target too —
//  one grouping, one set of views. What the iOS bundle adds on top (the AlarmKit
//  Live Activity) does not exist on macOS, which is why this file is separate.
//
//  OPH-336: the configurable widget alone. The target is macOS 14, where
//  AppIntentConfiguration always exists — the iOS 16 fallback the iOS bundle
//  carries has no Mac to fall back on.
//

import SwiftUI
import WidgetKit

@main
struct AllisWellWidgetMacBundle: WidgetBundle {
  var body: some Widget {
    AllisWellConfigurableWidget()
  }
}
