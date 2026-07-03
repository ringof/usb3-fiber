# USB3-over-Fiber Minimal Circuit Design
## DS100BR111 Redriver + SFP+ Optical Link

**Project:** Remote ADC SDR Receiver  
**Scope:** Minimum viable circuitry for USB3 SuperSpeed over optical fiber. Single PCB serves both host-side and remote-side roles via jumper selection. The DS100BR111 redriver is configured entirely by pin-strap resistors set at board assembly. The MCP2221A provides the SFP+ management interface and GPIO for TX_DISABLE and RX_LOS. No microcontroller, no firmware, no EEPROM, no Windows toolchain.

---

## Architecture Overview

```
USB3-A connector                              SFP+ cage
(SuperSpeed pairs)                            (optical module)
      |                                             |
      |  INB+/INB-   ┌─────────────────┐  INA+/INA-|
      └──────────────┤                 ├────────────┘
                     │   DS100BR111    │
      ┌──────────────┤   (pin mode,    ├────────────┐
      |  OUTA+/OUTA- │   3.3V)        │  OUTB+/OUTB-|
USB3-A connector     └─────────────────┘        SFP+ cage
(SuperSpeed pairs)         |                         |
                     [pin-strap                 [SFP+ module]
                      resistors]                     |
                                              [optical fiber]

                     ┌──────────┐
                     │ MCP2221A │── USB micro-B ── laptop
                     └──────────┘
                          |
                    SDA/SCL bus
                          |
                    ┌─────┴──────┐
                    │            │
               SFP+ A0h      SFP+ A2h
               (0x50)         (0x51)
               identity      diagnostics
```

**Channel assignment:**

```
A-channel:  INA  ← SFP+ RD+/RD-  (received optical data, post-CDR)
            OUTA → USB3-A SS TX   (SuperSpeed to host or FX3)

B-channel:  INB  ← USB3-A SS RX  (SuperSpeed from host or FX3)
            OUTB → SFP+ TD+/TD-  (data to transmit laser)
```

Each fiber link requires two boards — one at the antenna, one at the shack. Both are identical PCBs; jumpers JP1 and JP2 select the role. The USB3 data path is fully symmetric: the DS100BR111 is bidirectional and the SFP+ module handles both TX and RX in a single cage.

---

## Central Hypothesis

**This prototype exists to test one thing:**

> 10GbE SR SFP+ optical modules will transport USB3 SuperSpeed signalling intact — including LFPS bursts, link training sequences, electrical idle transitions, spread-spectrum clock modulation, and receiver detection — without modification to the modules or the USB3 endpoints.

This has been demonstrated by others in the amateur radio and USB extension communities, but it is not guaranteed by any specification. The Ethernet SFP+ module was not designed for this application. Its internal CDR, limiting amplifier, and signal detect logic were optimised for continuous 10GbE data streams, not for the PHY handshaking behaviours that USB3 requires during link training.

### What Could Go Wrong

```
USB3 PHY behaviour     Risk through the chain
--------------------   -------------------------------------------------------
LFPS bursts            Low-amplitude (~200–400 mVpp), burst-mode signal.
(link training,        Two gatekeepers in series, either of which can eat it:
U-state transitions)
                       (1) DS100BR111: if SD_TH is set too high or the
                       idle-to-active wake response is too slow, the redriver
                       declares idle on inter-burst gaps and fails to pass the
                       burst cleanly. This is the more controllable risk —
                       SD_TH and MODE address it directly.

                       (2) SFP+ module: CDR may not lock on short bursts;
                       limiting amplifier may suppress low-amplitude bursts;
                       LOS logic may assert on inter-burst gaps and squelch
                       output mid-sequence. This is not controllable from
                       outside the module — it is addressed by module
                       selection.

                       The redriver risk is resolved first. If LFPS still
                       fails after SD_TH tuning, the module is the suspect.

Electrical idle        Zero-amplitude gap in the SS data stream.
                       Again two gatekeepers:

                       (1) DS100BR111: SD_TH controls not only when idle is
                       declared but how quickly the redriver wakes back up
                       when signal resumes. A sluggish idle-to-active response
                       clips the leading edge of the next LFPS burst or
                       ordered set. MODE=High (Continuous Talk) is necessary
                       but not sufficient — SD_TH must also be biased toward
                       fast wake-up for reliable LFPS handling.

                       (2) SFP+ module: modules with output squelch gate TX
                       output when LOS asserts — which it will during idle.
                       DS100BR111 Continuous Talk does not prevent the SFP+
                       module's own squelch from firing. This remains the
                       primary uncontrolled risk in the design.

SSC clock modulation   USB3 host controllers spread the 5 Gbps reference
(±5000 ppm)            ±5000 ppm to reduce EMI. The SFP+ CDR must track this
                       continuously. 10GbE SR CDRs are specified for Ethernet
                       SSC profiles, which differ from USB3. Most modern CDRs
                       have sufficient capture range; older or narrow-band CDRs
                       may lose lock and introduce jitter.

Receiver detection     USB3 host asserts a DC test current and measures
                       termination impedance to confirm device presence.
                       This test occurs before any AC signalling. The AC
                       coupling in the signal path must not prevent this DC
                       current from reaching the far-end termination.
                       In practice the internal AC coupling of most SFP+
                       modules blocks the DC test — receiver detection may
                       fail or require a different termination arrangement.

Link training          TS1/TS2 ordered sets at 5 Gbps. These are standard
ordered sets           data patterns and should pass through any CDR with
                       adequate bandwidth. This is the lowest-risk behaviour.
```

### Why the Hypothesis Is Plausible

The CDR in a 10GbE SR module operates at 10.3125 Gbps, well above the 5 Gbps USB3 data rate. USB3 SS data patterns are within the CDR's operating range as a subset of its bandwidth. Community experience (primarily in USB-over-fiber projects using similar hardware) suggests that the CDR tracks SSC adequately and passes link training ordered sets. The primary failure modes in practice are LFPS propagation and electrical idle handling — and these have two components each: redriver idle behaviour (controllable via SD_TH and MODE) and module squelch behaviour (addressed by module selection).

MODE=High and careful SD_TH selection reduce the redriver to a transparent relay for burst signalling. That removes one gatekeeper from the equation. Whether the SFP+ module is also transparent to LFPS and idle is the central experimental question.

### Module Vendor Is a Primary Variable

Two 10GbE SR modules from different vendors may produce completely different results for USB3 transport. The CDR implementation, LOS threshold, squelch hysteresis, and any vendor-specific firmware loaded at manufacture all affect compatibility. **Module vendor must be treated as a first-order experimental variable, not a detail to be resolved after the board is built.**

The Finisar FTLX8571D3BCL is the recommended starting point because it is well-characterised, widely used in community USB-over-fiber experiments, and available in large quantities on the surplus market. It is not guaranteed to work, but it is the most likely to work based on available evidence.

### What the Prototype Validates

A successful Stage 2 optical test (sustained USB3 SuperSpeed transfer at > 300 MB/s through the fiber link, with stable enumeration and no errors) constitutes validation of the hypothesis **for the specific combination of modules used**. It does not validate the hypothesis for all SFP+ modules. Changing module vendor requires repeating the validation.

---

One PCB design serves both ends of the fiber link. Two 3-pin jumpers select the role at assembly time.

```
JP1 — VBUS power source
  Pins 1-2 (host role):    USB3-A VBUS → LDO input
  Pins 2-3 (remote role):  micro-B VBUS → LDO input

JP2 — USB2 D+/D- routing (for MCP2221A)
  Pins 1-2 (host role):    USB3-A USB2 pair → MCP2221A D+/D-
  Pins 2-3 (remote role):  micro-B D+/D- → MCP2221A D+/D-
```

The micro-B connector is populated on all builds regardless of role. On the remote (antenna) board it is the sole power and MCP2221A interface; on the host (shack) board it remains available as a backup. Both jumpers must be installed before powering the board — an uninstalled jumper leaves the LDO input or MCP2221A USB in an undefined state.

