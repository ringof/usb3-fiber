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

# --- Shared compositor (assembly + fab board pages) ---------------------------
# PyMuPDF is required for compositing; the pinned CI image (ringof/kicad-ci)
# guarantees it, so a missing fitz is a hard error rather than a silent fallback.
if ! python3 -c "import fitz" 2>/dev/null; then
  echo "ERROR: PyMuPDF (fitz) not importable by python3; cannot frame doc pages." >&2
  echo "       The CI image must provide PyMuPDF -- see ringof/kicad-ci." >&2
  exit 1
fi
HELPERS="$(mktemp -d)"

# compose.py <template.pdf> <bare.pdf> <out.pdf> <outline.pdf|->
#   Nest a bare (frameless) vector PDF into the framed template, aspect-fit into
#   the drawing area and centered above the title block. Stays fully vector.
#   With an outline.pdf (Edge.Cuts alone), the board is NORMALIZED: it fills a
#   fixed fraction of the sheet regardless of sprawling reference text, so the
#   board is the same size on every page. EXCEPTIONS that shrink to fit: real
#   geometry (a component/drawing extending past the outline) is always included,
#   and a final safety keeps any content (incl. text) from spilling off-sheet.
#   With "-" (drill maps), it content-fits the map's own board + size legend.
#   bbox() uses manual min/max so zero-area rects (thin lines) are never dropped
#   -- fitz's Rect union silently discards them, which sent leader lines off-sheet.
COMPOSE="$HELPERS/compose.py"
cat > "$COMPOSE" <<'PY'
import sys, fitz
tmpl, bare, out, outline = sys.argv[1:5]
base = fitz.open(tmpl); page = base[0]
src = fitz.open(bare); sp = src[0]; sr = sp.rect
mm = 72 / 25.4
top, title, side = 8 * mm, 40 * mm, 8 * mm
cw = page.rect.width - 2 * side
ch = page.rect.height - top - title

def bbox(rects):
    # thin-line-safe union: manual min/max so zero-area rects (lines) count too.
    rects = [r for r in rects if r.width >= 0 and r.height >= 0]
    if not rects:
        return None
    return fitz.Rect(min(r.x0 for r in rects), min(r.y0 for r in rects),
                     max(r.x1 for r in rects), max(r.y1 for r in rects))

draws = [d["rect"] for d in sp.get_drawings()]
texts = [fitz.Rect(b["bbox"]) for b in sp.get_text("dict")["blocks"]]
draw_bb = bbox(draws) or fitz.Rect(sr)          # all geometry (components, lines)
all_bb = bbox(draws + texts) or draw_bb          # + annotation text

if outline != "-":
    ob = fitz.open(outline)
    ref = bbox([d["rect"] for d in ob[0].get_drawings()]) or draw_bb
    s = 0.90 * min(cw / ref.width, ch / ref.height)          # normalize to outline
    s = min(s, 0.99 * min(cw / draw_bb.width, ch / draw_bb.height))  # incl. overhang
    s = min(s, 0.99 * min(cw / all_bb.width, ch / all_bb.height))    # never off-sheet
    ref_c = ref
else:
    s = 0.95 * min(cw / all_bb.width, ch / all_bb.height)     # drill: content-fit
    ref_c = all_bb

ox, oy = sr.x0, sr.y0
w, h = sr.width * s, sr.height * s
ax, ay = side + cw / 2, top + ch / 2
x0 = ax - (ref_c.x0 + ref_c.width / 2 - ox) * s
y0 = ay - (ref_c.y0 + ref_c.height / 2 - oy) * s
# Clamp the full content (incl. text) inside the margins and clear of the block.
x0 = max(x0, side - (all_bb.x0 - ox) * s)
oxo = (x0 + (all_bb.x1 - ox) * s) - (page.rect.width - side)
if oxo > 0: x0 -= oxo
y0 = max(y0, top - (all_bb.y0 - oy) * s)
oyo = (y0 + (all_bb.y1 - oy) * s) - (page.rect.height - title)
if oyo > 0: y0 -= oyo
page.show_pdf_page(fitz.Rect(x0, y0, x0 + w, y0 + h), src, 0)
base.save(out)
PY

