# Mechanical — enclosure & PCB end plates

The mechanical package for the USB3-over-Fiber link: the enclosure model and the
end-plate boards. It lives in **this repo, not a separate one** — see below.

> **Status: scaffold.** This README fixes the convention. Drop the enclosure STEP
> and the end-plate KiCad projects in here as they are created.

## Layout

```
mechanical/
  enclosure.step          # the case model — the EE↔ME interface artifact
  endplate-*/             # standalone KiCad projects, one per panel
```

Each end plate is its **own** self-contained KiCad project (its own
`fp-lib-table` / `sym-lib-table`); the root `usb3_fiber` board is untouched. The
end plates are **non-functional PCBs** — Edge.Cuts, connector cutouts, mounting
holes, and silkscreen (labels + logos) — fabricated in place of the blank panels
a stock enclosure ships with.

Because the board is symmetric — one design serves both the antenna-side and
shack-side ends of the link — a single set of end plates fits both units.

## Why in this repo, not a separate one

The end plates are **mechanically coupled** to the main board: their cutouts have
to track the board's connector positions — the USB3-A connector (`J3`/`J4`), the
SFP+ cage opening (`J1`), and the USB micro-B management port. Keeping them here
means a connector move and its matching cutout move land as **one atomic,
reviewed commit**, and they version and travel together. A separate repo would
split that into two places to keep in sync by hand — exactly the drift we're
avoiding.

## Versioning — deliberately separate from the board

A change under `mechanical/` **does not cut a board release.** The `dev-release`
/ `main-release` version lanes are scoped to the **root board's** files only —
they list `usb3_fiber.kicad_{sch,pcb,pro,dru}`, `library/`, and the lib-tables
explicitly rather than globbing `*.kicad_pcb` (which, as a git pathspec, would
match `mechanical/**` at any depth and false-trigger a board release). So an
end-plate silkscreen tweak never bumps the board's `vX.Y`. That scoping is
already in place — see #38.

The end plates are simple; build their fab outputs **on demand** for now, e.g.:

```sh
kicad-cli pcb export gerbers mechanical/endplate-front/endplate-front.kicad_pcb -o mechanical/endplate-front/gerbers/
kicad-cli pcb export drill   mechanical/endplate-front/endplate-front.kicad_pcb -o mechanical/endplate-front/gerbers/
```

A dedicated end-plate CI lane is a possible later addition, not a requirement.

## The board STEP is the interface

Mechanical design works from the board's exported **STEP** — board outline,
thickness, connector positions, component heights, and mounting holes.
`scripts/build_release.sh` already exports `usb3_fiber.step` (bundled inside the
`usb3_fiber-fabrication.zip` release asset). Publishing it as a **standalone
release asset** — so the case design can always pull the current board without
unzipping the fab package — is a small follow-up on the release jobs, and ties
into the 3D-model-completeness work. Until then, grab the STEP from inside the
latest release's fabrication zip, or regenerate it with:

```sh
kicad-cli pcb export step usb3_fiber.kicad_pcb -o usb3_fiber.step
```
