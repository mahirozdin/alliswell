# Privacy Policy

**Languages:** **English** · [Türkçe](PRIVACY.tr.md)

**Last updated: 2026-07-31**

This policy explains what AllisWell collects, why, and what you can do about it.
It applies to the AllisWell apps and to the hosted service at
<https://alliswell.space> (API: `https://api.alliswell.space`).

## Who is responsible for your data

**BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI** (trading as **BubiApps**) is the data controller for the hosted
service.

|                     |                                                                             |
| ------------------- | --------------------------------------------------------------------------- |
| **Registered name** | BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI                           |
| **Address**         | Mevlana Mah. Karasu Cad. No: 14, İç Kapı No: 16 · Talas / Kayseri · Türkiye |
| **E-mail**          | **info@bubiapps.com**                                                       |
| **Phone**           | +90 505 493 1041                                                            |

Contact for any privacy question or request: **info@bubiapps.com**. We answer
within 30 days, and within the shorter period the law requires where one applies
(KVKK: 30 days; GDPR: one month).

## What we collect

**Your account**

- E-mail address
- Password — stored only as an argon2id hash. We never store or see your plaintext password.
- Display name (optional)
- Timezone and language, so dates and reminders are correct for you

**What you create**

Tasks, projects, notes, tags, folders, reminders, and any files you upload. This
is your content. We store it so we can show it back to you and sync it across
your devices. We do not read it, mine it, or use it to train anything.

**Your devices**

For each install we keep a device id, the platform (iOS, Android, macOS,
Windows, Linux, web), and an optional push token. This exists so reminders reach
the right devices.

**Technical logs**

Our servers write request logs that include your IP address. We use them to keep
the service running and to investigate abuse and security problems. We also
record the IP address of each sign-in alongside the session, so you and we can
tell when a session was created.

## Why we may process your data, and on what legal basis

| What for                                      | Legal basis (GDPR)                      | Legal basis (KVKK, Law 6698)                                    |
| --------------------------------------------- | --------------------------------------- | --------------------------------------------------------------- |
| Running your account and syncing your content | Performance of a contract, Art. 6(1)(b) | Directly related to the performance of a contract, Art. 5/2-(c) |
| Keeping the service secure, preventing abuse  | Legitimate interests, Art. 6(1)(f)      | Legitimate interest, Art. 5/2-(f)                               |
| Google Calendar connection                    | Consent, Art. 6(1)(a)                   | Explicit consent (açık rıza)                                    |
| Meeting legal obligations                     | Legal obligation, Art. 6(1)(c)          | Legal obligation, Art. 5/2-(ç)                                  |

You can withdraw consent for the Google Calendar connection at any time by
disconnecting it. That does not affect anything we did before you withdrew it.

## Files you upload

Files go to **Cloudflare R2**, an S3-compatible object store. The bucket is
private.

The API never handles your file bytes. When you upload or download, the server
gives your app a short-lived presigned link — valid for about **15 minutes**,
for one file and one operation — and your device transfers the file directly.
The per-file limit on the hosted service is **10 MB**. (Self-hosted instances can
configure both of these differently.)

## Reminders and notifications

Reminders and alarms are scheduled and fired **locally on your device**. Your
task titles and contents are not sent to Apple's, Google's, or anyone else's
push service. The device registry described above only tells us which devices
exist; today nothing is pushed from our servers to them.

## Google Calendar (optional)

Only if you connect it:

- We store your Google OAuth tokens **encrypted at rest with AES-256-GCM**. The
  tokens never leave the server and are never sent back to the app.
- Your tasks are mirrored as events into the Google calendar you pick. This means
  the task's **title and description** are sent to Google.
- Events from that calendar are read back so you can see them next to your tasks.

Disconnecting stops all of this: we revoke the token, delete it, and delete the
cached copies of your Google events. Events that were already written to your
Google calendar stay there — you can delete them in Google Calendar.

Google's handling of the data in your Google account is governed by Google's own
privacy policy.

## Apple Calendar (optional)

Handled entirely on your device through Apple's EventKit. Nothing about your
Apple calendars is sent to our servers, and we cannot see them.

## AI features (optional)

AI is **off until you turn it on** — no provider, no AI surfaces. Nothing here
happens unless you add a provider key or start a share/voice action yourself.

- **Bring your own key.** When you connect a provider (Anthropic, OpenAI,
  Gemini, OpenRouter, or your own Ollama), your API key is stored **encrypted at
  rest with AES-256-GCM** on the server; only its last 4 characters are ever
  shown back to you, and the key is never returned to the app or sent anywhere
  except that provider.
- **What is sent, and to whom.** When you run an AI action — chat, "turn this
  into a task", summarize — the relevant text (the message you write, the task
  titles and notes the assistant needs as context, the shared text, or a voice
  **transcript**) is sent to **the provider you chose**, and only then. That
  provider's handling of it is governed by **their** privacy policy. Point it at
  a local **Ollama** and the text never leaves your own machine.
- **Voice stays on device.** Speech is recognized **on your device**; only the
  resulting text — never the audio — is ever sent, and only when you send it.
- **You always confirm.** The assistant can only _propose_; every task or note
  is created by your own tap, never automatically.
- **Connecting to Claude or ChatGPT (MCP).** If you link AllisWell to a Claude
  or ChatGPT subscription, that assistant reads your tasks through AllisWell's
  server over an authorized connection you can revoke; it can read and create,
  but **never delete**. What that assistant does with what it reads is governed
  by its own provider's policy.

