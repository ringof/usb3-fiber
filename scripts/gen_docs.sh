#!/usr/bin/env bash
# Generate the framed documentation PDFs with kicad-cli (native KiCad rendering).
#
# Why kicad-cli and not KiBot for these: KiBot's pcb_print reimplements the
# frame and does not fill the title-block variables in our container, so
# ${TITLE}/Rev/Date/Designer/... came out blank. kicad-cli plots the frame
# natively, so every variable renders.
#
# Robustness: we pass the worksheet and the provenance variables EXPLICITLY via
# --drawing-sheet and --define-var, so the frames never depend on the project's
# page_layout_descr_file or text_variables — both of which KiCad likes to blank
# or rewrite locally. CI applies them; the local project state can't break us.
#
# Env:
#   OUT       output dir (default: reports)
#   GIT_HASH  commit stamp for the frame (default: local)
# The title-block rev/date/title come from the board & schematic title blocks
# (inject provenance before calling this to stamp the release rev).
set -euo pipefail

SCH="usb3_fiber.kicad_sch"
PCB="usb3_fiber.kicad_pcb"
PRO="usb3_fiber.kicad_pro"
SCH_WKS="usb3_fiber-sch.kicad_wks"
FAB_WKS="usb3_fiber-fab.kicad_wks"
OUT="${OUT:-reports}"
GIT_HASH="${GIT_HASH:-local}"
mkdir -p "$OUT"

# Canonical provenance metadata. Read from the project text_variables when
# present, but fall back to constants so a KiCad-blanked project still renders a
# complete frame in CI.
read_var() {
  python3 - "$PRO" "$1" "$2" <<'PY'
import json, sys
pro, key, default = sys.argv[1:4]
try:
    v = json.load(open(pro)).get("text_variables", {}).get(key, "")
except Exception:
    v = ""
print(v or default)
PY
}
DESIGNER="$(read_var DESIGNER 'David Goncalves')"
LICENSE="$(read_var LICENSE 'CERN-OHL-P-2.0')"
REPO="$(read_var REPO 'github.com/ringof/usb3-fiber')"

# Shared frame variables (rev/date/title come natively from the title blocks).
VARS=(--define-var "DESIGNER=$DESIGNER"
      --define-var "LICENSE=$LICENSE"
      --define-var "REPO=$REPO"
      --define-var "GIT_HASH=$GIT_HASH")

# --- Schematic ----------------------------------------------------------------
kicad-cli sch export pdf "$SCH" -o "$OUT/usb3_fiber-schematic.pdf" \
  --drawing-sheet "$SCH_WKS" "${VARS[@]}"

# --- Assembly (top / bottom) --------------------------------------------------
kicad-cli pcb export pdf "$PCB" -o "$OUT/usb3_fiber-assembly-top.pdf" \
  --layers "F.Fab,F.Silkscreen,Edge.Cuts,Dwgs.User,Cmts.User" \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Top"

kicad-cli pcb export pdf "$PCB" -o "$OUT/usb3_fiber-assembly-bottom.pdf" \
  --layers "B.Fab,B.Silkscreen,Edge.Cuts,Dwgs.User,Cmts.User" --mirror \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Bottom"

# --- Fabrication / dimensions -------------------------------------------------
# Edge + dimensions/notes (Dwgs.User/Cmts.User) + the Fab Notes layer (User.1,
# which carries the Board Characteristics table).
kicad-cli pcb export pdf "$PCB" -o "$OUT/usb3_fiber-fabrication-drawing.pdf" \
  --layers "Edge.Cuts,Dwgs.User,Cmts.User,User.1" \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Fabrication"

echo "Generated framed documentation in $OUT/:"
ls -1 "$OUT"/usb3_fiber-*.pdf
