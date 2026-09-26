# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Added

- **The device keeps an extension request's tags (OPH-350).** Local schema v36 adds a
  nullable column to the extension's request table holding the request's tag names as a JSON
  list; the applier fills it from what the server sends, and a request already on the device
  fills in the next time the server sends it. The migration test's v24 fixture drops the new
  column and asks that it opens empty and fills; the v34 fixture now drops everything added
  after v34 — it had kept a later column, and the step that added it again failed the open.

- **The enterprise page's enquiry form can ask for a verification (EE-232).** Built with
  `VITE_SALES_CAPTCHA_PROVIDER` (`turnstile` or `hcaptcha`) and `VITE_SALES_CAPTCHA_SITE_KEY`,
  the form draws the provider's box, holds the send button until it is ticked, sends its
  answer with the enquiry and draws a fresh box after every attempt; a box that cannot load
  says so next to it, and the e-mail address below stays the way through. Built without
  them — the default — nothing changes: no script, no box, no field. A refused verification
  now reads as its own message rather than as a refused field.

- **A file the server itself receives is stored through one guarded path.** An
  attachment on an arriving email has no app or browser that could upload it, so the
  server writes it — and it now meets exactly the checks an upload from the app meets:
  the size limit, the type decided by the file's first bytes rather than its name (a
  photo sent as `invoice.pdf` is kept as the photo it is), and the storage quota,
  measured on the bytes. Nothing else can write a file this way; an app, an API key or
  an MCP client still uploads its own files directly.

- **Someone outside can send a photo with their request.** A public request
  page can now take one image or PDF, up to 5 MB. What it is gets decided by
  the file's first bytes rather than by its name, so a `.pdf` that is really a
  photo is stored and opened as a photo. A file we cannot accept never costs
  you the request: the words still arrive, and the page says which part did
  not.

  These files are marked as coming from outside and are never served back
  anonymously. On the request itself the desk now sees its attachments —
  which it never could before — and the ones a stranger sent say so, in
  words about where they came from rather than a claim about whether they
  are safe. A server can have them virus-scanned on the way in: a file the
  scanner flags is never kept, and the words "not scanned" appear only on a
  file that was not.

- **One link, several things to ask about — and the answer before the
  question.** A public link can now open onto a chosen set of topics instead
  of one: the visitor picks, then fills in the form. The older single-topic
  link is unchanged and is still what you get by default. The page also
  searches the answers that have been published for those topics, so somebody
  about to write in can read the fix instead — and the desk can see how often
  that happened.

  It all still works with JavaScript switched off, because the page is not
  allowed to run any: the search is an ordinary form, the results are links,
  and nothing about the visitor is stored anywhere — no cookie, no tracking.

- **The answer somebody worked out once, written down.** A desk can now keep
  its own answers: what people see, where it happens, and the fix. An article
  starts as a captured QUESTION — the method this follows says knowledge gets
  written while the work is still open, not in a documentation session nobody
  schedules — so a solved request turns into one with a single button, taking
  the comment you point at as the solution. Publishing is a separate
  permission from writing, because "is this fix right" and "is this ready for
  someone outside to read" are different judgements, made by different people.

  Reading and searching work with no signal, which is the point: the person
  who needs the answer is usually standing next to the machine. Search matches
  the way somebody types — `yazici` finds `Yazıcı` — and while you work a
  request, the articles that match it appear beside it.

- **The equipment register, and a QR label that opens it.** Machines, vehicles,
  computers and tools now have a place to live, with the filter a maintenance
  desk cannot get from a spreadsheet: what is about to run out. Each asset
  prints a QR label that a phone's own camera opens straight to its card — no
  extra app, and the tag is printed in text beside the code because a label on
  a lathe gets wet and scratched. When a warranty or a calibration is coming
  up, whoever holds the machine hears about it once; renewing the date arms
  the reminder again.