Turning AI off, or removing a connection, deletes the stored key and stops all
of the above. We never send your data to a provider you did not choose. On a
self-hosted instance, the operator may supply the provider keys instead — ask
your operator what they have configured.

## Who we share data with

No one, other than the infrastructure we need to run the service. Specifically:

- **We use Firebase for crash reporting, analytics and performance**, and
  nothing else. Google is the processor. What goes to it:
  - **Crashlytics** — stack traces, OS and device model, app version.
  - **Analytics (Google Analytics for Firebase)** — screen names, app version,
    coarse device model, country-level region, and a handful of events like
    "a task was created". Not what the task said.
  - **Performance** — how long requests and screens take.

  Each of these is tagged with your AllisWell **account id** so a crash can be
  matched to a report you send us. That id is a random string. It is never your
  e-mail address, and **the content you write — task titles, note bodies, file
  names — is never attached to any of it.**

- **There is no advertising, attribution or fingerprinting SDK**, in the app or
  in the API. We do not sell or rent your data, and we do not share it for
  advertising.
- **Self-hosted builds have none of this.** The Firebase configuration is not in
  the public source; a build made from the repository has no analytics and no
  crash reporting at all (docs/FIREBASE.md).
- We do not build profiles about you and we do not make automated decisions that
  have legal or similarly significant effects on you.

The processors we rely on are our server and database hosting, Cloudflare R2 for
the files you upload, **Google (Firebase)** for the crash and usage reporting
above, and — only if you connect them — Google for calendar sync and the **AI
provider you choose** (Anthropic, OpenAI, Google Gemini,
OpenRouter, or your own Ollama, which stays local). Cloudflare, Google and the
cloud AI providers are international, so data handled by them may be stored or
processed outside Türkiye and the EU. Where that happens, it is either necessary
to perform our contract with you or, for Google Calendar and AI features, based
on your explicit consent.

## How long we keep things

- **Your content** — until you delete it or delete your account.
- **Sign-in sessions** — refresh tokens expire 30 days after they are issued, and
  the sign-in IP stored with them goes at the same time.
- **Request logs** — only as long as we need them to operate and secure the
  service.
- **Google tokens** — until you disconnect, then deleted.

## Deleting your account

You can delete your account yourself, in the app: **Settings → delete account**.

Here is exactly what happens:

1. Deletion is **scheduled with a 3-day grace period**. Nothing is erased yet.
2. If you change your mind, sign in within those 3 days and cancel the deletion.
   Everything continues as normal. Asking to delete again does not extend the
   original deadline.
3. After 3 days, your account and its content are **permanently and irreversibly
   erased** — tasks, projects, notes, tags, folders, reminders, and your uploaded
   files in object storage. There is no backup copy we can restore for you.

If you cannot reach the in-app option, e-mail **info@bubiapps.com** and we
will process the deletion for you.

One limit worth knowing: we erase the workspaces you own. If you uploaded a file
into a workspace owned by someone else, that file belongs to their workspace and
stays with it.

## Your rights

**Under the GDPR**, you can ask us to give you a copy of your data, correct it,
erase it, restrict how we use it, or hand it over in a portable format. You can
object to processing based on our legitimate interests. You can also complain to
your national data protection authority.

**Under KVKK (Law 6698), Article 11**, you have the right to:

- learn whether we process your personal data;
- request information about it if we do;
- learn the purpose of the processing and whether the data is used accordingly;
- know the third parties to whom the data is transferred, in Türkiye or abroad;
- request correction if the data is incomplete or wrong;
- request deletion or destruction, under the conditions in Article 7;
- require that corrections and deletions be notified to the third parties the
  data was transferred to;
- object to a result reached solely by automated analysis that works against you;
- claim compensation if you suffer damage because the data was processed
  unlawfully.

Write to **info@bubiapps.com** to use any of these. We may ask you to
confirm you control the account's e-mail address before we act. Turkish
residents may also apply to the Personal Data Protection Authority (KVKK).

## Security

Passwords are hashed with argon2id. Sessions use short-lived tokens plus
rotating refresh tokens, which are stored hashed and are revoked as a family if
one is reused. Google OAuth tokens are encrypted with AES-256-GCM. Files sit in a
private bucket reachable only through expiring, single-file presigned links.
Traffic runs over HTTPS.

No system is perfectly secure, and we do not claim otherwise. If you find a
vulnerability, please see [SECURITY.md](../SECURITY.md) for how to report it.

## Children

AllisWell is not directed at children under 13, and we do not knowingly collect
personal data from them. If you believe a child under 13 has created an account,
write to **info@bubiapps.com** and we will delete it.

## Self-hosting

AllisWell's source is public under the **PolyForm Noncommercial 1.0.0** licence, and anyone can run their
own instance. **This policy only covers the hosted service run by APILLON BİLGİ
TEKNOLOJİLERİ at alliswell.space.** If you use somebody else's instance, that
operator is the data controller — their rules apply, not ours, and we have no
access to their data.

## Changes to this policy

If we change this policy we will update the "Last updated" date and publish the
new version in the app and in this repository. For changes that materially
affect you, we will tell you in the app before they take effect. The history of
every edit is public in the project's Git history.

## Contact

**BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI** — **info@bubiapps.com**
