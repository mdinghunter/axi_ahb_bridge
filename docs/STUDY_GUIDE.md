# AXI4 → AHB-Lite Bridge: A Study Guide

**Target:** a synthesizable AXI4 subordinate → AHB-Lite manager bridge, 32-bit both sides,
single outstanding transaction, single clock domain, with a self-checking randomized
testbench and FPGA bring-up on a Nexys A7-100T.

**Audience:** you. Strong on SystemVerilog RTL. New to AMBA, new to verification
methodology, new to formal/SVA.

**Budget:** ~10 full working days.

**Purpose:** portfolio / interview defensibility.

**Toolchain:** **QuestaSim** for simulation on **Linux / bash**, with a **full UVM
environment** (Questa's bundled UVM, `-L mtiUvm`); Vivado 2025.2.1 for synthesis,
implementation, and bitstream on `xc7a100tcsg324-1`.

**Ground rule:** this document contains no RTL. Formulas and 3-line pseudocode appear only
where a formula genuinely needs one. Every line of the design is yours.

---

## How to read this document

Sections 0–3 you should read end-to-end before writing anything — maybe 3 hours. Section 4
is the reason this project is worth doing; read it once now and re-read the relevant
subsection at the start of each stage. Sections 5–7 you will use continuously. Section 9 is
your exit exam: if you cannot answer those questions from your own design at the end, the
project did not do its job.

Scattered through the document you will find **[PUSH BACK]** markers. Those flag places
where I made a judgment call that a reasonable engineer could make differently. Treat them
as invitations, not decoration — the ability to say "I chose X over Y and here is why" is
most of what separates a portfolio project from a tutorial you followed.

---

## Section 0 — Environment and toolchain

Decisions here are cheap today and expensive in a week.

### 0.1 The split toolchain

Two tools, two jobs, and they do not overlap:

- **QuestaSim** owns simulation: compile, elaborate, run, assertions, coverage, waveforms.
  Vivado's XSim is not used at all.
- **Vivado 2025.2.1** owns synthesis, implementation, timing/utilization reports, and the
  bitstream for the Nexys A7-100T (`xc7a100tcsg324-1`).

That Vivado version number is still load-bearing even though you are not simulating with it.
Starting with **Vivado 2026.1 (June 2026)**, AMD retired the free Vivado ML Standard Edition
and replaced it with a tiered Basic / Core / Pro model. You are on 2025.2.1, which predates
that change. **Do not upgrade Vivado during this project, and archive your installer.** If
you ever need to reinstall, the free 2025.2 Standard Edition comes from the AMD download
*archive*, not the main downloads page. Artix-7 100T is comfortably inside free-edition
device support, so you will not hit a device-license wall at synthesis.

Questa's licensing is whatever your institution gives you. Two things to confirm on day zero,
because both change what you can claim in Section 7:

1. **Does your license include the covergroup/functional-coverage feature?** Some university
   bundles are code-coverage-only. Check by compiling a trivial covergroup and running
   `vsim -coverage`; if functional coverage is licensed out, you will find out in one minute
   instead of on day 8.
2. **Do you have QVIP (Questa Verification IP)?** This decides §5.5. Most university licenses
   do not include it.

### 0.2 Day-zero smoke test

Questa is a full-featured commercial simulator. Unlike XSim, you do **not** need to probe for
missing SystemVerilog features — classes, constraints, covergroups, the full SVA property
language including named properties, property instantiation, `implies`/`iff`, `nexttime`,
`s_eventually`, `followed-by` (`#-#`, `#=#`), sequence local variables, and `disable iff` all
work. Write assertions the way the LRM says to.

What you *do* need to prove on day zero is your **command line and your coverage flow**, on a
file where the tool is the only variable. Timebox it to 20 minutes:

```bash
vlib work
vlog -sv smoke.sv
vopt -o smoke_opt smoke_tb +acc +cover=bcefsx
vsim -c -coverage smoke_opt -do "run -all; coverage save smoke.ucdb; quit"
vcover report -details smoke.ucdb
```

Put one covergroup in `smoke.sv` with a coverpoint you know must reach 100%, one
`assert property` with `|->`, and one named property instantiated twice. You are not checking
the coverage number — you know what it will be. You are proving the whole chain works on your
install: that `vopt` is in the path, that the UCDB is written where you think, that
`vcover report` produces output. That chain is what produces the coverage figures in Section 7,
which is to say your actual portfolio claim.

Delete the file afterwards. It is a tooling probe, not an artifact, and the failure mode is
that it quietly grows into a mini-testbench you are attached to.

### 0.3 Repo layout and the command-line flow

Do not let a Vivado GUI project own your sources. The problem is not aesthetic:

- you cannot run a 200-seed regression from a GUI,
- you cannot diff or bisect a project file meaningfully,
- `.xpr` + `.cache/` + `.ip_user_files/` will fight your git history,
- and the thing an interviewer opens first is your repo, not your GUI.

Target layout:

```
axi_ahb_bridge/
  rtl/          your bridge, one module per file, nothing generated
  tb/
    agents/     axi_master_agent/, ahb_slave_agent/ (item, sequencer, driver, monitor, config)
    env/        environment, scoreboard, reference model, coverage subscriber
    seq/        sequence library (per-agent) and virtual sequences
    tests/      base test + one file per test
    sva/        bind-able checker modules and the property package
    top/        tb_top.sv, interfaces, clock/reset generation
  sim/          Makefile + Questa do-files + filelists (.f)
  fpga/         constraints (.xdc), the FPGA-only wrapper, build.tcl
  docs/         this file, your bug journal, your final writeup
  build/        gitignored: work/, *.ucdb, *.wlf, transcript, Vivado droppings
```

Drive simulation from a Makefile calling `vlib` / `vlog` / `vopt` / `vsim`. Drive synthesis
from a `build.tcl` in non-project mode (`read_verilog`, `synth_design`, `opt_design`,
`place_design`, `route_design`, `report_*`). Add a `.gitignore` covering `build/`, `work/`,
`transcript`, `*.wlf`, `*.ucdb`, `vsim.dbg*`, `*.jou`, `*.log`, and `.Xil/`.

**What "no GUI" does and does not mean.** It means the GUI must never *own* your sources —
files flow from the repo into the tools, never back. It does not mean you never open a window.
You will debug protocol bugs in the Questa waveform viewer, and refusing to is self-harm.
Launch it deliberately, on a failing seed, from a snapshot you built on the command line.

#### Linux / bash specifics

Questa is typically behind an environment module or a manual path prepend. Put whichever
applies in `~/.bashrc` — or better, in a `sim/env.sh` you source, so the repo documents its own
requirements:

Find out which UVM version your Questa actually ships **before you write any class code** —
UVM 1.2 and IEEE 1800.2 differ in enough small ways (`uvm_config_db` behavior, several
deprecations, `uvm_object` API details) that guessing wrong means chasing phantom errors for
an afternoon:

```bash
ls $(dirname $(which vsim))/../verilog_src/
```

Use *that* copy, not an Accellera drop you downloaded. Questa's bundled UVM is compiled
against its own DPI backend; mixing the two produces link errors whose messages point
nowhere near the actual cause.

```bash
module load questa        # or: export PATH=/tools/questa/bin:$PATH
export MGLS_LICENSE_FILE=<port>@<server>   # or LM_LICENSE_FILE, per your site
```

Sanity check with `which vsim vlog vopt vcover` and `vsim -version`. If `vsim` resolves but
the license does not, you get an error at `vsim` time, not `vlog` time — so run the §0.2 smoke
test all the way to `run -all` before you believe the environment is good.

Vivado is a separate environment. Source it only when you synthesize:

```bash
source /opt/Xilinx/2025.2.1/Vivado/settings64.sh
```

Do not source both in the same shell if you can avoid it — Vivado ships its own Tcl, and on
some sites the two installs fight over `LD_LIBRARY_PATH`. Two terminals, or two `env.sh`
scripts, is the cheap fix.

**Batch vs GUI, concretely:**

| Job | Command |
|---|---|
| Regression run | `vsim -c -coverage tb_opt -do sim/run.do` |
| One failing seed, waves | `vsim -gui -coverage tb_opt -do sim/wave.do` |
| Post-hoc wave viewing | `vsim -view build/run_1234.wlf` |
| Synthesis | `vivado -mode batch -source fpga/build.tcl` |

The post-hoc form matters more than it looks: log the `.wlf` for every regression run and you
can open a failure's waveform without re-running it, which turns a 200-seed nightly into
something you can actually debug the morning after.

**How to author `build.tcl` without knowing Tcl yet:** open the Vivado GUI once, perform the
step by hand, and read the Tcl Console — it echoes the exact command it just ran. That is using
the GUI as documentation rather than as a build system, and it is entirely legitimate.

**On `make`:** a Makefile earns its place at stage 1 under UVM — you immediately have a
multi-file class hierarchy, a `+UVM_TESTNAME` to vary, and a compile order that matters. This
is earlier than the hand-rolled plan needed it, and it is one of the few places where the UVM
decision makes something simpler rather than harder: the compile step stops being three
commands you retype and becomes one target you trust.

Keep it small. `compile`, `opt`, `run TEST=... SEED=...`, `regress`, `cov`. A Makefile with
pattern rules and auto-dependency generation before you have anything to build is
procrastination that feels like progress.

Initialize git **before** stage 1. Your commit history is a portfolio artifact — "fixed
1KB boundary comparator width" as a real commit with a real diff is worth more than a
polished final snapshot.

### 0.4 Six more decisions that are cheap now

1. **Parameterize both data widths** — `AXI_DATA_W` and `AHB_DATA_W` — even though you will
   set both to 32 and never change them in this project. Width conversion becomes a later
   stage rather than a rewrite, and the parameter forces you to write width-relative
   expressions instead of hardcoded `[31:0]` and `4'b1111`, which is where the unmaintainable
   version of this design comes from.
2. **Plumb `AWID`/`ARID` end to end** and return them on `BID`/`RID`, even with one
   transaction in flight. The ID path is not the hard part; discovering on day 12 that you
   have nowhere to put it is.
3. **One reset convention, everywhere.** Pick active-low, asynchronously asserted,
   synchronously de-asserted, and use the same name and polarity on both interfaces.
   AXI uses `ARESETn`, AHB uses `HRESETn` — decide now whether you tie them together
   (you do, single clock domain) and document it.
4. **SystemVerilog interfaces in the testbench, flat ports on the DUT.** Interfaces make the
   TB clean and give you a natural place to hang assertions and clocking blocks. Flat ports
   on the DUT keep synthesis and any future IP packaging simple, and keep your bridge usable
   by someone who doesn't have your interface files.
5. **`logic` only; `always_ff` / `always_comb` only.** No `reg`, no `wire`, no bare `always`.
   You already know why; the point is to decide once so you never mix.
6. **Seed discipline from the first randomized test.** `vsim -sv_seed <N>`, seed passed in
   from the Makefile, seed printed in the log banner, seed in the `.wlf` and `.ucdb`
   filenames, failing seeds recorded in the bug journal. A randomized failure you cannot
   reproduce is not a finding, it's a rumor.

### 0.5 Your on-board AXI master problem

Artix-7 has no processing system. There is no free AXI master on your board the way there
would be on a Zynq. You have two options, and you should decide now because it shapes the
`fpga/` wrapper:

- **A hand-written RTL traffic generator / BIST.** A small FSM that walks a fixed program of
  transactions (the same directed corner cases from your sim), drives your bridge's AXI
  port, checks results against expected values, and reports pass/fail on an LED plus a
  detailed log over UART. Cheap — maybe half a day — and it demonstrates exactly the thing
  you want to demonstrate.
- **MicroBlaze + AXI interconnect.** Real, more impressive-sounding, and free in Vivado on
  Artix-7. But it pulls in block design, software build flow, and a whole second debugging
  surface. Budget a full day minimum, realistically two.

**Recommendation: the traffic generator.** Take MicroBlaze as a stretch goal only if you
finish stage 9 early. **[PUSH BACK]** if your target roles are SoC-integration flavored
rather than RTL/DV flavored, the MicroBlaze path demonstrates something the traffic
generator doesn't, and may be worth the schedule risk.

---

## Section 1 — Domain concepts and vocabulary

### 1.1 Terminology, including the rename

ARM renamed master/slave to **Manager/Subordinate** in AMBA 5 (AXI IHI0022 Issue H onward,
AHB IHI0033 Issue C). Older documents, all existing RTL, and the signal names themselves
(`AWID`, `HMASTLOCK`) use the old terms. Use the new terms in your prose and the old ones
where the signal names force it, and be unbothered when sources mix them. Interviewers will
mix them too.

Words you need to use precisely, because sloppiness here *causes bugs*:

- **Transfer / beat** — one data item, one `VALID`+`READY` handshake on AXI, one data phase
  on AHB.
- **Burst** — a sequence of beats sharing one address command.
- **Transaction** — on AXI, the whole thing: address command + all data beats + response.
- **Address phase / data phase** — AHB only. They are *different cycles* for the same beat.
  This is the single most important sentence in this section.

### 1.2 AXI4, in one page

Five completely independent channels: **AW** (write address), **W** (write data), **B**
(write response), **AR** (read address), **R** (read data). Independent means exactly that
— there is no fixed timing relationship between them beyond a small set of ordering rules.

Every channel is a `VALID`/`READY` handshake. Transfer occurs on the rising edge where both
are high. Two rules that are violated constantly by beginners:

- A source must not wait for `READY` before asserting `VALID`. Concretely: `VALID` must not
  be combinationally derived from `READY`. A destination *may* wait for `VALID` before
  asserting `READY`.
- Once `VALID` is asserted it must remain asserted, with payload held stable, until the
  handshake completes. No withdrawing an offer.

Address command fields you care about: `AxADDR`, `AxLEN` (beats minus one), `AxSIZE`
(log2 of bytes per beat), `AxBURST` (FIXED / INCR / WRAP), `AxID`. Fields you will tie off
or ignore for this project: `AxCACHE`, `AxPROT`, `AxQOS`, `AxREGION`, `AxLOCK`, `AxUSER`.

Burst limits in AXI4 specifically: INCR up to 256 beats; WRAP restricted to 2, 4, 8, or 16
beats; FIXED up to 16 beats. A burst must not cross a **4KB** address boundary.

Responses: **one `BRESP` for an entire write burst**; **one `RRESP` per read beat**, with
`RLAST` on the final beat. The asymmetry matters enormously — see §4.6.

`WSTRB` carries one byte-enable per data byte and may be **non-contiguous**. That fact will
cost you a day if you don't plan for it — see §4.7.

### 1.3 AHB-Lite, in one page

One manager, one address bus, one data bus, one clock. Where AXI is five parallel
conversations, AHB is a single two-stage pipeline:

```
cycle:        0        1        2        3        4
address ph:  [A0]     [A1]     [A2]     [A3]
data phase:           [D0]     [D1]     [D2]     [D3]
```

The address phase of beat N+1 overlaps the data phase of beat N. `HREADY` low stretches
*both* phases in the same cycle — the current data phase and the pending address phase.

Signals: `HADDR`, `HTRANS[1:0]`, `HBURST[2:0]`, `HSIZE[2:0]`, `HWRITE`, `HWDATA`, `HRDATA`,
`HREADY`, `HRESP`, `HSEL`.

`HTRANS`: `IDLE` (00), `BUSY` (01), `NONSEQ` (10), `SEQ` (11). `NONSEQ` starts a burst;
`SEQ` continues one; `BUSY` is the manager saying "I'm not ready with the next beat, hold
the burst open"; `IDLE` means no transfer.

`HBURST`: `SINGLE`, `INCR` (undefined length), `WRAP4`, `INCR4`, `WRAP8`, `INCR8`,
`WRAP16`, `INCR16`. Note what is *not* there: there is no `INCR7`, no `INCR32`, no
`WRAP3`. AHB offers you exactly one variable-length option and it is undefined-length
`INCR`.

Constraints that will bite you:

- A burst must not cross a **1KB** address boundary. (Not 4KB. AHB is stricter than AXI
  here, and this asymmetry is the entire reason §4.4 exists.)
- `HADDR` must be aligned to `HSIZE`. A halfword transfer must be at an even address.
- `BUSY` must not be the final transfer of a burst. For fixed-length bursts a `BUSY` must be
  followed by a `SEQ` within the same burst.
- The subordinate cannot refuse a transfer. It can only insert wait states via `HREADY` or
  signal `ERROR` on `HRESP`. There is no backpressure channel from subordinate to manager
  in the AXI sense.
- `ERROR` is a **two-cycle response**: first cycle `HREADY` low with `HRESP` = ERROR, second
  cycle `HREADY` high with `HRESP` = ERROR. The manager gets one cycle of warning, during
  which it may change `HTRANS` to `IDLE` to cancel the rest of the burst.

AHB-Lite (IHI0033 Issue A) has **no write strobes**. Byte enables are expressed only as
`HSIZE` + aligned `HADDR`. `HWSTRB` was added later, in AHB5 (Issue C). Assume you don't
have it.

### 1.4 The five impedance mismatches

Everything hard about this project is one of these. Learn them as a list; you will use it
to explain your design in an interview.

| # | AXI says | AHB says | Consequence |
|---|---|---|---|
| 1 | Address and data are independent channels | Address phase and data phase are pipeline stages of one bus | You must build the pipeline offset by hand, and every off-by-one lives here |
| 2 | Bursts up to 256 beats, any length, 4KB boundary | Fixed lengths 4/8/16 or undefined INCR, 1KB boundary | You must split and re-encode bursts |
| 3 | Reads and writes are simultaneous, independent | One shared bus, one direction at a time | You must arbitrate, and arbitration can deadlock |
| 4 | Arbitrary non-contiguous byte strobes | Alignment-derived byte enables only | Some legal AXI beats become multiple AHB transfers or none |
| 5 | One response per write burst; per-beat read responses; consumer can backpressure with `RREADY` | Response per beat; manager cannot be stalled once committed | You must aggregate errors, buffer read data, and never commit before you can follow through |

---

## Section 2 — The spec subset that matters, and the exact right version

### 2.1 Get the right AXI document — this one is a trap

The current AXI specification is **not** what you want.

ARM IHI0022 **Issue J (March 2023) removed AXI3, AXI4, and AXI4-Lite from the document
entirely.** Issue J, K, and L specify AXI5-class interfaces only. If you download "the
latest AMBA AXI spec" you will get a document that does not contain the protocol you are
implementing, and you will waste real time before you notice.

**You want IHI0022 Issue H (specifically H.c)**, titled *AMBA AXI and ACE Protocol
Specification*. It is the last issue that fully specifies AXI3, AXI4, and AXI4-Lite. Get it
from ARM's site (free, account required) and keep a local copy — ARM has been moving
`developer.arm.com` documentation URLs to `support.arm.com`, and links rot.

What to read in Issue H, and what to skip:

| Read | Why |
|---|---|
| Ch. A1 — Introduction, architecture overview | Channel model. 20 minutes. |
| **A3.1–A3.3 — Channel definitions and handshake rules** | The `VALID`/`READY` dependency rules. Read A3.3.1 twice. |
| **A3.4 — Transfer behavior: burst types, address calculation** | Contains the INCR/WRAP/FIXED address arithmetic and the 4KB rule. This is the mathematical core of §4.3. |
| A3.4.3 — Data read/write structure, `WSTRB` | Narrow transfers and byte lane rules. |
| A3.4.4 — Read/write response structure | `OKAY`/`EXOKAY`/`SLVERR`/`DECERR`, and the per-burst vs per-beat asymmetry. |
| **A4 — Transaction attributes** | Skim. You are tying off `AxCACHE`/`AxPROT`. |
| A5 — Transaction identifiers, ordering | Read the ordering rules even though you are single-outstanding. It is what makes your design extensible and it is a guaranteed interview question. |
| A6 — Ordering model | Skim. |
| A7 (Atomic/exclusive), A8 (AXI4-Lite), C-onward (ACE) | **Skip entirely.** |

### 2.2 Get the right AHB document — get two

- **IHI0033 Issue A** — *AMBA 3 AHB-Lite Protocol Specification v1.0* (2006). Short, tight,
  and it is exactly the protocol you are implementing. This is your primary reference. It is
  widely mirrored by universities, which is convenient, but prefer ARM's own copy so you
  know the revision.
- **IHI0033 Issue C** — *AMBA AHB Protocol Specification* (AHB5). This supersedes Issue A and
  covers both AHB-Lite and AHB5 in one document. Issue B introduced AHB5; Issue C added
  write strobes (`HWSTRB`), signal-width properties, user signaling, and parity protection.

Read Issue A cover to cover — it is genuinely short. Then read Issue C's sections on burst
operation and the 1KB rule, because the later document states some things more clearly than
the 2006 original.

Specifically, in the AHB document, the sections that matter:

- Transfer types (`HTRANS`) and the `BUSY` rules
- Burst operation, `HBURST` encodings, wrapping vs incrementing
- The 1KB boundary rule and its justification
- Address alignment vs `HSIZE`
- Wait states and `HREADY`
- The two-cycle `ERROR` response, and what a manager may do during it

### 2.3 Why AHB-Lite and not full AHB — and not AHB5

The names mislead. AHB-Lite is not a cut-down version of the current AHB; it is the
**ancestor** of it:

```
AMBA 2 (1999)   AHB        multi-manager, arbiter, SPLIT/RETRY, HRESP[1:0]   IHI0011A
                  |         (ARM removed the multi-manager machinery)
AMBA 3 (2006)   AHB-Lite   single manager, HRESP is 1 bit: OKAY / ERROR      IHI0033A
                  |         (ARM added features on top of AHB-Lite)
AMBA 5 (2015+)  AHB5       AHB-Lite + HWSTRB, HNONSEC, exclusives, multi-sel IHI0033B/C
```

This is why IHI0033 Issue C covers AHB-Lite and AHB5 in one document and states that "AHB"
refers to both. Full multi-manager AHB is not in the current specification at all.

**What full AHB adds, and why each addition is wrong for this project:**

| Feature | Signals | Problem |
|---|---|---|
| Arbitration | `HBUSREQ`, `HGRANT`, `HLOCK`, `HMASTER` | Belongs to the interconnect, not the bridge. You would be building two components. |
| `RETRY` response | `HRESP[1:0]` | "That transfer didn't happen — re-issue it." |
| `SPLIT` response | `HRESP[1:0]`, `HSPLITx` | Same, plus you now need an arbiter to talk to. |

`HRESP` shrinking from 2 bits to 1 is the tell: AHB-Lite exists because ARM deleted the two
responses meaning *"un-happen that transfer."*

That collides directly with AXI, which has no notion of an un-happening. Under `RETRY`, the
§4.7 commitment rule is not enough — your W buffer cannot pop on address-phase completion,
because you may have to drive the same beat again. You would need a **rewind point** across
the W buffer, the beat counter, the address generator, and the error latch. Same for losing
`HGRANT` mid-burst: resume from beat 6 of 12 with a fresh `NONSEQ`.

That is a genuinely interesting commit-vs-rollback problem, and it is the strongest argument
against my choice. I still say no, for four reasons: SPLIT/RETRY is dead technology and
invites "why?" rather than good follow-up questions; rollback support costs ~2 days taken
directly out of stages 5, 8 and 9; nothing you would plug into wants it (Cortex-M0/M0+/M3/M4
expose AHB-Lite, M23/M33 expose AHB5, and your board has no AHB fabric at all); and the
transferable half of the lesson is already in §4.7 — AXI solved this problem by making
commitment *safe* rather than reversible.

**The sharper question is AHB-Lite vs AHB5.** AHB5 has `HWSTRB` — real per-byte write
strobes. Target AHB5 and **§4.2 largely evaporates**: `WSTRB` maps straight to `HWSTRB`, and
the strobe-decomposition bug class disappears along with the `WSTRB`=0 hang.

I chose AHB-Lite *because* it lacks `HWSTRB`. The missing feature is what generates the bug
class, and §4.2 is one of the better ones — it punishes the assumption that equal data widths
imply a 1:1 beat mapping. That is a deliberate choice to make the project harder.

**[PUSH BACK]** — pick full AHB if you have a specific full-AHB subordinate to talk to, or if
you are targeting legacy-SoC work where SPLIT/RETRY literacy is an asset; if you want the
rollback problem, add a RETRY-capable mode *after* stage 9 rather than rebuilding on IHI0011A
from day 1. Pick AHB5 if interoperating with current IP matters more to you than the §4.2 bug
class — but then add width conversion to reclaim the difficulty you just removed.

### 2.4 Why AXI4 and not AXI5

The honest starting point: **ARM disagrees with this choice.** Their AMBA 5 material states
that AXI3 and AXI4 "are not recommended for new designs and have been superseded by the AXI5
interface." Three real advantages to going AXI5→AHB5:

1. You download the current specification instead of hunting for Issue H (§2.1).
2. ARM document 101375 describes an actual **AXI5-to-AHB5 bridge**. A reference functional
   description exists for exactly that pairing, and does not exist for AXI4→AHB-Lite.
3. It is the protocol ARM is actually investing in.

**The counter-argument is that AXI5's additions are orthogonal to what a bridge does.**

What AXI5 adds over AXI4: atomic transactions, cache stashing, wakeup signaling,
deallocating transactions, cache maintenance for persistence, and data poisoning/checking.
That list is coherency and system-level power/reliability machinery — it exists so AXI aligns
with CHI in coherent multi-core interconnects.

Now compare against what this bridge does: burst decomposition, 1KB boundary handling, the
two-stage pipeline offset, error aggregation, and the commitment rule. **The burst, handshake,
and ordering machinery is essentially unchanged between AXI4 and AXI5** — `AxLEN`, `AxSIZE`,
`AxBURST`, `WSTRB`, the 4KB rule, and the `VALID`/`READY` dependency rules are the same. Every
bug in Section 4 is the same bug. You would read several hundred additional pages of optional,
property-gated feature surface to build the same state machine, and a bridge to a simple
peripheral bus does not *implement* those features — it passes them through or declines them,
because AHB has no semantics for a stash hint or an atomic compare-swap.

Two concrete costs:

| Cost | Detail |
|---|---|
| Lose the learning ecosystem | ZipCPU, Spear, Verification Academy, forum threads, interview question banks — all AXI4. You would be learning a protocol *and* verification methodology with no scaffolding. |
| "AXI5" is ill-defined | It is a superset of optional features. Implementing it means implementing a *profile*, and hours go into deciding and documenting exclusions. That is spec-lawyering, not design. |

(On XSim this list had a third entry — Vivado's AXI VIP does not support AXI5 — but you are
not simulating in Vivado, so that cost does not apply to you. See §5.5.)

Plus market reality: AXI4/AXI4-Lite is what appears in existing RTL, AMD/Xilinx IP, and FPGA
job descriptions. AXI5 lives mostly in ARM's coherent interconnects and CPU IP.

**The hedge — do this, it is cheap.** Build AXI4→AHB-Lite, then spend two hours on IHI0022L's
introduction and change list, enough to say:

> AXI5's additions are coherency and system-level features. A bridge to a peripheral bus
> either passes them through or refuses them; AHB has no semantics for any of them. The burst
> decomposition, pipeline offset, and error aggregation problems are identical. The one AXI5
> feature I would genuinely want here is `AWAKEUP` for low-power handshaking.

That is most of the interview value for roughly 2% of the cost, and it is a better answer than
one from someone who implemented AXI5 without asking why.

**[PUSH BACK]** — go AXI5 if you are targeting ARM or CPU/coherent-interconnect IP companies,
where AXI5 literacy is the point. Also reasonable if having document 101375 as a checkable
reference for your exact pairing matters more to you than the ecosystem; having a reference to
check against is not cheating. My position that AXI4 is where production is and AXI5 is where
roadmaps are is a bet on the market, not a technical claim.

### 2.5 One more document worth having

ARM publishes documentation for an actual **AXI-to-AHB bridge** product (document 101375,
"AXI5 to AHB5 bridge"), including its functional description of 1KB boundary crossing. It
describes an AXI5→AHB5 bridge rather than AXI4→AHB-Lite, so do not copy its decisions
blindly, but it is useful as a sanity check on your architecture: when your design and
ARM's diverge, you should be able to say why.

Note one thing it does that you should consider: when a transaction crosses a 1KB boundary,
it converts to undefined-length `INCR` and drives `NONSEQ` on the first address after the
boundary. That is a real design pattern, not a hack.

---

## Section 3 — Architecture

### 3.1 Block diagram

```
                AXI4 SUBORDINATE PORT                              AHB-LITE MANAGER PORT
                  (HCLK, HRESETn)                                    (HCLK, HRESETn)

  AW  ==>+-------------+
         |             |    +--------------+    +---------------+   +--------------+
  AR  ==>|  CHANNEL    |==> |   COMMAND    |==> |    BURST      |==>|  AHB ADDRESS |==> HADDR
         |  ARBITER    |    |   DECODER    |    |   SEQUENCER   |   |  PHASE FSM   |==> HTRANS
         |             |    |  + SPLITTER  |    |               |   |              |==> HBURST
         | one cmd in  |    |              |    | - addr gen    |   | IDLE/NONSEQ/ |==> HSIZE
         | flight; R/W |    | - decode     |    | - beat count  |   | SEQ/BUSY     |==> HWRITE
         | priority    |    |   len/size/  |    | - INCR/WRAP/  |   |              |==> HSEL
         | policy      |    |   burst      |    |   FIXED math  |   +------+-------+
         +------+------+    | - 1KB split  |    | - last-beat   |          ^  |
                |           | - WSTRB ->   |    |   flag        |   HREADY |  | commit
                |           |   HSIZE/     |    +-------+-------+          |  v
                |           |   HADDR      |            |         +-------------------+
  W   ==>+------+------+    +------+-------+            |         |   DATA PHASE      |==> HWDATA
         |  W BUFFER   |           |                    |         |   ALIGNMENT       |
         |  (skid,     |===========+====================+========>|                   |<== HRDATA
         |   >= 1 beat |                                          | one cycle behind  |<== HRESP
         |   lookahead)|                                          | the address phase |<== HREADY
         +------+------+                                          +---------+---------+
                ^                                                           |
                |                                                           |
  B   <==+------+------+                                                    |
         |  RESPONSE   |<---------------------------------------------------+
  R   <==|  ASSEMBLER  |
         |             |
         | - RLAST gen |
         | - per-beat  |
         |   RRESP     |
         | - ONE BRESP |
         |   per burst |
         | - error     |
         |   latch     |
         | - R skid    |
         |   buffer    |
         +-------------+
```

### 3.2 What each block owns

**Channel arbiter.** Owns the decision of which AXI command — a pending `AW` or a pending
`AR` — gets the AHB bus next, and owns the guarantee that once chosen, that command runs to
completion before the other is considered. It also owns the *write-data readiness* gate:
see §4.7 for why an `AW` must not be granted purely because it arrived.

**Command decoder + splitter.** Owns translating one AXI command into a sequence of one or
more AHB-legal bursts. This block does the 1KB math and the `WSTRB` analysis. Its output
should be a clean internal command: start address, number of beats, transfer size, burst
encoding, and a flag saying whether this is the final sub-burst of the parent AXI
transaction. Getting that internal command struct right is most of the design.

**Burst sequencer.** Owns beat-by-beat address generation — INCR increment, WRAP
wraparound, FIXED repeat — and the beat counter that decides when to switch `HTRANS` from
`NONSEQ` to `SEQ` and when the burst ends.

**AHB address phase FSM.** Owns `HTRANS` and the commit semantics. Once this block drives
`NONSEQ` or `SEQ`, the bridge is contractually obligated to produce the corresponding data
phase next cycle. This is the block where "can I actually follow through?" must be answered
*before* the transition, not after.

**Data phase alignment.** Owns the one-cycle offset. For writes, it presents the correct
`HWDATA` in the cycle *after* its address phase, held stable while `HREADY` is low. For
reads, it captures `HRDATA` only on cycles where `HREADY` is high, and knows which
outstanding address phase that data belongs to.

**W buffer.** Owns decoupling AXI `WVALID` timing from AHB commitment. Minimum useful depth
is one beat of lookahead; see §4.7 for the argument.

**Response assembler.** Owns AXI response semantics: exactly `AWLEN+1` `R` beats with
`RLAST` on the last, per-beat `RRESP`, exactly one `BRESP` per write burst, error
stickiness across a split burst, and `R`-channel backpressure absorption.

### 3.3 The design decisions you must make, with my recommendations

**D1 — Fixed-length AHB bursts, or always undefined-length INCR?**

You can map an AXI INCR burst onto AHB either by greedily emitting `INCR16`/`INCR8`/`INCR4`
plus leftover singles, or by emitting a single undefined-length `INCR` burst
(`NONSEQ`, then `SEQ` for every subsequent beat, then `IDLE`).

**Recommendation: undefined-length `INCR`.** It is fully legal, it is what real bridges
including ARM's own do when splitting at boundaries, it removes an entire class of
"I promised 8 beats and delivered 6" bugs, and it costs you essentially nothing on a simple
subordinate. The greedy decomposition is the more impressive-sounding answer and the more
bug-dense one.

**[PUSH BACK]** — the counter-argument is real: some AHB subordinates optimize on knowing
the burst length in advance (prefetch, page-open policies in a memory controller), and
"my bridge always says INCR" is a legitimate criticism in an interview. The strong answer
is to implement undefined-length INCR, *know* that fixed-burst mapping exists, and be able
to describe exactly which bugs it would introduce. If you finish stage 9 early, implement
it as a compile-time parameter and you get a genuinely good talking point.

**D2 — How much write data do you buffer before committing the AHB address phase?**

Options: commit as soon as `AW` arrives (broken, see §4.7); require one `W` beat buffered
(sufficient); require the whole burst buffered (safe, high latency, needs a deep FIFO).

**Recommendation: one beat of lookahead.** Commit an address phase only when the data for
that beat is already in your buffer. This is the minimum correct answer and the one that
demonstrates you understand the hazard.

**D3 — Read/write arbitration policy.**

Options: fixed priority (reads first, or writes first), round-robin, or last-served-loses.

**Recommendation: round-robin between the two channels, with the write side additionally
gated on data availability.** Fixed priority is simpler but gives you a starvation story you
will have to defend. Whatever you choose, write down the argument for why it cannot
deadlock — that argument is §4.7 and it is worth a paragraph in your README.

**D4 — Do you register the AXI inputs?**

Registering `AW`/`AR`/`W` costs a cycle of latency and buys you timing margin and a much
easier time reasoning about combinational paths from AXI `VALID` to AHB `HTRANS`.

**Recommendation: register them.** On an Artix-7 at 100 MHz you probably don't need to, but
the combinational path from `HREADY` through your FSM to `HTRANS` and `HADDR` is the one
that will show up in your timing report, and keeping the AXI side clean makes that path
easier to see.

**D5 — What happens to the AHB bus between AXI transactions?**

`HTRANS` = `IDLE`, and you must decide whether `HADDR`/`HSIZE`/`HWRITE` hold their previous
value or go to a default. The spec doesn't care. Pick one, and make sure your assertions
don't accidentally check the don't-care value.

---

## Section 4 — Where the real bugs live

This is the section you asked for. Each subsection: what the problem is, why it is hard,
the math or structure it needs, the specific bugs you will hit, and how to test for it.

I have ordered these roughly by when they will hit you.

---

### 4.1 The pipeline offset

**What it is.** AHB's address phase for beat N+1 happens in the same cycle as the data phase
for beat N. Your bridge must maintain two pieces of state that advance at the same time but
refer to different beats.

**Why it's hard.** Every signal in your design is now implicitly tagged with "which pipeline
stage is this?" and nothing in the language reminds you. `HWDATA` belongs to the address
you drove *last* cycle. `HRDATA` belongs to the address you drove *last* cycle. `HREADY`
gates *both* stages simultaneously. The error response arrives two cycles after the address
phase that caused it.

**The structure it needs.** Think of it as a one-deep pipeline register carrying beat
metadata forward: when an address phase completes (`HREADY` high while `HTRANS` is
`NONSEQ`/`SEQ`), you shift that beat's context — is it a write, which AXI beat index it is,
whether it's the last beat, which byte lanes it covers — into a "data phase context"
register. The data phase logic consults *only* that register, never the current address
phase signals.

If you find yourself writing logic in the data phase that looks at `HADDR`, you have the
bug.

**Bugs you will hit:**

- `HWDATA` presented in the same cycle as its address. Your first AHB write will look
  plausible and write the wrong data or write nothing.
- `HWDATA` changing while `HREADY` is low. The address phase held correctly but the data
  phase didn't. Manifests as: works with a zero-wait-state subordinate, fails the moment
  you add wait states — which is why §5 insists you never test with `HREADY` tied high.
- Capturing `HRDATA` on a cycle where `HREADY` is low. You will capture garbage, and on
  real hardware or an X-propagating sim you will capture X.
- Advancing your AXI-side beat counter on the address phase instead of the data phase, so
  `RLAST` comes out one beat early.
- Not holding `HADDR`/`HTRANS`/`HSIZE`/`HBURST`/`HWRITE` stable while `HREADY` is low.
  This is an outright protocol violation and your AHB checker should catch it immediately.

**How to test for it.** An AHB subordinate BFM whose wait-state count is randomized per
transfer, including zero and including long stalls (say 0–7, with an occasional 15). Then
two assertions on the AHB interface: (a) when `HREADY` is low, every address-phase signal
is stable from the previous cycle; (b) when a data phase completes, the data corresponds to
the address phase that completed one "ready cycle" earlier — which you check with a
reference model, not an assertion.

Critically: run the *same* directed test at wait-states-always-zero and at
wait-states-random. If it passes the first and fails the second, you have a pipeline bug,
and knowing that shortcut saves you hours of debugging.

---

### 4.2 Non-contiguous and empty `WSTRB`

**What it is.** AXI hands you per-byte write enables. AHB-Lite has none — byte enables are
implied by `HSIZE` plus an aligned `HADDR`. So the bridge must express an arbitrary 4-bit
strobe pattern as a *sequence* of size/address pairs.

**Why it's hard.** Most people assume equal data widths means a 1:1 beat mapping. It does
not. Consider a 32-bit AXI write beat at address 0x1000:

| `WSTRB` | Meaning | Legal AHB expression |
|---|---|---|
| `1111` | all four bytes | one word transfer, `HSIZE`=word, `HADDR`=0x1000 |
| `0011` | low halfword | one halfword transfer at 0x1000 |
| `1100` | high halfword | one halfword transfer at 0x1002 |
| `0110` | middle two bytes | **not one transfer** — halfword at 0x1001 is unaligned. Two byte transfers, at 0x1001 and 0x1002 |
| `1010` | bytes 1 and 3 | two byte transfers, at 0x1001 and 0x1003 |
| `0000` | nothing | **zero AHB transfers**, but the AXI beat must still be consumed and counted |

So one AXI beat becomes zero, one, or up to four AHB transfers. Your beat counters on the
two sides are no longer the same counter.

**The math.** For a strobe pattern, the decomposition is: find maximal aligned power-of-two
runs of set bits. A run of length L starting at byte offset B within the beat is expressible
as a single transfer iff L is a power of two and B is a multiple of L. Otherwise split.
Greedy from the largest aligned run down to bytes always terminates and is always legal.

**Bugs you will hit:**

- Assuming `WSTRB` is always all-ones, because your first testbench only ever generates
  full-width aligned writes. This bug is invisible until you randomize strobes — which is
  the entire argument for §5.
- The `WSTRB` = 0 case hanging the bridge: you emit no AHB transfer, so your data-phase
  completion event never fires, so you never advance the beat counter, so `BVALID` never
  asserts.
- Emitting an unaligned `HADDR` for a halfword or word transfer. Your AHB checker must
  assert alignment against `HSIZE`; without that assertion this bug is silent because a
  simple BFM memory model will happily accept it.
- Getting the byte-lane mapping backwards: on a 32-bit AHB bus, a byte transfer at address
  0x1001 puts its data on `HWDATA[15:8]`, not `HWDATA[7:0]`. Little-endian byte lane
  placement is address-derived, and this is a classic.

**How to test for it.** Constrain your AXI write driver to generate `WSTRB` from a
distribution that deliberately includes all-ones (common), all-zeros (rare but present),
single bits, and non-contiguous patterns. Then check the *memory contents* in your
subordinate model byte-by-byte against a reference — including checking that bytes whose
strobe was low are **unchanged**, which a naive "did the write land" check misses entirely.

**[PUSH BACK]** — you could legitimately declare non-contiguous `WSTRB` out of scope and
respond `SLVERR`, or assume an upstream master that never generates it. That is a defensible
engineering decision if you *document* it. It is not defensible if you simply never thought
about it, and the difference is visible in an interview within about two questions.

---

### 4.3 Burst address arithmetic: INCR, WRAP, FIXED

**What it is.** Generating the address for beat N of an AXI burst, and mapping it onto AHB.

**Why it's hard.** INCR is easy and lulls you. WRAP has genuinely fiddly arithmetic. And
AXI permits the *first* beat of a burst to be unaligned while all subsequent beats are
aligned — a rule that quietly breaks the naive "address += size" loop.

**The math.**

Let `nbytes = 1 << AxSIZE` (bytes per beat) and `len = AxLEN + 1` (beats).

*INCR:*
```
aligned_addr  = AxADDR - (AxADDR mod nbytes)      // clear low AxSIZE bits
addr[0]       = AxADDR                            // first beat may be unaligned
addr[n]       = aligned_addr + n * nbytes         // for n >= 1
```

*WRAP:* `len` must be 2, 4, 8, or 16, and `AxADDR` must already be aligned to `nbytes`.
```
total_bytes    = len * nbytes
wrap_boundary  = AxADDR - (AxADDR mod total_bytes)
addr[n]        = wrap_boundary + ((AxADDR + n*nbytes - wrap_boundary) mod total_bytes)
```
Because `total_bytes` is a power of two, the `mod` is a bit mask — and the whole thing
reduces to "increment the low log2(total_bytes) bits, leave the upper bits alone." Which is
a much easier thing to implement than the formula suggests, and a much easier thing to get
subtly wrong if you don't derive it.

*FIXED:* `addr[n] = AxADDR` for all n. Maps to `len` repeated AHB `SINGLE` transfers, each
with `HTRANS` = `NONSEQ`. It cannot be an AHB `INCR` burst because the address doesn't
increment.

**Mapping to AHB `HBURST`:** WRAP4/8/16 on AHB requires the start address to be aligned to
the *total* wrap size, and requires the beat count to match exactly. If your AXI WRAP burst
satisfies those, you can pass it through as a matching AHB WRAP burst. If it doesn't — or if
you took decision D1 — you decompose it into the individual addresses and emit them as
undefined-length `INCR`... except that the addresses are not monotonically increasing, so
`INCR` is wrong. **A wrapped sequence emitted as separate transfers must use `NONSEQ` at
the wrap point**, or you have lied to the subordinate about the address relationship.

That last sentence is the trap in this subsection and I want you to sit with it: `SEQ` means
"this address is the previous address plus the transfer size." At the wrap point it isn't.

**Bugs you will hit:**

- Ignoring the unaligned-first-beat rule and computing `addr[1] = AxADDR + nbytes`, which is
  unaligned and therefore illegal on AHB.
- Computing the wrap mask from `nbytes` instead of `len * nbytes`.
- Emitting `SEQ` across the wrap point.
- Accepting a WRAP burst with `len` = 3 or 5 (illegal in AXI) and producing nonsense instead
  of an error. Decide whether you check for it; either answer is fine, silence isn't.
- Truncating the address arithmetic. If `AxADDR` is 32 bits and you compute an intermediate
  in fewer bits, you get wraparound at the wrong power of two — this is the same failure
  class as the 1KB comparator bug in §4.4.

**How to test for it.** Directed tests first: WRAP4 at the wrap boundary, WRAP4 one beat
before the boundary, WRAP16 with the largest size, INCR with a maximally unaligned start.
Then randomized, with your reference model computing the expected address sequence
independently — write the reference model from the spec formula, not by copying your RTL,
or you will simply confirm your own bug.

---

### 4.4 The 1KB boundary split

**What it is.** AHB forbids a burst from crossing a 1KB address boundary. AXI4 permits
bursts up to 4KB (it only forbids crossing 4KB). So a legal AXI burst can cross up to three
1KB boundaries and must be split into up to four AHB bursts.

**Why it's hard.** It is arithmetic on a boundary, which is where off-by-one lives; and the
split has protocol consequences beyond the address, because the first transfer after a split
must be `NONSEQ`, not `SEQ`.

**The math.**
```
bytes_to_boundary  = 1024 - (current_addr mod 1024)
beats_to_boundary  = floor(bytes_to_boundary / nbytes)
beats_this_subburst = min(beats_remaining, beats_to_boundary)
```
Then the next sub-burst starts at the boundary, with `HTRANS` = `NONSEQ`.

**Bugs you will hit — and one of these is a documented real-world bug:**

- **Comparator width.** `bytes_to_boundary` ranges from 1 to 1024 inclusive. 1024 does not
  fit in 10 bits. If you compute this in a 10-bit expression, the case where `current_addr`
  is exactly 1KB-aligned gives you 0 instead of 1024, and your bridge splits every burst
  into single beats — or worse, computes zero beats and hangs. This exact class of bug (a
  max-value comparison that silently wraps) has been found in shipped open-source AXI DMA
  code. It is worth being smug about catching, which means it is worth writing the directed
  test for it: **a burst starting exactly on a 1KB boundary.**
- Emitting `SEQ` on the first beat after the split. The address is discontinuous from the
  subordinate's perspective only in the sense that the burst ended — but if you left
  `HBURST` as a fixed-length encoding and continued with `SEQ`, you have violated the 1KB
  rule in fact even though your address arithmetic was right.
- Splitting correctly but forgetting that the AXI-side response aggregation spans the
  split: one AXI write burst that became three AHB bursts still returns exactly **one**
  `BRESP`. See §4.6.
- Computing the split from the *aligned* address instead of the actual first-beat address,
  or vice versa. Pick one and be consistent with §4.3.
- Applying the 1KB rule only to the first sub-burst. If the AXI burst is long enough,
  sub-burst 2 can also hit a boundary. The split must be a loop, not a single decision.

**How to test for it.** Directed: burst starting at 0x3FC with 16 beats of 4 bytes (crosses
0x400); burst starting exactly at 0x400; burst starting at 0x3FF (unaligned *and* crossing);
a 256-beat INCR of 4-byte beats starting at 0x0F00, which crosses three boundaries. Then a
coverage bin — `crosses_1k` as a cross against burst type and size — so you can prove your
random tests actually exercised it. Add a coverpoint for "number of sub-bursts generated"
with bins for 1, 2, 3, 4.

---

### 4.5 `HREADY`, `BUSY`, and read-channel backpressure

**What it is.** AXI's `RREADY` lets the master stall read data. AHB gives you no way to stall
incoming read data once you've committed the address phase. Something has to absorb the
difference.

**Why it's hard.** Your instinct will be to use `BUSY` — that's what it's for, after all.
But `BUSY` is a *manager-side* stall inserted at the **address** phase, and it doesn't stop
data already in flight. If you drove an address phase last cycle, the data phase is
happening this cycle whether `RREADY` is high or not.

**The structure it needs.** A skid buffer on the R path, plus a commitment rule: do not
drive the address phase for beat N+1 unless you have somewhere to put beat N+1's data. With
a one-entry skid buffer that means "don't commit if the buffer holds an item that hasn't
been accepted." Then `BUSY` (or `IDLE`, if the burst can be ended) is what you drive during
the stall.

`BUSY` rules you must respect:
- `BUSY` must not be the last transfer of a burst.
- For a fixed-length burst, a `BUSY` must be followed by a `SEQ` within that burst — you
  cannot use `BUSY` to bail out.
- `BUSY` between transfers holds the address of the *next* transfer.

**Bugs you will hit:**

- Dropping read data when `RREADY` is low. Silent in a testbench where `RREADY` is tied
  high, which it will be in your first testbench.
- Inserting `BUSY` after the final beat of a burst — a protocol violation that a simple
  memory-model subordinate will not notice, so you need an assertion.
- The one-cycle-too-late stall: you check `RREADY` in the same cycle you assert `HTRANS`,
  but by then the previous address phase is already producing data. The check must be one
  stage upstream.
- Deadlock: you stall the AHB burst waiting for `RREADY`, but your `RVALID` generation is
  gated on something that only advances when the AHB burst advances. Circular. This is the
  read-side twin of §4.7.

**How to test for it.** An AXI master driver that de-asserts `RREADY` according to a
randomized pattern, including: never (baseline), every other cycle, long stalls of 10+
cycles, and a stall specifically on the *last* beat of a burst. Assertions on the AHB
interface for the `BUSY` rules. And a hang detector — see §5.4, because a deadlock in
simulation looks exactly like a test that's still running.

---

### 4.6 Error responses and the write/read asymmetry

**What it is.** AHB reports errors per data phase. AXI reports one response per write burst
and one per read beat. Translating between them requires you to hold state, and to keep
your promises to the AXI master even after things have gone wrong.

**Why it's hard.** The failure mode is not "wrong response," it is "hang." AXI masters wait
forever for the beat count they were promised.

**The rules, precisely:**

*Writes.* One AXI write burst → possibly many AHB transfers → exactly **one** `BRESP`. If
any AHB transfer errored, `BRESP` = `SLVERR`. So you need a sticky error latch, cleared at
the start of each AXI transaction, that survives across a 1KB split. And:

- You must still **consume every remaining `W` beat** from the AXI master. The master has
  already committed to sending `AWLEN+1` beats and will not stop because of your internal
  error. If you stop asserting `WREADY`, you hang the bus.
- You may choose to cancel the remaining AHB transfers (drive `HTRANS` = `IDLE` during the
  first cycle of the two-cycle ERROR response) or to continue. Cancelling is generally
  preferred. Decide and document.

*Reads.* Per-beat `RRESP`, but you must still return **exactly `ARLEN+1` beats** with
`RLAST` on the final one. If beat 3 of 8 errors, you return 8 beats: beat 3 with `SLVERR`,
and beats 4–8 with something (typically `SLVERR` as well, and don't-care data), and `RLAST`
on beat 8. You **cannot** truncate the burst.

*Both.* The AHB `ERROR` response takes two cycles. Your data-phase logic must not treat the
first cycle (where `HREADY` is low) as a completed transfer.

**Bugs you will hit:**

- Truncating a read burst on error. The AXI master waits for `RLAST` forever. Textbook hang.
- Emitting one `BRESP` per AHB transfer instead of per AXI burst — so a 16-beat write
  produces 16 `BRESP`s and the master's outstanding-transaction accounting explodes.
- Clearing the error latch at the wrong boundary: per sub-burst instead of per AXI
  transaction, so an error in sub-burst 1 is forgotten by the time sub-burst 3 responds
  `OKAY`.
- Stopping `WREADY` when an error occurs, hanging the write channel.
- Treating the first cycle of the two-cycle ERROR as a completed data phase, double-counting
  the beat.
- Asserting `BVALID` before the final `W` beat has been accepted. AXI requires the write
  response to follow the last data beat.

**How to test for it.** Your AHB subordinate BFM needs an error-injection mode: a
configurable address range that always errors, plus a random per-transfer error probability.
Then directed tests for: error on the first beat, error on the last beat, error on a beat in
the middle of a 1KB-split burst, error on a `WSTRB`-decomposed sub-transfer. For each, the
scoreboard checks the exact beat count returned and the exact response value — not just
"an error came back."

---

### 4.7 The write-commitment deadlock

**What it is.** AHB's address phase is a commitment. Once you drive `NONSEQ` and the
subordinate accepts it, you *must* supply `HWDATA` in the next data phase. AXI's `W`
channel is independent of `AW` and the data may not have arrived yet.

**Why it's hard.** There is no legal way out. `BUSY` cannot help you here — `BUSY` is
inserted *between* transfers of a burst, and cannot precede the first data phase of the
burst you just started. If you commit an address phase with no data available, you are
stuck driving stale or X data onto the bus and there is no protocol-legal recovery.

Worse: the naive fix creates a deadlock. If you grant the arbiter to the write channel on
`AWVALID` and then wait for `WVALID`, while the master is waiting for you to accept a read
that you've now blocked — with certain master behaviors you can construct a circular wait.

**The structure it needs.** A commitment rule, stated as an invariant you can write on a
whiteboard:

> The AHB address phase FSM may transition to `NONSEQ`/`SEQ` for a write beat only if that
> beat's data is already held in the W buffer.

With a one-beat skid buffer, this costs one cycle of latency and is bulletproof. The
arbiter must respect the same rule: a pending `AW` is not *eligible* for grant until at
least one `W` beat is buffered.

**Bugs you will hit:**

- Committing on `AWVALID` alone. Works in every testbench where the driver sends `AW` and
  `W` in the same cycle — which is what your first hand-written driver will do, because
  it's the obvious thing to write. Fails the instant the driver delays `W`.
- Fixing it by stalling with `IDLE` after `NONSEQ`. That's a protocol violation: you cannot
  retract a committed address phase.
- Fixing it by buffering the entire burst, which works but needs a 256-entry FIFO for a
  worst-case AXI4 INCR burst — 8Kb of block RAM for a design that should fit in fabric.
- Arbiter starvation: a write command that never becomes eligible because the master is
  waiting on a read that the arbiter has parked. Prove your arbiter cannot do this.

**How to test for it.** Your AXI driver must have an independently randomized `W`-channel
delay: `W` arriving before `AW`, in the same cycle, and 1–20 cycles after. Add a coverpoint
on `AW`-to-first-`W` delay with bins for negative, zero, small, and large. And add the hang
detector. **This stage is the one that most often blows the schedule**, so budget for it.

---

### 4.8 The bug that only appears on hardware: X-propagation and reset

**What it is.** Your simulation testbench drives every signal to a known value. Real
hardware powers up with block RAM contents undefined, and your bridge's internal registers
undefined until reset.

**Why it's hard.** A 2-state-ish testbench hides it. If your AHB BFM returns 0 for
unwritten addresses instead of X, a read-before-write bug looks like a successful read of
zero. If your bridge has a register that is never reset and only happens to be initialized
by the first transaction, simulation may work and hardware may not.

**Bugs you will hit:**

- Registers not in the reset list, working in sim because the first write initializes them.
- Capturing `HRDATA` when `HREADY` is low, which propagates X in a proper sim and garbage on
  hardware — see §4.1. If your BFM never drives X on `HRDATA` during wait states, you will
  not catch this. **Make it drive X.**
- A state machine with an incomplete case statement inferring a latch, or reaching an
  unreachable state on hardware and never leaving it. Add a `default` that returns to a safe
  state, and an assertion that the default is never taken.
- Reset released asynchronously into your FSM causing a metastable state transition. Use
  synchronous de-assertion.

**How to test for it.** Make your AHB subordinate BFM drive `HRDATA` to `'x` on every cycle
where `HREADY` is low, and drive uninitialized memory as `'x`. Run one test with reset
asserted mid-transaction. Run Vivado's `report_methodology` and lint output and read every
warning — not skim, read.

**Use Questa's X-propagation mode.** This subsection is exactly what `-xprop` is built for.
Standard RTL simulation is optimistic about X: an `if (x_valued_condition)` quietly takes the
else branch, and a mux with an X select can produce a clean value when both inputs happen to
agree. Real gates do not behave that way. Compile one regression pass with:

```bash
vopt -xprop -o tb_xprop tb_top +acc
```

and run your full directed suite through it. Un-reset registers, `HRDATA` captured during a
wait state, and FSM state corruption all become visible failures rather than lucky passes.
Two practical notes: xprop makes simulation meaningfully slower, so use it for one pass at
stage 9 rather than for every run; and it will produce some noise on the reset-release cycle
that you should read carefully before dismissing — some of it is real.

Then on hardware, use the traffic generator's pass/fail LED, and if it fails, that's an ILA
session.

---

## Section 5 — Verification strategy

### 5.1 What a naive setup silently fails to catch

Here is the testbench you will build if you don't plan: an AXI driver task that sends a
write burst then a read burst, an AHB subordinate that is a simple memory array with
`HREADY` tied high, and a `$display` comparing read data to write data.

It will pass. It will catch approximately none of Section 4. Specifically, tied-high
`HREADY` hides every bug in §4.1 and §4.5; always-ones `WSTRB` hides all of §4.2;
same-cycle `AW`/`W` hides §4.7; no error injection hides §4.6; aligned power-of-two
addresses hide §4.3 and §4.4; and a "did the data match" check hides beat-count and `RLAST`
bugs entirely because it never counts beats.

Each of those is a one-line change to the testbench and each one is load-bearing.

### 5.2 The five things your environment must have

These five are methodology-independent — they are as necessary in a hand-rolled testbench as
in UVM. What changes under UVM is only *where each one lives*, which §5.6 lays out. Read this
section for the content and §5.6 for the container; do not let the container become the
project.

**1. An AHB subordinate BFM with a randomized personality.** Not a memory model — a memory
model *plus* a wait-state generator (0 to N, weighted so 0 is common but not universal),
an error-injection region and probability, and X-driving on `HRDATA` during wait states.
Make the personality configurable per test so you can run "easy mode" and "hostile mode" on
the same test and compare.

**2. Protocol checkers on both interfaces, as SVA.** This is where you learn assertions, and
this project is an unusually good vehicle for it because the properties are concrete. Start
with the handshake rules — they're the easiest and catch the most:

- AXI: `VALID` asserted implies `VALID` stays asserted and payload stable until `READY`.
- AXI: after reset, `VALID` is low.
- AXI: `RLAST` asserted exactly once per read burst, on beat `ARLEN+1`.
- AXI: exactly one `BVALID` per write burst, and not before the last `WVALID`&`WREADY`.
- AHB: when `HREADY` is low, all address-phase signals stable.
- AHB: `HADDR` aligned to `HSIZE`.
- AHB: `HTRANS` == `SEQ` implies `HADDR` == previous `HADDR` + transfer size (except at wrap).
- AHB: no burst crosses a 1KB boundary.
- AHB: `BUSY` is not the final transfer of a burst.

**Write these as named, parameterized properties and instantiate them per channel.** Questa
supports the full SVA property language — property declarations with formal arguments,
property instantiation, `implies` / `iff`, sequence local variables, `first_match`,
`s_eventually`, `nexttime`, and the `#-#` / `#=#` followed-by operators. A single
`property valid_stable(valid, ready, payload)` instantiated five times across AW/W/B/AR/R is
both less code and less opportunity for a copy-paste bug than five hand-written copies. Put
the properties in a package or a bind-able checker module and `bind` it to the interface;
that keeps the DUT and the TB clean and lets you reuse the same checker in the FPGA-wrapper
simulation.

**3. A reference model, written from the spec.** A behavioral model that takes an AXI
transaction and produces the expected sequence of AHB transfers, plus the expected AXI
response. Write it from the formulas in §4.3 and §4.4 — **do not derive it from your RTL**,
or you will validate your bug against itself. This is the single highest-value component of
the testbench and the thing an interviewer will ask about.

**4. A byte-accurate scoreboard.** Compare the subordinate's memory contents byte by byte,
*including* asserting that unstrobed bytes are unchanged. Compare the returned beat count.
Compare `RLAST` position. Compare `BRESP`/`RRESP` values. A scoreboard that only checks
"the data I read back equals the data I wrote" is checking one of five properties.

**5. Functional coverage, and coverage of your own assertions.** See §5.3.

**[DECIDED] — UVM, full environment.** An earlier revision of this document argued against
UVM on schedule grounds. That argument was real but it was a preference, not a finding, and
the decision has gone the other way: **this project uses a full UVM environment** — active
agents on both interfaces, a scoreboard fed by analysis ports, a coverage subscriber, a
virtual sequencer, and a test library. §5.6 specifies it.

Keep the honest cost in view rather than pretending it away. UVM adds roughly two days if you
have written a UVM environment before, and four to six if you have not — and almost none of
that time teaches you anything about AXI or AHB. It goes to factory registration, `config_db`
plumbing, phase ordering, sequencer/driver handshakes, and the particular misery of a
`uvm_config_db::get` that silently returned false. Budget it explicitly (§6) instead of
discovering it on day 6.

The failure mode to guard against is specific: **a half-finished UVM environment around a
working bridge reads worse than a complete hand-rolled testbench around the same bridge.** So
set a hard checkpoint — if the environment is not passing a single directed write transaction
end-to-end by the end of day 5, fall back to the hand-rolled version. The RTL, the reference
model, the coverage model, and the SVA suite all carry over unchanged, so the fallback costs
you the UVM days and nothing else. Decide at the checkpoint, not by drift.

Questa is UVM's native home — bundled source, `-L mtiUvm`, `uvm_hdl` backdoor access, proper
`+UVM_TESTNAME` / `+UVM_VERBOSITY` handling, and `-uvmcontrol=all` for UVM-aware GUI debug —
so the tooling will not be your obstacle.

### 5.3 Coverage: the model is the claim, not the number

Define your coverage model **before** you start randomizing, because a coverage model
written after the fact is a description of what you happened to test.

Coverpoints worth having:

- `burst_type`: FIXED, INCR, WRAP
- `len_bucket`: 1, 2, 3–4, 5–8, 9–16, 17–64, 65–255, 256
- `size`: byte, halfword, word
- `addr_alignment`: aligned to size, unaligned
- `crosses_1k`: yes / no
- `subbursts_generated`: 1, 2, 3, 4
- `wstrb_pattern`: all, none, single byte, contiguous-aligned, contiguous-unaligned,
  non-contiguous
- `wait_states`: 0, 1, 2–3, 4–7, 8+
- `error_injected`: none, first beat, middle beat, last beat
- `aw_to_w_delay`: W-first, same-cycle, 1–3, 4–10, 11+
- `rready_pattern`: always, alternating, long-stall, stall-on-last

Crosses that matter: `burst_type × crosses_1k`, `size × addr_alignment`,
`wstrb_pattern × size`, `error_injected × len_bucket`.

**The thing nobody tells you:** an assertion that never fires is not a passing assertion, it
is an untested assertion. For every meaningful `assert property`, write a matching
`cover property` on its antecedent. Questa additionally records assertion attempt/pass/fail
counts in the UCDB automatically, so `vcover report -assert` will tell you which of your
properties never had a real attempt — but keep the explicit `cover property` for the handful
you most want to make a claim about, because "I covered the antecedent deliberately" reads
better than "the tool happened to count it."

#### The UCDB flow

This is the mechanical part, and it is what makes the Section 7 numbers producible.

```bash
# one run
vopt -o tb_opt tb_top +acc +cover=bcefsx
vsim -c -coverage -sv_seed $SEED -L mtiUvm tb_opt \
     +UVM_TESTNAME=$TEST +UVM_VERBOSITY=UVM_MEDIUM \
     -do "run -all; coverage save build/cov/${TEST}_$SEED.ucdb; quit"

# merge the regression
vcover merge build/cov/merged.ucdb build/cov/run_*.ucdb

# report
vcover report -details -html -htmldir docs/coverage build/cov/merged.ucdb
vcover report -assert  build/cov/merged.ucdb        # assertion attempt/pass counts
vcover report -details -cvg build/cov/merged.ucdb   # covergroups only
```

`+cover=bcefsx` turns on branch, condition, expression, FSM, statement, and extended
toggle coverage. Code coverage is a weaker claim than functional coverage — 100% statement
coverage proves nothing about protocol correctness — but it is nearly free here and it is
genuinely useful for one thing: finding RTL you wrote and never exercised, which is usually
either dead code or a missing test.

Merging across seeds is the part that matters. A single seed will never close your model;
200 merged seeds might. Name the UCDB after the test *and* the seed — under UVM your
regression sweeps both axes, and a coverage hole needs to trace back to a reproducible
`+UVM_TESTNAME` / `-sv_seed` pair. Check the HTML report into `docs/coverage/` at the end.

**Exclusions.** When you decide a bin is unreachable (§7.1's WRAP16-crossing-1KB example),
record it as a real exclusion with a reason string rather than deleting the bin:

```bash
vcover exclude -du axi_ahb_bridge -togglenode ... -comment "unreachable: AXI WRAP is size-aligned"
```

An exclusion with a written justification is a much stronger artifact than a coverage model
that quietly never contained the hard bin.

### 5.4 The hang detector

A deadlock in simulation is indistinguishable from a long test. Build this on day one:

- A global watchdog: if no AXI transaction completes for N cycles (say 5000), `$fatal` with
  a dump of your FSM states and pending counts.
- A per-transaction timeout: each outstanding transaction records its start time; if it
  exceeds a bound derived from its beat count and max wait states, fail.

You will hit both of these in stages 5 and 8 and they will save you hours each time.

**Under UVM, do not rely on objections alone for this.** A `phase.drop_objection` that never
happens gives you a test that hangs in `run_phase` with no diagnostic, which is strictly worse
than the `$fatal` above. Set `uvm_phase::set_max_ready_to_end_iterations` sanely, configure a
global timeout via `uvm_top.set_timeout(...)`, and keep the watchdog component in the
environment anyway — it fires *at the moment of the hang* with your state dumped, which the
UVM timeout does not. The watchdog is a `uvm_component` subscribing to both monitors' analysis
ports; that is a five-minute port from the free-standing version.

An alternative worth knowing on Questa: a `s_eventually` liveness property (`AWVALID` implies
`s_eventually BVALID`) expresses exactly this and Questa supports it. But an unbounded
liveness property in simulation only fails at end-of-simulation, which is far less useful for
debug than a watchdog that fires at the moment of the hang with your state dumped. Use the
watchdog as the primary mechanism; the `s_eventually` version is a nice thing to have in the
suite and a good line in your writeup.

### 5.5 An independent referee

On XSim the obvious free referee was Vivado's AXI VIP (PG267), which ships ARM-licensed
protocol assertions. That is packaged for Vivado's own simulator; getting it to compile
standalone under Questa is possible but fiddly and is not a good use of a day. Your options,
in order of preference:

**1. Questa Verification IP (QVIP), if your license includes it.** This is the best outcome —
Mentor/Siemens' AXI and AHB assertion-based VIP is thorough, it is what commercial teams
actually use, and running it alongside your own checkers gives you exactly the second-opinion
value you want. QVIP ships as UVM agents, so under the §5.6 environment this gets *easier*
rather than harder: instantiate the AXI agent with `is_active = UVM_PASSIVE` next to your own
agent on the same interface and let it monitor. Check your license on day zero (§0.1); most
university bundles do *not* include QVIP, so do not build your plan around it.

**2. An open-source AXI protocol monitor.** `pulp-platform/axi` ships `axi_test.sv` with a
monitor and assertion set; `alexforencich/verilog-axi` has checker infrastructure too. These
compile anywhere and cost you an hour. Not ARM-licensed, so a weaker claim than QVIP — but a
genuine independent implementation, which is the property that actually matters: a
disagreement between your checker and someone else's is informative either way.

**3. No third-party referee.** Entirely defensible for a portfolio project. If you go this
route, say so plainly in the README rather than letting the omission read as an oversight,
and lean harder on the two things that substitute for it: a reference model written
independently from the spec (§5.2 item 3), and assertion coverage proving your own checkers
actually fired (§5.3).

Whichever you pick, **do not use a VIP as your primary stimulus** — set every third-party
agent to `UVM_PASSIVE`. Writing your own AXI sequences and driver is how you learn the
protocol, and that is the point of this project. The referee's job is to catch the case where
you misread a rule and then encoded that same misreading into both your RTL and your checker;
it cannot do that job if it is also generating your traffic.

---

### 5.6 The UVM environment

The component hierarchy, concretely. Nothing here is exotic — it is the standard two-agent
shape — but writing it down before you start is what keeps the build from sprawling.

```
axi_ahb_base_test
  └── bridge_env
        ├── axi_master_agent          (UVM_ACTIVE)
        │     ├── axi_sequencer
        │     ├── axi_driver          drives AW/W/AR, samples B/R
        │     └── axi_monitor         analysis_port #(axi_txn)
        ├── ahb_slave_agent           (UVM_ACTIVE — it must respond)
        │     ├── ahb_sequencer       response sequences: wait states, ERROR, X
        │     ├── ahb_driver          drives HREADY/HRESP/HRDATA
        │     └── ahb_monitor         analysis_port #(ahb_txn)
        ├── qvip_axi_agent            (UVM_PASSIVE — §5.5, if licensed)
        ├── bridge_scoreboard         2× uvm_analysis_imp + the reference model
        ├── coverage_subscriber       uvm_subscriber #(axi_txn), holds the §5.3 covergroups
        ├── watchdog                  §5.4, subscribes to both monitors
        └── virtual_sequencer         handles to both sequencers
```

**Transaction items.** `axi_txn` carries address, `len`, `size`, burst type, the data and
`WSTRB` arrays, and the response. `ahb_txn` carries one address phase plus its data phase.
Constrain `WSTRB` in the item itself, weighted per §4.2 — the whole point is that the
non-contiguous patterns are rare unless you ask for them.

**The AHB agent is active.** This is the part people get wrong. Your AHB side is a
*subordinate*, so the agent's driver is responding rather than initiating, and the adversarial
personality from §5.2 item 1 lives in a **response sequence** on its sequencer rather than
hard-coded in the driver. That indirection is what lets you swap "easy mode" and "hostile
mode" per test without touching the driver, and it is worth the extra file.

**Sequences.** One per §6 stage, roughly: `single_beat_seq`, `incr_burst_seq`,
`wrap_burst_seq`, `fixed_burst_seq`, `boundary_cross_seq`, `sparse_wstrb_seq`,
`error_inject_seq`, plus a `random_traffic_seq` that layers them. Virtual sequences coordinate
the AXI stimulus with the AHB response personality — e.g. "hostile wait states *and* errors on
the last beat of every burst."

**Tests.** A `base_test` that builds the env, applies a default config, and sets the default
sequence; then one short file per test that overrides config or swaps the virtual sequence.
Tests should be nearly empty. If a test file is long, its content belongs in a sequence or the
config object.

**Config objects.** One `bridge_env_cfg` holding the two agent configs and the AHB
personality knobs (wait-state distribution, error rate, error region, X-drive enable). Set it
in the test, `uvm_config_db::set` it once at env level, `get` it in `build_phase`. Resist
scattering individual knobs into the `config_db` by name — a single typed config object is one
`get` that either works or fails loudly, versus a dozen that fail silently.

**What carries over from §5.2 unchanged.** The reference model is a plain class the scoreboard
owns — spec-derived, still not RTL-derived. The SVA properties stay outside the class world
entirely: still `bind`-ed checker modules on the interfaces, unaffected by the methodology. The
coverage model is the same covergroups, sampled in a subscriber instead of a monitor callback.
The intellectual content of Section 5 is unchanged; you are changing the container.

---

## Section 6 — Staged build order

**Twelve working days, not ten.** The original ten-day plan assumed a hand-rolled testbench.
A full UVM environment (§5.6) adds two days if you have built one before and four to six if
you have not; the table below prices it at two and a half, which assumes some prior exposure.
If UVM is genuinely new to you, plan for fourteen and say so up front rather than
discovering it on day 8.

Days are indicative; the "kills schedules" column is the honest part.

| # | Days | Build | Test until | The bug you will hit |
|---|---|---|---|---|
| 0 | 0.5 | Repo restructure, Makefile, filelists, gitignore. Questa env script; §0.2 smoke test through `vcover report`. Confirm the bundled UVM version (§0.3). | `make sim` runs an empty top, prints a banner with the seed, and writes a UCDB you can report on. | A license or path problem. Better now than on day 8. |
| 1 | 1.5 | **UVM skeleton, DUT-free.** `tb_top` + interfaces + clock/reset. Both agents with items, sequencers, drivers, monitors. `bridge_env`, config object, `base_test`, a trivial sequence. Drivers loop back to each other or drive nothing. | `+UVM_TESTNAME=base_test` elaborates, runs, drops its objection, and exits 0 with a clean report summary. One item flows sequence → driver → monitor → analysis port. | `uvm_config_db::get` returning false silently. Objection never dropped → hang. Factory override not taking because the item wasn't registered. **All framework, no protocol. Budget it honestly.** |
| 2 | 0.5 | AHB subordinate response behavior: memory array, randomized wait states, error region, X on `HRDATA` during waits — as a **response sequence** on the AHB sequencer (§5.6), not baked into the driver. | A directed AHB sequence does a single write then read with 0, 1, and 5 wait states and gets the right data back. | Your driver captures `HWDATA` in the wrong cycle. Fixing it here teaches you §4.1 before your DUT depends on it. |
| 3 | 1.0 | Bridge skeleton: AXI ports, AHB ports, arbiter, single-beat (`AxLEN`=0) INCR pass-through. Register the AXI inputs. Scoreboard + reference model wired to both monitors. | Directed single-beat word write and read at aligned addresses pass with randomized wait states, **checked by the scoreboard** rather than by eye. | `HWDATA` one cycle early. §4.1. Almost guaranteed. |
| 4 | 1.0 | Multi-beat INCR bursts as undefined-length AHB `INCR`. Burst sequencer, beat counter, `RLAST` generation. `incr_burst_seq`. | Directed INCR bursts of 2, 4, 7, 16 beats pass. Beat counts checked, not just data. | `HADDR` not held stable during wait states; `RLAST` one beat early. AHB checker catches the first, scoreboard the second. |
| 5 | 1.5 | **Backpressure and commitment.** W buffer + commitment rule (§4.7). R skid buffer + `BUSY` handling (§4.5). Randomized `AW`/`W` delay and `RREADY` patterns in the AXI driver. Watchdog component + `uvm_top.set_timeout` (§5.4). Virtual sequence pairing hostile AHB responses with hostile AXI timing. | Same tests as stage 4 pass under hostile randomization: `W` delayed 20 cycles, `RREADY` stalling on the last beat. | Write-commitment deadlock. **This stage kills schedules.** Budget 2 days and be pleased if it's 1.5. |
| 6 | 0.5 | 1KB boundary splitting (§4.4). `boundary_cross_seq`. | Directed: start at 0x3FC, start exactly at 0x400, 256-beat burst crossing three boundaries. `subbursts_generated` coverage bin hits 4. | The 10-bit comparator that returns 0 instead of 1024. Watch for it specifically. |
| 7 | 1.0 | WRAP and FIXED bursts (§4.3). Reference model computes expected address sequence independently. | WRAP4/8/16 at and near boundaries, FIXED bursts of 2 and 16, unaligned INCR starts. | `SEQ` emitted across the wrap point. Wrap mask computed from `nbytes` instead of `len*nbytes`. |
| 8 | 1.0 | `WSTRB` decomposition (§4.2) and error responses (§4.6). Sticky error latch across splits. Weighted `WSTRB` constraint in `axi_txn`. | Non-contiguous strobes produce correct byte-level memory contents including unchanged bytes. Error on first/middle/last beat returns correct beat count and one `BRESP`. | Read burst truncated on error → hang. `WSTRB`=0 → hang. **Second schedule killer.** |
| 9 | 1.5 | Full randomized regression: shell loop over `+UVM_TESTNAME` × `-sv_seed`, UCDBs merged with `vcover merge`. SVA suite on both interfaces as bound, parameterized properties + matching `cover property`. Coverage subscriber and closure, HTML report. One `-xprop` pass (§4.8). Passive referee agent if available (§5.5). | 200+ runs pass across the test list. Coverage model closed or every hole explained in writing as a justified exclusion. xprop pass clean. | Assertions that never fired. Coverage holes revealing whole scenarios you never generated. xprop exposing an un-reset register. |
| 10 | 1.5 | `fpga/` wrapper: RTL traffic generator running the directed corner cases, pass/fail LED, UART result log. XDC, non-project `build.tcl`, synth + impl, timing and utilization reports. | Bitstream loads on the Nexys A7, LED reports pass, UART log matches simulation. | Something that only fails on hardware — §4.8. Also: your first real timing path, `HREADY` → `HTRANS`. |
| 11 | 0.5 | README, bug journal, results writeup, coverage report checked in. | A stranger can clone, run `make sim`, and understand what the design does in 5 minutes. | You'll discover a result you can't state honestly and have to go re-measure. |

**The day-5 checkpoint.** Per §5.2: if stage 1 has not produced a UVM environment that runs a
transaction end-to-end by the end of day 5, stop and fall back to a hand-rolled class-based
testbench — transaction class, driver, monitor, scoreboard, coverage collector, `mailbox`
between monitor and scoreboard. Every later stage is unaffected; the reference model, coverage
model, SVA suite, and RTL all carry over verbatim. Make that call deliberately on day 5, not
by drifting into day 9 with a broken `config_db`.

**Honest schedule notes.** Stages 5 and 8 are where this project either works or slips. They
are the stages with deadlock and hang failure modes, which are the slowest kind to debug.
Stage 1 is the new risk the UVM decision introduced, and it is front-loaded on purpose —
framework problems on day 2 are recoverable, the same problems on day 9 are not. Stage 10 is
the one most likely to eat an unplanned extra day, because FPGA bring-up always does.

If you are behind at the end of day 9, **cut stage 10 to synthesis-and-timing-reports only**
(no bitstream) rather than cutting stage 9. Verification quality is the thing that makes this
portfolio-worthy; a bitstream is a nice photo. Cutting stage 9 to save the bitstream inverts
the value of the project — and under UVM it inverts it harder, because an unexercised UVM
environment is the specific artifact that reads as cargo-cult.

### 6.1 Shortcuts that make this easier and less valuable

Named so you can recognize the temptation:

- **Tying `HREADY` high in the BFM.** Saves a day, deletes §4.1 and §4.5 from the project.
  Recommend strongly against — this is the shortcut that turns the project into a wire.
- **Only generating aligned, all-strobes, power-of-two-length bursts.** Saves stage 8,
  deletes §4.2. Against.
- **Checking only "data read back matches data written."** Saves an hour, deletes beat-count,
  `RLAST`, and response checking. Against.
- **Skipping the independent reference model and comparing against your RTL's own address
  generator.** Feels like it works. Validates your bug against itself. Strongly against.
- **Reporting only single-seed coverage instead of merging.** Saves ten minutes of Makefile
  work and makes your headline coverage number meaningless. Against — merging is the whole
  reason a 200-seed regression is worth running.
- **Undefined-length `INCR` instead of fixed-burst decomposition.** This one I am *not*
  calling a shortcut — it's a legitimate design choice (see D1). But you must be able to
  articulate the tradeoff, or it becomes one.
- **Skipping the FPGA and claiming simulation-only.** Legitimate if stated. You have a
  board, so it would be a shame.

Three more that only exist because of the UVM decision:

- **Putting the AHB personality in the driver instead of a response sequence.** Saves two
  hours in stage 2 and quietly removes your ability to vary hostility per test, which is the
  thing stage 5 depends on. Against.
- **Fat tests.** Stimulus written directly in `run_phase` instead of in sequences. Works,
  and it means you have written a hand-rolled testbench wearing UVM class names — which is
  worse than either option honestly chosen, because it invites the one question you cannot
  answer well. Against.
- **Using UVM but never using the factory, config objects, or a virtual sequence.** If none
  of the mechanisms earn their place, the two-and-a-half days bought you a keyword. Either
  use them or take the fallback path deliberately and say why in the README. Both are
  defensible; the middle is not.

---

## Section 7 — The quantifiable result

Portfolio work lives or dies on whether the numbers are honest. Here is what to instrument
and, more importantly, how to state it.

### 7.1 What to measure

**Functional coverage.** Report the percentage *and the model*, and say it is **merged across
N seeds**. "94% functional coverage" is meaningless alone; "94% of a 148-bin model covering
burst type × 1KB crossing × strobe pattern × wait states × error injection, merged across 200
seeds; the 9 uncovered bins are WRAP16 crossing a 1KB boundary, excluded with justification
because AXI WRAP bursts are size-aligned" is a real claim, and the second half is the part
that shows you understand your own design. Check in the `vcover report -html` output.

**Code coverage,** as a secondary number: statement/branch/expression/FSM from `+cover=bcefsx`.
State it as secondary — it is a weak correctness claim and an interviewer will respect you
more for saying so than for leading with 100% statement coverage.

**Seeds passed.** "N randomized seeds passed with zero failures" plus the constraint
configuration. Record the seed list. If you had failures you fixed, say so — a project with
zero recorded failures reads as either untested or dishonest.

**Assertion count, provenance, and attempt counts.** "27 SVA properties: 14 derived from
IHI0022H sections A3.3–A3.4, 13 from IHI0033A sections 3–5; all 27 recorded a non-zero attempt
count in the merged UCDB." Cite the sections. The attempt-count clause is the one most people
cannot produce and it is the difference between "I wrote assertions" and "my assertions ran."
Do not write "AXI compliant" — you have not run a compliance suite, and any interviewer who
knows the difference will ask.

**X-propagation.** "Full directed suite re-run under `vopt -xprop` with no failures." One
sentence, and it is a sentence very few portfolio projects can write.

**Throughput.** Measure cycles per AXI beat under a zero-wait-state subordinate, and compare
to the theoretical AHB floor. AHB with no wait states delivers one beat per cycle after a
one-cycle pipeline fill, so an N-beat burst should take N+1 cycles plus your bridge's fixed
overhead. State your overhead as a number: "a 16-beat INCR read completes in 21 cycles from
`ARVALID` to `RLAST`, versus a theoretical floor of 17; the 4-cycle delta is input
registration (1), arbitration (1), and address-phase commit (1), plus response registration
(1)." That level of specificity is rare and it is what makes a project memorable.

**Latency.** Two numbers: `AWVALID` → first `HTRANS` != IDLE, and last `HREADY` → `BVALID`.

**Area and timing.** From non-project Vivado synth + impl on `xc7a100tcsg324-1`: LUT count, FF
count, block RAM count, and Fmax. State Fmax honestly: report the constraint you actually
met and the worst negative slack, post-implementation, not post-synthesis, and name the
part and speed grade. Post-synthesis Fmax numbers are optimistic and everybody knows it.

**The bug journal.** This is the artifact I would most want to see, and almost nobody has
one. A table in `docs/BUGS.md`:

| # | Symptom | Root cause | Spec clause | How it was caught | Test added |
|---|---|---|---|---|---|

Fill it in *as you go*, not retroactively. Fifteen entries in that table is a better
portfolio than a bridge with no bugs, because the bridge with no bugs is a bridge that
wasn't tested. And "how it was caught" is where you demonstrate that your verification
strategy actually worked — if half your bugs were caught by staring at waveforms rather than
by a check, that's a finding about your testbench and you should say so.

### 7.2 How to state it in one paragraph

Draft this on day 10 and put it at the top of your README. Something with the shape of:

> A parameterizable AXI4 subordinate to AHB-Lite manager bridge, 32-bit, single outstanding
> transaction, verified with a constrained-random SystemVerilog environment in QuestaSim.
> Handles INCR, WRAP, and FIXED bursts up to 256 beats, 1KB boundary splitting,
> non-contiguous write strobes, and error aggregation. Verified against a spec-derived
> reference model with a byte-accurate scoreboard, [N] bound SVA properties (all with
> non-zero attempt counts), and a [M]-bin functional coverage model closed to [X]% merged
> across [K] passing seeds; full directed suite additionally clean under X-propagation.
> Implemented with Vivado on a Nexys A7-100T at [F] MHz using [L] LUTs and [R] FFs.
> [B] bugs found and documented during development.

Every bracket is a number you must actually have. If you can't fill one in, don't invent it
— delete the clause.

---

## Section 8 — Curated resources

### Specifications (get these first)

- **ARM IHI0022, Issue H.c — *AMBA AXI and ACE Protocol Specification*.** The last issue
  containing AXI4. Free from ARM with an account; the historical PDF has also been mirrored
  at `developer.arm.com/-/media/Arm Developer Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf`.
  Note ARM is migrating documentation from `developer.arm.com` to `support.arm.com`, so if a
  link 301s, follow it. **Do not use Issue J, K, or L — AXI4 was removed in Issue J.**
- **ARM IHI0033, Issue A — *AMBA 3 AHB-Lite Protocol Specification v1.0* (2006).** Short and
  exactly on target. Widely mirrored by universities (e.g. University of Michigan EECS 373
  course readings) but prefer ARM's copy so you know the revision.
- **ARM IHI0033, Issue C — *AMBA AHB Protocol Specification* (AHB5).** Supersedes Issue A,
  covers AHB-Lite and AHB5 together, adds `HWSTRB` and clearer burst text. Use as a
  secondary reference.
- **ARM IHI0011A — *AMBA Specification (Rev 2.0)* (1999).** Full multi-master AHB, plus ASB
  and APB. **Not** a document you implement against — read the arbitration and SPLIT/RETRY
  sections only, and only to understand what AHB-Lite removed and why (§2.3). One hour, and
  it makes you noticeably better at explaining your own design choice. Mirrored at
  University of Michigan EECS 373 and University of Waterloo CS452 course pages.
- **ARM document 101375 — AXI5 to AHB5 bridge.** A real product's functional description,
  including 1KB boundary crossing behavior. Different protocol generation than yours, so
  read it as a sanity check rather than a template.

### Tool documentation

**QuestaSim (Siemens EDA):**

- ***Questa SIM User's Manual*** — the chapters on Verification with Assertions and
  Coverage, Code Coverage, and Functional Coverage. The coverage chapter is where the UCDB
  save/merge/report flow in §5.3 is documented properly.
- ***Questa SIM Command Reference*** — the pages for `vlog`, `vopt`, `vsim`, `vcover`, and
  `coverage save`. In particular read `vopt`'s `-xprop` section (§4.8) and `vcover merge`'s
  options for merging across differing designs, which you will hit if you change the RTL
  mid-regression.
- **`verror <number>`** — the single most useful Questa command nobody tells you about. Every
  Questa message has a numeric code; `verror 7061` prints a full explanation of what that
  error actually means and usually what to do about it. Use it instead of pasting the message
  into a search engine.
- **`vsim -help`, and `-do` files.** Put your run recipe in `sim/run.do` rather than in a
  giant quoted `-do` string; it is version-controllable and you can add `onerror {quit -f -code 1}`
  so a regression actually fails your shell loop instead of dropping into an interactive prompt.

**UVM:**

- ***Universal Verification Methodology (UVM) 1.2 User's Guide*** (Accellera) — read the
  chapters on the component hierarchy, sequences, and TLM. Free PDF from Accellera. Match the
  edition to whichever UVM your Questa bundles (§0.3); if it ships 1800.2, read the IEEE
  1800.2 UVM Reference alongside it, because the class API changed.
- ***UVM Class Reference*** — the searchable HTML in
  `$(dirname $(which vsim))/../verilog_src/uvm-*/docs/`, if your install includes it. Local
  and version-correct, which is worth more than a search-engine result for a different UVM.
- ***Questa SIM User's Manual*, the UVM chapter** — `-L mtiUvm`, `-uvmcontrol=all` for
  UVM-aware debug in the GUI, and how Questa's UVM-aware waveform/transaction viewing works.
  This is the part that makes UVM debuggable rather than a black box.
- **`+UVM_TESTNAME`, `+UVM_VERBOSITY`, `+uvm_set_config_int`, `+uvm_set_verbosity`** — learn
  these four plusargs early. They let you change test, noise level, and config from the
  command line without recompiling, which is what makes a regression loop practical.

**Vivado (synthesis path only):**

- **UG901 — *Synthesis*** and **UG904 — *Implementation***, for the non-project flow commands
  in `build.tcl`.
- **UG835 — *Tcl Command Reference***, for `synth_design` / `report_timing_summary` /
  `report_utilization` options.

### Learning material

- **Chris Spear & Greg Tumbush, *SystemVerilog for Verification: A Guide to Learning the
  Testbench Language Features*, 3rd edition (Springer, 2012).** ISBN 978-1-4614-0714-0. The
  standard text, and notably it uses Questa/ModelSim examples throughout. For this project
  read chapters on interfaces, OOP/classes, randomization and constraints, threads and
  inter-process communication, and functional coverage. Its UVM chapters are now directly
  relevant — read them alongside the UVM references below rather than skipping them. Available via the Internet Archive lending library if you want to try
  before buying.
- **ZipCPU (Dan Gisselquist), zipcpu.com.** Free, opinionated, and unusually good on exactly
  the topics you need. Start with *Understanding AXI Addressing* (2019-04-27) for the burst
  address arithmetic, then *Building the perfect AXI4 slave* (2019-05-29), then *Common AXI
  Themes on Xilinx's Forum* (2021-03-20) — that last one is a catalogue of the mistakes
  people actually make, which maps closely onto Section 4 above. His formal-verification
  posts are the best free introduction to bus property writing even if you never run
  SymbiYosys.
- **verificationacademy.com** — Siemens' own site, so it is written against Questa
  specifically. Both the courses (the SVA and functional-coverage tracks) and the forums are
  relevant, and the AHB/AXI assertion threads (e.g. "AHB 1KB Address Boundary Check
  Assertion") are concrete worked examples of exactly the properties you'll be writing. This
  is a noticeably better resource for you now than it was on XSim.
- **vlsiverification.net** has a compact AXI burst-types page with address calculation worked
  through, useful as a quick cross-check on your §4.3 formulas.

### Reference implementations — read *after* you write, not before

- `alexforencich/verilog-axi` on GitHub. High-quality AXI infrastructure. Its issue tracker
  is genuinely educational — issue #12 is the 4K-boundary comparison bug referenced in §4.4,
  in production-quality code, which should calibrate your expectations about how easy that
  bug is to make.
- `pulp-platform/axi` on GitHub. Well-documented, formally-verified-adjacent AXI components.
  Also your most likely source of a third-party protocol monitor for §5.5.

Read either of these before you've built your own and you will absorb their architecture
without understanding why. Read them after stage 9 and you'll have opinions.

---

## Section 9 — Self-check questions

Answerable from your own design, not from a search engine. If you can't answer one at the
end, that's a gap in the design, not in the question.

1. In your bridge, exactly which cycle does `HWDATA` for beat N become valid, relative to
   the cycle in which beat N's `HADDR` was accepted? Draw the waveform with two wait states.

2. Your bridge has committed an AHB address phase for a write beat. What is the complete set
   of conditions that made that commitment safe? What would happen — cycle by cycle — if one
   of them were removed?

3. An AXI master issues `AWADDR`=0x3F8, `AWLEN`=15, `AWSIZE`=2 (4 bytes), `AWBURST`=INCR.
   How many AHB bursts does your bridge generate, what is `HTRANS` on each transfer, and
   where exactly does `NONSEQ` appear?

4. Why is `bytes_to_1k_boundary` unable to fit in 10 bits, and what does your RTL do about
   it? Which specific test would fail if you got this wrong, and does that test exist in
   your suite?

5. An AXI WRAP16 burst with `AWSIZE`=2 starts at 0x1040. List the sixteen addresses. Which
   AHB `HTRANS` value does your bridge drive at the wrap point, and why is the other one
   wrong?

6. A write beat arrives with `WSTRB`=4'b1001. How many AHB transfers does your bridge emit,
   at what addresses and sizes, and on which `HWDATA` byte lanes does each place its data?

7. Beat 5 of a 12-beat AXI read burst gets an AHB `ERROR`. Describe the complete AXI
   response your bridge produces: how many `R` beats, what `RRESP` on each, and where
   `RLAST` lands. What happens to the remaining AHB transfers?

8. Same scenario but for a write. How many `BRESP`s? What is the value? What must your
   bridge continue to do on the `W` channel and why does the bus hang if it doesn't?

9. Your AXI master de-asserts `RREADY` for 20 cycles in the middle of a burst. Trace what
   happens on the AHB side. Where does the read data go? At which point in the pipeline did
   you decide not to issue the next address phase, and why not one stage later?

10. Construct a scenario in which your arbiter could deadlock, then explain the specific
    property of your implementation that makes it impossible. If you can't do the second
    half, you have a bug.

11. Name three bugs in your bridge that a testbench with `HREADY` tied high would not have
    caught. For each, name the check in your current testbench that does catch it.

12. Pick an assertion in your suite. What is its antecedent? What is your evidence that the
    antecedent ever occurred during your regression? If you don't have that evidence, what
    is the assertion actually proving?

13. Your reference model and your RTL disagree on an address sequence. What is your procedure
    for deciding which one is wrong, and what does it say about how you wrote the reference
    model?

14. What is your bridge's worst-case timing path post-implementation, in what units, and
    what would you change first if you needed 30% more Fmax? Would that change cost you
    throughput?

15. You chose undefined-length AHB `INCR` over fixed-length burst decomposition. Name two
    concrete situations where that choice costs performance, and describe the specific new
    bug class you'd be signing up for if you switched.

16. A colleague wants to add support for four outstanding AXI transactions. Which of your
    blocks change, which don't, and where does the AXI ordering model (IHI0022H chapter A5)
    constrain what you're allowed to do with the responses?

17. Your merged coverage report shows 96%. What are the missing 4%, and for each hole: is it
    unreachable, is it a missing constraint in your generator, or is it a scenario you chose
    not to support? What does your exclusion file say and would you defend each entry?

---

## Where to push back on me

Consolidated, so you don't have to hunt for the inline markers:

- **The 12-day schedule.** I allocated 1.5 days each to stages 5 and 8. If you've never
  debugged a bus deadlock, those could each be 2.5. I also priced the UVM skeleton (stage 1)
  at 1.5 days, which assumes prior UVM exposure; with none, it is closer to 3 and the whole
  plan is 14. The schedule is aggressive and I'd rather you know that than discover it on
  day 10. If it slips, cut stage 10's bitstream, not stage 9's verification.
- **Undefined-length `INCR` (D1).** Defensible either way. My argument is bug-density; the
  counter-argument is that fixed-burst decomposition is where the more interesting bugs are,
  which is exactly what you said you wanted from this project. If you have the schedule,
  parameterize it and do both.
- **Using UVM (§5.2, §5.6).** An earlier revision of this document argued against it on
  schedule grounds; that call has been reversed and the plan now builds a full UVM
  environment. The reversal is worth understanding rather than just accepting: the anti-UVM
  argument was never a technical finding, only a judgement about where two-plus days are best
  spent, and it collapses the moment your target roles filter on UVM — which most DV
  postings do. What remains true is the cost. Push back on me in the other direction if you
  find yourself on day 6 with a `config_db` you cannot debug: the fallback in §6 is real, it
  is not a defeat, and a finished hand-rolled testbench beats an unfinished UVM one in every
  audience that matters.
- **Calling CDC a separate project.** I stand by it — async CDC bugs are largely invisible in
  RTL simulation and you have no formal or CDC-lint tooling in the base Questa flow, so you'd
  be adding a failure mode you can't observe. If your site's license happens to include
  Questa CDC or Questa Formal, that changes the calculation and is worth checking. Even then
  it should displace something, not be added.
- **AXI4 over AXI5 (§2.4).** ARM says AXI4 is not recommended for new designs; I chose it
  anyway because AXI5's additions are orthogonal to a bridge and because AXI5 costs you the
  entire learning ecosystem. Note that one of my original arguments — losing Vivado's AXI VIP
  — no longer applies to you, so this call is slightly weaker than it was.
- **AHB-Lite over full AHB or AHB5 (§2.3).** Full AHB's SPLIT/RETRY is the one genuinely interesting thing I cut; AHB5's `HWSTRB` would delete §4.2 entirely. Both reconsiderable — see the marker in §2.3.
- **The traffic generator over MicroBlaze.** Schedule-driven. If SoC integration is what you
  want to demonstrate, my recommendation is wrong for you.
- **Single outstanding transaction.** This is the biggest scope cut in the whole plan and the
  one an interviewer is most likely to poke at. My argument is that outstanding-transaction
  support without the verification infrastructure to shake it out is worse than not having
  it. Question 16 exists so you can answer the poke well.
- **The register-the-AXI-inputs recommendation (D4).** At 100 MHz on Artix-7 you may not need
  it, and it costs a cycle of latency that shows up in your §7.1 numbers. If your first
  timing report has comfortable slack, you could reasonably drop it.

---

## Before you start

1. Set up `sim/env.sh` with your Questa module load and license variable; confirm with
   `vsim -version` (§0.3).
2. Run the day-zero smoke test all the way through `vcover report` (§0.2). Twenty minutes,
   and it proves the coverage chain that your entire Section 7 claim depends on.
3. Confirm on day zero whether your license includes functional coverage and whether it
   includes QVIP (§0.1) — the second answer decides §5.5.
4. Find out which UVM your Questa bundles and use that copy, not a downloaded Accellera drop
   (§0.3). Compile a hello-world `uvm_test` with `-L mtiUvm` before you write anything real.
5. Download IHI0022 **Issue H** — not the latest — and IHI0033 Issue A (§2). Read §2.3 and §2.4 if you have not already; they justify the two protocol choices you did not make.
6. Read §1.4 and §4.1 again. Everything else is detail hanging off those two.
7. Create `docs/BUGS.md` with the empty table from §7.1. Fill it in as you go.

Then start stage 0. When you're ready for stage-by-stage tutoring, come back and tell me
which stage you're on and what you're seeing — I'll tutor rather than tell.
