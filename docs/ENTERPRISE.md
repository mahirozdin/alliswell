# AllisWell Enterprise

A service desk, a permission system and an org chart, added to the AllisWell you already
know — running on your own servers, against your own database, and still working when the
Wi-Fi on the shop floor does not.

AllisWell itself is free for personal use and always will be. **Enterprise** is a separate,
commercially licensed edition for organisations that need more than one person's tasks: a
company where every department files work on every other department, where an outside firm
opens requests too, and where somebody has to answer for how long any of it took.

## Who it is for

Picture a factory of a few thousand people. Accounting, HR, maintenance, IT, quality,
logistics — every one of them a unit with its own work, its own inbox and its own idea of
what "urgent" means. They serve each other internally, and they serve the firms they work
with externally. Today that traffic lives in a mix of phone calls, a shared mailbox and
somebody's spreadsheet, and nobody can answer *how many requests are open in maintenance
right now* without asking maintenance.

Enterprise is built for exactly that shape: an organisation big enough that departments
need boundaries, and small enough that nobody wants to run three separate systems to get
them. It is designed to be operated by the company itself — installed once, on hardware
the company controls, with no request ever leaving the building unless the company decides
it should.

## What it adds

### Teams and subdomains

Each team gets its own address. Someone who signs in at `acme.yourdomain` sees acme's
work and nothing else — and the isolation is enforced on the server, not hidden in the
interface: a request for another team's data comes back as a plain 404 that does not even
disclose that the team exists.

Registration on a team's subdomain is **invitation only**. Invitations carry a link and a
code, expire, and can be revoked before they are used. The whole flow completes on an
instance with no mail server configured, which matters the first time you install this on
a machine inside a factory network.

### Permissions

Access is described by named permissions rather than by a handful of hard-coded roles.
Roles are assembled from those permissions, so "a maintenance supervisor may reassign
within their unit but may not close a ticket" is something an administrator expresses
instead of something they file a feature request about. Every permission is documented,
and the documentation and the code are checked against each other — a permission that
exists only in prose, or only in the source, fails the build.

### Units

A unit is a department, a workshop, a site — whatever shape the organisation actually has.
Units own their content and their inbox. Sharing across units is explicit: one unit grants
another access to something specific, the counterparty gets exactly the rights that were
granted, and the grant can be withdrawn later with the access disappearing on the other
side.

<figure class="shot">
  <picture>
    <source srcset="/shots/ee/units-admin-dark-en.jpg" media="(prefers-color-scheme: dark)">
    <img src="/shots/ee/units-admin-light-en.jpg" alt="The units screen: four units with member counts, one marked as the one you run and one archived" loading="lazy" width="900">
  </picture>
  <figcaption>Units are the shape of the organisation. Content follows the unit, not the person.</figcaption>
</figure>

### The service desk

A service catalogue describes what each unit offers and where a request for it should
land. A request becomes a ticket in that unit's inbox. Tickets and tasks stay different
things — a ticket is a promise to someone, a task is work on a list — and a ticket can be
converted into assigned task work without losing the thread between them.

**And it works offline.** The ticket in a unit's inbox is on the device, readable and
editable, before the network comes back. This is not a small detail in a building where
the shop floor has one bar of signal and the office has fibre: the service desk that only
works at a desk is the reason the phone call never stopped.

<figure class="shot">
  <picture>
    <source srcset="/shots/ee/ticket-queue-dark-en.jpg" media="(prefers-color-scheme: dark)">
    <img src="/shots/ee/ticket-queue-light-en.jpg" alt="The request queue: four tickets with priority dots, status and SLA state, one marked SLA missed and one closed with SLA met" loading="lazy" width="900">
  </picture>
  <figcaption>The queue a unit works from. Priority, status and the SLA promise on every row.</figcaption>
</figure>

### SLAs and service health

Response and resolution targets run on a **business calendar, not a wall clock** — working
hours, holidays, the team's time zone, and shifts, because a factory does not stop at 18:00
and a target measured against a three-shift day is a different number than one measured
against a nine-to-five. Daylight-saving transitions are handled rather than approximated.

Services can be watched at a health URL. When one goes down, an incident is opened; when
it is still down a minute later, another one is not.

<figure class="shot">
  <picture>
    <source srcset="/shots/ee/sla-dashboard-dark-en.jpg" media="(prefers-color-scheme: dark)">
    <img src="/shots/ee/sla-dashboard-light-en.jpg" alt="The SLA dashboard: percentage of promises kept over 314 requests, broken down by unit and by service, with the breached requests listed underneath" loading="lazy" width="900">
  </picture>
  <figcaption>What was promised against what happened — by unit, and by service.</figcaption>
</figure>

### A public request portal

Not everyone who needs to ask you for something has an account, and giving a supplier a
login is often the wrong answer. A team can publish a request form at a public URL that
routes into a unit, with an expiry date, a revoke switch and a cap on how much it can be
used. The person who files a request gets a link they can use to follow it.

