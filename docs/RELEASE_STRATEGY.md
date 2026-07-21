# Release Strategy

How `usb3-fiber` versions the design, builds fabrication packages, and publishes
releases. Implemented by `.github/workflows/dev-release.yml` and
`main-release.yml` (with `dev-checks.yml` for pre-merge validation), sharing a
single versioning policy in `scripts/next_version.sh`.

## Branches & CI

Two-tier flow: **feature → `dev` → `main`**.

- **`dev-*`** feature branches are where work happens. They merge (squash) into
  **`dev`**, the permanent integration branch.
- **`dev`** collects vetted work. Each merge cuts a **pre-release** (see below).
  When the design is ready to spin, `dev` merges (squash) into **`main`**.
- **`main`** is the release branch. A merge here promotes the design to a
  **production revision**.
- Both `dev` and `main` are protected (PR required); `main` is the stricter
  release gate.

CI:

- **`dev-checks`** runs on `dev-*` pushes and on **PRs into `dev` and `main`**:
  ERC, DRC, BOM completeness, and schematic + assembly drawings as artifacts. So
  the same checks gate both feature→dev and dev→main.
- **`dev-release`** runs on every merge to `dev` and publishes/refreshes the
  **pre-release** for that iteration.
- **`main-release`** runs on every merge to `main` (and can be dispatched
  manually) and publishes **production revisions** and their packages.

## Versioning

Semantic `MAJOR.MINOR`. Think of it as **`main` = production board spins;
`dev` = the iterations toward the next spin.**

**`main` advances to the next whole `.0`; `dev` does the minor increments** in
between. `dev`'s major line simply follows whatever `main` last shipped.

| Event | Version |
|---|---|
| `dev` merge, pre-1.0 | `0.1 → 0.2 → 0.3 …` (minor++) |
| **first `dev → main`** | **`1.0`** |
| `dev` merge, post-1.0 | `1.1 → 1.2 → 1.3 …` (minor++ in the 1.x line) |
| **next `dev → main`** | **`2.0`** |
| `dev` merge, post-2.0 | `2.1 → 2.2 …` |
| **next `dev → main`** | **`3.0`** |

- **`main` release** = `<latest main major + 1>.0`; first-ever → `1.0`. Every
  production release is a whole major — no auto-minor, and no manual major
  decision needed. Published as a normal (non-prerelease) Release so it lands as
  "Latest".
- **`dev` pre-release** = minor increment within the **current major line**,
  whose major follows the latest `main` release (`0` while pre-1.0). The first
  `dev` pre-release after a `main` `X.0` starts at `X.1`; the very first
  pre-release while pre-1.0 uses the seed (`0.1`). Published with `--prerelease`
  so it never claims "Latest".

The "back it into dev" step is **automatic**: `dev-release` reads `main`'s latest
major through the shared script, so the first pre-release after `main` ships
`1.0` computes as `1.1` on its own — no manual back-merge of a version number.

**GitHub Releases are the source of truth** for the version — no number lives in
the design files. Tags are `v<MAJOR>.<MINOR>`; the title matches (pre-releases
add a ` (pre-release)` suffix). The policy is implemented **once** in
`scripts/next_version.sh` (unit-tested offline by `scripts/test_next_version.sh`)
and called by both lanes, so `dev` and `main` can't drift apart.

> **Legacy tags:** the earlier alpha releases (`revA`/`revB`/`revC`) predate this
> scheme. Both workflows scope their release scan to `v<MAJOR>.<MINOR>` tags, so
> those alpha tags are simply ignored by the version math.

### Pre-releases (dev lane)

`dev-release` runs on every merge to `dev` and publishes a `--prerelease`:

- Computes the next `dev` version via `scripts/next_version.sh dev 0.1` and
  publishes when a design file changed since the last release (of any kind);
  docs/CI/script-only merges are a no-op.
- **First run seeds the line** at `v0.1` from the design at `dev` HEAD —
  automated, no manual tag.
- **Does not retire at 1.0.** After `main` ships `1.0`, `dev` continues in the
  `1.x` line (`1.1`, `1.2`, …) building toward the next `main` (`2.0`); after
  `2.0` it runs `2.x`; and so on.

Both lanes accept the same manual `version` override / `dry_run` inputs.

## When is a new revision cut?

