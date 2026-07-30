# ADR-0002 — AGPL-3.0 license

> **Superseded.** AllisWell moved to **PolyForm Noncommercial 1.0.0** at v1.0.0
> because the product is being commercialised — see
> [ADR-0024](0024-license-polyform-noncommercial.md). Releases up to and
> including v0.9.0 remain AGPL-3.0 for anyone who received them. The record
> below is kept as written; it is history, not current policy.

- **Status:** **Superseded by [ADR-0024](0024-license-polyform-noncommercial.md)** (2026-07-31)
- **Date:** 2026-07-14
- **Related task:** OPH-001

## Context

The project must be genuinely open source and self-hostable, remain sustainable, and welcome
contributors. The main strategic risk for self-hosted productivity platforms is closed-source SaaS
forks that give nothing back.

## Decision

License the entire repository under **GNU AGPL-3.0-only**.

## Alternatives considered

- **MIT/Apache-2.0:** maximally permissive, slightly friendlier to corporate contributors — but
  allows closed SaaS forks of the whole platform.
- **Fair-code / BSL (n8n-style):** protects commercially but is *not* open source by OSI
  definition; conflicts with the stated vision.

Comparable products chose the same path: Vikunja (AGPL), AppFlowy (AGPL), Plane (AGPL).

## Consequences

- Anyone can use, self-host and modify freely; network use of modified versions requires
  publishing source — protects the commons.
- Some enterprises avoid AGPL dependencies; acceptable because AllisWell is an *application*, not
  a library to embed.
- While the contributor base is small (no CLA), relicensing later is still feasible if ever
  needed; revisit only with strong cause.
