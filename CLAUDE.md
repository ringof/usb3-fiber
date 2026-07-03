# CLAUDE.md — Working Agreement for `usb3-fiber`

Guidance for Claude (and any agent) working in this repository. This is a
**KiCad hardware project**, not a software codebase — the "code" is a schematic,
a PCB layout, and a component library, and the "build" is a set of
manufacturing outputs produced by `kicad-cli`.

## Project

USB3 SuperSpeed over optical fiber: a DS100BR111 redriver + SFP+ optical link
that carries USB3 through a 10GbE SR module. A single symmetric PCB serves both
host and remote roles via jumper selection; the MCP2221A provides the SFP+
management (I²C) interface. No microcontroller, no firmware. See
`docs/USB3_Fiber_Link_Minimal_Circuit.md` for the architecture and the central
hypothesis, and `docs/fab_specification.txt` for the fab/stackup/impedance spec.

## Repository layout

The KiCad project lives at the **repo root** (flattened from the former
`usb3_fiber/` subdirectory).

- `usb3_fiber.kicad_pro / .kicad_sch / .kicad_pcb / .kicad_prl` — the design.
- `usb3_fiber.kicad_dru` — custom design rules (high-speed length/skew/coupling/
  isolation/via-count). Read this before touching DRC.
- `fp-lib-table` / `sym-lib-table` — project-local library tables (use
  `${KIPRJMOD}`; keep paths relative).
- `library/` — `usb3_fiber.kicad_sym`, `usb3_fiber.pretty/` footprints,
  `3dmodels/` STEP files.
- `datasheets/`, `docs/`.

**KiCad 10.0** is the project baseline (latest stable 10.0.4). The committed
files are still in the 8.0 format (`version 20240108`) pending the Phase 0
migration — the first task is to open in KiCad 10 and re-save to the v10 format.
Do not author changes against the old format; migrate first.

## Working agreement

- **Planning first.** For any multi-step change, write/update a plan document and
  get approval before implementing. `docs/REPO_MIGRATION_PLAN.md` is the current
  active plan.
- **Commit & push only with explicit approval.** Never commit or push without
  being asked to.
- **Branch discipline.** Flow is **feature → `dev` → `main`**. Both `dev` and
  `main` are protected. Do work on `dev-*` feature branches, which merge (squash)
  into the permanent **`dev`** integration branch; `dev` merges (squash) into
  **`main`** only when cutting a release. **Authorization to do work is NOT
  authorization to create a branch** — do not create a branch unless the user
  names it. Unrelated fixes go on the current branch as separate commits unless
  directed otherwise. (See `docs/RELEASE_STRATEGY.md`.)
- **Evidence before claims.** Do not assert a design problem or file an issue on
  untested theory. Back every finding with concrete evidence: a `grep`/file read,
  a datasheet reference, or `kicad-cli` ERC/DRC/BOM output. (Example: the
  `In1.Cu`/`In2.Cu` "signal vs plane" finding was confirmed by reading the PCB
  layer stanza, not assumed.) Existing observations override untested theory.
- **Change documentation.** Before committing a design-touching change, give the
  user a copy-pastable block with: (1) what changed and why, (2) how to
  regenerate outputs (`kicad-cli` commands), (3) how to validate (which
  ERC/DRC/BOM/3D checks must pass), (4) regression check (re-run the dev-CI check
  set).
- **No `gh` CLI here.** GitHub operations go through the GitHub MCP tools, not
  `gh`. When batch-filing findings as issues, use those tools (or offer a
  script), not `gh issue create`.

## Design-rule baseline

- Manufacturing capability reference: **JLCPCB, standard 4-layer process.** Set
  missing DRC rules and validate existing ones against it; keep board settings
  (`.kicad_pro` `board_design_settings`) and `usb3_fiber.kicad_dru` in sync with
  it.
- Preserve the existing high-speed rules in `usb3_fiber.kicad_dru`
  (USB3_SS/SFP_SS/USB2 length, skew, coupling, pair-to-pair isolation, via
  count). Understand a rule before changing it.

## CI, provenance & releases (planned — see migration plan)

Not yet implemented; being built per `docs/REPO_MIGRATION_PLAN.md`. Target model:

- **`dev-*` CI** (gate unless noted): ERC, DRC, BOM check, 3D-model completeness
  (warning on dev), KLC library compliance (warning). Also generates schematic
  PDF + assembly drawings as artifacts.
- **`main` CI**: all checks (3D-completeness becomes a **gate**), produces the
  full fab/design package (Gerbers, drill, BOM, CPL, schematic PDF, assembly
  drawings, STEP), and publishes a GitHub Release.
- **Revision & provenance**: `${REVISION}` (alpha: Rev A → B → C) and
  `${GIT_HASH}` are **injected at build time** into the title block and bottom
  silkscreen — never committed back to the design files. **GitHub Releases are
  the source of truth** for the current revision.

| Check | dev-* | main |
|---|---|---|
| ERC | gate | gate |
| DRC | gate | gate |
| BOM check | gate | gate |
| 3D-model completeness (fitted parts) | warning | gate |
| KLC library compliance | warning | warning |

## Useful `kicad-cli` commands (KiCad 10)

```sh
# from the project directory
kicad-cli sch erc   usb3_fiber.kicad_sch --output erc.rpt
kicad-cli pcb drc   usb3_fiber.kicad_pcb --output drc.rpt   # honors .kicad_dru
kicad-cli sch export pdf usb3_fiber.kicad_sch --output schematic.pdf
kicad-cli sch export bom usb3_fiber.kicad_sch --output bom.csv
kicad-cli pcb export gerbers usb3_fiber.kicad_pcb --output gerbers/
kicad-cli pcb export drill   usb3_fiber.kicad_pcb --output gerbers/
kicad-cli pcb export pos     usb3_fiber.kicad_pcb --output cpl.csv   # pick-and-place
kicad-cli pcb export step    usb3_fiber.kicad_pcb --output usb3_fiber.step
```

## Reference docs

- `docs/USB3_Fiber_Link_Minimal_Circuit.md` — architecture + design intent.
- `docs/fab_specification.txt` — stackup, impedance, fab constraints (Rev A).
- `docs/REPO_MIGRATION_PLAN.md` — the active infrastructure plan.
