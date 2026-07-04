# Turnkey Assembly & KiBot Pipeline

How the CI produces **overseas-turnkey-ready** manufacturing outputs, via
[KiBot](https://github.com/INTI-CMNB/KiBot). Generic where possible, **JLCPCB-
profiled** where it matters.

## What turnkey needs (and where we were weak)

| Input | Status before | Now |
|---|---|---|
| Gerbers + drill | ✅ ok | JLCPCB gerber/drill profile |
| **Position / CPL** | ⚠️ geometrically right but **not rotation-corrected** | KiBot `rotated` variant (`_rot_footprint`) → JLCPCB-correct rotations |
| **BOM with LCSC** | ⚠️ generic, ~half of parts lack LCSC | JLCPCB BOM keyed on the `LCSC` field |
| iBOM / 3D render | ✗ | added |

The rotation correction is the big one — without it, an assembly house places
parts turned 90°/180°.

## Design decisions

- **Fab-agnostic base, JLCPCB profile.** One `.kibot.yaml`; the JLCPCB-specific
  outputs live in a `JLCPCB/` group. Other fab houses can get their own group
  later without disturbing this.
- **LCSC is the source of truth for assembly.** Our schematic already carries an
  **`LCSC`** field. KiBot's `only_jlc_parts` filter (LCSC matches `^C\d+`)
  selects what gets assembled; everything else is treated as do-not-place.
- **Rotation corrections** come from KiBot's built-in rotations database via the
  `rotated` variant. Odd footprints can be nudged with a per-part
  `JLCRotOffset` field — no global table to maintain.
- **BOM gate flips to LCSC-required.** The completeness check now fails a fitted
  part that has **no `LCSC`** (was: MPN *or* LCSC). This makes a green build mean
  "actually orderable as turnkey." Expect it to flag parts until the BOM is
  fully populated (issue #14 writ large).
- **PCB gets its own worksheet.** The board points at `usb3_fiber-fab.kicad_wks`
  (the schematic uses `usb3_fiber-sch.kicad_wks`), so the fab/assembly sheet can
  carry documentation-specific zones without disturbing the schematic frame.
  Both start from the same collision-safe title block (`${REVISION}` field +
  `${GIT_HASH}`/`${LICENSE}`/`${DESIGNER}`/`${REPO}` vars), so provenance
  injection stamps them identically.
- **Two documentation PDFs, both on the fab worksheet.**
  - `assembly_docs` → `usb3_fiber-assembly.pdf`: **Top** + **Bottom** in one PDF
    (Fab + Silk + Edge + `Dwgs.User`/`Cmts.User`) — what a placement operator reads.
  - `fab_docs` → `usb3_fiber-fabrication-drawing.pdf`: a **notes/stackup** page, a
    monochrome page **per copper layer** (`repeat_layers: copper`), and a **drill
    map** (`repeat_layers: drill_pairs`), with hole positions shown
    (`drill_marks: full`).

  `Dwgs.User` / `Cmts.User` ride on the relevant pages, so dimensions, notes, and
  KiCad-placed **stackup / board-characteristics tables** drawn on those layers in
  the board editor render automatically. KiCad has no true Draftsman editor —
  this layer-driven approach is how the documentation gets built up. The per-page
  label comes from `pcb_print`'s `sheet:` (frame variable `${SHEETNAME}`, with
  `%ln`/`%lpn` expanding the layer / drill-pair name on repeated pages).

## What KiBot does NOT change (hard constraints)

- **Provenance injection stays.** `scripts/inject_provenance.py` still writes the
  title-block **`rev` field** and the **`GIT_HASH`** text variable *before* KiBot
  runs, so the rendered schematic/board and the custom worksheet keep their
  Rev + commit stamp. KiBot only *generates*; it never owns the revision.
- **GitFlow / release orchestration stays.** The two-tier `feature → dev → main`
  flow, conditional uprev (release only on design change), and the
  design-commit `GIT_HASH` all remain in the workflows. Actions just call `kibot`
  instead of `kicad-cli`.

## Pipeline shape

- **`dev-checks`** (feature→dev, dev→main PRs): ERC / DRC / BOM-LCSC **gates run
  on `kicad-cli`** so the `ENFORCE=false` bring-up toggle stays in our hands
  (KiBot preflights would hard-gate immediately). **KiBot generates the doc
  outputs** — schematic PDF, assembly drawings, iBOM — from the shared
  `usb3_fiber.kibot.yaml`, so dev and release render them the same way.
- **`main-release`** (merge to main): inject provenance → KiBot generates the
  full turnkey package (gerbers, drill, rotation-corrected CPL, JLCPCB BOM, iBOM,
  3D renders, STEP, schematic PDF, assembly drawings) → publish under the rev.

## The order-turnkey checklist (human side)

Tooling makes the outputs; a real order also needs:
1. **Every assembled part has an `LCSC`** number (the BOM gate enforces this).
2. **Do-not-place parts flagged** (no LCSC / DNP) so they're excluded.
3. Cost tuning: prefer JLCPCB **basic** parts over **extended** where practical.

## Open config decisions

- **`only_smd`** in the position file — `true` = SMT-only CPL (JLCPCB SMT
  service); set `false` if you want THT parts (SFP cage, USB, etc.) in the CPL
  for full turnkey. **Defaulted to `false`** here so nothing assembled is missing
  from placement; revisit per how you order.
- Container/runner: the KiBot Docker image pinned to KiCad 10.