# Framed, empty template (border + title block; Eco1.User carries no artwork),
# stamped with the per-page LAYER label and Page N of M.
make_template() {  # make_template <label> <pagenum> <pagecount> <out.pdf>
  kicad-cli pcb export pdf "$PCB" -o "$4" --mode-single \
    --layers "Eco1.User" --include-border-title --theme "$THEME" \
    --drawing-sheet "$FAB_WKS" "${VARS[@]}" \
    --define-var "LAYER=$1" --define-var "PAGENUM=$2" --define-var "PAGECOUNT=$3"
}

# Board-outline references (Edge.Cuts alone) that compose.py normalizes the board
# to: normal orientation for top/copper/silk/mask, mirrored for the bottom view.
# Same page setup as the bare plots, so the outline lands at matching coordinates.
OUTLINE_N="$HELPERS/outline_n.pdf"
OUTLINE_M="$HELPERS/outline_m.pdf"
kicad-cli pcb export pdf "$PCB" -o "$OUTLINE_N" --mode-single \
  --layers "Edge.Cuts" --theme "$THEME" "${VARS[@]}"
kicad-cli pcb export pdf "$PCB" -o "$OUTLINE_M" --mode-single \
  --layers "Edge.Cuts" --mirror --theme "$THEME" "${VARS[@]}"

# --- Schematic ----------------------------------------------------------------
kicad-cli sch export pdf "$SCH" -o "$DOCS/usb3_fiber-schematic.pdf" \
  --drawing-sheet "$SCH_WKS" "${VARS[@]}"

# --- Assembly: top + bottom in ONE pdf, scaled to fill the sheet --------------
# Component placement only (Fab + Silk + Edge); no dimensions / fab notes. Bare
# (frameless) plots composited into the framed sheet like the layer pages, so the
# board fills the sheet instead of sitting tiny at 1:1. Paged 1..2 of 2.
ATMP="$(mktemp -d)"
kicad-cli pcb export pdf "$PCB" -o "$ATMP/top_bare.pdf" --mode-single \
  --layers "F.Fab,F.Silkscreen,Edge.Cuts" --theme "$THEME" "${VARS[@]}"
kicad-cli pcb export pdf "$PCB" -o "$ATMP/bot_bare.pdf" --mode-single \
  --layers "B.Fab,B.Silkscreen,Edge.Cuts" --mirror --theme "$THEME" "${VARS[@]}"
make_template "Assembly - Top"    1 2 "$ATMP/top_tmpl.pdf"
make_template "Assembly - Bottom" 2 2 "$ATMP/bot_tmpl.pdf"
python3 "$COMPOSE" "$ATMP/top_tmpl.pdf" "$ATMP/top_bare.pdf" "$ATMP/top.pdf" "$OUTLINE_N"
python3 "$COMPOSE" "$ATMP/bot_tmpl.pdf" "$ATMP/bot_bare.pdf" "$ATMP/bot.pdf" "$OUTLINE_M"
merge_pdf "$DOCS/usb3_fiber-assembly.pdf" "$ATMP/top.pdf" "$ATMP/bot.pdf"
rm -rf "$ATMP"

# --- Fabrication drawing (multipage) ------------------------------------------
# Page order: (1) cover/overview, (2) one page per PCB layer, (3) drill map(s).
# All board pages are composited into the framed sheet (fill the sheet at a
# consistent size). The cover is a full-page 1:1 text+preview layout, rendered
# directly. Page N of M is injected via PAGENUM/PAGECOUNT.
FABTMP="$(mktemp -d)"
fab_pages=()