```
Role summary:
  Host board:    USB3-A carries both SuperSpeed data and power
                 micro-B available as backup / secondary MCP2221A port
  Remote board:  USB3-A carries SuperSpeed data only (no VBUS expected)
                 micro-B is primary power and MCP2221A interface
```

---

## Power Supply

The LD1117S33TR (SOT-223) converts the VBUS input (selected by JP1) to the single 3.3V rail that powers all board circuitry.

```
VBUS (5V, via JP1)
    |
[LD1117S33TR — ST Microelectronics]
  Package:   SOT-223
  Output:    3.3V fixed
  Max:       800mA
  Dropout:   ~1.1V @ 800mA — adequate with 5V input
  Cost:      ~$0.40
    |
3.3V rail → DS100BR111 VIN, SFP+ VCC_RX/VCC_TX,
            MCP2221A VDD, pull-up resistors
```

### Power Budget

```
DS100BR111:   ~130mA @ 3.3V  =  0.43W  (both channels active, VOD=1000mVpp)
SFP+ module:  ~300mA @ 3.3V  =  1.00W  (typical 10GbE SR, laser on)
MCP2221A:      ~25mA @ 3.3V  =  0.08W
Misc:           ~20mA @ 3.3V  =  0.07W  (LEDs, pull-ups)
Total 3.3V:   ~475mA          =  1.58W

Total from VBUS input: ~1.6W
USB 2.0 port budget:  2.5W (500mA × 5V) — comfortable margin
USB 3.0 port budget:  4.5W (900mA × 5V) — no concern
LD1117S33TR max:      4.0W (800mA × 5V) — ~2.4W headroom
```

A USB 2.0 port on the micro-B is sufficient to power the board. The micro-B carries no SuperSpeed signals — it is purely power and MCP2221A USB.

### LDO Thermal Considerations

The LD1117S33TR dissipates the voltage difference between VBUS and 3.3V as heat:

```
P_dissipated = (V_in − V_out) × I_load
             = (5.0 − 3.3) × 0.475 A
             ≈ 0.81 W
```

The SOT-223 package can handle this with an adequate copper pour on the exposed tab — a 1 cm² pour tied to the GND plane is sufficient to keep junction temperature below 85°C at room ambient. However, the LDO is mounted adjacent to the SFP+ cage, which is itself a heat source (~1W). Layout must ensure the LDO tab pour does not thermally couple to the SFP+ VCC supply traces.

The LD1117 is appropriate for this prototype. For a production design, a 5V→3.3V synchronous buck regulator is preferred: lower heat, lower output noise, and better efficiency. The prototype prioritises simplicity and single-sourcing over efficiency.



```
LDO input:  100nF + 10µF to GND, within 5mm of LDO input pin
LDO output: 100nF + 10µF to GND, within 5mm of LDO output pin
```

---

## DS100BR111 Configuration — Pin Mode

The DS100BR111 is configured entirely by resistors at board assembly. No EEPROM, no software, no tools. The device reads pin states at power-on and runs autonomously.

### 3.3V Operation

The DS100BR111 operates in 3.3V mode on this board. Power pin behaviour differs from the 2.5V mode and must be understood before laying out the schematic.

```
VIN (pin 15):    Connect to 3.3V rail. Primary power input.
                 100nF + 10µF decoupling to GND close to pin.

VDD (pins 21,22): Do NOT connect to 3.3V rail.
                  In 3.3V mode VDD is the internal LDO output,
                  not a supply input. Connecting VDD to the rail
                  back-drives the LDO. Decoupling caps (100nF each)
                  to GND only — no supply connection.

VDD_SEL (pin 16): Tie to GND. Selects 3.3V mode (LDO enabled).
                  If left floating, device enters 2.5V mode and
                  requires an external 2.5V supply on VDD.
```

### 4-Level Pin Encoding

EQ, DEM, VOD_SEL, MODE, and SD_TH are all 4-level pins. Each has an internal 30 kΩ pull-up and 60 kΩ pull-down. The external resistor sets one of four levels:

```
Level   External resistor       State
  3     1 kΩ to VIN (3.3V)     Logic High
  2     No connect (float)      Float
  1     20 kΩ to GND            Mid-low
  0     1 kΩ to GND             Logic Low
```

In 3.3V mode, Level 3 pull-up resistors must reference VIN, not VDD — VDD is not a supply rail in this mode.

### Pin-Mode Resistor Table

```
Pin              Setting    Resistor           Rationale
---------------  ---------  -----------------  ------------------------------------
ENSMB (pin 3)    Level 0    1 kΩ to GND        Enables pin control mode.
                                               Non-negotiable.

MODE (pin 18)    Level 3    1 kΩ to VIN        10GbE Continuous Talk.
                                               USB3 uses LFPS for electrical idle,
                                               not SAS/SATA OOB. SAS mode (Level 0)
                                               would gate on OOB bursts and suppress
                                               LFPS, preventing SS enumeration.
                                               Continuous Talk bypasses all OOB
                                               detection — outputs stay active
                                               whenever signal exceeds SD_TH.

EQA0 (pin 10)    Level 0    1 kΩ to GND        Minimum EQ on INA (SFP+ → OUTA).
EQA1 (pin 9)     Level 0    1 kΩ to GND        INA receives post-CDR output from
                                               the SFP+ module's internal limiting
                                               amplifier. The CDR has already
                                               re-timed and re-driven the data;
                                               the eye is fully open. Board trace
                                               is under 2cm. EQ on a clean signal
                                               amplifies noise, not signal.

EQB0 (pin 1)     Level 0    1 kΩ to GND        Starting point for INB (USB3-A → OUTB).
EQB1 (pin 2)     Level 2    No connect         INB receives USB3 SS from host via
                            (4-level footprint) ~0.5m cable. Cable loss is ~3–6 dB
                                               at 2.5 GHz — a real but modest channel.
                                               One step above minimum is a reasonable
                                               first guess; actual optimal value
                                               depends on the specific cable and
                                               PCB stackup, and must be confirmed
                                               during bring-up. Populate EQB pins as
                                               4-level footprints for resistor-swap
                                               tuning without PCB rework.

DEMA (pin 4)     Level 0    1 kΩ to GND        0 dB de-emphasis on OUTA (→ USB3).
                                               Host RX has its own CTLE/DFE.
                                               0.5m cable is within host EQ range.

DEMB (pin 5)     Level 0    1 kΩ to GND        0 dB de-emphasis on OUTB (→ SFP+).
                                               Sub-2cm trace; SFP+ module CDR
                                               handles it. De-emphasis here would
                                               reduce eye amplitude with no benefit.

VOD_SEL (pin 17) Level 2    No connect         ~1000 mVpp output swing.
                                               SFP+ CML input spec: 150–1200 mVpp.
                                               1000 mVpp is solidly mid-range.
                                               Note: OUTA is hardware-limited to
                                               700 mVpp in pin mode regardless of
                                               VOD_SEL setting (TI datasheet §7.4).
                                               700 mVpp is within USB3 RX spec.

SD_TH (pin 14)   Level 2    No connect         Default starting point (assert 180 mVpp,
                            (adjust early       deassert 110 mVpp).
                            if enum fails)      SD_TH is a first-order bring-up
                                               setting, not a secondary tuning pin.
                                               It controls not only the signal-present
                                               threshold but how quickly the redriver
                                               wakes from idle. A threshold too high
                                               causes the redriver to declare idle on
                                               LFPS inter-burst gaps, clipping the
                                               leading edge of the next burst and
                                               preventing link formation entirely.
                                               If enumeration is intermittent or never
                                               succeeds, SD_TH is the first adjustment
                                               — before EQ, before DEM. See Bring-Up
                                               Adjustment Path.

TX_DIS (pin 6)   Low        GND direct         Both channels always enabled.
                                               TX_DIS=High disables OUTB only.

VDD_SEL (pin 16) Low        GND direct         3.3V operation (see above).
```