Each lane publishes **only when a design file changed** since its base release;
docs/CI/script-only merges are a **no-op** — they run the workflow, determine
nothing changed, and stop without building or publishing.

- **`dev-release`** compares against the **most recent release of any kind**.
- **`main-release`** compares against the **most recent production
  (non-prerelease) release** — a `dev` pre-release never gates a production spin.
  The **first** production release always publishes `v1.0` (it is the promotion
  of the current design to production, not a diff).

**Design files** (a change to any of these triggers an uprev):

- `usb3_fiber.kicad_sch`, `usb3_fiber.kicad_pcb`, `usb3_fiber.kicad_pro`,
  `usb3_fiber.kicad_dru`
- `library/**` (symbols, footprints, and STEP models), `fp-lib-table`,
  `sym-lib-table`

The root board files are listed **explicitly** in the workflows (not as
`*.kicad_*` globs, which as git pathspecs match at any depth and would let a
future sibling KiCad project under `mechanical/` false-trigger a board release).

**Not design files** (never trigger an uprev): `README.md`, `docs/**`,
`.github/**`, `scripts/**`, and `*.kicad_prl` (editor/UI state).

The comparison is made against **the last release's commit**, not just the
merge's own diff — so a design edit that landed in an earlier (unpublished)
commit is still caught, and a later docs-only merge cannot mask it.

## Provenance (`${REVISION}` and `${GIT_HASH}`)

Both are **injected at build time** (`scripts/inject_provenance.py`) into the
project text variables and rendered into the schematic/PCB **title block** and
the **bottom silkscreen**. Nothing is committed back to the design files — the
defaults committed in `*.kicad_pro` (`DEV` / `local`) are only placeholders for
local opens.

- `${REVISION}` — the version being published (e.g. `0.3`, `1.0`).
- `${GIT_HASH}` — **the last commit that touched a design file**, not `HEAD`.

Stamping the *design* commit (rather than the build's `HEAD`) keeps the mark
truthful and stable: a docs-only commit never changes it, and the same physical
design never ends up stamped with two different hashes.

## Release assets

Each release attaches five **stable-named** assets (no version/hash in the
filename), so `…/releases/latest/download/<name>` links stay valid across
production revisions:

| Asset | Contents |
|---|---|
| `usb3_fiber-schematic.pdf` | Schematic (direct download, no unzip) |
| `usb3_fiber-assembly.pdf` | Assembly drawing (top + bottom, framed) |
| `usb3_fiber-fabrication-drawing.pdf` | Fabrication drawing / dimensions |
| `usb3_fiber-gerbers.zip` | Gerbers + drill (JLCPCB-ready) |
| `usb3_fiber-fabrication.zip` | Full package: gerbers, drill, BOM, CPL, PDFs, STEP |

The version and git hash live inside the files and in the release title/tag, not
in the filenames.

> `…/releases/latest/download/<name>` resolves to the latest **production**
> release. During the pre-1.0 phase (only `v0.x` pre-releases exist), link people
> to the specific pre-release's page instead — pre-releases never claim "Latest".

## Manual releases

Both workflows listen to a manual `workflow_dispatch` in addition to their push
trigger — driven entirely by inputs, no YAML editing.

- **`version`** — force a specific number (`main`: e.g. `2.0`; `dev`: e.g. `0.7`).
  Blank = automatic. Re-publishing an existing version is idempotent: the job
  refreshes that release's assets (`gh release upload --clobber`) instead of
  failing, so it doubles as the "re-publish / fix a release" button.
- **`dry_run: true`** — build the full turnkey package and upload it as **run
  artifacts** (`release-package`) **without** publishing. Forces a build even
  when no design file changed, so the pipeline (e.g. a KiBot config change) can
  be validated before committing to a real release. Provenance is still injected,
  so the artifacts carry the version they *would* be published under.

## Edge cases

- **First pre-release:** no prior release → seed `v0.1`.
- **First production release:** no prior production release → `v1.0` (always
  publishes — it is the promotion of the current design to production).
- **`dev` after a `main` release:** `dev`'s major follows the latest `main`, so
  the first pre-release after `1.0` is `1.1` (not `0.x`, not `2.0`); pre-releases
  are `--prerelease` so they never advance the `main` number.
- **Doc-only merge after a design change is already released:** no-op on either
  lane — the released design is unchanged.
- **`main` merge with no design change since the last production release:** no-op
  — a production major is never spent on nothing.