- **The list you already have in Excel can be loaded in.** Upload a CSV, read
  a line-by-line report of what will be created, updated or refused, and only
  then approve it — nothing is written before that. Turkish column headings
  and `31.12.2027` dates are understood as they are typed, because converting
  a thousand rows by hand defeats the point.

- **A request can say which machine it is about, and the machine remembers.**
  Requests now carry the equipment they concern, and every piece of equipment
  keeps the list of requests it has caused — including the ones already
  archived, which is the whole point: most of a machine's history is in the
  past. Alongside it are the twelve-month counts that answer the question
  nobody could ask before, namely whether a machine should be replaced rather
  than repaired again. Change windows can say which machines they touch, too.

- **A request now shows everything it caused, and a way to say it has come
  back.** The request screen lists all the work opened from it rather than one
  piece, and can open another without leaving the page. Where a request is
  waiting on something, it says what. And when the same matter turns up again,
  one action opens a new request carrying the old one's summary and ties the
  two together — the old one is left exactly as it was, because a request that
  was finished stays finished.

- **The search reachability gate refuses an exemption that is no longer true
  (OPH-348).** An entity may be exempt from having a screen that searches it,
  with a written reason ("no screen yet"). When a screen started calling it,
  the gate stopped looking at the exemption and carried the stale reason
  green. It now fails, naming the caller, until the exemption is deleted; the
  extension's change entity lost its exemption this way.

- **The device keeps which machine a draft request is about (OPH-349).** A
  request written with no signal waits on the phone as a draft, and a draft can
  now be written from a machine's card; the machine travels with it, so the
  request that arrives later is tied to the machine like one filed online. The
  one extension table the device writes into rather than mirrors, so the value
  is the device's own and a pull no longer takes it back off the draft on
  screen. Kept from local schema v35. The migration test gained a fixture for a
  device holding an unsent draft — the only kind that runs the new step — and
  deleting the step turns it red.

- **The device keeps what kind of work an extension's request is (OPH-346).**
  The server sends it with the request, and the queue filters by it with no
  signal, so the value lives in the local copy. Kept from local schema v34. A
  request already on the device fills in the next time the server sends it.
  The migration test's device-that-already-holds-requests fixture grew with it,
  and deleting the new step turns that test red.

- **The device keeps who asked for an extension's request, and where the
  answer goes (OPH-344).** The server always sent both; the local copy dropped
  them, so a screen with no signal could not show them. Kept from local schema
  v33. A request already on the device fills in the next time the server sends
  it. The migration test gained a fixture for a device that already holds such
  requests, the only kind that runs the column steps; it proved two older steps
  that no test had ever run.

- **The device's local copy learned one more kind of record (OPH-327).** An
  extension can register an entity that lives on the phone beside tasks and
  notes — pulled, searched by the same folded-text rules, and readable with no
  signal. The schema step is per entity rather than one step for several,
  because their shapes are decided by the features that add them and those
  land at different times. Nothing changes for an install without the
  extension: the table is there and stays empty.

- **A file can be attached to things the extension adds, not just the four core
  ones (OPH-325).** What a file may hang on is now a registry rather than a
  fixed list, so an extension can register its own kind and the upload, the
  read surface and the cascade all work without core naming it. The column
  stopped being an ENUM to allow it; the values core itself accepts are
  unchanged, and a kind nobody registered is still refused.
- **Search reaches what the extension stores (OPH-326).** The device's search
  runs off a registry of searchable entities instead of a hand-written list per
  table, so a kind the extension adds is findable with everything else, by the
  same folded-text rules. Local-first is unchanged: the query never leaves the
  device.
- **A push can say that a notification is waiting (OPH-329).** The wire
  contract has a third type, carrying an identifier and — when it should be
  seen — one fixed sentence chosen from the catalogue. Nothing about what
  happened travels with it: the device fetches the row itself. ADR-0038 said
  the payload had two types and it now says three.