**Schematic note — dual-function pins:** Pins 4 and 5 are labelled SDA/DEMA and SCL/DEMB in the datasheet, with the SMBus name listed first. In pin mode (ENSMB = GND) these pins are DEMA and DEMB — de-emphasis resistors to GND. Do not connect them to the I2C bus. Doing so would wire SDA and SCL directly to the de-emphasis resistors and to GND, holding the I2C bus permanently low while shorting the resistors. This must be called out as an explicit schematic note.

### Signal Integrity Margin

The resistor values above are derived from first principles for the stated geometry (sub-2cm board traces, ~0.5m USB3 cable). Whether they are adequate in practice depends on PCB stackup, connector quality, return path continuity, and AC coupling cap placement — none of which are known until the board is built and measured.

The settings should be treated as a starting point, not a guaranteed operating point. USB3 compliance requires a specific eye diagram opening at the receiver; whether the default settings achieve this must be confirmed by measurement. The 4-level footprints on EQB are specifically intended to make this adjustment without PCB rework.

### Bring-Up Adjustment Path

These are expected adjustments during bring-up, not rare exceptions. The ordering matters: idle and signal-detect issues prevent the link from ever forming; EQ and DEM issues only appear after the link is stable.

```
Symptom                            Adjustment
---------------------------------  -----------------------------------------------
Enumeration intermittent or        SD_TH: try 20 kΩ to GND (Level 1, lower
never succeeds                     threshold, faster wake-up from idle). First
                                   knob to move before touching anything else.
                                   If this fixes it, the redriver was the gatekeeper.
                                   If not, the SFP+ module is suspect — swap vendor.

USB3 enumerates at HS (480 Mbps)   SS link training failed. Try SD_TH if not already
not SuperSpeed (5000 Mbps)         done. Then module vendor swap before EQ changes.

USB3 cable RX eye marginal         EQB: increase via resistor swap (consult Table 3).
(link is up but marginal)          This is a signal integrity issue, not idle/burst.

ISI at USB3 host RX                DEMA: no connect → -3 dB (float → Level 2)
(link is stable, payload suffers)

ISI at SFP+ module input           DEMB: no connect → -3 dB (float → Level 2)

OUTA amplitude inadequate          Not adjustable in pin mode (700 mVpp fixed).
                                   Switch ENSMB to SMBus slave if >700 mVpp needed.
```

### Note on Rejected EEPROM Configuration Path

EEPROM boot mode (ENSMB = float) was evaluated and rejected for this design. The reasons are documented here for future reference:

The DS100BR111 in EEPROM master mode hardcodes its EEPROM read to I2C address 0xA0 (7-bit: 0x50). This is the same address as the SFP+ module's A0h management page — a fixed address defined by the SFF-8472 specification and shared by every SFP+ module ever made. The conflict cannot be resolved without an I2C multiplexer (TCA9548A). Additionally, the EEPROM data format is a TI-proprietary binary structure generated by TI's SigCon Architect tool (Windows-only, no open-source equivalent). The sum of added complexity — discrete EEPROM, I2C mux, Windows toolchain, boot sequencing logic — exceeds any benefit for a fixed-geometry application. Pin-strap mode requires seven resistors, set once at assembly, with no toolchain dependencies.

---

## Pin-by-Pin Connection Reference

### SFP+ Cage — 20-Pin Edge Connector (SFF-8472)

```
Pin   Name         Connect?   Connection / Treatment
----  -----------  ---------  -------------------------------------------------
  1   VEE TX GND   MUST       PCB GND plane
  2   TX_FAULT     IGNORE     Leave unconnected. No action available on TX_FAULT
                              in pin mode; optical modules typically do not assert.
  3   TX_DISABLE   MUST       MCP2221A GP0/pin 2 (GPIO_OUT, active HIGH disables laser).
                              Default LOW = laser enabled.
  4   SDA          MUST       MCP2221A SDA + 4.7 kΩ pull-up to 3.3V
  5   SCL          MUST       MCP2221A SCL + 4.7 kΩ pull-up to 3.3V
  6   MOD_ABS      OPTIONAL   Open-drain, pulled LOW by module when seated.
                              10 kΩ pull-up to 3.3V; connect to MCP2221A GPIO
                              for module-present detection, or leave unconnected.
  7   RS0          IGNORE     Rate select for dual-rate SFP devices.
                              All 10G SR/LR modules ignore this. Leave open.
  8   RX_LOS       MUST       330 Ω to red LED (LOS indicator) + MCP2221A GP1/pin 6
                              (GPIO_IN). Active HIGH = no received optical signal.
                              10 kΩ pull-up to 3.3V (LOS is open-drain).
  9   RS1          IGNORE     Same as RS0. Leave unconnected.
 10   VEE RX GND   MUST       PCB GND plane
 11   VEE RX GND   MUST       PCB GND plane
 12   RD-          MUST       DS100BR111 INA- (100Ω diff, 100nF AC coupling)
                              SFP+ module provides internal AC coupling on RD
                              outputs; these caps are technically redundant but
                              are retained per DS100BR111 application circuit and
                              as insurance against modules that do not.
 13   RD+          MUST       DS100BR111 INA+ (100Ω diff, 100nF AC coupling)
                              Same rationale as RD-.
 14   VEE RX GND   MUST       PCB GND plane
 15   VCC_RX       MUST       3.3V via 10 Ω series + 100nF to GND
 16   VCC_TX       MUST       3.3V via 10 Ω series + 100nF to GND
 17   VEE TX GND   MUST       PCB GND plane
 18   TD+          MUST       DS100BR111 OUTB+ (100Ω diff, 100nF AC coupling)
                              Required by SFF-8431: AC coupling on TD lines is the
                              host board's responsibility, not the module's.
 19   TD-          MUST       DS100BR111 OUTB- (100Ω diff, 100nF AC coupling)
                              Same — SFF-8431 mandates these caps on this side.
 20   VEE TX GND   MUST       PCB GND plane
```

VCC5 (5V supply pin, some cage footprints): omit unless module datasheet
requires it. The FTLX8571D3BCL and all 10G SR modules used in this design
are 3.3V-only. Verify byte 65 of A0h (nominal supply voltage) after first
module seating if using unfamiliar modules.

---

### DS100BR111 — 24-Pin WQFN (Pin Mode, 3.3V)

