#!/usr/bin/env python3
"""Inject build-time provenance into the KiCad design, in place.

Writes provenance onto the ephemeral CI checkout, just before KiBot exports:

  - REVISION and GIT_HASH -> the ``REVISION`` / ``GIT_HASH`` **project text
    variables** (usb3_fiber.kicad_pro). The design renders ``${REVISION}`` /
    ``${GIT_HASH}`` from these — in the custom worksheet title block *and* in the
    bottom-silkscreen text on the board ("Rev: ${REVISION}  Commit: ${GIT_HASH}").
    They are committed as placeholders (DEV / local), so BOTH must be set here or
    the silk/worksheet render the placeholder. (Previously only GIT_HASH was set,
    so released boards showed "Rev: DEV" while the commit stamped correctly.)
  - REVISION is ALSO written to the schematic/board title-block ``rev`` field,
    belt-and-suspenders for the title block's own revision entry.

This is intentionally the *only* place provenance is stamped, so KiBot never
owns the revision — it just generates from an already-stamped design. Never
committed back; runs on the throwaway checkout only.

Usage:
    inject_provenance.py --revision REV --git-hash HASH \\
        [--pro FILE] [--sch FILE] [--pcb FILE]

Env fallbacks: REVISION, GIT_HASH (CLI flags win).
"""
import argparse
import json
import os
import re
import sys


def inject_project_vars(pro_path, revision, git_hash):
    """Set the REVISION and GIT_HASH project text variables. ${REVISION} and
    ${GIT_HASH} on the silkscreen and worksheet resolve from here."""
    with open(pro_path) as f:
        p = json.load(f)
    tv = p.setdefault("text_variables", {})
    tv["REVISION"] = revision
    tv["GIT_HASH"] = git_hash
    with open(pro_path, "w") as f:
        json.dump(p, f, indent=2)


def inject_revision(path, revision):
    """Stamp the title-block `rev` field (in addition to the project var)."""
    with open(path) as f:
        t = f.read()
    t, n = re.subn(r'\(rev "[^"]*"\)', f'(rev "{revision}")', t, count=1)
    if n != 1:
        sys.exit(f"ERROR: expected exactly one (rev ...) in {path}, replaced {n}")
    with open(path, "w") as f:
        f.write(t)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--revision", default=os.environ.get("REVISION"),
                    help="revision value (env: REVISION)")
    ap.add_argument("--git-hash", default=os.environ.get("GIT_HASH"),
                    help="GIT_HASH value (env: GIT_HASH)")
    ap.add_argument("--pro", default="usb3_fiber.kicad_pro")
    ap.add_argument("--sch", default="usb3_fiber.kicad_sch")
    ap.add_argument("--pcb", default="usb3_fiber.kicad_pcb")
    args = ap.parse_args(argv)

    if not args.revision:
        ap.error("REVISION required (--revision or env REVISION)")
    if not args.git_hash:
        ap.error("GIT_HASH required (--git-hash or env GIT_HASH)")

    inject_project_vars(args.pro, args.revision, args.git_hash)
    for path in (args.sch, args.pcb):
        inject_revision(path, args.revision)

    print(f"Injected REVISION='{args.revision}' + GIT_HASH='{args.git_hash}' "
          f"project text vars; stamped title-block rev")
    return 0


if __name__ == "__main__":
    sys.exit(main())
