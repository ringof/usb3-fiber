# Release Strategy

How `usb3-fiber` versions the design, builds fabrication packages, and publishes
releases. Implemented by `.github/workflows/main-release.yml` (and
`dev-checks.yml` for pre-merge validation).

## Branches & CI

Two-tier flow: **feature → `dev` → `main`**.

- **`dev-*`** feature branches are where work happens. They merge (squash) into
  **`dev`**, the permanent integration branch.
- **`dev`** collects vetted work. When a release is wanted, `dev` merges (squash)
  into **`main`**.
- **`main`** is the release branch. A merge here builds and (if the design
  changed) publishes a revision.
- Both `dev` and `main` are protected (PR required); `main` is the stricter
  release gate.

CI:

- **`dev-checks`** runs on `dev-*` pushes and on **PRs into `dev` and `main`**:
  ERC, DRC, BOM completeness, and schematic + assembly drawings as artifacts.
  So the same checks gate both feature→dev and dev→main.
- **`main-release`** runs on every merge to `main` (and can be dispatched
  manually) and is responsible for revisions and published packages.

## Revisions

- Revisions use an **alpha scheme**: Rev A → B → C …
- **GitHub Releases are the source of truth.** The next letter is computed by
  reading the latest release's tag (`revA` → `revB`); there is no revision number
  stored in the design files.
- Tags are `rev<LETTER>`; the release title is `Rev <LETTER>`.

## When is a new revision cut?

`main-release` publishes a **new** revision **only when a design file changed
since the last release**. Docs/CI/script-only merges are a **no-op** — they run
the workflow, determine nothing changed, and stop without building or publishing.

**Design files** (a change to any of these triggers an uprev):

- `*.kicad_sch`, `*.kicad_pcb`, `*.kicad_pro`, `*.kicad_dru`, `*.kicad_sym`
- `library/**`, `fp-lib-table`, `sym-lib-table`

**Not design files** (never trigger an uprev): `README.md`, `docs/**`,
`.github/**`, `scripts/**`, and `*.kicad_prl` (editor/UI state).

The comparison is made against **the last release's commit**, not just the
merge's own diff — so a design edit that landed in an earlier (unpublished)
commit is still caught, and a later docs-only merge cannot mask it.

## Provenance (`${REVISION}` and `${GIT_HASH}`)

Both are **injected at build time** into the project text variables and rendered
into the schematic/PCB **title block** and the **bottom silkscreen**. Nothing is
committed back to the design files — the defaults committed in `*.kicad_pro`
(`DEV` / `local`) are only placeholders for local opens.

- `${REVISION}` — the alpha letter being published.
- `${GIT_HASH}` — **the last commit that touched a design file**, not `HEAD`.

Stamping the *design* commit (rather than the build's `HEAD`) keeps the mark
truthful and stable: a docs-only commit never changes it, and the same physical
design never ends up stamped with two different hashes. The hash always points
at the commit that actually defines the released design.

## Release assets

Each release attaches three **stable-named** assets (no rev/hash in the
filename), so `…/releases/latest/download/<name>` links stay valid across
revisions:

| Asset | Contents |
|---|---|
| `usb3_fiber-schematic.pdf` | Schematic (direct download, no unzip) |
| `usb3_fiber-gerbers.zip` | Gerbers + drill (JLCPCB-ready) |
| `usb3_fiber-fabrication.zip` | Full package: gerbers, drill, BOM, CPL, schematic PDF, assembly drawings, STEP |

The revision and git hash live inside the files and in the release title/tag,
not in the filenames.

## Manual releases

Dispatch `main-release` manually (Actions → main-release → Run workflow) and
optionally set **`revision`** to force-publish a specific letter. Re-publishing
an existing revision is idempotent: the job refreshes that release's assets
(`gh release upload --clobber`) instead of failing.

## Edge cases

- **First release:** no prior release → Rev A.
- **Rev Z → next:** the letter simply increments (`Z` → `[`); if the alpha
  prototype ever reaches Z, revisit the scheme.
- **Doc-only merge after a design change is already released:** no-op, as
  intended — the released design is unchanged.
