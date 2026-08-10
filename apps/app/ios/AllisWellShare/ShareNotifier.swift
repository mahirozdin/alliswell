//
//  ShareNotifier.swift
//  AllisWellShare — the "your share is waiting" banner (OPH-242, ADR-0029).
//
//  Since an app extension cannot bring its host app forward on iOS 18+, the
//  payload waits in the App Group until the app next runs. Without a banner
//  that wait is indistinguishable from the original complaint ("I shared
//  something and nothing happened"), so the extension posts one.
//
//  The banner is a NUDGE, never the transport. Tapping it just launches
//  AllisWell, which drains the App Group the way it would have on any other
//  launch. If notifications are denied, the share is not lost — it simply
//  arrives the next time the app is opened. That degradation is the whole
//  reason the drain, and not the tap, carries the payload.
//
import Foundation
import UserNotifications

enum ShareNotifier {

    /// One stable identifier, so sharing three things before opening the app
    /// coalesces into one banner instead of stacking three.
    private static let requestIdentifier = "aw.share.pending"

    static func schedulePendingBanner() {
        let center = UNUserNotificationCenter.current()

        // NEVER requestAuthorization from an appex: there is no app context to
        // present the system prompt in. We read the decision the app already
        // has (alarms ask for it) and stay quiet when we do not have it.
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return
            }

            let content = UNMutableNotificationContent()
            // Localised in the extension's own bundle — an appex cannot reach
            // the Flutter i18n assets. The shared TEXT is deliberately absent:
            // this lands on a lock screen.
            content.title = NSLocalizedString(
                "share.pending.title",
                value: "Shared with AllisWell",
                comment: "Notification title after a share is saved"
            )
            content.body = NSLocalizedString(
                "share.pending.body",
                value: "Open AllisWell to turn it into a task.",
                comment: "Notification body after a share is saved"
            )
            content.sound = nil

            // A short trigger rather than nil: a scheduled request is handed to
            // the notification daemon, which survives this extension being torn
            // down the moment it completes its request.
            let request = UNNotificationRequest(
                identifier: requestIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: 0.5,
                    repeats: false
                )
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
}
