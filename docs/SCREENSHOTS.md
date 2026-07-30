# Screenshots — how the images in this repo are produced

Everything under [`screenshots/`](../screenshots) and [`store/`](../store) is
generated, not hand-assembled. This file is the recipe, so anybody (or any
agent) can reproduce or refresh the whole set after a UI change.

Nothing here is mocked up: every image is the real app, signed into a real API,
reading a real database.

---

## 0. The demo workspace

One dataset feeds every image — the README, the landing page and both stores —
so a feature never looks different in two places.

```bash
docker compose up -d mysql redis minio     # infra
npm run db:migrate
npm run dev                                # API on :3000

node scripts/seed-demo.mjs                 # demo@alliswell.space / AllisWellDemo2026
```

[`scripts/seed-demo.mjs`](../scripts/seed-demo.mjs) writes 7 projects, 9 tags,
~47 tasks (overdue, today, this week, the next 30 days, three board columns and
a completed history), 4 recurring series, 8 notes, 4 folders, 7 uploaded files
and 7 quick-access shortcuts — all through the public REST API, so nothing in a
screenshot is a state the product cannot actually reach.

Dates are computed relative to the run, so "today" is always believable.

Two deliberate rules in that script, both learned the hard way:

- **Overdue tasks never get `isUrgent`.** Since OPH-138 an urgent task
  synthesises an alarm at its own due time, so an overdue urgent row opens the
  app straight into the full-screen ring — correct behaviour, useless demo. The
  overdue rows keep `priority: 'urgent'` and its red flag.
- **`--backdate`** rewrites `completed_at` directly in the database, because it
  is server-owned and always stamped `now`. Without it every completion reads as
  today, which buries Home under struck-through rows and leaves
  Settings ▸ Completed with a one-day "timeline". It is the script's only bypass
  of the API and it is skipped automatically when no database is reachable.

---

## 1. Web — `screenshots/web/`

```bash
cd apps/app
flutter build web --release --dart-define=ALLISWELL_API_URL=http://localhost:3000
cd ../..
python3 -m http.server 8080 --directory apps/app/build/web &

npm run shots:web          # → screenshots/web/*.png
```

[`scripts/screenshots/web.mjs`](../scripts/screenshots/web.mjs) drives a real
headless Chrome over the DevTools protocol: 1440×900 desktop and 390×844 phone,
both at `deviceScaleFactor: 2`, light and dark, one PNG per surface.

Three things in it are worth knowing before you edit it:

| Trap | What actually happens |
| --- | --- |
| Flutter renders to a canvas | There is no DOM to click. The session, the locale and view preferences (`alliswell_home_view: 'board'`) are injected into `localStorage` **before the app boots**, instead of driving the sign-in form or the app bar by coordinate. |
| `document.querySelector('canvas')` finds nothing | The scene host lives in `flt-glass-pane`'s **shadow root**. Readiness is `flutter-view flt-glass-pane`. |
| `Page.reload` right after `Page.navigate` | Answers "Not attached to an active page" — the navigation is still in flight. Go via `about:blank` instead, which also guarantees a fresh boot per shot. |

## 2. iOS — `screenshots/ios/`

Real iPhone 17 Pro Max simulator, native **1320 × 2868** — which is a valid
App Store 6.9" submission size, so these files are the store set as well.

```bash
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl spawn booted defaults write -g AppleLanguages -array "en-US"
xcrun simctl spawn booted defaults write -g AppleKeyboards -array "en_US@hw=US;sw=QWERTY"
xcrun simctl shutdown booted && xcrun simctl boot "iPhone 17 Pro Max"   # both need a reboot

xcrun simctl status_bar booted override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi

cd apps/app && flutter build ios --simulator --debug \
  --dart-define=ALLISWELL_API_URL=http://localhost:3000
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.alliswell.alliswell

xcrun simctl io booted screenshot screenshots/ios/01-home.png
```

**Set the keyboard, not just the language.** With a Turkish keyboard still
active, typing `demo@alliswell.space` produces `demo'allıswellçspace` — `@`
becomes `'`, `.` becomes `ç` and `i` becomes `ı`. Both defaults need a simulator
reboot to take effect.

Navigation between shots is done with taps (there is no `simctl tap`); the
`mcp__Claude_Code_iOS_Simulator__control` tool or Xcode's UI test runner both
work. Tab bar y ≈ 900 pt; Home 53 · Inbox 136 · Projects 219 · Notes 302 ·
Files 385.

## 3. Android — `screenshots/android/`

Pixel 9 Pro XL emulator, native **1344 × 2992**.

```bash
emulator -avd Pixel_9_Pro_XL &
cd apps/app && flutter build apk --debug --dart-define=ALLISWELL_API_URL=http://10.0.2.2:3000
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.alliswell.alliswell/.MainActivity

adb exec-out screencap -p > screenshots/android/01-home.png
```

`10.0.2.2` is the host as seen from inside the emulator — `localhost` there is
the emulator itself.

**A debug APK is ~170 MB**, and a stock AVD's `/data` fills up. If `adb install`
reports "Requested internal only, but not enough space", raise
`disk.dataPartition.size` in `~/.android/avd/<name>.avd/config.ini` and restart
the emulator with `-wipe-data`.

## 4. Store assets — `store/`

```bash
node scripts/screenshots/store.mjs
```

Composes the device captures above into the exact canvases Apple and Google
require, adds the caption band, and renders the feature graphic and icons. Sizes
and the per-store checklist are in [STORE-LISTING.md](STORE-LISTING.md) §3.

---

## When to regenerate

Any change to Home, the Board, the task detail, Notes, Files or the theme.
The set is cheap to rebuild and expensive to have wrong: a stale screenshot is
the one piece of documentation nobody reads critically.
