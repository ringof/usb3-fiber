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
# Note: pcb export pdf needs --include-border-title to plot the frame at all
# (unlike sch export pdf, which includes it by default).
#
# Env:
#   OUT       output dir (default: reports). PDFs land in $OUT/docs/.
#   GIT_HASH  commit stamp for the frame (default: local)
# Rev/date/title come from the board & schematic title blocks (inject provenance
# before calling this to stamp the release rev).
set -euo pipefail

SCH="usb3_fiber.kicad_sch"
PCB="usb3_fiber.kicad_pcb"
PRO="usb3_fiber.kicad_pro"
SCH_WKS="usb3_fiber-sch.kicad_wks"
FAB_WKS="usb3_fiber-fab.kicad_wks"
OUT="${OUT:-reports}"
DOCS="$OUT/docs"
GIT_HASH="${GIT_HASH:-local}"
mkdir -p "$DOCS"

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

# Merge PDFs into one file (poppler's pdfunite, else ghostscript).
merge_pdf() {
  local out="$1"; shift
  if command -v pdfunite >/dev/null 2>&1; then
    pdfunite "$@" "$out"
  elif command -v gs >/dev/null 2>&1; then
    gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$out" "$@"
  else
    echo "ERROR: no PDF merge tool (pdfunite/gs) available" >&2
    return 1
  fi
}

# --- Schematic ----------------------------------------------------------------
kicad-cli sch export pdf "$SCH" -o "$DOCS/usb3_fiber-schematic.pdf" \
  --drawing-sheet "$SCH_WKS" "${VARS[@]}"

# --- Assembly: top + bottom in ONE pdf ----------------------------------------
# Component placement only (Fab + Silk + Edge). No dimensions / fab notes here.
# --black-and-white: user layers (Dwgs/Cmts/User.1) and the worksheet otherwise
# plot in faint pastel colors that wash out; B&W renders everything solid and
# legible, which is what a fab/assembly drawing wants anyway.
TMP="$(mktemp -d)"
kicad-cli pcb export pdf "$PCB" -o "$TMP/top.pdf" --mode-single \
  --layers "F.Fab,F.Silkscreen,Edge.Cuts" --include-border-title --black-and-white \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Top"
kicad-cli pcb export pdf "$PCB" -o "$TMP/bottom.pdf" --mode-single \
  --layers "B.Fab,B.Silkscreen,Edge.Cuts" --mirror --include-border-title --black-and-white \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Bottom"
merge_pdf "$DOCS/usb3_fiber-assembly.pdf" "$TMP/top.pdf" "$TMP/bottom.pdf"
rm -rf "$TMP"

# --- Fabrication drawing (multipage: one page per PCB layer) ------------------
# A real fab drawing shows each fabrication layer on its own page, with the
# Edge.Cuts outline for reference, followed by a fab-notes page (dimensions,
# fab-spec text, Board Characteristics table). Each page is rendered on its own
# (--mode-single, one layer + edge) and the pages are merged, so every page
# carries the outline and its own LAYER label -- and we sidestep the
# --mode-multipage "outputs a folder" bug.
FAB_LAYERS="F.Cu In1.Cu In2.Cu B.Cu F.Silkscreen B.Silkscreen F.Mask B.Mask"
FABTMP="$(mktemp -d)"
fab_pages=()
n=0
for L in $FAB_LAYERS; do
  n=$((n + 1))
  page="$FABTMP/$(printf '%02d' "$n")_${L//./_}.pdf"
  kicad-cli pcb export pdf "$PCB" -o "$page" --mode-single \
    --layers "$L,Edge.Cuts" --include-border-title --black-and-white \
    --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=$L"
  fab_pages+=("$page")
done
# Fab notes / dimensions page.
notes="$FABTMP/99_notes.pdf"
kicad-cli pcb export pdf "$PCB" -o "$notes" --mode-single \
  --layers "Edge.Cuts,Dwgs.User,Cmts.User,User.1" --include-border-title --black-and-white \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Fab Notes"
fab_pages+=("$notes")
merge_pdf "$DOCS/usb3_fiber-fabrication-drawing.pdf" "${fab_pages[@]}"
rm -rf "$FABTMP"

echo "Generated framed documentation in $DOCS/:"
ls -1 "$DOCS"/usb3_fiber-*.pdf
