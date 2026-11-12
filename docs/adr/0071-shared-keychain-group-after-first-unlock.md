# ADR-0071 — The widget token sits in a shared Keychain group, readable after first unlock

- **Status:** Accepted
- **Date:** 2026-11-12
- **Related task:** OPH-457, OPH-462, OPH-464 (issue #50)
- **Related:** [ADR-0070](0070-widget-token.md) (the token), [ADR-0038](0038-server-to-device-delivery.md)
  §8 (why the session is `WhenUnlocked`), [ADR-0010](0010-home-screen-widgets-architecture.md) §7
  (the App Group); contract: [WIDGETS.md §3.2](../WIDGETS.md#32-widget-self-fetch-contract-ios-50)

## Context

The widget token of ADR-0070 is written by the app (Dart, `flutter_secure_storage`) and read by
the WidgetKit extension, a separate process with its own sandbox. Two questions decide whether the
extension can read it when it matters:

1. **Which Keychain access group.** An item in the app's default group is invisible to the
   extension. Apple lets an App Group name serve as a Keychain access group without a
   `keychain-access-groups` entitlement, and both targets already carry
   `group.com.alliswell.alliswell` (ADR-0010 §7).
2. **Which accessibility class.** The session is stored with the plugin's default,
   `kSecAttrAccessibleWhenUnlocked` (`secure_secret_store.dart` passes no options). A widget
   timeline is built while the phone is locked as often as not; a token that reads `null` behind
   the lock screen would make the fetch fail exactly when the widget is looked at.

ADR-0038 §8 said that changing the Keychain class "is a security decision with a re-key migration
and gets its own ADR". This is that ADR, for the widget token only.

## Decision

1. **Only the widget token moves.** Key `aw_widget_token`, written by a separate `WidgetTokenStore`
   with `IOSOptions(groupId: 'group.com.alliswell.alliswell', accessibility:
   KeychainAccessibility.first_unlock_this_device)`. The session (`alliswell_session`) keeps the
   default options: `WhenUnlocked`, the app's own access group, unreadable by the extension.
   **No re-key migration**: no existing item changes class or group.
2. **Access group = the App Group id**, `group.com.alliswell.alliswell`, exactly as the plugin
   passes `groupId` to `kSecAttrAccessGroup` (no team prefix). No new entitlement.
3. **Class `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.** *Assumption, recorded:* the
   decision asked for "AfterFirstUnlock"; the `ThisDeviceOnly` variant is the same class without
   migration through an encrypted backup. The token is bound to one device row
   (`notification_devices.id`); a copy restored onto another phone would be a credential for a
   device that is not there. A restored phone mints its own token at the first foreground.
4. **The extension only reads.** It never writes, renews or deletes the item; the app owns its
   life (mint, renew, delete on sign-out after the server record is gone). Before the first unlock
   after a restart the read fails (`errSecInteractionNotAllowed`) and the extension draws the App
   Group snapshot without fetching.
5. **Not synchronised.** `synchronizable: false` (the plugin default) — never iCloud Keychain.

The exact item (service, account, group, class) is written once, in WIDGETS.md §3.2, for the Dart
and Swift sides to match byte for byte.

## Alternatives considered

- **Move the whole session to `AfterFirstUnlock` in the shared group.** It would also unlock a
  background sync on iOS, but it exposes the refresh token to a second process, needs a re-key
  migration of every signed-in install, and buys nothing this round needs (iOS background refresh
  and silent push stay off).
- **Write the token into App Group `UserDefaults`.** Readable while locked, but it is a plain file
  in the container, included in backups — a credential belongs in the Keychain.
- **Plain `kSecAttrAccessibleAfterFirstUnlock`.** Migrates with encrypted backups; see decision 3.
- **A small Swift method channel instead of the plugin.** Full control over the attributes, but a
  second write path to keep correct; the plugin's layout is pinned in the contract instead, and a
  plugin upgrade that changes it fails the Dart test that pins the options.

## Consequences

- A locked phone that has been unlocked once since boot refreshes its widget; one that has not
  shows the last App Group snapshot until the first unlock.
- A `flutter_secure_storage` upgrade must be checked against the contract's service/account/group
  (the plugin source of the version in `pubspec.lock`); the device check reads the item from the
  extension once.
- ADR-0038 §8's reasoning for the session stands unchanged; iOS background refresh is still off.
