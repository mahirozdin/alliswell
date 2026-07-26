<!--
  ACTION REQUIRED BEFORE STORE SUBMISSION:
  1. The mailbox privacy@alliswell.space does NOT exist yet. Create it, or replace
     every occurrence of that address in this file and in PRIVACY.tr.md.
  2. Maintainers: the 3-day grace period stated below is the default
     (ACCOUNT_DELETION_GRACE_DAYS, apps/api/src/config.js). If the hosted
     deployment ever changes it, update both policy files to match.
-->

# Privacy Policy

**Languages:** **English** · [Türkçe](PRIVACY.tr.md)

**Last updated: 2026-07-26**

This policy explains what AllisWell collects, why, and what you can do about it.
It applies to the AllisWell apps and to the hosted service at
<https://alliswell.space> (API: `https://api.alliswell.space`).

## Who is responsible for your data

**APILLON BİLGİ TEKNOLOJİLERİ** is the data controller for the hosted service.

Contact for any privacy question or request: **privacy@alliswell.space**

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

## Who we share data with

No one, other than the infrastructure we need to run the service. Specifically:

- **We do not use any third-party analytics, advertising, or tracking SDKs.**
  There is no Firebase, no Crashlytics, no Sentry, no ad network, no attribution
  or fingerprinting SDK in the app or the API.
- **We do not sell or rent your data**, and we do not share it for advertising.
- We do not build profiles about you and we do not make automated decisions that
  have legal or similarly significant effects on you.

The processors we do rely on are our server and database hosting, Cloudflare R2
for the files you upload, and — only if you connect it — Google for calendar
sync. Cloudflare and Google are international providers, so data handled by them
may be stored or processed outside Türkiye and the EU. Where that happens, it is
either necessary to perform our contract with you or, for Google Calendar, based
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

If you cannot reach the in-app option, e-mail **privacy@alliswell.space** and we
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

Write to **privacy@alliswell.space** to use any of these. We may ask you to
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
write to **privacy@alliswell.space** and we will delete it.

## Self-hosting

AllisWell is open source under the **AGPL-3.0** licence, and anyone can run their
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

**APILLON BİLGİ TEKNOLOJİLERİ** — **privacy@alliswell.space**