```
Pin   Name              Connect?   Connection / Treatment
----  ----------------  ---------  ------------------------------------------------
  1   EQB0/AD3          MUST       1 kΩ to GND (EQB0 = Level 0)
  2   EQB1/AD2          MUST       No connect — float (EQB1 = Level 2).
                                   Populate as 4-level footprint for bring-up tuning.
  3   ENSMB             MUST       1 kΩ to GND (pin mode)
  4   SDA/DEMA          MUST       1 kΩ to GND (DEMA = Level 0, 0 dB de-emphasis).
                                   *** PIN MODE ONLY: this is DEMA, not SDA. ***
                                   Do NOT connect to I2C bus.
  5   SCL/DEMB          MUST       1 kΩ to GND (DEMB = Level 0, 0 dB de-emphasis).
                                   *** PIN MODE ONLY: this is DEMB, not SCL. ***
                                   Do NOT connect to I2C bus.
  6   TX_DIS            MUST       GND direct (both channels always enabled)
  7   OUTA+             MUST       USB3-A SS TX+ (100Ω diff, 100nF AC coupling)
  8   OUTA-             MUST       USB3-A SS TX- (100Ω diff, 100nF AC coupling)
  9   AD1/EQA1          MUST       1 kΩ to GND (EQA1 = Level 0, min EQ)
 10   AD0/EQA0          MUST       1 kΩ to GND (EQA0 = Level 0, min EQ)
 11   INB+              MUST       USB3-A SS RX+ (100Ω diff, 100nF AC coupling)
                                   FX3 has its own AC coupling caps on its SS TX
                                   outputs. These caps are local input bypass for
                                   the DS100BR111 per its application circuit.
                                   Two caps in series across the cable (~50nF
                                   effective) is harmless at 5 Gbps.
 12   INB-              MUST       USB3-A SS RX- (100Ω diff, 100nF AC coupling)
                                   Same rationale as INB+.
 13   LOS               NC         Leave unconnected. In pin mode LOS monitors INA
                                   (SFP+ received signal) only — same condition as
                                   SFP+ RX_LOS on pin 8. Redundant with existing
                                   LED and MCP2221A GP1. DNP 10 kΩ pull-up footprint
                                   to 3.3V retained for potential future use.
 14   SD_TH             MUST       No connect — float (default starting point).
                                   First-order bring-up setting. See pin-mode
                                   resistor table and Bring-Up Adjustment Path.
 15   VIN               MUST       3.3V supply. 100nF + 10µF to GND. Primary power.
 16   VDD_SEL           MUST       GND direct (3.3V mode)
 17   VOD_SEL/READEN    MUST       No connect — float (VOD = 1000 mVpp).
                                   In pin mode this pin is VOD_SEL, not READEN.
 18   MODE/DONE         MUST       1 kΩ to VIN (3.3V). Continuous Talk mode.
                                   In pin mode this pin is MODE, not DONE.
 19   OUTB-             MUST       SFP+ TD- (100Ω diff, 100nF AC coupling)
 20   OUTB+             MUST       SFP+ TD+ (100Ω diff, 100nF AC coupling)
 21   VDD               MUST       100nF to GND ONLY. Not connected to supply.
 22   VDD               MUST       100nF to GND ONLY. Not connected to supply.
 23   INA-              MUST       SFP+ RD- (100Ω diff, 100nF AC coupling)
 24   INA+              MUST       SFP+ RD+ (100Ω diff, 100nF AC coupling)
 DAP  GND (thermal pad) MUST       PCB GND plane, minimum 4 vias. This pad is the
                                   sole ground connection for the device. Do not omit.
```

**Resistor BOM:** 6× 1 kΩ 0402 to GND, 1× 1 kΩ 0402 to VIN.
No-connect (float) pads: pins 2, 14, 17. Pins 4 and 5 are GND resistors, not I2C.

---

### MCP2221A — QFN-16 (MCP2221AT-I/ML)

```
Pin   Name    Connect?   Connection / Treatment
----  ------  ---------  ----------------------------------------------------------
  1   VDD     MUST       3.3V supply. 100nF + 10µF to GND close to pin.
  2   GP0     MUST       SFP+ TX_DISABLE (cage pin 3). GPIO_OUT, default LOW.
                         330 Ω series resistor protects pin if accidentally
                         reconfigured as input while SFP+ TX_DISABLE is driven.
  3   RESET#  MUST       10 kΩ pull-up to 3.3V. Active LOW reset input.
                         Internal pull-up exists but external resistor improves
                         noise immunity during power ramp.
  4   UARTRX  IGNORE     UART not used. Leave unconnected.
                         Internal pull-up holds HIGH. UART CDC port enumerates
                         on host regardless; does not affect I2C/HID operation.
  5   UARTTX  IGNORE     UART not used. Leave unconnected.
  6   GP1     MUST       SFP+ RX_LOS (cage pin 8). GPIO_IN.
                         Active HIGH = no received optical signal.
                         330 Ω series resistor.
  7   GP2     OPTIONAL   Unassigned on first build. Footprint present.
                         Candidate: heartbeat LED (GPIO_OUT, toggled at 1 Hz
                         by host script; confirms MCP2221A communication path).
                         330 Ω series resistor to LED if populated.
  8   GP3     OPTIONAL   Unassigned on first build. Footprint present.
  9   SCL     MUST       SFP+ SCL (cage pin 5). 4.7 kΩ pull-up to 3.3V on bus.
 10   SDA     MUST       SFP+ SDA (cage pin 4). 4.7 kΩ pull-up to 3.3V on bus.
                         Direct connection — no mux required (DS100BR111 not
                         on this bus in pin mode).
 11   VSS     MUST       GND
 12   VUSB    MUST       100nF to GND ONLY. Output of internal USB LDO.
                         Do NOT connect to 3.3V supply rail — back-drives LDO.
 13   D-      MUST       USB micro-B D- (via JP2)
 14   D+      MUST       USB micro-B D+ (via JP2)
 15   NC      IGNORE     No connection.
 16   NC      IGNORE     No connection.
 EP   EP      MUST       Exposed pad. GND. Solder to GND copper pour with
                         minimum 4 vias under pad.
```

**GP pin assignment:**

```
GP0  OUT   SFP+ TX_DISABLE   HIGH = laser off; default LOW = laser on
GP1  IN    SFP+ RX_LOS       HIGH = no received optical signal
GP2  —     Unassigned, footprint only (heartbeat LED candidate)
GP3  —     Unassigned, footprint only
```

**I2C bus note:** In pin mode the DS100BR111 is not on the I2C bus at all. The MCP2221A talks exclusively to SFP+ A0h (0x50) and A2h (0x51). No address conflicts exist. No mux is required.

---

### Cross-Device Connection Summary

```
Signal              From                     To
------------------  -----------------------  -----------------------------
SFP+ RD+/RD-        SFP+ pins 13/12          DS100BR111 INA+/INA- (AC)
SFP+ TD+/TD-        DS100BR111 OUTB+/OUTB-   SFP+ pins 18/19 (AC)
USB3 SS TX+/TX-     DS100BR111 OUTA+/OUTA-   USB3-A SS TX pins (AC)
USB3 SS RX+/RX-     USB3-A SS RX pins        DS100BR111 INB+/INB- (AC)
SFP+ SDA            SFP+ cage pin 4          MCP2221A SDA (+ 4.7 kΩ pull-up)
SFP+ SCL            SFP+ cage pin 5          MCP2221A SCL (+ 4.7 kΩ pull-up)
SFP+ TX_DISABLE     MCP2221A GP0             SFP+ cage pin 3 (330 Ω series)
SFP+ RX_LOS         SFP+ cage pin 8          MCP2221A GP1 + LOS LED (330 Ω)
MCP2221A D+/D-      USB micro-B              MCP2221A pins 14/13 D+/D- (via JP2)
```

All eight AC coupling capacitors on DS100BR111 CML paths are 100nF 0402, placed
within 2mm of the DS100BR111 pins on the DS100BR111 side of each pair. The OUTB caps
(SFP+ TD side) are mandatory per SFF-8431 — the host board owns this coupling. The INA
caps (SFP+ RD side) and INB caps (USB3 side) are redundant with coupling provided by
the SFP+ module and FX3 respectively, but are retained per DS100BR111 application
circuit guidance.

---

## LEDs and Diagnostic Indicators

### LED Polarity Convention

**Lit = problem, dark = healthy** — except PWR which is the opposite.
A fully operational board in a dark room shows one green LED. This convention
is standard in telecom hardware and minimises misreading during bring-up.

### LED Definitions

```
Silkscreen  Colour  Drive                Resistor  Lit Means           Dark Means
----------  ------  -------------------  --------  ------------------  ----------------
PWR         Green   LD1117S33TR output   1 kΩ      Board is powered    Board unpowered
LOS         Red     SFP+ RX_LOS pin 8   330 Ω     No optical signal   Fiber link live
SPARE       Green   MCP2221A GP2/pin 7 (DNP) 330 Ω (unpopulated)   (unpopulated)
```

**PWR:** Confirms the LDO has output and the 3.3V rail is live. Hardware-driven,
always on when powered. Does not confirm jumper state, module seating, or
USB3 enumeration — it is purely a power-on indicator.

**LOS (Loss of Signal):** Driven directly by the SFP+ module's internal optical
power monitor. No firmware or host involvement required. Valid as soon as the
module is seated and powered, before any USB enumeration. Asserts when received
optical power drops below ~-17 dBm (typical for 10G SR modules).

