#!/usr/bin/env bash
# Dev-CI check runner for the usb3-fiber KiCad project (KiCad 10 `kicad-cli`).
#
# Runs ERC, DRC (honoring usb3_fiber.kicad_dru), and a BOM completeness check,
# and generates the schematic PDF + assembly drawings as artifacts. All output
# lands in reports/.
#
# Gating is governed by ENFORCE:
#   ENFORCE=false (default) -> checks run and report, but never fail the job
#                              (bring-up mode: captures the baseline as artifacts)
#   ENFORCE=true            -> ERC / DRC / BOM violations fail the job
# Flip to true once the Phase 0/5 baseline is triaged, and add these as required
# status checks in the main ruleset at the same time.
set -uo pipefail

SCH="usb3_fiber.kicad_sch"
PCB="usb3_fiber.kicad_pcb"
ENFORCE="${ENFORCE:-false}"
mkdir -p reports
fail=0

note() {
  echo "$1"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"
}

emit_report() {
  # Echo a report file into the run log (collapsible group) and the job summary
  # (collapsible <details>), so the full ERC/DRC/BOM detail is visible without
  # downloading the artifact.
  local title="$1" file="$2"
  [ -f "$file" ] || return 0
  echo "::group::$title"
  cat "$file"
  echo "::endgroup::"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '\n<details><summary>%s</summary>\n\n```\n' "$title"
      cat "$file"
      printf '\n```\n\n</details>\n'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

note "## Dev-CI checks (ENFORCE=$ENFORCE)"

# --- ERC (gate) ---------------------------------------------------------------
# Full report as artifact; --severity-error means only errors set the exit code.
if kicad-cli sch erc "$SCH" -o reports/erc.rpt --severity-error --exit-code-violations; then
  note "- ✅ ERC: no errors"
else
  note "- ❌ ERC: errors found (see reports/erc.rpt)"; fail=1
fi

# --- DRC (gate; honors usb3_fiber.kicad_dru automatically) --------------------
if kicad-cli pcb drc "$PCB" -o reports/drc.rpt --severity-error --exit-code-violations; then
  note "- ✅ DRC: no errors"
else
  note "- ❌ DRC: errors found (see reports/drc.rpt)"; fail=1
fi

# --- BOM check (gate) ---------------------------------------------------------
# Export fitted parts only (--exclude-dnp; exclude-from-BOM parts are dropped by
# the exporter), then verify completeness.
kicad-cli sch export bom "$SCH" -o reports/bom.csv \
  --fields "Reference,Value,Footprint,Manufacturer Part Number,LCSC" \
  --labels "Reference,Value,Footprint,MPN,LCSC" \
  --exclude-dnp || note "- ⚠️ BOM export failed"
if python3 scripts/bom_check.py reports/bom.csv | tee reports/bom_check.txt; then
  note "- ✅ BOM check: all fitted parts complete"
else
  note "- ❌ BOM check: incomplete fitted rows (see reports/bom_check.txt)"; fail=1
fi

# --- Artifacts (never gate) ---------------------------------------------------
kicad-cli sch export pdf "$SCH" -o reports/schematic.pdf \
  || note "- ⚠️ schematic PDF export failed"
kicad-cli pcb export pdf "$PCB" -o reports/assembly_top.pdf \
  --layers "F.Fab,F.Silkscreen,Edge.Cuts" \
  || note "- ⚠️ top assembly drawing export failed"
kicad-cli pcb export pdf "$PCB" -o reports/assembly_bottom.pdf \
  --layers "B.Fab,B.Silkscreen,Edge.Cuts" --mirror \
  || note "- ⚠️ bottom assembly drawing export failed"

# --- Report detail (echoed to the run log + job summary) ----------------------
emit_report "ERC report (erc.rpt)" reports/erc.rpt
emit_report "DRC report (drc.rpt)" reports/drc.rpt
emit_report "BOM completeness (bom_check.txt)" reports/bom_check.txt

# --- Verdict ------------------------------------------------------------------
if [ "$fail" -ne 0 ]; then
  if [ "$ENFORCE" = "true" ]; then
    note ""
    note "**Result: FAILED** (ENFORCE=true)."
    exit 1
  fi
  note ""
  note "**Result: violations found but not gated** (ENFORCE=false — bring-up mode). Baseline is in the uploaded reports."
fi
exit 0
