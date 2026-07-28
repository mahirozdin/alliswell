// The Live Activity AlarmKit needs (OPH-182, round 9 #8).
//
// `AlarmKit.AlarmAttributes` IS an `ActivityAttributes`: the system presents a
// scheduled alarm as a Live Activity on the Lock Screen and in the Dynamic
// Island before and around the alert. An app that schedules AlarmKit alarms
// without shipping a matching `ActivityConfiguration` — and without
// `NSSupportsLiveActivities` in BOTH Info.plists — can have its alarms dropped,
// which is the failure round 9 spent an evening on.
//
// The alert itself (full screen, Onayla/Ertele) is drawn by the system from the
// `AlarmPresentation` the app scheduled; this file only owns the ambient
// surfaces. It renders the presentation the alarm already carries, so there is
// no localization here — the app passed pre-localized strings (NOTIFICATIONS
// §2b).

import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
  import ActivityKit
#endif
#if canImport(AlarmKit)
  import AlarmKit
#endif

#if canImport(AlarmKit)
  @available(iOS 26.0, *)
  struct AWAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: AlarmAttributes<AWAlarmMetadata>.self) { context in
        AWAlarmLockScreenView(context: context)
          .activityBackgroundTint(nil)
      } dynamicIsland: { context in
        DynamicIsland {
          DynamicIslandExpandedRegion(.leading) {
            Image(systemName: "alarm.fill")
              .foregroundStyle(context.attributes.tintColor)
          }
          DynamicIslandExpandedRegion(.center) {
            Text(context.attributes.presentation.alert.title)
              .font(.headline)
              .lineLimit(2)
          }
          DynamicIslandExpandedRegion(.bottom) {
            AWAlarmModeLabel(state: context.state)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } compactLeading: {
          Image(systemName: "alarm.fill")
            .foregroundStyle(context.attributes.tintColor)
        } compactTrailing: {
          AWAlarmModeLabel(state: context.state)
            .font(.caption2)
        } minimal: {
          Image(systemName: "alarm.fill")
            .foregroundStyle(context.attributes.tintColor)
        }
      }
    }
  }

  @available(iOS 26.0, *)
  private struct AWAlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<AWAlarmMetadata>>

    var body: some View {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "alarm.fill")
          .font(.title2)
          .foregroundStyle(context.attributes.tintColor)
        VStack(alignment: .leading, spacing: 4) {
          Text(context.attributes.presentation.alert.title)
            .font(.headline)
            .lineLimit(2)
          if let body = context.attributes.metadata?.body, !body.isEmpty {
            Text(body)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          AWAlarmModeLabel(state: context.state)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding()
    }
  }

  /// What the alarm is doing right now, in the one vocabulary the system gives
  /// us: counting down to its next ring, paused, or alerting.
  @available(iOS 26.0, *)
  private struct AWAlarmModeLabel: View {
    let state: AlarmPresentationState

    var body: some View {
      switch state.mode {
      case .countdown(let countdown):
        Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
      case .paused:
        Image(systemName: "pause.circle")
      case .alert:
        Image(systemName: "bell.and.waves.left.and.right.fill")
      @unknown default:
        EmptyView()
      }
    }
  }
#endif