- **A "+" on the home-screen widget (OPH-333).** Tapping it opens the app with
  the new-task sheet already up — the same sheet as the Home "+" button, with
  the same day pre-filled. It is a shortcut into the app rather than a way to
  add from the widget itself: a widget cannot take typed text, so nothing is
  created until you save. On iPhone it sits in the date header of the large
  sizes and in a narrow column of its own on the medium one; on Android it
  closes the header.
- **A widget per project, and two on the lock screen (OPH-336).** Each widget
  you place can now show everything, as before, or a single project — so two
  widgets can follow two projects, each named at the top in its own colour.
  On iPhone, iPad and Mac it is the widget's "Edit" (iOS 17 / macOS 14 and
  later); on Android, long-press the widget and reconfigure it (before Android
  12 the choice appears as you place it). A widget you never set keeps showing
  everything. The iPhone lock screen gains two small widgets: the next task
  and when it is due — overdue first, and saying "Overdue" in words, since the
  lock screen draws in one tint — and today's open count. Which tasks belong to
  which list is still worked out in the app, never in the widget.
- **A private widget, and a compact one (OPH-337).** Settings › General has a
  Widget card with two switches. "Private widget" shows "Private task" in
  place of every title — on the home screen, on the lock screen, in every
  project's widget — and it does that before anything is written for the
  widget, so the titles never leave the app at all; the counts, times and
  colours stay. It is also why the app now reads that setting before it
  writes a widget's data, even at start-up. "Compact widget" draws tighter
  rows with slightly smaller type, and never shrinks the circle you tap.
- **A project's tasks can be sorted (OPH-338).** The Tasks tab of a project
  has the same sort button as Home, at the end of its add-a-task row, with
  the same choices — date, priority, title, and reversed. It shares Home's
  choice, so both lists are always in the same order; until now the tab was
  simply in the order the tasks were created, newest first. Finished tasks
  still sink to the bottom whatever the order.

### Changed

- **A deploy no longer ships an extension commit whose own CI has not passed
  (OPH-345).** The core half of a release only reaches a server through the
  release gate; the extension half was fetched from whatever its ref pointed
  at. Now the deploy resolves that ref to one commit first, before any build,
  and continues only if that commit's run of the extension's CI workflow
  (`DEPLOY_OVERLAY_CI_WORKFLOW`, default `EE CI`) succeeded — a red, still
  running, never run or unreadable result stops it, with the reason in the
  job summary. The server is then handed that exact commit, not the ref, so
  what was checked is what ships. **Operators:** the extension token
  (`DEPLOY_OVERLAY_TOKEN`) now needs to read Actions runs as well as contents
  (fine-grained: Actions + Contents, read-only; classic: `repo`); without it
  the deploy stops and says so.

- **A server whose extension cannot be served now refuses, instead of serving
  the plain build's rules (OPH-343, ADR-0041).** An extension brings its own
  rules — who may delete what, which writes a device may push. Until now, if
  one failed to load, the API carried on without them, and a member it had
  restricted was served with the plain build's wider rights. Now, when an
  extension is enabled and fails to load — or is missing while the database
  holds migrations it wrote, or `EE_REQUIRED=true` says it must be there —
  every request except `/health/*` answers **503 `EXTENSION_UNAVAILABLE`**, and
  `/health/ready` answers 503 with the reason under `checks.extension`. A plain
  install (no extension, or `EE_REQUIRED=false`) is unchanged, byte for byte.
  Deploys that ship an extension set `EE_REQUIRED=true` themselves.

- **The app knows whether the server answered the last time it asked
  (OPH-342).** Most of the app works offline and never needs to know. A
  screen that writes straight to the server does: it can now grey itself out
  before it is pressed, and say why, instead of failing after someone typed a
  paragraph. The answer comes from the traffic the app already makes, not
  from the phone's network icon — hotel wi-fi is a network that reaches
  nothing.
- **The widget documents say what shipped (OPH-339).** The README gains a
  Widgets section; the widget design notes, the product spec and the roadmap
  were read against the code and corrected where they described a plan rather
  than the build — the widget's thirty-day horizon, the "+" that opens the app,
  the Android drawing layer, the Mac's one remaining signing step.
