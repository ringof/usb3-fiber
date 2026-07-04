# KLC Compliance & Accepted Deviations

How this project relates to the **KiCad Library Convention (KLC)**, and the
places where we **intentionally deviate** from it.

KLC is checked in dev CI by `scripts/klc_check.sh` (kicad-library-utils over
`library/usb3_fiber.kicad_sym` and `library/usb3_fiber.pretty/`). It is
**warning-level only — it never gates a build** (see `docs/REPO_MIGRATION_PLAN.md`
Phase 5). The report is published to the `ci-docs` branch (`klc.txt`) and echoed
into the CI job summary.

The goal is **not** zero violations. KLC is written for the *official* KiCad
libraries; this is a **self-contained project library** with turnkey-assembly
requirements. A handful of KLC rules conflict with those requirements, and
"fixing" them would damage the design or the manufacturing pipeline. Those cases
are listed here as accepted deviations; everything else is remediated (tracked
in #36 and batch issues #32–#35).

## Accepted deviations

### 1. Custom BOM / part-spec fields — violates **S6.2** ("unexpected property")

Symbols carry non-standard fields that KLC flags as unexpected:

- `MANUFACTURER`, `Manufacturer Part Number` (MPN), `Vendor` / `Vendor Part
  Number` (LCSC), `PARTREV`
- Value-class attributes on the generic spec symbols: `Voltage`, `Tolerance`,
  `Temperature Coefficient`, `Impedance`, `DC Resistance`, `Max Current`, …

**Why kept:** these drive the **turnkey outputs** — the LCSC/JLCPCB BOM and the
rotation-corrected CPL read the `LCSC` / MPN / manufacturer fields (see
`usb3_fiber.kibot.yaml` and `docs/TURNKEY.md`). Deleting them to satisfy KLC
would break assembly ordering. **We keep them and accept the S6.2 flag.**

### 2. Project-local 3D-model paths — flagged by **F9.1 / F9.3**

KLC expects 3D-model paths under `${KICAD10_3DMODEL_DIR}/…` (the *official*
library install location). Our models are **committed to the repo** at
`library/3dmodels/*.step` and referenced as:

```
${KIPRJMOD}/library/3dmodels/<model>.step
```

**Why kept:** `${KIPRJMOD}` (project root) keeps the library **self-contained and
reproducible** — the models travel with the repo and resolve in CI without any
system-wide KiCad library install. This is the correct convention for a project
library; the KLC rule targets the official global library. **Accepted.**

### 3. Generic value symbols have no datasheet — part of **S6.2**

`C_Spec`, `R_Spec`, `FB_Spec` are **generic value symbols** (a capacitor /
resistor / ferrite placeholder whose value is set per-instance), not specific
orderable parts, so they have no single datasheet. Leaving `Datasheet` empty on
these is intentional. **Accepted.** (Orderable parts do carry a datasheet.)

## What we DO remediate

Everything not listed above is fixed on the `dev-klc-compliance` branch, in
batches:

- **#32** — metadata & library linkage: footprint-filter formatting/escaping,
  missing/surplus filters, symbol keywords, footprint descriptions, and adding
  datasheets to orderable parts.
- **#33** — silkscreen, courtyard, and fabrication-layer graphics.
- **#34** — 3D-model requirements (path standardization per deviation 2, plus
  offset/rotation).
- **#35** — pin & pad conventions (per-part, against datasheets).

## Baseline

Post KiCad-10 library migration: **231 violations** (65 symbol + 166 footprint).
The accepted deviations above account for a portion that will remain in the
report by design; the remainder is the remediation target.