**LED state matrix:**

```
PWR     LOS     Interpretation
------  ------  ---------------------------------------------------------
dark    dark    Board unpowered (both expected when off)
lit     lit     Board powered, no fiber or far end not transmitting
lit     dark    Optical signal present — normal operating state
```

There is no state in which PWR is dark and LOS is lit (LOS is open-drain;
it has no drive when the module is unpowered).

**SPARE footprint:** One green LED footprint is present but unpopulated on
the first build. Recommended use: heartbeat, driven by MCP2221A GP2 (pin 7) toggled
at 1 Hz by the host diagnostic script. Confirms the entire MCP2221A
communication path is healthy at a glance. Requires three lines of Python.

---

## Diagnostics Beyond the LEDs

The LEDs give binary go/no-go. The following gives numbers.

### MCP2221A — SFP+ Management Interface

The MCP2221A appears on the host as a USB HID device (EasyMCP2221 Python
library) and optionally as a CDC COM port (Microchip GUI tool). No driver
installation required on Linux or macOS.

**GPIO reads (binary):**

```
GP0  Write  SFP+ TX_DISABLE  Assert high to disable laser; low to enable
GP1  Read   SFP+ RX_LOS      Same signal as LOS LED, readable in software
GP2  Write  Spare LED        Heartbeat toggle if populated
GP3  —      Unassigned
```

**SFP+ A0h (0x50) — static identity, read at first bring-up:**

```
Bytes    Field                   Example (FTLX8571D3BCL)
-------  ----------------------  ----------------------------------
0        Identifier              0x03 = SFP
2        Connector               0x07 = LC
3–10     Compliance              10G SR, 850nm
12       BR nominal (×100Mbps)   0x67 = 10.3 Gbps
20–35    Vendor name             "FINISAR CORP   "
40–55    Vendor part number      "FTLX8571D3BCL  "
60–61    Wavelength              850 nm
84–91    Date code
92–94    Diagnostic type         0x68 = DDM supported, internal cal
```

Read A0h first. Confirms module is seated and responsive, DDM is supported,
and part identity matches expectations before attempting A2h reads.

**SFP+ A2h (0x51) — live diagnostics, update in real time:**

```
Bytes    Field            Units      Healthy range (SR module, room temp)
-------  ---------------  ---------  ------------------------------------
96–97    Temperature      °C × 256   0–70°C
98–99    Supply voltage   100 µV     3.1–3.5V
100–101  TX bias current  2 µA       5–100 mA (zero = laser off or dead)
102–103  TX output power  0.1 µW     -3 to +3 dBm typical
104–105  RX input power   0.1 µW     > -11 dBm for a working link
```

These five measurements are the primary quantitative diagnostics for the fiber
link and are available before USB3 enumeration is attempted.

**Link margin:**

```
margin (dB) = RX_power_dBm − module_sensitivity_dBm
```

For FTLX8571D3BCL: sensitivity = −11.1 dBm. On a 1m OM3 patch with 0.5 dB
insertion loss and −3 dBm TX power: margin ≈ 7.6 dB. Anything above 3 dB is
comfortable. Below 1 dB warrants investigation before proceeding to USB3 tests.

### USB3 Enumeration (Host OS)

```
Linux:    lsusb -t           confirms SuperSpeed (5000M) negotiated
          dmesg | grep usb   shows SS link negotiation messages
Windows:  Device Manager     shows "USB3" or "SuperSpeed" annotation
```

If the device enumerates at High Speed (480 Mbps) instead of SuperSpeed, the SS
link has fallen back. Check cable, FX3 firmware, and DS100BR111 signal integrity.

### USB3 Throughput (Host Software)

The FX3 with SDDC_FX3 firmware streams data as a bulk USB endpoint. Throughput
is directly measurable with SDR host software or a raw USB benchmark. Expected:
> 300 MB/s sustained for a healthy SuperSpeed link. Sustained below 200 MB/s
with no errors suggests SS speed fallback.

### DS100BR111 (Pin Mode — No Register Access)

No register readback is available in pin mode. The device is fully transparent
once powered. The observable outcome is either correct USB3 operation or not.

**SMBus slave mode escape hatch:** If register readback becomes necessary during
a difficult bring-up, switching to SMBus slave mode requires: replace the 1 kΩ
ENSMB resistor to GND with 1 kΩ to VIN; populate SDA/SCL pull-up resistors
(2–5 kΩ to 3.3V); connect MCP2221A GP2 (pin 7) / GP3 (pin 8) to the SDA/SCL pads. PCB footprints
for all of this are present but DNP on first build. Note: in SMBus slave mode
the DS100BR111 shares the I2C bus at an address that must be kept clear of 0x50
and 0x51, and SFP+ A0h can only be accessed when the DS100BR111 is not also
being addressed (time-multiplexed access required).

---

## SFP+ Module Selection

**Module vendor is a first-order experimental variable.** Two 10GbE SR modules from different vendors may behave completely differently for USB3 transport. CDR implementation, LOS threshold, output squelch behaviour, and any vendor firmware loaded at manufacture all affect USB3 compatibility independently of the module's optical performance. A module that passes optical diagnostics may still fail USB3 link training.

### Why Vendor Matters

```
Variable                Impact on USB3 transport
----------------------  ---------------------------------------------------
CDR capture range       Must track USB3 SSC (±5000 ppm). Wide-capture CDRs
                        (common in 10GbE SR) generally cope; narrow-band CDRs
                        (some older or storage-class modules) may lose lock.

LOS assert threshold    If LOS asserts during electrical idle or LFPS gaps,
and squelch behaviour   the module may gate TX output mid-training sequence.
                        This kills enumeration even if the redriver is in
                        Continuous Talk mode. Threshold and squelch hysteresis
                        vary by vendor and are not always documented.

Limiting amplifier      Optimised for Ethernet data patterns; may respond
response                differently to LFPS bursts (~250 MHz, short duty
                        cycle) than to continuous 5 Gbps data.

Vendor firmware         Some modules contain embedded microcontrollers that
                        monitor diagnostics and can alter module behaviour.
                        Batch variation within the same part number is possible.
```

### Recommended Starting Module: Finisar FTLX8571D3BCL

```
Vendor:        Finisar (now II-VI / Coherent)
Part:          FTLX8571D3BCL
Data rate:     10.3125 Gbps
Wavelength:    850nm VCSEL
Fiber:         OM3/OM4 multimode, LC duplex
Typical reach: 300m OM3, 400m OM4
CDR:           Wide capture range, known good for USB3 in community use
DDM:           Full SFF-8472 A2h diagnostics
Availability:  Commodity surplus — large quantities on eBay, ~$5–15
```

This module is the recommended first choice because it has been used successfully for USB3-over-fiber by others. It is not guaranteed to work, and **each batch sourced from surplus must be validated**, as firmware variants within the same part number have been reported.

### Alternative: Avago / Broadcom AFBR-703SDZ

Similar specifications to the FTLX8571D3BCL. Known good for USB3 transport in community use. Use as a second option if Finisar is unavailable.

### Alternative: 8GFC (8 Gigabit Fibre Channel)

```
Data rate:     8.5 Gbps line rate
Wavelength:    850nm VCSEL
Fiber:         OM3/OM4, LC duplex
CDR:           Typically narrower capture range than 10GbE SR
               May be less tolerant of USB3 SSC
```

8GFC modules are on the same hardware platform as 10GbE SR but with different CDR tuning. Try 10GbE SR first.

### Module Compatibility Test Protocol

Before committing to a module for production use, run this minimum test sequence:

