# AXI4 → AHB5 Bridge

Synthesizable AXI4 subordinate → AHB5 manager bridge, plus a UVM
verification environment. 32-bit address/data, single outstanding
transaction, single clock domain. See `README.md` for the protocol
mismatches and the status checklist (keep the checklist current).

## Layout

- `rtl/` — synthesizable bridge (empty so far)
- `tb/ahb/` — AHB interface, packages, slave BFM, reference model, `ahb_txn`
- `tb/test/` — UVM tests; `tb/top/tb_top.sv` — top-level
- `sim/` — Vivado xsim flow (the only simulator): `Makefile`, and `tb.f` (compile-order filelist; add new files here)
- `docs/` — AXI spec (IHI0022H), AHB spec (IHI0033C, covers AHB-Lite and AHB5), `JOURNAL.md`, `STUDY_GUIDE.md`
- `build/` — generated, gitignored; never edit or commit

## Commands

- Vivado xsim: `make -C sim run` (knobs: `SEED`, `TEST`, `N_TRANS`, `TIMEOUT_NS`), `regress` (`N` seeds), `gui`, `clean`
- Run the regression before committing anything that touches `rtl/` or `tb/`, and report failures verbatim.

## Ground rules

**Working style**
- The goal of this project is for the user to learn RTL design and design verification (DV). Optimize for their learning, not speed: they write the RTL themselves; I explain, review and quiz rather than hand over finished designs. Explain non-obvious protocol or UVM choices briefly; don't silently hand over large blocks of code. Prefer small, reviewable steps over big drops.
- Propose the design (FSM states, ports, interfaces) and get agreement before writing substantial new RTL or testbench architecture.
- Cite the spec (section/rule) when implementing protocol behavior, not memory. The PDFs are in `docs/`.
- Don't commit, push, or touch git history unless asked. Commit messages: short imperative subject, match existing style.  No Claude attribution: no `Co-Authored-By` trailer and no "Generated with Claude Code" line in commits or PR descriptions. `docs/notes/` is the user's private, git-ignored notes (journal, study guide): don't edit or rewrite anything there unless asked.

**RTL**
- Synthesizable SystemVerilog only in `rtl/`: `always_ff`/`always_comb`, no delays, no `initial`, no testbench constructs, no latches.
- Single clock, active-low sync reset (`ARESETn`/`HRESETn` tied to one reset). Use AMBA signal names exactly as in the specs.
- FSMs: enumerated state type, separate next-state logic, explicit defaults for every output.
- Bridge must stay protocol-legal on both sides at all times (including during reset and stalls). When in doubt, hold values stable while `VALID && !READY` (AXI) or `!HREADY` (AHB).

**Verification**
- Every feature lands with a test that fails without it. Self-checking only: no eyeballing waveforms as pass criteria.
- Checks go through the scoreboard/reference model, not duplicated RTL logic.
- Constrained-random with a reproducible `SEED`; log the seed. Directed tests for corner cases (errors, wait states, narrow/unaligned, 4KB boundary).
- Protocol assertions live in bindable checkers, not inside the RTL.
- Target xsim only. Check that SV/UVM features are supported by xsim before relying on them (e.g. coverage, bind, constraint support).

**Scope**
- Follow the README checklist order unless told otherwise. Don't add features (multiple outstanding, async clocks, AXI IDs beyond what's needed) without asking.
- `tb/tb_vivado_test.sv` is a scratch file for xsim experiments; not part of the build.
