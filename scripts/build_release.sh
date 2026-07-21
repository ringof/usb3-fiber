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

# --- Version marker stamped into the package ----------------------------------
# The committed VERSION.txt is a de-numbered "development snapshot" so a zip of
# the source tree is never anonymous yet never goes stale. The released package
# carries the exact version + commit on its Version: line. Build-time only —
# the committed file is untouched.
sed "s#^Version:.*#Version:  v${REVISION}   (commit ${GIT_HASH})#" \
  VERSION.txt > "$OUT/VERSION.txt"

# --- Framed documentation PDFs (schematic, assembly, fabrication) -------------
# Rendered by kicad-cli (gen_docs.sh), NOT KiBot: kicad-cli plots the title
# block natively and fills every variable, whereas KiBot's frame renderer left
# them blank in this container. Provenance was injected above, so the frames
# pick up the release rev; GIT_HASH is threaded through. Writes to $OUT/docs/.
# A failure fails the release — the framed docs are part of the package.
OUT="$OUT" GIT_HASH="$GIT_HASH" bash scripts/gen_docs.sh

# --- Turnkey data + iBOM + STEP via KiBot -------------------------------------
# KiBot starts its own virtual display (xvfbwrapper) for the outputs that need
# one (render_3d), so we call it directly — no xvfb-run wrapper (the image ships
# no xauth).
#
# Essential outputs — a failure here fails the release.
kibot -c "$CFG" -e "$SCH" -b "$PCB" -d "$OUT" --skip-pre all \
  ibom step \
  JLCPCB_gerbers JLCPCB_drill JLCPCB_position JLCPCB_bom

# 3D renders are best-effort — raytrace/3D can be flaky in headless CI and must
# not sink an otherwise-complete release.
kibot -c "$CFG" -e "$SCH" -b "$PCB" -d "$OUT" --skip-pre all \
  render_top render_bottom \
  || echo "WARN: 3D render step failed; release continues without renders."

echo "Built package for v${REVISION} (git ${GIT_HASH}):"
find "$OUT" -type f | sort
