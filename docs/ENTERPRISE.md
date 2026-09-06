# AllisWell Enterprise

A service desk, a permission system and an org chart, added to the AllisWell you already
know — running on your own servers, against your own database, and still working when the
Wi-Fi on the shop floor does not.

AllisWell itself is free for personal use and always will be. **Enterprise** is a separate,
commercially licensed edition for organisations that need more than one person's tasks.

> **What it does, with screenshots, is on the website:**
> **[alliswell.space/enterprise](https://alliswell.space/enterprise)**
> · **[Türkçe](https://alliswell.space/enterprise/tr)**

## Why this file is short now

It used to carry the whole description, and it went stale: for four epics it told readers
that directory integration was not included, while LDAP, SAML, OIDC and SCIM had all
shipped. Nothing anywhere said so, because the gate guarding this file asserts that it
exists and is linked — never that a word of it is still true.

The description moved to a page assembled from components, whose copy sits in a checked
module beside the screenshots it refers to, so that drift has somewhere to be caught
(ADR-0036). What stays here is the part that belongs in the repository rather than on a
sales page: the licence, read next to [LICENSE](../LICENSE) and
[ADR-0024](adr/0024-license-polyform-noncommercial.md) by people evaluating the free
edition. That is a different audience, not a smaller one.

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
