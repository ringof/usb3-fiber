# USB3-Fiber KiCad Repository Migration Plan

Porting the repository-infrastructure work proven out on
[`ringof/taprx888`](https://github.com/ringof/taprx888) to this project, adapted
to the requirements agreed for this repo.

> **Scope note:** This plan covers *repository, layout, CI, release, provenance,
> and library/rule-hygiene infrastructure* — the automation and quality layer
> around the KiCad design. It deliberately excludes the AI-authored
> schematic-review documents that lived at the top of the taprx888 repo.

---

## 1. What the taprx888 effort delivered (infra layer)

Setting the review write-ups aside, the reusable pattern was: a headless
`kicad-cli` CI pipeline producing checks and fabrication outputs; `GIT_HASH`
provenance stamped into the design; ERC/DRC/library findings filed as tracked
issues; a README with download links; fabrication outputs published as releases;
and a LICENSE.

## 2. Current state of this repo

- ✅ Migrated to **KiCad 10.0** (`version 20260206`; latest stable 10.0.4),
  4-layer, targeting JLCPCB.
- ✅ **Flattened** to the repo root (out of the former `usb3_fiber/` subdir); an
  orphan `.history` gitlink accidentally committed during the migration was
  removed and `.gitignore`d.
- ✅ `LICENSE` (CERN-OHL-P v2) and root `README.md` added.
- ✅ **`main` protected** (see the policy below) and **squash-only merges**
  configured.
- ✅ **Dev CI** (`dev-checks.yml`): ERC/DRC/BOM + schematic/assembly drawings,
  bring-up mode (`ENFORCE=false`).
- ✅ **Provenance (title block)**: `${REVISION}` / `${GIT_HASH}` text variables
  defined and referenced in the schematic + PCB title blocks; injected at build
  time by the release CI.
- **Strong** design docs already committed: `docs/fab_specification.txt` and
  `docs/USB3_Fiber_Link_Minimal_Circuit.md`, plus a custom
  `usb3_fiber.kicad_dru` with high-speed rules.
- **Still missing / in progress:** main-release CI + release packaging (this
  branch), the **bottom-silkscreen** provenance text (needs placement in KiCad —
  see Phase 2 note), flipping `ENFORCE=true` + required checks, and the
  library/fab-rule audit (Phase 5).
- Known static finding: `In1.Cu`/`In2.Cu` are typed `signal` in the PCB though
  the fab spec defines them as GND/PWR planes (same class as taprx888 #12).

## 3. Agreed requirements

These decisions drive the plan below:

1. **Repo layout — flatten.** The KiCad project lives at the **repo root**, not
   nested in a duplicate `usb3_fiber/` folder. Move via history-preserving
   `git mv`. Safe: all internal paths use `${KIPRJMOD}` / `${KICAD8_3DMODEL_DIR}`
   (verified — no hardcoded `usb3_fiber/` references).
2. **Branch model.** `main` is protected. Work happens on `dev-*` branches.
   **✅ Configured** via a `main` branch ruleset (Settings → Rules → Rulesets):
   require a pull request before merging (**0 required approvals**), **restrict
   deletions**, **block force pushes**, with a **Repository admin bypass**.
   Required status checks are intentionally **off for now** — the ERC/DRC/BOM
   gates get added to this ruleset once the dev CI (Phase 3) is live. Merges are
   **squash-only** (Settings → General → Pull Requests), which also keeps `main`
   linear.
3. **Dev CI** (on `dev-*`): ERC, DRC, BOM check, and generation of schematic PDF
   + assembly-drawing outputs as build artifacts.
4. **Main CI** (on `main`): produce the full design/fabrication package and
   **uprev the revision** stamped on the silkscreen.
5. **Revision scheme.** **Alpha** (Rev A → B → C), **injected at build time**
   (same mechanism as `GIT_HASH`, nothing committed back to `main`).
   **GitHub Releases are the source of truth** for the current revision.
6. **Library audit.** Evaluate **all** local library assets (symbols,
   footprints, 3D models) for compliance with the **KiCad Library Convention
   (KLC)** via `kicad-library-utils`. KLC results are **warning-level only** —
   never a build gate.
7. **Fab/assembly rule baseline.** Adopt **JLCPCB (standard 4-layer process)**
   capabilities as the reference. Set any missing DRC rules and validate
   existing ones against it.
8. **3D-model completeness.** Every **fitted** component must have a working 3D
   model. **Unplaced/DNP** parts are exempt. Enforced as a **gate on the main /
   fab path** (warning on dev).
9. **BOM check.** Every fitted part must have MPN + footprint + value with no
   empty required fields, DNP handled correctly. **Gate.**

**Gate vs. warning summary**

| Check | dev-* | main |
|---|---|---|
| ERC | gate | gate |
| DRC (JLCPCB + custom rules) | gate | gate |
| BOM check | gate | gate |
| 3D-model completeness (fitted parts) | warning | **gate** |
| KLC library compliance | warning | warning |

## 4. Target repository layout (after flatten)

```
/
├── usb3_fiber.kicad_pro / .kicad_sch / .kicad_pcb / .kicad_prl / .kicad_dru
├── fp-lib-table / sym-lib-table
├── library/            (usb3_fiber.kicad_sym, .pretty/, 3dmodels/)
├── datasheets/
├── docs/               (fab_specification.txt, minimal-circuit doc, this plan)
├── README.md
├── LICENSE
└── .github/workflows/  (dev-checks.yml, main-release.yml)
```

## 5. Phased plan

### Phase 0 — Migrate to KiCad 10.0 + baseline capture
- **Migrate the project to KiCad 10.0** first: open in KiCad 10 and re-save so all
  `.kicad_pro/.kicad_sch/.kicad_pcb/.kicad_sym/.kicad_mod` files are rewritten to
  the v10 S-expression format. This is a large, mechanical diff — keep it in its
  own commit, separate from any substantive change, so later diffs stay readable.
- Pin CI to **KiCad 10.0.x** (10.0.4 at time of writing).
- Then run `kicad-cli sch erc` and `kicad-cli pcb drc` (fed `usb3_fiber.kicad_dru`)
  to capture a violation baseline — the reference point for Phase 5 issues.

### Phase 1 — Layout flatten + repo hygiene
- `git mv usb3_fiber/* .` (and dotfiles) to bring the project to the repo root;
  merge `usb3_fiber/docs/` into root `docs/`. Verify project opens and lib
  tables resolve.
- Root `README.md` (description from the minimal-circuit doc, architecture
  summary, download-links section pointing at Releases, build-from-source note).
- `LICENSE` — **CERN-OHL-P v2** (permissive, hardware-native; SPDX
  `CERN-OHL-P-2.0`). Added.
- Extend `.gitignore` for `kicad-cli` output dirs (`fab/`, `gerbers/`, etc.).

### Phase 2 — Provenance (build-time injection)
- Add `${GIT_HASH}` and `${REVISION}` text variables; reference them in the
  schematic title block and the **bottom silkscreen**.
- CI fills both at build time — short SHA for `GIT_HASH`, the computed alpha
  letter for `REVISION`. Nothing is committed back to the design files.

### Phase 3 — Dev CI (`.github/workflows/dev-checks.yml`, on `dev-*`)
- Headless `kicad-cli` in a pinned KiCad 10.0.x container.
- Jobs: **ERC** (gate), **DRC** (gate, incl. custom `.kicad_dru`), **BOM check**
  (gate), **3D-completeness** (warning), **KLC** (warning).
- Generate **schematic PDF** and **assembly drawings** (fab/assembly PDF + CPL);
  upload as build artifacts.

### Phase 4 — Main CI + release (`.github/workflows/main-release.yml`, on `main`)
- All dev checks, plus **3D-completeness as a gate**.
- Compute next alpha revision by reading the **latest GitHub Release**; inject
  `REVISION` + `GIT_HASH`.
- Export the full package: Gerbers, drill, BOM, CPL, schematic PDF, assembly
  drawings, and STEP. Zip and **publish as a new GitHub Release** under the new
  rev (e.g. `revB`).

### Phase 5 — Rule + library hardening
- **Fab rules (JLCPCB standard 4-layer):** reconcile `.kicad_pro`
  `board_design_settings` and `usb3_fiber.kicad_dru` against JLCPCB's published
  capabilities; enable checks found disabled in the taprx888 pattern (courtyard,
  dielectric/impedance); fix the `In1.Cu`/`In2.Cu` `signal`→plane typing.
- **KLC audit:** run `kicad-library-utils` klc-check over the symbol lib,
  `.pretty` footprints, and 3D models; wire it into CI as a warning-level report.
- File remaining Phase-0 and audit findings as tracked GitHub issues.

### Phase 6 — First tagged release
- With CI green on `main`, cut the first release (**Rev A**, matching the fab
  spec revision history) — the first provenance-stamped, reproducible package.

## 6. Suggested execution order

`Phase 0` → `Phase 1` → `Phase 2` → `Phase 3` → `Phase 4` → `Phase 5` →
`Phase 6`.

Phases 1–2 touch layout + provenance and are the lowest-risk first PR. Phases
3–4 stand up the two-tier CI. Phase 5 is the rule/library hardening pass. Phase
6 is the payoff: a reproducible, revision-stamped fabrication package driven off
GitHub Releases.

## 7. Open items

*(Resolved: LICENSE = CERN-OHL-P v2. KiCad version = 10.0, migrated up front in
Phase 0.)*