```
1. Optical check (A2h):
   Confirm TX bias > 0, RX power within expected range, link margin > 3 dB.
   This tests the module optically but says nothing about USB3 compatibility.

2. USB3 enumeration:
   Connect USB3 device (storage or hub) through the fiber link.
   Confirm SuperSpeed (5000M) enumeration, not High Speed fallback.
   A High Speed fallback means SS link training failed.

3. Sustained transfer:
   Run a 1 GB transfer. Confirm > 300 MB/s, zero errors.
   This exercises SSC tracking and CDR stability under continuous load.

4. Cold start / re-enumeration:
   Power-cycle the USB3 device 10 times and confirm consistent SS enumeration.
   Some modules enumerate correctly once but fail on re-plug if the idle
   handling disrupts the CDR between enumerations.

5. Module swap:
   Repeat with a module from a different batch or different vendor.
   If behaviour differs, the module is a variable — document which modules pass.
```

A module that passes all five stages is validated for this application.


---

## Bill of Materials

| Qty | Part | Package | Function | Approx cost |
|-----|------|---------|----------|-------------|
| 1 | DS100BR111 | WQFN-24 | USB3↔SFP+ redriver | ~$10 |
| 1 | SFP+ cage | Standard edge | Module socket | ~$3 |
| 1 | MCP2221A | QFN-16 (MCP2221AT-I/ML) | USB→I2C bridge + GPIO | ~$1.50 |
| 1 | LD1117S33TR | SOT-223 | 5V→3.3V LDO, 800mA | ~$0.40 |
| 1 | USB micro-B | Through-hole | Power + MCP2221A interface | — |
| 1 | USB3-A | Through-hole | SuperSpeed data connector | — |
| 3 | JP1, JP2×2 | 3-pin 2.54mm | Host/remote role select (JP2 is a pair) | — |
| 7 | 1 kΩ 0402 | — | DS100BR111 pin-mode resistors | — |
| 1 | 10 kΩ 0402 | — | RESET# pull-up (MCP2221A) | — |
| 2 | 4.7 kΩ 0402 | — | I2C bus pull-ups (SDA, SCL) | — |
| 2 | 10 kΩ 0402 | — | LOS pull-up + MOD_ABS pull-up | — |
| 2 | 330 Ω 0402 | — | GP0/GP1 series protection (MCP2221A) | — |
| 2 | 10 Ω 0402 | — | SFP+ VCC_RX / VCC_TX series | — |
| 8 | 100nF 0402 | — | DS100BR111 CML AC coupling | — |
| 9 | 100nF 0402 | — | Decoupling (see consolidated reference) | — |
| 4 | 10µF 0805 | — | Bulk decoupling (LDO in/out, DS100BR111 VIN, MCP2221A VDD) | — |
| 1 | LED green | 0805 | PWR indicator | — |
| 1 | LED red | 0805 | LOS indicator | — |
| 1 | LED green | 0805 | SPARE (DNP on first build) | — |
| 1 | 1 kΩ 0402 | — | PWR LED current limit | — |
| 2 | 330 Ω 0402 | — | LOS LED + SPARE LED current limit | — |
| 1 | SFP+ module | — | Finisar FTLX8571D3BCL preferred | ~$5–15 |

**Total active ICs: 2 (DS100BR111 + MCP2221A)**  
**Microcontroller: not required**  
**Firmware: not required on board — MCP2221A driven entirely from host Python**  
**EEPROM: not required — configuration is fully defined by pin-strap resistors**

---

## PCB Layout Rules

Non-negotiable for reliable USB3 SuperSpeed operation:

```
Differential pair impedance:     100Ω ± 10% on all SS and CML pairs
USB3 connector to DS100BR111:    maximum 25mm trace length
DS100BR111 to SFP+ cage:         maximum 15mm trace length
AC coupling cap placement:       within 2mm of DS100BR111 CML pins
Ground plane:                    continuous, unbroken — no splits,
                                 no vias crossing under differential pairs
DS100BR111 thermal pad:          minimum 4 GND vias through DAP
VDD pins 21/22:                  decoupling caps only — no supply connection
VIN pin 15:                      100nF + 10µF, closest caps on board
```

---

## Prototype Validation Sequence

### Step 1 — Board Power-On

```
Power board via micro-B (JP1 set to remote/micro-B role for bench work).
Check PWR LED lit.
Measure 3.3V rail at test point.
Confirm < 500 mV ripple.
```

### Step 2 — MCP2221A Enumeration

```
Connect micro-B to laptop.
Confirm MCP2221A appears as USB HID device (and CDC COM port).
Linux: lsusb shows "Microchip Technology, Inc. MCP2221"
Run: python -c "import EasyMCP2221; print(EasyMCP2221.Device())"
Expected: device object with no errors.
```

### Step 3 — SFP+ Module Identity (A0h)

```
Insert SFP+ module into cage.
Read A0h via MCP2221A:
  mcp.I2C_read(0x50, 16, reg=20)
Verify vendor name and part number.
Confirms: module seated, I2C bus working, DDM supported.
```

### Step 4 — Laser Enable and TX Power (A2h)

```
Confirm GP0 (TX_DISABLE) is LOW (laser enabled — default after power-on).
Read A2h: mcp.I2C_read(0x51, 10, reg=96)
Bytes 0–1: temperature (°C × 256)
Bytes 4–5: TX bias current (2 µA/LSB) — non-zero confirms laser firing
Bytes 6–7: TX output power (0.1 µW/LSB) — convert to dBm, verify in spec
```

### Step 5 — Fiber Insertion and RX Power

```
Connect OM3 LC duplex patch between both boards.
Read A2h on both boards.
Bytes 8–9: RX input power (0.1 µW/LSB) — convert to dBm.
Calculate link margin = RX power − module sensitivity (−11.1 dBm typical).
Healthy: > 3 dB margin on both ends.
LOS LED should extinguish on both boards when fiber is connected.
```

### Stage 1 — Copper DAC Cable (No Fiber)

```
Replace SFP+ modules with a passive SFP+ DAC cable (1m).
Connect USB3 device (storage drive or hub) to far end.
Verify USB3 enumeration through redriver pair.
Run sustained transfer: > 300 MB/s, 1 GB+ with zero errors.
Pass: clean enumeration, full USB3 bandwidth, no errors.
```

### Stage 2 — Optical Link

```
Replace DAC cable with two SFP+ modules + OM3 fiber patch.
Run pre-enumeration A2h checks (Steps 4–5 above).
Verify link margin > 3 dB both ends and LOS LEDs dark.
Connect USB3 device and repeat Stage 1 tests through fiber.
Pass: identical results to Stage 1.

Troubleshooting priority:
  1. Check A2h optical power first — separates optical from USB3 problems
  2. If optical power good but USB3 fails at High Speed: SS link training failed.
     Check EQB resistors. Swap to a known-good module vendor before other steps.
  3. If SS enumerates but is unstable: SSC tracking suspect — try 10GbE SR
     modules from Finisar or Avago before adjusting redriver settings
  4. If SS is stable but throughput is low: check for SS→HS fallback under load,
     then revisit EQ and DEM settings
```

---

## Related Design Constraints

### USB2 Lines

The USB2 differential pair (D+/D−) is deliberately omitted from the fiber data
path. USB2 is a conducted EMI source that would compromise the antenna unit's
noise floor. The FX3 enumerates via SuperSpeed only. This requires FX3 firmware
configured for SuperSpeed-only enumeration and no USB2 fallback in the fiber link.
This is intentional, not an oversight.

### DFU Firmware Loading

USB DFU for FX3 operates over USB2 and is unavailable through the fiber link.
The production antenna unit must boot firmware from SPI NOR flash:

```
Required on antenna PCB:
  SPI NOR flash (e.g. W25Q32 or equivalent)
  6-pin SPI programming header (externally accessible)
  Optional: direct USB connector for bench development (disconnect before field use)
```

See AN76405 (Cypress/Infineon) for FX3 SPI boot implementation details.

---

## What Does Not Require Configuration