- **The Mac app needs macOS 12 or later.** The Flutter toolchain raised its own
  minimum, and the Mac build had not been run since the push-notification work,
  so the project and its CocoaPods lock now say what the build already did.
- **The Mac app is ready for its widget (OPH-335).** It now writes the widget's
  data and receives the widget's taps itself — the widget library the phones
  use has no Mac side, so on a Mac those writes had been failing silently. The
  widget arrives once its extension is signed with the developer account.
- **The documented extension surface matches what the code offers (OPH-328).**
  The seam reference lists the two registries above, and the attachments page
  stopped describing a shape that had been out of date since July.
- **The generated API reference follows the registry change (OPH-325).**
  `docs/openapi.json` and `docs/API.md` no longer enumerate the four attachment
  targets, because the route no longer promises exactly those four.

### Fixed

- **An account of your own no longer shows a team's controls (EE-290).** On a server that
  also serves teams, somebody with only a personal workspace met a "Requests" tab that could
  list nothing and send nothing, and Settings rows for running a team — services, SLA
  management, the team's AI keys, identity sources, the mail relay, public request links,
  outgoing webhooks, approvals, the audit log — over screens that could not load. The tab now
  appears only on a team's own address, those rows only for that team's owner or admins, and
  a web address left on the tab moves to Home. Inside a team, a personal task no longer wears
  the team's history button or people card. A server running without the enterprise
  extension shows none of it, whatever license it was left, and the Notifications group's
  subtitle names what the page holds.