# Generate the drill map(s) first so we can count them for the total page count.
DRLTMP="$(mktemp -d)"
kicad-cli pcb export drill "$PCB" -o "$DRLTMP/" \
  --format excellon --excellon-separate-th --generate-map --map-format pdf \
  || echo "WARN: drill map generation failed"
drill_maps=()
for m in $(ls "$DRLTMP"/*.pdf 2>/dev/null | sort); do drill_maps+=("$m"); done

FAB_LAYERS="F.Cu In1.Cu In2.Cu B.Cu F.Silkscreen B.Silkscreen F.Mask B.Mask"
read -ra _FL <<< "$FAB_LAYERS"
# Total pages = cover + one per layer + one per drill map.
PC=$((1 + ${#_FL[@]} + ${#drill_maps[@]}))
pg=0

# (1) Cover / overview -- FIRST page. Requirements + board preview: the spec text
#     (Cmts.User), board-characteristics table (User.1), and dimensions
#     (Dwgs.User) sit alongside a preview of the populated board (F.Silkscreen +
#     F.Fab + Edge.Cuts) -- "here's the spec, and here's what you're building".
#     Full-page 1:1 layout, so it is rendered directly rather than rescaled.
pg=$((pg + 1))
notes="$FABTMP/00_notes.pdf"
kicad-cli pcb export pdf "$PCB" -o "$notes" --mode-single \
  --layers "F.Silkscreen,F.Fab,Edge.Cuts,Dwgs.User,Cmts.User,User.1" \
  --include-border-title --theme "$THEME" --drawing-sheet "$FAB_WKS" "${VARS[@]}" \
  --define-var "LAYER=Overview" --define-var "PAGENUM=$pg" --define-var "PAGECOUNT=$PC"
fab_pages+=("$notes")

# (2) One page per PCB layer, board scaled to fill the sheet. Edge.Cuts is always
#     included, so the board outline sets the same extent across every layer.
n=0
for L in $FAB_LAYERS; do
  n=$((n + 1)); pg=$((pg + 1))
  bare="$FABTMP/${n}_bare_${L//./_}.pdf"
  tmpl="$FABTMP/${n}_tmpl_${L//./_}.pdf"
  page="$FABTMP/$(printf '%02d' "$n")_${L//./_}.pdf"
  kicad-cli pcb export pdf "$PCB" -o "$bare" --mode-single \
    --layers "$L,Edge.Cuts" --theme "$THEME" "${VARS[@]}"
  make_template "$L" "$pg" "$PC" "$tmpl"
  python3 "$COMPOSE" "$tmpl" "$bare" "$page" "$OUTLINE_N"
  fab_pages+=("$page")
done

# (3) Drill map(s), composited like the layer pages so the board matches scale.
di=0
for m in "${drill_maps[@]}"; do
  di=$((di + 1)); pg=$((pg + 1))
  # Label each page by plating class from the map filename (test NPTH before
  # PTH -- 'NPTH' contains 'PTH' as a substring).
  case "$m" in
    *NPTH*) drill_label="Drill Map (NPTH)" ;;
    *PTH*)  drill_label="Drill Map (PTH)" ;;
    *)      drill_label="Drill Map" ;;
  esac
  tmpl="$FABTMP/drill_tmpl_$(printf '%02d' "$di").pdf"
  framed="$FABTMP/drill_$(printf '%02d' "$di").pdf"
  make_template "$drill_label" "$pg" "$PC" "$tmpl"
  python3 "$COMPOSE" "$tmpl" "$m" "$framed" -
  echo "  framed $drill_label ($di)"
  fab_pages+=("$framed")
done

merge_pdf "$DOCS/usb3_fiber-fabrication-drawing.pdf" "${fab_pages[@]}"
rm -rf "$FABTMP" "$DRLTMP" "$HELPERS"

echo "Generated framed documentation in $DOCS/:"
ls -1 "$DOCS"/usb3_fiber-*.pdf
