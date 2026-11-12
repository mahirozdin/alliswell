# ADR-0069 — The urgent-alarm device is a server-held per-device flag

- **Status:** Accepted
- **Date:** 2026-11-12
- **Related task:** OPH-432, OPH-433, OPH-434, OPH-435, OPH-436, OPH-445, OPH-446, OPH-447,
  OPH-448, OPH-449, OPH-452, OPH-453 (issue #48)
- **Amends:** [ADR-0015](0015-alarm-delivery-and-reminder-profiles.md) decision 4 ("delivery is a
  per-device concern") for urgent alarms only

## Context

Issue #48: every signed-in device schedules every urgent alarm from its own replica, so a phone,
a tablet, a Mac and a browser tab ring together. The owner asked for a per-device switch "ring
urgent alarms on this device", on for the first device and off for every later one, changeable for
any device from any device (web included), with name, platform, last seen, rename and remove
(= sign out) in Settings ▸ Devices.

Constraints found in the code:

- The device list already exists on the server (`notification_devices`, one row per install,
  registered with `PUT /notification-devices/:id`), but nothing tied a row to a session:
  "remove" deleted the row while the install stayed signed in and re-registered.
- A preference in `localKv` cannot be changed from another device, and a client-side "first
  device" rule races when two devices register at once.
- An updated install must not go silent because it has not heard from the server yet; a freshly
  signed-in device must not ring before the server has decided.

## Decision

1. **The flag lives on the server.** `notification_devices.rings_urgent` (boolean, default 0) and
   `rings_urgent_source` (`auto` | `user` | `backfill`). Responses of `GET`/`PUT` carry
   `ringsUrgent` and `ringsUrgentSource`; old clients ignore them.
2. **One rule, decided on insert or takeover** (`PUT` of a new row, or of a row registered by
   another account), in one transaction with the user's row locked (`SELECT … FOR UPDATE`):

   | The user's rows with `rings_urgent = 1` | New row | Other rows |
   | --- | --- | --- |
   | none | 1, `auto` (web included) | — |
   | all of them web with source `auto` or `backfill`, and the new device is not web | 1, `auto` | those web rows 0, same transaction (hand-over) |
   | any other case | 0, `auto` | untouched |

   A heartbeat (same user, existing row) never touches the flag. `PATCH
   /notification-devices/:id {ringsUrgent?, deviceName?}` works on the caller's own rows, writes
   source `user`, and switching off the last ringing device is allowed with the warning
   `NO_URGENT_DEVICE` (warn, never block). Deleting the last ringing row promotes the most recently
   seen non-web row (else web) to 1, `auto`, in the same transaction.
3. **Web.** A browser tab may be an alarm device. It starts off while another device rings; a
   web-only account rings on web; the first phone or desktop that registers takes the alarm over
   from an automatically chosen web row. A web row the user switched on is never handed over. The
   web row says it rings only while the tab is open.
4. **Existing accounts (backfill, owner decision 2026-11-12).** After the update the account's
   **first-added device** rings and every other device is off; the user turns others on in
   Settings ▸ Devices. Every row gets source `backfill`. *Assumption, stated to the owner:* the
   choice is made among non-web devices seen in the last 14 days, else web devices seen in the
   last 14 days, else all of the user's devices — oldest `created_at` first, ties by id — so an
   install unopened for years cannot swallow the alarm. A device that ends up off shows a one-time
   card: "Bu cihazda acil alarmlar kapalı. Alarmlar {cihaz}’da çalıyor." + "Bu cihazda da çal".
5. **Four client states, one gate.** The app keeps the last answer in `localKv`
   (`alliswell_rings_urgent`) as `on`, `off`, `unknown` or `legacy`:

   | State | When | Urgent alarms on this device |
   | --- | --- | --- |
   | `on` / `off` | from the register or list response | `on` rings; `off` becomes a normal notification |
   | `unknown` | a fresh sign-in or an account switch, until the register response | normal notification — nothing is lost, nothing rings twice |
   | `legacy` | an updated install with a restored session and no stored value, or a server without the field | rings as before the update |

   One pure function applies it before planning, in the foreground scheduler, the ring overlay
   and the Android headless turn. An off device still receives every reminder as a normal
   notification.
6. **Remove = sign out.** `refresh_tokens.device_id` binds a session family to its device (sent as
   `deviceId` on sign-in and refresh, set once per family). `DELETE /notification-devices/:id`
   revokes that family in the same transaction, then deletes the row and promotes as in 2; the
   removed install is signed out and wiped at its next refresh. In the other direction, revoking a
   family (session list, password change, sign out everywhere, token reuse) deletes the device rows
   bound to it. There is no separate sign-out route. Removing a device is delete-like and stays out
   of MCP (I-12); the device endpoints are REST only — device infrastructure, not task data.
7. **Silencing elsewhere.** Acknowledging or snoozing a ringing urgent alarm sends the existing
   ids-only wake (`{v, type: 'wake'}`, I-13) to the account's other ringing Android devices,
   bypassing the per-minute wake gate, and every Android scheduler pass cancels a delivered urgent
   notification whose occurrence is no longer ringing. iOS gets no silent push (ADR-0038 §8 stands).

## Alternatives considered

- **Keep the switch device-local.** Cannot be changed from another device and cannot guarantee a
  single default device.
- **"Most recently seen device" as the backfill.** The CEO's proposal; the owner chose the
  first-added device. The 14-day guard keeps the owner's rule from picking a dead install.
- **Web always off.** A web-only account would then have no alarm device at all.
- **A separate sign-out route next to DELETE.** Two ways to remove a device that differ only in
  whether the session survives; "remove" in the UI means sign out.
- **Silent push + `AlarmManager.stop` on iOS to silence a ringing iPhone.** Delivery is not
  guaranteed, is throttled, and never reaches a force-quit app; the background mode stays off.

## Consequences

- **Easier:** one ringing device by default, changeable from anywhere; a removed device really
  signs out; Android devices stop ringing when the alarm is answered elsewhere.
- **Harder:** two migrations (`notification_devices` flag + source with its tested backfill,
  `refresh_tokens.device_id`); the auth paths learn `deviceId`; the gate must be applied
  identically in three places, so it is one pure function with a parity test.
- **Known limits, said in Settings ▸ Devices:** an **iPhone that is ringing cannot be silenced from
  another device** — AlarmKit offers no remote path; it stops when answered on the iPhone, or at
  its next foreground pass. Android can be silenced remotely. A removed device's access token lives
  up to `AUTH_ACCESS_TTL_SEC`, and alarms it already scheduled may ring once until it next runs.
- **Follow-ups (candidates):** a Notification Service Extension spike for remote stop on iPhone;
  excluding the acknowledging client from the alarm-stop wake.

## Note — 2026-11-12, as shipped (OPH-432…436, OPH-445…449, OPH-452, OPH-453)

The decision stands; the auth work kept it, so no new ADR. What the code fixed in detail:

- **#6, session binding.** The app sends `deviceId` only after this server has answered
  `ringsUrgent`; an older server's 400 is retried once without it, so sign-in never fails on it. A
  bound family keeps its device whatever a later refresh names. `DELETE` by an API key is 403
  (session management, ADR-0032). `GET` adds `hasSession`, and the app warns when a removed device
  had none. The reverse cleanup keeps a device row that another live family is still bound to, and
  never touches rows bound to no family (older clients).
- **#6, access-token limit.** Revoking the family stops the next refresh, not the current access
  token: the removed device keeps working for up to `AUTH_ACCESS_TTL_SEC` (15 minutes by default).
  How an open web tab's socket behaves after that is a device check.
- **#6, the wipe.** Only a revoked family (`AUTH_REFRESH_REUSED`) ends in the remote sign-out wipe.
  A refresh token that merely expired signs out and keeps the replica. With unsent or refused
  changes the revoked path still signs out, halts sync and drops the OS alarms, but keeps the
  replica for the same person's next sign-in (OPH-355's "never a silent loss").
- **#5, the gate.** The headless Android turn reads the same stored answer (no key = `legacy`) and
  the stored chain profile and sounds, so its urgent ids equal the foreground's. Home shows the
  one-time card when this device is off and another rings. The alarm band says "No device rings
  urgent alarms" when the server knows the flag and none rings.
- **#7, the stop wake.** It fires for an urgent reminder snoozed, or acknowledged, completed or
  cancelled with its last ring in [now − 45 min, now + 1 min], to the members' Android devices with
  `rings_urgent = 1`. The acknowledging device is not excluded yet (the sync event carries no
  client id) — a candidate task.
