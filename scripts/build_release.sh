#!/usr/bin/env bash
# Build the full fabrication + design package for a release, with build-time
# provenance injection.
#
# REVISION and GIT_HASH are written into the project text variables just before
# export, so ${REVISION} / ${GIT_HASH} in the title block (and any silkscreen
# text that references them) resolve to the real values. This is done on the
# ephemeral CI checkout only and is never committed back.
#
# Requires env: REVISION, GIT_HASH. Produces everything under out/.
set -euo pipefail

SCH="usb3_fiber.kicad_sch"
PCB="usb3_fiber.kicad_pcb"
PRO="usb3_fiber.kicad_pro"
: "${REVISION:?REVISION required}"
: "${GIT_HASH:?GIT_HASH required}"

OUT="out"
GERB="$OUT/gerbers"
mkdir -p "$GERB"

# --- Inject provenance (build-time only; never committed back) ----------------
# GIT_HASH -> project text variable, rendered as ${GIT_HASH} in the title block.
# REVISION -> the schematic/board title-block `rev` field, rendered by KiCad's
# built-in ${REVISION}. Writing the field (not a project var named REVISION)
# avoids the name clash with that built-in.
python3 - "$PRO" "$SCH" "$PCB" "$REVISION" "$GIT_HASH" <<'PY'
import json, re, sys
pro, sch, pcb, rev, gh = sys.argv[1:6]
with open(pro) as f:
    p = json.load(f)
p.setdefault("text_variables", {})
p["text_variables"]["GIT_HASH"] = gh
with open(pro, "w") as f:
    json.dump(p, f, indent=2)
for path in (sch, pcb):
    with open(path) as f:
        t = f.read()
    t, n = re.subn(r'\(rev "[^"]*"\)', f'(rev "{rev}")', t, count=1)
    if n != 1:
        sys.exit(f"ERROR: expected one (rev ...) in {path}, replaced {n}")
    with open(path, "w") as f:
        f.write(t)
print(f"Injected rev='{rev}' into title blocks; GIT_HASH='{gh}' text var")
PY

# --- Fabrication outputs ------------------------------------------------------
kicad-cli pcb export gerbers "$PCB" -o "$GERB/"
kicad-cli pcb export drill   "$PCB" -o "$GERB/"
kicad-cli pcb export pos     "$PCB" -o "$OUT/usb3_fiber-cpl.csv" \
  --format csv --units mm --side both
kicad-cli pcb export step    "$PCB" -o "$OUT/usb3_fiber.step"

# --- Design outputs -----------------------------------------------------------
kicad-cli sch export pdf "$SCH" -o "$OUT/usb3_fiber-schematic.pdf"
kicad-cli sch export bom "$SCH" -o "$OUT/usb3_fiber-bom.csv" \
  --fields 'Reference,Value,Footprint,Manufacturer,Manufacturer Part Number,LCSC,${QUANTITY}' \
  --labels 'Refs,Value,Footprint,Mfr,MPN,LCSC,Qty' \
  --group-by 'Value,Footprint' --exclude-dnp
kicad-cli pcb export pdf "$PCB" -o "$OUT/usb3_fiber-assembly-top.pdf" \
  --layers "F.Fab,F.Silkscreen,Edge.Cuts"
kicad-cli pcb export pdf "$PCB" -o "$OUT/usb3_fiber-assembly-bottom.pdf" \
  --layers "B.Fab,B.Silkscreen,Edge.Cuts" --mirror

echo "Built package for rev${REVISION} (git ${GIT_HASH}):"
find "$OUT" -type f | sort
