# USB3-Fiber KiCad Repository Migration Plan

Porting the repository-infrastructure work proven out on
[`ringof/taprx888`](https://github.com/ringof/taprx888) to this project.

> **Scope note:** This plan covers *repository, CI, release, and provenance
> infrastructure only* — the automation and hygiene layer around the KiCad
> design. It deliberately excludes the AI-authored schematic-review documents
> that lived at the top of the taprx888 repo; those are out of scope here.

---

## 1. What the taprx888 effort delivered (infra layer)

Setting the review write-ups aside, the reusable pattern from taprx888 was:

1. **CI fabrication workflow** — GitHub Actions running `kicad-cli` headless to
   produce ERC/DRC reports plus Gerbers, drill files, BOM, and pick-and-place on
   push and on tag.
2. **Provenance** — a `GIT_HASH` text variable stamped into the schematic title
   block and the bottom silkscreen, so every fabrication output traces back to a
   commit.
3. **ERC/DRC hygiene** — violations (undersized vias, disabled
   courtyard/dielectric checks, copper layers all typed `signal` instead of
   dedicated planes, missing libraries, footprint/BOM attribute mismatches)
   filed as discrete, tracked GitHub issues.
4. **README + releases** — project description, download links, fabrication
   outputs published as tagged releases.
5. **LICENSE** — MIT.

## 2. Current state of this repo vs. that target

| Area | taprx888 target | usb3-fiber now |
|---|---|---|
| README (root) | present, with download links | **missing** |
| LICENSE | MIT | **missing** |
| CI workflow | GH Actions + `kicad-cli` | **none** (`.github/` absent) |
| `GIT_HASH` provenance | title block + silkscreen | `text_variables: {}` — **empty** |
| Copper layer types | dedicated GND/PWR planes | `In1.Cu`/`In2.Cu` typed **`signal`** despite fab spec defining them as GND/PWR planes |
| ERC/DRC baseline | audited, tracked | **never run in CI**; custom `.kicad_dru` exists but no report artifact |
| Releases | fab outputs tagged | **none** |
| Design docs | added during the effort | **already strong** (`docs/fab_specification.txt`, `docs/USB3_Fiber_Link_Minimal_Circuit.md`) |
| KiCad version | 9.0 | 8.0 (`version 20240108`) |

**Takeaway:** this project is *ahead* of where taprx888 started on design
documentation (detailed fab spec + custom `.kicad_dru` already committed), but
has **none** of the repo/CI/release/provenance scaffolding. The work here is
almost entirely additive infrastructure.

## 3. Key decisions (confirm before executing)

- **Deliverable scope** — default: land this plan + draft PR first, execute
  phases after review.
- **KiCad version** — *recommendation: pin CI to KiCad 8 first* to match the
  committed files (`20240108`), get green, then treat the 8→9 file-format
  migration as a separate tracked change so a version bump doesn't muddy the
  first CI run.
- **License** — taprx888 used MIT; a hardware-specific license
  (e.g. CERN-OHL-S) may fit a PCB project better. **Open — owner's call.**

---

## 4. Phased plan

### Phase 0 — Baseline capture (no design changes)
- Run `kicad-cli sch erc` and `kicad-cli pcb drc` (the latter fed the custom
  `usb3_fiber.kicad_dru`) to capture a *current* violation baseline. This is the
  reference point that surfaces the concrete findings for Phase 4 — the same way
  taprx888's via/courtyard/layer issues were discovered.
- Confirm KiCad 8 vs 9 (see §3).

### Phase 1 — Repo hygiene
- Root `README.md`: project description (drawn from
  `docs/USB3_Fiber_Link_Minimal_Circuit.md`), architecture summary, a
  download-links section pointing at releases, and a build-from-source note.
- `LICENSE` — per §3 decision.
- Extend `.gitignore` for `kicad-cli` output dirs (`fab/`, `gerbers/`, etc.).

### Phase 2 — CI fabrication pipeline (`.github/workflows/`)
- Headless `kicad-cli` in a pinned container.
- **On push/PR:** run ERC + DRC (feeding `usb3_fiber.kicad_dru`), upload reports
  as build artifacts, fail the build on violations.
- **On tag:** additionally export Gerbers, drill, BOM, and CPL/pick-and-place,
  zip them, and attach to a GitHub Release.

### Phase 3 — Provenance
- Define a `GIT_HASH` text variable and reference `${GIT_HASH}` in the schematic
  title block and the bottom silkscreen; have CI inject the short SHA before
  export so every fabrication package is traceable to a commit. Directly ports
  the taprx888 "Add GIT_HASH to title block" / "…to bottom silkscreen" work.

### Phase 4 — ERC/DRC audit → tracked issues
- Triage the Phase 0 baseline; file each finding as its own GitHub issue.
- **Already identified statically:** `In1.Cu` and `In2.Cu` are typed `signal` in
  `usb3_fiber.kicad_pcb`, but `docs/fab_specification.txt` §2 defines them as
  dedicated GND / PWR planes. Same class of finding as taprx888 issue #12 ("all
  copper layers defined as `signal` — no dedicated plane layers").
- Remaining findings (via sizing, courtyard/dielectric enforcement,
  footprint/BOM attribute mismatches, library references) fall out of the actual
  DRC/ERC run.

### Phase 5 — First tagged release
- Once CI is green, cut the first release (suggest `revA`, matching the fab
  spec's Rev A revision history) to produce the first traceable fab package.

---

## 5. Suggested execution order

`Phase 0` → `Phase 1` → `Phase 2` → `Phase 3` → `Phase 4` → `Phase 5`.

Phases 1–2 are the lowest-risk, highest-value first PR (no design-file edits).
Phase 3 touches the schematic/PCB files. Phase 4 is triage + issue filing.
Phase 5 is the payoff — a reproducible, provenance-stamped fabrication package.
