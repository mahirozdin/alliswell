# Support

**Languages:** **English** · [Türkçe](SUPPORT.tr.md)

Something not working, a question, or a request? Here is every way to reach us,
and what to expect from each.

## Contact us

| | |
| --- | --- |
| **E-mail** | **info@bubiapps.com** — the fastest route, and the one the stores list |
| **Bug reports & feature requests** | [GitHub Issues](https://github.com/mahirozdin/alliswell/issues) — public, searchable, and where the work actually gets tracked |
| **Security problems** | See [SECURITY.md](../SECURITY.md) — please do **not** open a public issue for these |
| **Commercial licensing** | **info@bubiapps.com** — see [Licence & commercial use](../README.md#-licence--commercial-use) |
| **Phone** | +90 505 493 1041 |

**Response time:** we aim to answer e-mail within **two business days**. Account
and data-deletion requests are handled within **30 days**, as the law requires.

**Operator:** BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI (trading as
BubiApps) · Mevlana Mah. Karasu Cad. No: 14, İç Kapı No: 16 · Talas / Kayseri ·
Türkiye

## What to include in a bug report

The more of this you can give us, the faster it gets fixed:

1. **What you expected, and what happened instead.**
2. **Where** — Home, Board, a task's detail, the widget, and so on.
3. **Which device and version** — Settings ▸ About shows the app version;
   the platform and OS version help too.
4. **Whether it happens every time**, or once.
5. If it involves a **reminder that did not ring**, please open
   **Settings ▸ Reminders ▸ Alarm log** and include what it says. That log exists
   precisely so this question is answerable.

## Frequently asked

### A reminder did not ring

Check three things, in this order:

1. **Notifications are allowed** — the app shows a red banner on Home when they
   are not, with a Fix button.
2. **Exact alarms are allowed** (Android) — Settings ▸ Apps ▸ AllisWell ▸
   Alarms & reminders. Android revokes this silently on some OEM builds.
3. **The alarm log** — Settings ▸ Reminders ▸ Alarm log records every scheduled
   and delivered alarm. If the log shows it was delivered but you heard nothing,
   the OS suppressed it; send us the entry and we can usually say why.

Battery optimisation on Samsung, Xiaomi, Huawei and OnePlus devices is the most
common cause. Excluding AllisWell from battery optimisation fixes it.

### I forgot my password

Sign in is e-mail + password. If you cannot get in, write to
**info@bubiapps.com** from the address on the account.

### How do I delete my account and everything in it?

In the app: **Settings ▸ Account ▸ Delete account**. Deletion is scheduled with a
short grace period so an accidental tap is recoverable, then everything is
removed — tasks, notes, files, calendar links, the lot. You can also write to
**info@bubiapps.com** and we will do it for you.

Full detail: [Privacy Policy — Deleting your account](PRIVACY.md#deleting-your-account).

### Can I move my data somewhere else?

Yes. Notes export as Markdown from the note menu, and if you self-host, the
database is yours — the schema is documented and nothing is obfuscated.

### Does AllisWell use my data to train AI?

No. AI features are **off until you turn them on**, there is no AllisWell AI
account, and when you do enable them you are using **your own** provider key or
your own Claude/ChatGPT subscription. The consent screen states each provider's
real data policy before you connect it — including the ones that do train on
free-tier input. See [docs/AI.md](AI.md).

### Is it free?

For personal use and self-hosting, yes — permanently, with no tier and no ads.
Commercial use needs a licence: see
[Licence & commercial use](../README.md#-licence--commercial-use).

### I want to run it on my own server

Everything you need is in [docs/SELF-HOSTING.md](SELF-HOSTING.md): one
`docker compose up`, TLS, backups, upgrades and object storage. Self-hosting is
free for personal use; support for it is best-effort through GitHub Issues.

## Known limitations

We would rather you read these here than discover them:

- **No sharing or collaboration yet.** Workspaces exist in the data model; the
  UI to invite anyone does not. AllisWell is single-user today.
- **No location-based reminders.** Apple Reminders has them; we do not.
- **Apple Calendar is one-way** on the current release — tasks you choose are
  written into the calendar you pick, and changes made in Apple Calendar do not
  come back. Google Calendar is two-way.
- **Alarm delivery depends on the OS.** We do everything the platform allows
  (iOS 26 AlarmKit, Android's alarm channel) and log what happens, but an
  aggressive battery manager can still delay a notification.

The current state of all of this is tracked in [ROADMAP.md](../ROADMAP.md).
