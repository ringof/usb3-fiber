#!/usr/bin/env bash
# KLC (KiCad Library Convention) audit — WARNING-LEVEL, never gates.
#
# Clones kicad-library-utils at runtime and runs its symbol + footprint checkers
# over our local library. Writes a de-ANSI'd report to $OUT/klc.txt and prints a
# one-line summary. Always exits 0 — this is advisory only (per the migration
# plan, KLC is a warning-level report, never a build gate).
#
# Clone-at-runtime for now (no pin); the exact checker commit is recorded in the
# report header. Baking the checker into the CI image (and pinning it) is a
# later hardening step.
#
# Env: OUT  output dir (default: reports). Report lands at $OUT/klc.txt.
set -uo pipefail

OUT="${OUT:-reports}"
mkdir -p "$OUT"
REPORT="$OUT/klc.txt"
LIBSYM="library/usb3_fiber.kicad_sym"
PRETTY="library/usb3_fiber.pretty"
UTILS_URL="https://gitlab.com/kicad/libraries/kicad-library-utils.git"

TOOLS="$(mktemp -d)"
trap 'rm -rf "$TOOLS"' EXIT

if ! git clone --depth 1 "$UTILS_URL" "$TOOLS" >/dev/null 2>&1; then
  echo "WARN: could not clone kicad-library-utils; skipping KLC audit" | tee "$REPORT"
  exit 0
fi

# Strip ANSI colour so the report reads cleanly in the job summary.
strip() { sed -r 's/\x1b\[[0-9;]*m//g'; }

{
  echo "=== KLC audit (warning-level; never gates) ==="
  echo "checker: kicad-library-utils @ $(git -C "$TOOLS" rev-parse --short HEAD)"
  echo
  echo "--- Symbols ($LIBSYM) ---"
  python3 "$TOOLS/klc-check/check_symbol.py" "$LIBSYM" 2>&1 | strip || true
  echo
  echo "--- Footprints ($PRETTY) ---"
  for m in "$PRETTY"/*.kicad_mod; do
    python3 "$TOOLS/klc-check/check_footprint.py" "$m" 2>&1 | strip || true
  done
} > "$REPORT" 2>&1

# Count all violations per section (includes G-rules, not just S*/F*).
sym=$(awk '/^--- Symbols/{s=1;next} /^--- Footprints/{s=0} s&&/Violating/{c++} END{print c+0}' "$REPORT")
fp=$(awk '/^--- Footprints/{f=1} f&&/Violating/{c++} END{print c+0}' "$REPORT")
echo "KLC audit: ${sym:-0} symbol + ${fp:-0} footprint violations (warning-level; see $REPORT)"
exit 0