| Function | Status |
|----------|--------|
| Redriver initialization sequence | Not required at runtime — pin straps are read once at power-on |
| SFP+ management interface (I2C) | Not required for data transport — used only for diagnostics |
| Clock or timing input to redriver | Not required |
| Reset sequence beyond power-up | Not required |
| Microcontroller | Not required |
| Firmware | Not required on the board |
| USB protocol awareness | Not required — DS100BR111 is protocol-agnostic |
| EEPROM | Not required — pin straps provide complete configuration |

The DS100BR111 is protocol-transparent. It does not know it is carrying USB3
SuperSpeed. USB3 link negotiation occurs entirely between the FX3 and the host
controller — the redriver is invisible to that process.

---

## Dev Board vs Production Circuit Comparison

| Feature | Dev Board | Production Minimum |
|---------|-----------|-------------------|
| Power input | USB micro-B VBUS (via JP1/JP2) | Dedicated 5V supply |
| 3.3V generation | LD1117S33TR LDO (~0.8W dissipated as heat) | Synchronous buck regulator preferred |
| Board roles | Host or remote, jumper-selected | Dedicated single-role PCB |
| DS100BR111 config | Pin-strap resistors (identical to production) | Pin-strap resistors |
| SFP+ management | MCP2221A I2C + GPIO | Not required — TX_DISABLE tied low |
| LOS monitor | SFP+ RX_LOS → MCP2221A GP1 + LED | Optional LED direct from RX_LOS |
| Diagnostics | Full EasyMCP2221 Python + A2h DDM | A2h readable if I2C wired |
| USB3 data path | Identical | Identical |

The USB3 SuperSpeed data path is **identical in both cases**. The dev board
additions are entirely orthogonal to the signal being transported. A validated
dev board fully validates the production signal path.

---

## JP1 / JP2 Jumper Wiring Detail

Both jumpers are 3-pin 2.54mm headers with a single shorting block selecting one of two positions.

```
JP1 — VBUS source (powers the LD1117S33TR input)

  Pin 1 ── USB3-A VBUS
  Pin 2 ── LDO_IN (common, connects to LD1117S33TR input)
  Pin 3 ── micro-B VBUS

  Shorting pins 1-2: host role (USB3-A VBUS powers board)
  Shorting pins 2-3: remote role (micro-B VBUS powers board)

JP2 — MCP2221A USB2 D+/D- source

  Pin 1 ── USB3-A USB2 D+ (or D-)
  Pin 2 ── MCP2221A D+ (or D-) (common)
  Pin 3 ── micro-B D+ (or D-)

  Shorting pins 1-2: host role (USB3-A USB2 pair to MCP2221A)
  Shorting pins 2-3: remote role (micro-B D+/D- to MCP2221A)

JP2 is a pair of 3-pin headers — one for D+, one for D-.
Both must be shorted in the same position at all times.
Silk screen must label positions: pin 1 = HOST, pin 3 = REMOTE.
```

Board must not be powered with either jumper uninstalled.

---

## Consolidated Decoupling Reference

All capacitors are ceramic unless noted. Place all caps on the same side of the PCB as their associated IC, as close to the relevant pin as the package allows.

```
Location                      Cap       Note
----------------------------  --------  ------------------------------------------
DS100BR111 VIN (pin 15)       100nF     Within 1mm of pin. Primary supply bypass.
DS100BR111 VIN (pin 15)       10µF      Within 5mm. Bulk.
DS100BR111 VDD (pin 21)       100nF     NOT connected to supply — decoupling only.
DS100BR111 VDD (pin 22)       100nF     NOT connected to supply — decoupling only.
DS100BR111 INA+ coupling      100nF     0402. Within 2mm of pin 24, DS100BR111
                                        side. Module provides internal AC coupling;
                                        these caps are redundant but retained.
DS100BR111 INA- coupling      100nF     0402. Within 2mm of pin 23, DS100BR111 side.
DS100BR111 INB+ coupling      100nF     0402. Within 2mm of pin 11, DS100BR111 side.
                                        FX3 has its own caps; double-coupling harmless.
DS100BR111 INB- coupling      100nF     0402. Within 2mm of pin 12, DS100BR111 side.
DS100BR111 OUTA+ coupling     100nF     0402. Within 2mm of pin 7, DS100BR111 side.
DS100BR111 OUTA- coupling     100nF     0402. Within 2mm of pin 8, DS100BR111 side.
DS100BR111 OUTB+ coupling     100nF     0402. Within 2mm of pin 20, DS100BR111 side.
                                        REQUIRED by SFF-8431 — TD-side coupling is
                                        the host board's obligation, not the module's.
DS100BR111 OUTB- coupling     100nF     0402. Within 2mm of pin 19, DS100BR111 side.
                                        Same — SFF-8431 mandated.
MCP2221A VDD (pin 1)          100nF     Within 1mm of pin.
MCP2221A VDD (pin 1)          10µF      Within 5mm. Bulk.
MCP2221A VUSB (pin 12)        100nF     Required. VUSB is LDO output — do not
                                        connect to supply, cap to GND only.
LD1117S33TR input             100nF     Within 2mm of input pin.
LD1117S33TR input             10µF      Electrolytic or tantalum acceptable.
LD1117S33TR output            100nF     Within 2mm of output pin.
LD1117S33TR output            10µF      Required for LDO stability.
SFP+ VCC_RX (cage pin 15)     100nF     After 10Ω series resistor.
SFP+ VCC_TX (cage pin 16)     100nF     After 10Ω series resistor.
```

---

## Schematic Review Checklist

Work through this list against the schematic before sending for layout.

**Power and ground:**
- [ ] LD1117S33TR: input connected to JP1 pin 2 (LDO_IN). Output is 3.3V rail. ADJ pin not present on fixed-voltage variant — confirm correct part number ordered.
- [ ] DS100BR111 VIN (pin 15): connected to 3.3V rail with 100nF + 10µF to GND.
- [ ] DS100BR111 VDD (pins 21, 22): each has 100nF to GND. No connection to 3.3V rail. This is the single most common DS100BR111 schematic error.
- [ ] DS100BR111 VDD_SEL (pin 16): tied directly to GND. Not floated.
- [ ] DS100BR111 DAP (thermal pad): connected to GND net. Appears as a symbol pin or via annotation in KiCAD — confirm it is not floating.
- [ ] MCP2221A VDD (pin 1): connected to 3.3V rail with 100nF + 10µF to GND.
- [ ] MCP2221A VUSB (pin 12): 100nF to GND only. Not connected to 3.3V rail.
- [ ] MCP2221A VSS (pin 11): connected to GND. EP (exposed pad) also to GND, with minimum 4 vias.
- [ ] SFP+ VCC_RX (pin 15) and VCC_TX (pin 16): each has 10Ω series resistor from 3.3V rail, then 100nF to GND at cage pin.
- [ ] All SFP+ VEE pins (1, 10, 11, 14, 17, 20): connected to GND.

**DS100BR111 pin-mode resistors:**
- [ ] ENSMB (pin 3): 1kΩ to GND.
- [ ] MODE (pin 18): 1kΩ to VIN (3.3V rail). Not to VDD.
- [ ] EQA0 (pin 10): 1kΩ to GND.
- [ ] EQA1 (pin 9): 1kΩ to GND.
- [ ] EQB0 (pin 1): 1kΩ to GND.
- [ ] EQB1 (pin 2): no connect / 4-level footprint, no resistor loaded.
- [ ] DEMA (pin 4): 1kΩ to GND. Confirm this pin is NOT connected to SDA. Check pin number against chosen schematic symbol.
- [ ] DEMB (pin 5): 1kΩ to GND. Confirm this pin is NOT connected to SCL. Check pin number against chosen schematic symbol.
- [ ] VOD_SEL (pin 17): no connect / float.
- [ ] SD_TH (pin 14): no connect / float as starting point. Populate as 4-level footprint (20 kΩ to GND pad present but DNP). This is a first-order bring-up adjustment point — see Bring-Up Adjustment Path.
- [ ] TX_DIS (pin 6): GND direct.
- [ ] VDD_SEL (pin 16): GND direct.
- [ ] LOS (pin 13): unconnected. DNP 10kΩ pull-up footprint to 3.3V present but not loaded.

