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

# Install the PCB color theme where kicad-cli looks for it (the versioned colors
# dir), and reference it by name via --theme. It renders the worksheet/frame in
# the schematic's maroon (#800000) with black layer artwork, so the PCB
# drawings match the schematic frame instead of being stark B&W.
THEME="usb3_fiber"
KV="$(kicad-cli version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
COLORS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kicad/${KV:-10.0}/colors"
mkdir -p "$COLORS_DIR"
cp usb3_fiber-colors.json "$COLORS_DIR/$THEME.json"

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
# --theme usb3_fiber: maroon worksheet (like the schematic) + black layer
# artwork, instead of KiCad's washed-out pastel user-layer colors.
TMP="$(mktemp -d)"
kicad-cli pcb export pdf "$PCB" -o "$TMP/top.pdf" --mode-single \
  --layers "F.Fab,F.Silkscreen,Edge.Cuts" --include-border-title --theme "$THEME" \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Top"
kicad-cli pcb export pdf "$PCB" -o "$TMP/bottom.pdf" --mode-single \
  --layers "B.Fab,B.Silkscreen,Edge.Cuts" --mirror --include-border-title --theme "$THEME" \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Bottom"
merge_pdf "$DOCS/usb3_fiber-assembly.pdf" "$TMP/top.pdf" "$TMP/bottom.pdf"
rm -rf "$TMP"

# --- Fabrication drawing (multipage) ------------------------------------------
# Page order: (1) fab notes, (2) one page per PCB layer, (3) drill map(s).
# Each layer page (--mode-single, layer + Edge.Cuts) carries the outline and its
# own LAYER label; pages are merged (sidesteps --mode-multipage's folder bug).
FABTMP="$(mktemp -d)"
fab_pages=()

# (1) Fab notes / dimensions -- FIRST page.
notes="$FABTMP/00_notes.pdf"
kicad-cli pcb export pdf "$PCB" -o "$notes" --mode-single \
  --layers "Edge.Cuts,Dwgs.User,Cmts.User,User.1" --include-border-title --theme "$THEME" \
  --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=Fab Notes"
fab_pages+=("$notes")

# (2) One page per PCB layer.
FAB_LAYERS="F.Cu In1.Cu In2.Cu B.Cu F.Silkscreen B.Silkscreen F.Mask B.Mask"
n=0
for L in $FAB_LAYERS; do
  n=$((n + 1))
  page="$FABTMP/$(printf '%02d' "$n")_${L//./_}.pdf"
  kicad-cli pcb export pdf "$PCB" -o "$page" --mode-single \
    --layers "$L,Edge.Cuts" --include-border-title --theme "$THEME" \
    --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=$L"
  fab_pages+=("$page")
done

# (3) Drill map(s), framed in OUR drawing sheet. kicad-cli's drill export can't
#     take a drawing sheet, so we nest each native (vector) map inside a framed,
#     empty template page (aspect-fit above the title block) with PyMuPDF -- the
#     result stays fully vector. The pinned CI image (ringof/kicad-ci) guarantees
#     PyMuPDF on `python3`, so a missing fitz is a hard error: we never silently
#     ship an unframed drill map.
DRLTMP="$(mktemp -d)"
kicad-cli pcb export drill "$PCB" -o "$DRLTMP/" \
  --format excellon --excellon-separate-th --generate-map --map-format pdf \
  || echo "WARN: drill map generation failed"

if ! python3 -c "import fitz" 2>/dev/null; then
  echo "ERROR: PyMuPDF (fitz) not importable by python3; cannot frame drill maps." >&2
  echo "       The CI image must provide PyMuPDF -- see ringof/kicad-ci." >&2
  exit 1
fi

di=0
for m in $(ls "$DRLTMP"/*.pdf 2>/dev/null | sort); do
  di=$((di + 1))
  # Label each page by plating class from the map filename (test NPTH before
  # PTH -- 'NPTH' contains 'PTH' as a substring).
  case "$m" in
    *NPTH*) drill_label="Drill Map (NPTH)" ;;
    *PTH*)  drill_label="Drill Map (PTH)" ;;
    *)      drill_label="Drill Map" ;;
  esac
  # Framed, empty template for this page: border + title block only, carrying the
  # per-page LAYER label (Eco1.User has no artwork).
  drill_tmpl="$FABTMP/drill_tmpl_$(printf '%02d' "$di").pdf"
  kicad-cli pcb export pdf "$PCB" -o "$drill_tmpl" --mode-single \
    --layers "Eco1.User" --include-border-title --theme "$THEME" \
    --drawing-sheet "$FAB_WKS" "${VARS[@]}" --define-var "LAYER=$drill_label"
  # Nest the vector map into the framed template. set -e aborts the build on any
  # composite failure instead of falling back to a bare, unframed map.
  framed="$FABTMP/drill_$(printf '%02d' "$di").pdf"
  python3 - "$drill_tmpl" "$m" "$framed" <<'PY'
import sys, fitz
tmpl, mp, out = sys.argv[1:4]
base = fitz.open(tmpl); page = base[0]
src = fitz.open(mp); sp = src[0]; sr = sp.rect
mm = 72 / 25.4
# Horizontal drawing area, inside the frame margins.
cx0, cx1 = 8 * mm, page.rect.width - 8 * mm
cw = cx1 - cx0
# Vertical budget: aspect-fit the map while keeping clear of the title-block strip.
top, title = 8 * mm, 40 * mm
ch = page.rect.height - top - title
s = min(cw / sr.width, ch / sr.height)          # aspect-fit (unchanged scale)
w, h = sr.width * s, sr.height * s
x0 = cx0 + (cw - w) / 2
# KiCad's drill-map page has a large blank lower margin, so centering the page
# rect leaves the artwork riding high in the sheet. Measure the real content
# (drawings + text) and center THAT on the sheet instead. The map's blank margins
# overlap the frame/title block harmlessly -- KiCad PDFs have no opaque background.
content = None
for d in sp.get_drawings():
    content = d["rect"] if content is None else content | d["rect"]
for b in sp.get_text("dict")["blocks"]:
    r = fitz.Rect(b["bbox"]); content = r if content is None else content | r
if content is None or content.is_empty:
    content = sr
y0 = page.rect.height / 2 - (content.y0 + content.height / 2) * s
y0 = max(y0, top - content.y0 * s)              # don't ride above the top margin
overflow = (y0 + content.y1 * s) - (page.rect.height - title)
if overflow > 0:                                # don't spill into the title block
    y0 -= overflow
page.show_pdf_page(fitz.Rect(x0, y0, x0 + w, y0 + h), src, 0)
base.save(out)
PY
  echo "  framed $drill_label ($di)"
  fab_pages+=("$framed")
done

merge_pdf "$DOCS/usb3_fiber-fabrication-drawing.pdf" "${fab_pages[@]}"
rm -rf "$FABTMP" "$DRLTMP"

echo "Generated framed documentation in $DOCS/:"
ls -1 "$DOCS"/usb3_fiber-*.pdf