<figure class="shot">
  <picture>
    <source srcset="/shots/ee/portal-links-dark-en.jpg" media="(prefers-color-scheme: dark)">
    <img src="/shots/ee/portal-links-light-en.jpg" alt="The public request portal admin screen: published request forms with their expiry, usage against quota and revoke controls" loading="lazy" width="900">
  </picture>
  <figcaption>Each public form has an expiry, a cap and a revoke switch.</figcaption>
</figure>

The anonymous surface was designed on purpose rather than by accident: it is the one door
in the product that is open without authentication, and it is treated that way.

### Meeting notes that turn into work

Upload a recording of a meeting and get back a note that separates who said what and pulls
out the decisions. A decision can be turned into a ticket in one step, which is the half of
"meeting minutes" that normally never happens.

The transcription runs through a provider **you choose**, on **your team's own key**,
entered by your own administrator — usage is metered so a long recording cannot quietly
become a large invoice. What the vendor keeps is governed by the contract your organisation
has with that vendor, and the page in the product that sets this up says so plainly rather
than promising something we do not control.

### A history that answers "who changed this"

Every change writes a history entry in the same transaction as the change itself, so there
is no version of events where the work happened and the record did not. Items carry their
own history, readable in the app.

## What does not change

Everything the free edition does, Enterprise still does, on the same codebase:

- **One app, six platforms** — iOS, Android, Web, macOS, Windows, Linux.
- **Offline-first** — the local database is the app's source of truth; the network catches up.
- **Your data on your database** — self-hosted MySQL, on your hardware or your cloud account.
  See [SELF-HOSTING.md](SELF-HOSTING.md).
- **Two-way calendar sync**, **alarms that ring through Silent and Focus**, notes, files,
  projects and search — unchanged.

## What is not in it

The honest list, because a demo that discovers this later is worse than a page that says it
now:

- **Reporting and analytics dashboards** are not part of this edition. Counts and
  breakdowns exist in the product's own screens; a report builder does not.
- **Directory integration** — LDAP/Active Directory, single sign-on, automatic user
  provisioning — is not included. Accounts are created by invitation.
- **Packages describe what a team is sold, not a hard boundary around each individual
  feature.** An operator can put a team on a package with a narrower feature list and
  smaller limits, and the product reports and enforces those limits — but Enterprise is
  sold and installed as one edition, not as modules that can be bought separately.

## Licensing

Two licences are involved, and buying one of them does not change the other.

**The free edition** is source-available under
[PolyForm Noncommercial 1.0.0](../LICENSE). Free here means free for a *person*: your own
life, your own machine, hobby projects, study, self-hosting your own instance. It is also
free for charities, schools, universities, public research bodies and government
institutions. It is **not** free for a company running it for its team — at any size — nor
for reselling it or offering it to others as a hosted service. Those need a commercial
licence.

If you arrived here from the free edition, that is the sentence worth reading twice:
**free for you, not free for your employer.** The full table of who is and is not covered,
and the reasoning behind the licence — including why it is not AGPL — is in the README's
[Licence and commercial use](../README.md#-licence--commercial-use) section and in
[ADR-0024](adr/0024-license-polyform-noncommercial.md).

One more thing that belongs in a licensing section rather than in a footnote: the project
was AGPL-3.0 until v1.0.0, and **releases up to and including v0.9.0 remain AGPL-3.0 for
anyone who received them.** A licence granted cannot be withdrawn. The current terms apply
going forward, not backwards.

Being straight about the label: PolyForm Noncommercial is **source-available**, not OSI
"open source" — it discriminates against commercial use, which the Open Source Definition
forbids. We say source-available because the other word would not be true.

**Enterprise** is proprietary and separate. It is used only under a written **AllisWell
Enterprise Agreement** executed with BubiApps; having access to it grants nothing by
itself. It does not alter the free edition's terms in either direction — the public
repository stays under PolyForm Noncommercial, and a copy you already hold stays yours
under the licence you received it under.

A commercial licence also comes with the self-hosting support the free tier does not.

### Packages

The product has a package concept, and a fresh installation ships with three of them
already defined: **Starter**, **Business** and **Enterprise**. They are shapes, not a price
list — seats, workspaces, how much of the request portal a team may use, how long history
is kept. An operator running the instance edits them, renames them, or adds their own; a
team is put on one, and the product reports and enforces the limits that package carries.

So when this page says "packages", it means that mechanism — not three boxes with prices
under them. What your organisation is entitled to is written in your agreement.

### What it costs

There is no price list on this page, and nothing is being hidden by that. Enterprise is not
a download with a checkout; it is installed and configured with you, on your hardware, and
the shape of the agreement depends on how many people and how many departments are in it.
That conversation is short, and it is the honest way to answer a question whose real answer
is "it depends on your organisation".

> **Interested?** Write to **[info@bubiapps.com](mailto:info@bubiapps.com)** and tell us how
> many people and how many departments — that is enough to start. If what you need is a
> commercial licence for the free edition rather than Enterprise, the same address handles
> that too.