**AC coupling — DS100BR111 CML paths:**
- [ ] INA+ (pin 24): 100nF in series, cap placed on IC side of the differential pair.
- [ ] INA- (pin 23): 100nF in series, cap placed on IC side.
- [ ] INB+ (pin 11): 100nF in series, IC side.
- [ ] INB- (pin 12): 100nF in series, IC side.
- [ ] OUTA+ (pin 7): 100nF in series, IC side.
- [ ] OUTA- (pin 8): 100nF in series, IC side.
- [ ] OUTB+ (pin 20): 100nF in series, IC side.
- [ ] OUTB- (pin 19): 100nF in series, IC side.

**I2C bus:**
- [ ] MCP2221A SDA (pin 10): connected to SFP+ cage SDA (pin 4). 4.7kΩ pull-up to 3.3V on the bus.
- [ ] MCP2221A SCL (pin 9): connected to SFP+ cage SCL (pin 5). 4.7kΩ pull-up to 3.3V on the bus.
- [ ] No other devices on the I2C bus. DS100BR111 SDA/SCL pads are DEMA/DEMB in pin mode — not connected to bus.

**MCP2221A GPIO:**
- [ ] GP0 (pin 2): 330Ω series to SFP+ TX_DISABLE (cage pin 3).
- [ ] GP1 (pin 6): 330Ω series from SFP+ RX_LOS (cage pin 8). Also connects to LOS LED (330Ω to LED to GND) and 10kΩ pull-up to 3.3V.
- [ ] GP2 (pin 7): footprint only. No active connection. 330Ω series to spare LED footprint if populated.
- [ ] GP3 (pin 8): footprint only. No active connection.
- [ ] RESET# (pin 3): 10kΩ pull-up to 3.3V.
- [ ] UARTRX (pin 4): unconnected.
- [ ] UARTTX (pin 5): unconnected.

**Jumpers:**
- [ ] JP1 pin 1: USB3-A VBUS. Pin 2: LDO input. Pin 3: micro-B VBUS.
- [ ] JP2 (pair): pin 1: USB3-A D+/D-. Pin 2: MCP2221A D+/D-. Pin 3: micro-B D+/D-.
- [ ] Both JP2 headers (D+ and D-) are always shorted in the same position.

**LEDs:**
- [ ] PWR LED: anode to 3.3V via 1kΩ, cathode to GND.
- [ ] LOS LED: anode to MCP2221A GP1 net (after 330Ω series from GP1 side), cathode to GND. Confirm polarity — LED must be OFF when RX_LOS is LOW (optical signal present).
- [ ] Spare LED footprint: 330Ω series to GP2. DNP.

**SFP+ cage ignored pins:**
- [ ] TX_FAULT (pin 2): unconnected.
- [ ] MOD_ABS (pin 6): footprint with 10kΩ pull-up to 3.3V, unconnected or to GP2/GP3 if desired.
- [ ] RS0 (pin 7), RS1 (pin 9): unconnected.

---

## PCB Layout Review Checklist

Work through this list against the layout before sending for fabrication.

**Stackup and impedance:**
- [ ] Confirm stackup with fab. For 100Ω differential impedance on a standard 4-layer stackup (1.6mm, 35µm copper, FR4), typical differential trace width/gap is ~0.2mm/0.2mm. Verify with fab's impedance calculator before routing.
- [ ] If using a 2-layer board: 100Ω differential is achievable but requires wider traces (~0.35mm/0.2mm) and a continuous GND pour on the bottom layer under all high-speed traces. 2-layer is not recommended — use 4-layer.
- [ ] All DS100BR111 CML pairs (INA, INB, OUTA, OUTB) routed at confirmed 100Ω ±10% differential impedance.
- [ ] USB3 SuperSpeed pair on USB3-A connector routed at 100Ω ±10%.

**Critical distance rules:**
- [ ] USB3-A connector to DS100BR111 INB/OUTA: ≤ 25mm total trace length per signal.
- [ ] DS100BR111 INA/OUTB to SFP+ cage: ≤ 15mm total trace length per signal.
- [ ] AC coupling caps: within 2mm of DS100BR111 pins, on the IC side of the pair (not the connector side).

**DS100BR111 land pattern and thermal:**
- [ ] WQFN-24 land pattern: confirm pad dimensions against TI datasheet drawing. 4mm × 4mm body, 0.5mm pitch.
- [ ] DAP (thermal/ground pad): copper pour connected to GND plane through minimum 4 vias, recommended 9 (3×3 grid). Via drill ≥ 0.3mm, annular ring ≥ 0.15mm. Do not tent these vias.
- [ ] VDD pads (pins 21, 22): decoupling caps directly adjacent. No supply connection — confirm no accidental connection to 3.3V pour in the region.

**LD1117S33TR thermal:**
- [ ] SOT-223 exposed tab: copper pour on component layer, minimum 1cm², connected to GND plane through ≥ 4 vias. Tab is electrically GND.
- [ ] LDO placement: keep LDO thermal pour away from SFP+ VCC traces to avoid conducted thermal coupling.

**Ground plane:**
- [ ] Continuous unbroken GND plane on reference layer under all high-speed differential pairs. No splits, no slots, no vias crossing under pairs.
- [ ] GND stitching vias around the high-speed region perimeter (DS100BR111, SFP+ cage, USB3-A connector): ring of vias at ≤ 3mm spacing.
- [ ] SFP+ cage GND tabs: all tabs soldered to GND plane. Confirm footprint has GND pads for all cage tabs.
- [ ] DS100BR111 DAP vias connect to the same GND plane as the high-speed return path — not isolated copper island.

**Differential pair routing:**
- [ ] All CML pairs routed as coupled differential pairs throughout. No section where the two signals route independently.
- [ ] Length matching within each differential pair: ≤ 0.1mm skew between + and − traces.
- [ ] No 90° corners on high-speed traces. 45° chamfers or curved routing only.
- [ ] Pairs cross no other high-speed signals at right angles if possible. Where unavoidable, cross on different layers with GND layer between.
- [ ] No vias on INA, INB, OUTA, OUTB pairs if avoidable. If vias are required, use matched via pairs (one per conductor) with GND vias alongside.

**AC coupling caps:**
- [ ] Cap footprint orientation: cap body on the IC side of the pair, stub toward the connector. Placing the cap on the wrong side puts the stub between the cap and the IC input — the stub is unmatched and radiates.
- [ ] Cap GND reference: no GND via or pad between the differential pair — GND below the pair on reference plane only.

**MCP2221A and I2C:**
- [ ] I2C traces (SDA, SCL): low-speed, no impedance control required. Route after high-speed pairs. Keep away from high-speed region.
- [ ] Pull-up resistors: place close to MCP2221A, not at SFP+ cage end.
- [ ] GP0/GP1 330Ω series resistors: place close to MCP2221A pins, not at SFP+ cage.

**LEDs and indicators:**
- [ ] PWR LED: visible from board edge or top. Not obstructed by SFP+ module when inserted.
- [ ] LOS LED: same.
- [ ] LED current-limit resistors: between supply/signal and LED anode, not between cathode and GND.

**Mechanical:**
- [ ] SFP+ cage: confirm footprint matches selected cage. Cage locking tabs (if present) have corresponding PCB notches.
- [ ] USB3-A connector: strain relief pads present and connected to GND.
- [ ] micro-B connector: strain relief pads present and connected to GND.
- [ ] JP1 and JP2 silk screen: clearly labels HOST and REMOTE positions. Both jumpers on same side of board, accessible without removing SFP+ module.
- [ ] Test points: 3.3V rail, GND, and SDA/SCL exposed as test points accessible with a probe.

---

*Document covers the fiber link board only. For full antenna unit integration including ADC, LMK61xx clock, power supply filtering, and GPSDO interface, see companion design documents.*

