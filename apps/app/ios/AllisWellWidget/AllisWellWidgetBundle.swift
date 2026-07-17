//
//  AllisWellWidgetBundle.swift
//  AllisWellWidget
//
//  The extension's @main. We ship only the home-screen widget for now — the
//  Control (iOS 18 Control Center) and Live Activity templates were removed
//  (OPH-131). They can come back as their own tasks.
//

import SwiftUI
import WidgetKit

@main
struct AllisWellWidgetBundle: WidgetBundle {
  var body: some Widget {
    AllisWellWidget()
  }
}