- **On the web, "Open settings" in the alarm fix sheet no longer opens a dead tab
  ([#19](https://github.com/mahirozdin/alliswell/issues/19)).** The sheet sent every browser to an
  iPhone settings address. It now tells the three cases apart: a browser that has not been asked
  gets an "Allow notifications" button that asks; one that has blocked the site gets the address
  bar steps to unblock it and a "Check again" button; and one that cannot receive notifications at
  all (Safari on an iPhone outside the Home Screen) says how to get them, with no button. The
  Settings row now updates after the sheet fixes something.

- **The quick-access button stays under your finger while you drag it
  ([#17](https://github.com/mahirozdin/alliswell/issues/17)).** It used to fall behind — the
  faster the drag, the further — and a quick release could park it on the side you had just
  left. It now follows the finger exactly, from the first pixels of the drag, and lands on the
  side you let go of.

- **The enterprise page's list caught up with the app again.** Change management and
  problem records had moved into the app while the page still called them "API only";
  both are now listed as in the app, each naming the one part that still goes through the
  API (moving a change along; a problem's root cause and status). A live list across
  several units, which the page said did not exist, is listed as there, and three shipped
  capabilities that were missing are added: incidents apart from service requests, archived
  requests that stay readable, and the absence calendar. Two lines said more than the
  product does and now say less: the SLA line names what is still entered through the API
  (target durations, shifts, holidays), and the partners line no longer offers a
  per-customer SLA, which nothing can attach yet.

- **The enterprise page says what is there today.** Its "what is not in it yet?" answer
  still named an asset register, change approvals, a satisfaction survey and requests by
  e-mail — all shipped since — and its offline line promised that requests are edited with
  the internet down (tasks and notes are; a request is read offline, a new one waits as a
  draft, and writing to one needs a connection). The page's claims about the product are
  now built from one capability list, where each item says whether it is in the app, API
  only, in pilot or not there. The package table gains a row for every module, and the
  copy check refuses a page whose "not yet" answer, capability rows or offline sentences
  differ from the list, or whose other answers say something is missing.

- **CI and `docker-compose` pull MinIO from Chainguard's registry (OPH-347).**
  MinIO
  no longer publishes a public image: quay.io's `minio/minio`, which replaced
  Docker Hub's in 1.10.2, now issues a token and still answers 401 for the
  manifest. Both API jobs died on the container start before a single
  integration test ran, and a fresh `docker compose up` would have hit the
  same wall. `cgr.dev/chainguard/minio` is the same server; the
  storage-backed integration tests passed against it before the switch. The
  compose service runs as root so that a data volume written by the old
  image stays readable.
- **On Android, three things the app asks for in the background never
  happened (OPH-341).** Ticking a task's circle on the home-screen widget, the
  six-hourly refresh that re-arms your reminders without opening the app, and
  the midnight redraw that moves the widget to the new day all send a message
  to one small receiver — and that receiver had never been declared, so every
  one of those messages went nowhere, silently, since each of them shipped. It
  is declared now, open to this app only, and a test reads the manifest so it
  cannot quietly go missing again. The iPhone was not affected.
- **The Android widget turns the day over by itself (OPH-334).** Its groups —
  overdue, today, this week — used to stay on yesterday until the app was
  opened or a six-hourly background turn happened to run. A one-time job now
  asks for a refresh shortly after local midnight and schedules the next one,
  and every background refresh ends by redrawing the widget. It is not
  to-the-minute: Android may hold it until the phone's next maintenance window.
- **A link that starts the app now lands where it points (OPH-333).** Opening
  the app from a widget row, a calendar event or a printed label while it was
  not running could end on Home instead of the task: the link arrived while the
  session was still being restored, and nothing kept it. It now waits and is
  followed once you are signed in.

## [1.13.0] — 2026-09-19

### Added

- **A reminder can now reach you when the app is not running.** Until this
  release every alarm was armed by the device itself, which meant the device had
  to have been awake since you set it — a reminder created on your laptop simply
  did not exist on a phone you had not opened, and a browser tab closed at 13:55
  could not ring at 14:00. The server now takes the three roles the device
  cannot: it sends a silent nudge the moment a reminder changes, so your phone
  syncs and arms the real alarm with its full behaviour; it sends the
  notification itself at fire time for a device whose schedule is out of date —
  which on the web is every time, because no browser can schedule anything for a
  closed tab; and on Android a periodic turn catches up underneath both. A
  device that already synced after the change is left alone, so nothing tells you
  twice. OPH-315, OPH-320, OPH-321, OPH-322,
  [ADR-0038](docs/adr/0038-server-to-device-delivery.md),
  [#15](https://github.com/mahirozdin/alliswell/issues/15).

- **"Notifications in this browser": off, silent, or with sound.** The request
  behind this was a working day in an open-plan office — a reminder that opens a
  window on the screen without a noise everybody else has to hear. Silent is the
  default, and it silences everything: the notification arrives without a sound
  and the alarm screen stays quiet, but it *says* it is deliberately silent and
  offers to start the sound, because an alarm that looks like it is ringing and
  is not is the one thing this app refuses to do. Off drops this browser's
  subscription rather than quietly swallowing what arrives. And because Firefox
  plays its own notification sound whatever we ask for, the setting says so —
  where you can do something about it, not at 3 a.m. OPH-316.

- **A push can become a window on your screen, and it can do it quietly.** The
  service worker that receives one now knows what to show: the app writes each
  reminder's finished sentence into this browser's own storage, already
  translated and already respecting your privacy setting, and the worker only
  looks it up — what travels over Google's or Mozilla's servers is still just an
  identifier. When the lookup finds nothing it falls back to exactly the wording
  a device in privacy mode already uses, rather than inventing a third voice for
  the same moment. Notifications arrive silent by default, which is the whole
  point of the request behind this: being reached without disturbing the people
  around you. Clicking one opens the task — focusing the tab you already have,
  or opening a new one on the right screen if there is none. OPH-314,
  [ADR-0039](docs/adr/0039-a-service-worker-is-the-one-thing-dart-cannot-be.md),
  [#16](https://github.com/mahirozdin/alliswell/issues/16).

- **The browser stops pretending it scheduled something.** On the web AllisWell
  was handed the same notification plumbing as a phone, and that plumbing does
  not exist in a browser — so every alarm it "scheduled" threw an error the app
  quietly wrote to a diagnostic log and carried on. The web has its own gateway
  now. It can ask for permission, from a button rather than on page load, and
  subscribe this browser so the server can reach it; what it cannot do — schedule
  anything by itself, because no browser can — it says instead of swallowing.
  And permission being granted is no longer read as "you are covered": if the
  server has no keys to send with, or the subscription has been revoked, Home
  says so and offers the thing that fixes it. On an iPhone this works only for
  AllisWell added to the Home Screen, which is Apple's rule, and the app tells
  you that rather than looking broken. OPH-313,
  [ADR-0039](docs/adr/0039-a-service-worker-is-the-one-thing-dart-cannot-be.md),
  [#16](https://github.com/mahirozdin/alliswell/issues/16).

- **The part that actually sends.** AllisWell can now talk to Google's and the
  browsers' push services — when an instance has been given credentials, and
  only then. The encryption a browser requires is left to the library that
  specialises in it, because getting it subtly wrong fails silently; everything
  around it — which failures are worth retrying, which are not, how long to wait
  — is ours, and matches how the rest of the server makes outbound calls. Google
  needs a signed assertion rather than a password, which is a dozen lines here
  instead of a large dependency, and the hour-long token it hands back is bought
  once rather than for every message. The distinction the whole thing turns on
  is not success versus failure but **gone** versus **try again**: a
  subscription somebody revoked answers the same way forever, so it is written
  off once and skipped from then on, while a push service having a bad minute
  says nothing at all about the device. Nothing calls this yet. OPH-312,
  [ADR-0038](docs/adr/0038-server-to-device-delivery.md).

- **A device can say how to reach it, and the server can remember what it
  already sent.** A browser subscription is an address plus two keys, which does
  not fit in the single field an Android token needs, so it gets its own — and
  the device registry now takes one and gives back everything except those keys,
  which the browser already has and nothing is served by echoing. Half a
  subscription is refused rather than stored: a half-filled row looks registered
  and is skipped by everything that reads it, and silence is indistinguishable
  from "nothing was due". A subscription the browser revoked stays revoked
  however often you open the tab — only registering a new one brings the device
  back. Alongside it, a small delivery log whose whole job is to make sending
  something twice impossible: claiming a row is what reserves a delivery, so two
  servers sweeping at the same moment cannot both send the same reminder.
  Nothing sends anything yet. OPH-311,
  [ADR-0038](docs/adr/0038-server-to-device-delivery.md).

- **An instance can be told how to send a push, or not be told at all.** There is
  still nothing sending one — this is the configuration and the boot-time checks
  that will govern it. The credentials are the switch: set none of them and
  nothing registers, nothing is sent, and the server behaves exactly as it did
  before. Set half of them and it refuses to start, naming the line you left
  out, because a half-filled block looks configured to whoever filled it in and
  its failure arrives days later as "the reminder never popped up" to somebody
  who cannot read the logs. The keys are measured rather than merely counted —
  they are 65 bytes and 32, so swapping them is caught at startup instead of
  months later as an encryption failure nobody can interpret — and the Google
  service account is given as a *file*, never as an environment variable, since
  a private key in the environment ends up in `ps` and in every crash dump. An
  instance that has no keys does not have the discovery endpoint at all, so one
  404 tells the app both "no key here" and "this server does not do push", and
  it never offers a setting that could not work. OPH-310,
  [ADR-0038](docs/adr/0038-server-to-device-delivery.md).

- **The app puts itself on the notification device list.** The registry endpoint
  has been correct and unused since July: nothing in the app had ever called it,
  so on every real instance the table was empty. That table is what the rest of
  this work stands on — the server decides who needs a push by asking when a
  device was last heard from — so the app now registers on sign-in, says hello
  again whenever it comes back to the foreground, and takes itself off the list
  when you sign out. It registers under the id the sync engine already uses for
  this install rather than inventing one, and it waits for that id on a fresh
  install instead of creating a second row that would never go away. A device
  also says which language it is in, because your phone and your laptop need not
  agree and the alert has to be written in one of them. The device's *name* is
  filled in by the server from the request itself rather than guessed at by the
  app — a wrong name in that list is worse than a blank one. OPH-309,
  [#15](https://github.com/mahirozdin/alliswell/issues/15).

- **A push payload names rows, and a gate keeps it that way.** Nothing is sent
  yet — this is the contract that will govern it when something is. A push
  crosses Google's, Apple's or Mozilla's servers on its way to a phone, and the
  privacy policy tells people that a task's title never makes that trip. So
  there is now exactly one place a push body can be built, every transport must
  pass through its check, and `npm run check:push-payload` fails the build when
  what the code would send stops matching what a person agreed it may send.
  Declaring the allowed keys is not enough on its own: the obvious leak is a new
  field called `title`, but the quiet one is an existing field holding a
  sentence — so identifiers must be shaped like identifiers, times like times,
  and a push the user actually sees carries the *name* of a fixed message rather
  than the message. The gate also rebuilds every payload beside a task whose
  every field is a sentence and reads the wire format back, which is a second
  question the allowlist cannot answer for it. OPH-308, [ADR-0038](docs/adr/0038-server-to-device-delivery.md),
  [#15](https://github.com/mahirozdin/alliswell/issues/15),
  [#16](https://github.com/mahirozdin/alliswell/issues/16).


### Changed

- **What a push carries, stated exactly.** [PRIVACY.md](docs/PRIVACY.md) now
  separates the two cases instead of one sentence covering both: in a browser
  nothing readable crosses a push service — the service worker reads the words
  from this device's own cache — while a phone notification that must appear with
  the app closed is drawn by Apple or Google from what the push carries, so one
  fixed generic sentence ("You have 1 reminder") travels with it. It is the same
  sentence for every AllisWell user and it never contains anything from your
  task. The exact strings live in a file a person has to agree to, and CI fails
  if a new word appears. OPH-320.

- **The platform table in [NOTIFICATIONS.md](docs/NOTIFICATIONS.md) is generated
  from the app.** It used to be prose, and it described a web permission flow no
  line of code performed — for months. It is rendered now from the same
  declaration the app obeys before it asks for a push token, and a CI gate fails
  when the document and the build disagree. OPH-317,
  [#16](https://github.com/mahirozdin/alliswell/issues/16).

### Fixed

- **Urgent alarms reach the phone again — they had stopped reaching the operating
  system at all.** On a release build the alarm sound was being stripped out of
  the app by the Android build's resource shrinker, because nothing references it
  by id: the only thing that asks for it does so by name, while the app is
  running. Every urgent reminder then failed to schedule, the app wrote the
  failure into its alarm log and carried on, and the result was the worst kind of
  quiet: Settings still said "Urgent alarms — Ready", no warning appeared, and
  opening the app still rang the alarm screen — because that runs off a timer
  inside the app and never needed the system. What did not happen was the only
  thing that mattered: a phone with AllisWell closed stayed silent. Debug builds
  do not shrink resources, which is why this was invisible in development and
  could only be reproduced on a real device, on a release build, by waiting.
  OPH-324.

- **The local database no longer blocks its own readers.** The replica is opened
  with write-ahead logging and a wait instead of an immediate failure, which
  matters because two parts of the app open it at once: the home-screen widget's
  background code writes to the same file the app is reading. It survived until
  now because that write is a single statement; a sync pull holds the file for as
  long as the network takes. The replica holds writes that have not reached the
  server yet, so this is the one place the app could lose something for good.
  OPH-318.

## Earlier releases

v0.1.0 … v1.11.0: [docs/changelog/v0.1.0-v1.11.0.md](docs/changelog/v0.1.0-v1.11.0.md).
