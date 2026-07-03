#!/usr/bin/env bash
# Build the full fabrication + design package for a release, via KiBot, with
# build-time provenance injection.
#
# Order matters: provenance (title-block rev + GIT_HASH) is injected into the
# ephemeral checkout FIRST, then KiBot generates from the already-stamped
# design. KiBot never owns the revision — it only generates. Nothing is
# committed back. See docs/TURNKEY.md.
#
# Preflights (ERC/DRC) are skipped here: gating already happened on the PR into
# main (dev-checks). This job just produces the package.
#
# Requires env: REVISION, GIT_HASH. Produces everything under out/.
set -euo pipefail

CFG="usb3_fiber.kibot.yaml"
SCH="usb3_fiber.kicad_sch"
PCB="usb3_fiber.kicad_pcb"
: "${REVISION:?REVISION required}"
: "${GIT_HASH:?GIT_HASH required}"

OUT="out"
mkdir -p "$OUT"

# --- Inject provenance (build-time only; never committed back) ----------------
python3 scripts/inject_provenance.py --revision "$REVISION" --git-hash "$GIT_HASH"

# --- Generate the package with KiBot ------------------------------------------
# Essential outputs (fab + docs) — a failure here fails the release.
xvfb-run -a kibot -c "$CFG" -e "$SCH" -b "$PCB" -d "$OUT" --skip-pre all \
  schematic_pdf assembly_top assembly_bottom ibom step \
  JLCPCB_gerbers JLCPCB_drill JLCPCB_position JLCPCB_bom

# 3D renders are best-effort — raytrace/3D can be flaky in headless CI and must
# not sink an otherwise-complete release.
xvfb-run -a kibot -c "$CFG" -e "$SCH" -b "$PCB" -d "$OUT" --skip-pre all \
  render_top render_bottom \
  || echo "WARN: 3D render step failed; release continues without renders."

echo "Built package for rev${REVISION} (git ${GIT_HASH}):"
find "$OUT" -type f | sort
