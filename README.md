# USB3-over-Fiber Link

USB3 SuperSpeed carried over an optical fiber link, using a **DS100BR111**
redriver into a **10GbE SR SFP+** optical module. A single symmetric PCB serves
both ends of the link — host-side and remote-side roles are selected by jumpers.
The **MCP2221A** provides the SFP+ management (I²C) interface and GPIO for
`TX_DISABLE` / `RX_LOS`. **No microcontroller, no firmware, no EEPROM.**

Built as the remote front-end for an SDR receiver: put the ADC at the antenna
and stream USB3 back to the shack over fiber.

## How it works

```
USB3-A connector        ┌───────────────┐        SFP+ cage
(SuperSpeed pairs) ─────►│  DS100BR111   │◄─────► (optical module) ──► fiber
                        │ (pin-strapped, │
                        │   3.3V)        │
                         └───────────────┘
                                │ SDA/SCL
                          ┌───────────┐
                          │ MCP2221A  │── USB micro-B ── laptop (SFP+ mgmt)
                          └───────────┘
```

Each fiber link needs **two identical boards** — one at the antenna, one at the
shack — with jumpers `JP1`/`JP2` selecting the role. The USB3 path is fully
symmetric: the DS100BR111 is bidirectional and the SFP+ module handles both TX
and RX in one cage.

## Central hypothesis

This prototype exists to test one thing:

> A 10GbE SR SFP+ optical module will transport USB3 SuperSpeed signalling
> intact — LFPS bursts, link training, electrical-idle transitions,
> spread-spectrum clocking, and receiver detection — without modifying the
> module or the USB3 endpoints.

It has been done in the amateur-radio and USB-extension communities, but it is
guaranteed by no specification. See
[`docs/USB3_Fiber_Link_Minimal_Circuit.md`](docs/USB3_Fiber_Link_Minimal_Circuit.md)
for the architecture, channel assignment, and the failure modes this board is
built to probe.

## Repository layout

| Path | Contents |
|---|---|
| `usb3_fiber.kicad_pro/.kicad_sch/.kicad_pcb` | The design. |
| `usb3_fiber.kicad_dru` | Custom high-speed design rules (length/skew/coupling/isolation/via-count). |
| `fp-lib-table` / `sym-lib-table` | Project-local library tables (`${KIPRJMOD}`). |
| `library/` | Symbols (`usb3_fiber.kicad_sym`), footprints (`.pretty/`), 3D models (`3dmodels/`). |
| `datasheets/` | Component datasheets. |
| `docs/` | Design intent, fab spec, turnkey/CI pipeline, release strategy, and the repo migration plan. |

## Requirements

- **KiCad 10.0** (latest stable 10.0.4) — the project baseline.

## Building the manufacturing outputs

From the repo root, with `kicad-cli` (KiCad 10):

```sh
kicad-cli sch erc   usb3_fiber.kicad_sch --output erc.rpt
kicad-cli pcb drc   usb3_fiber.kicad_pcb --output drc.rpt   # honors .kicad_dru
kicad-cli sch export pdf     usb3_fiber.kicad_sch --output schematic.pdf
kicad-cli sch export bom     usb3_fiber.kicad_sch --output bom.csv
kicad-cli pcb export gerbers usb3_fiber.kicad_pcb --output gerbers/
kicad-cli pcb export drill   usb3_fiber.kicad_pcb --output gerbers/
kicad-cli pcb export pos     usb3_fiber.kicad_pcb --output cpl.csv
kicad-cli pcb export step    usb3_fiber.kicad_pcb --output usb3_fiber.step
```

## Fabrication

4-layer FR4, ENIG, controlled impedance (100 Ω differential on the high-speed
pairs), targeting **JLCPCB's standard 4-layer process**. Full stackup,
impedance, and drill/feature constraints are in
[`docs/fab_specification.txt`](docs/fab_specification.txt).

## Downloads

Latest release (see [all releases](../../releases)):

- 📄 **[Schematic (PDF)](https://github.com/ringof/usb3-fiber/releases/latest/download/usb3_fiber-schematic.pdf)**
- 🧩 **[Assembly drawing (PDF)](https://github.com/ringof/usb3-fiber/releases/latest/download/usb3_fiber-assembly.pdf)** — top + bottom component placement
- 📐 **[Fabrication drawing (PDF)](https://github.com/ringof/usb3-fiber/releases/latest/download/usb3_fiber-fabrication-drawing.pdf)** — overview/spec, per-layer, and drill maps
- 🛠 **[Gerbers — JLCPCB-ready (zip)](https://github.com/ringof/usb3-fiber/releases/latest/download/usb3_fiber-gerbers.zip)**
- 📦 **[Full fabrication + design package (zip)](https://github.com/ringof/usb3-fiber/releases/latest/download/usb3_fiber-fabrication.zip)** — Gerbers, drill, BOM, CPL, schematic PDF, assembly + fabrication drawings, STEP

Packages are built and version-stamped by CI. Versioning is semantic
(`vMAJOR.MINOR`): `dev` publishes `v0.x` pre-releases, and promotion to `main`
cuts production releases (`v1.0`, then `v2.0`, …). The version and git hash are
stamped into the title block and bottom silkscreen at build time, and named in
each release's title/tag. The download links above resolve to the newest
**production** release; during the pre-1.0 phase (only `v0.x` pre-releases so
far), grab the assets from the specific pre-release on the
[Releases page](../../releases). See
[`docs/RELEASE_STRATEGY.md`](docs/RELEASE_STRATEGY.md) for how versions and
releases work (a new version is cut only when the design changes).

## Status

Prototype. This is an unproven design intended to validate the central
hypothesis above. The current revision is whatever the latest
[release](../../releases) is — it's stamped into the board, not hardcoded here.

## License

[CERN-OHL-P v2](LICENSE) (CERN Open Hardware Licence Version 2 – Permissive,
SPDX `CERN-OHL-P-2.0`).
