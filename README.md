![status](https://img.shields.io/badge/status-work%20in%20progress-orange)

# AXI4 → AHB-Lite Bridge

A synthesizable protocol bridge that presents an AXI4 subordinate interface
and drives an AHB-Lite manager interface, with a UVM environment.

32-bit data and address on both sides, single outstanding transaction,
single clock domain.

## Protocol Mismatches

- **Byte enables.** AXI carries `WSTRB` per beat; AHB-Lite has no equivalent
  and expresses byte enables only through `HSIZE` plus address alignment.
- **Pipelining.** AHB's address and data phases are offset by a cycle but AXI's
  channels are independent.
- **Bursts.** AXI burst length is explicit in `AxLEN`, but AHB `INCR` is
  undefined-length. Both protocols forbid a burst crossing an address
  boundary, at different sizes: 4KB for AXI, 1KB for AHB. The bridge
  sidesteps AHB's rule by emitting a run of `SINGLE` transfers, which is
  not an incrementing burst.
- **Backpressure and errors.** `HREADY` stalls, `HTRANS=BUSY`, and AHB's
  two-cycle `ERROR` response all have to map onto AXI's `RRESP`/`BRESP`
  and ready/valid handshakes.

## Status

- [x] AHB-Lite verification environment: interface, protocol package,
      slave BFM with byte lanes, wait states, protocol assertions
- [x] AHB golden memory model and self-checking directed tests
- [x] Constrained-random AHB stimulus: address, size, direction and data,
      checked against the golden model
- [ ] AHB monitor and `ahb_txn` as a `uvm_sequence_item`
- [ ] AXI4 interface and protocol package
- [ ] Bridge RTL, minimal: single outstanding, `AxLEN=0`, `OKAY` only
- [ ] UVM environment: AXI manager agent, AHB subordinate agent, scoreboard
- [ ] ERROR responses end to end: two-cycle AHB `HRESP` mapped to
      `RRESP`/`BRESP`
- [ ] Bursts: `AxLEN>0` decomposed into a run of AHB `SINGLE` transfers
- [ ] Bound SVA protocol checkers, both sides
- [ ] Functional coverage closure
- [ ] FPGA bring-up on Artix-7

## Running the tests

    make -C sim run              # one seed, waves to build/
    make -C sim run N_TRANS=5000 # one seed, longer random stream
    make -C sim wave             # open the last run in Visualizer
    make -C sim regress N=50     # 50 seeds with coverage
    make -C sim cov              # merge and report
