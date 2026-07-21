# Using AI review on this project

This project is developed largely with AI assistance (Claude and similar), and
AI-assisted *review* of the design is welcome — it can be genuinely useful. It
can also confidently invent problems that don't exist and waste real review
cycles. This file exists so that anyone pointing an AI at this board does it the
way that helps, not the way that misleads.

Read this before pasting the design into any AI tool and reporting what it says.
It is the same "Evidence before claims" rule already in `CLAUDE.md`, spelled out
for AI output specifically.

## The core rule: a finding is a lead, never a verdict

An AI model will state things about this design with total confidence, including
things that are wrong. Its sense of the netlist — what is *actually* wired to
what — is weak unless it has been carefully grounded first (see below). It also
tends to tell you what sounds alarming, or what flatters the question you asked.

So: treat every AI finding as a **lead to check against the real design**, not as
a result. Nothing an AI says gets filed as an issue, and nothing gets acted on,
until it has been verified against the current schematic/PCB and the closed
issues. If you can't personally verify a finding, say so when you report it —
"the model flagged X, I haven't confirmed it" — don't pass it on as fact.

This is not hypothetical. On the sibling board `ringof/taprx888`, an AI reviewer
once "conclusively" reported that a controller's power/ground was inverted — it
wasn't. The model was reasoning without the reference material. That near-miss is
why both repos carry this document.

## Ground the model before you trust a single word

Before you ask an AI anything design-level about this board, give it, in roughly
this order:

1. **The datasheets for the actual parts on this board:**
   - **DS100BR111** — USB3 SuperSpeed redriver (`U2`). Local copy:
     `datasheets/ds100br111.pdf`. This is the heart of the signal path; its
     receiver/driver equalization straps and I/O conventions are where most
     real questions live.
   - **MCP2221A** — USB-to-I²C/UART bridge (`U1`) that provides the SFP+
     management interface. (No microcontroller and no firmware are involved —
     if a model starts reasoning about firmware, it has lost the plot; see
     `docs/USB3_Fiber_Link_Minimal_Circuit.md`.)
   - **The SFP+ module + cage** (`J1`/`J2`) — the relevant MSA specs (SFF-8431
     for the electrical/host side, SFF-8419/SFF-8074 for the connector) define
     the management I²C, LOS/TX-fault sidebands, and supply/decoupling rules.
     See `datasheets/hsio_cn_expressport_sfp.pdf` and the module datasheet
     (`datasheets/Ux76-A20-x00xx.pdf`).
   - **LD1086-3.3** (`U4`) — the 3.3 V LDO. Local family datasheet:
     `datasheets/LD1117.pdf`.
   - Note: the `datasheets/` folder also contains parts (e.g. FT232H, USB2517)
     that are **not** on the current BOM — do not let a model "review" against a
     part this board doesn't use. The authoritative part list is the schematic
     and the BOM the CI check exports, not the datasheet folder.
2. **The design intent** — `docs/USB3_Fiber_Link_Minimal_Circuit.md` (the
   architecture and the central hypothesis) and `docs/fab_specification.txt`
   (stackup, impedance, fab constraints). Much of what an ungrounded model
   "finds" about layer stackup or impedance is answered directly here.
3. **The current design** — the `usb3_fiber.kicad_sch` / `usb3_fiber.kicad_pcb`
   from the repo (or, better, an exported netlist/PDF), not a description of it.
4. **The closed issues** —
   <https://github.com/ringof/usb3-fiber/issues?q=is%3Aissue+state%3Aclosed>.
   Closed issues are already-decided items. An ungrounded model will
   "rediscover" them as new problems. Always check a finding against the closed
   list — and the open list — first.

An AI that hasn't been given these is not reviewing the board — it's guessing
about a board.

## How to actually run a useful review (the method)

1. **Prime it** with the material above — datasheets, design intent, and the
   schematic/netlist — before asking for findings.
2. **Expect the first pass to be poor, and challenge it.** Don't accept the
   opening answer; push back, ask it to trace the actual net, ask how it knows.
3. **Distill.** Its raw output is feedstock, not conclusions. Pull out the
   claims worth checking, verify each against the real design and the closed
   issues, and only then do you have something worth filing.
4. **File verified findings as normal issues** — one item each, "clear is kind,"
   with the datasheet / app-note / spec reference that backs it, in the house
   style already used across this tracker (see the existing DRC/ERC/KLC issues).
   File them as *your* findings that you've checked — not as "the AI said."

## What AI is genuinely good for here

Not all warnings — it's real help when grounded: sanity-checking a pinout
against a datasheet you've *also* handed it, cross-referencing an SFF/MSA or
DS100BR111 requirement, drafting issue text, explaining an unfamiliar corner of
the SFP+ management interface, or generating BOM/CI/tooling scripts (much of this
repo's CI was built exactly that way). The pattern that works is **"help me check
a specific thing I can then verify,"** not "tell me what's wrong with this
board." The difference between useful and misleading is entirely in the grounding
you give it and the checking you do after. Do both, or don't report the output.

## Related

- `CLAUDE.md` — the working agreement, including "Evidence before claims."
- `docs/USB3_Fiber_Link_Minimal_Circuit.md` — architecture and design intent.
- `ringof/taprx888:docs/AI_REVIEW.md` — the sibling board's version of this
  guidance, where the near-miss above originated.
