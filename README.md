![status](https://img.shields.io/badge/status-work%20in%20progress-orange)

# AXI4 → AHB-Lite Bridge

A synthesizable protocol bridge that presents an AXI4 subordinate interface and drives an AHB-Lite manager interface, with a UVM environment. 

32-bit data and address on both sides, single outstanding transaction,
single clock domain.

## Protocol Mismatches

- **Byte enables.** AXI carries `WSTRB` per beat; AHB-Lite has no equivalent
  and expresses byte enables only through `HSIZE` plus address alignment.
- **Pipelining.** AHB's address and data phases are offset by a cycle but AXI's
  channels are independent.
- **Bursts.** AXI burst length is explicit in `AxLEN`, but AHB `INCR` is
  undefined-length, and AXI's 1KB boundary rule has no AHB counterpart.
- **Backpressure and errors.** `HREADY` stalls, `HTRANS=BUSY`, and AHB's
  two-cycle `ERROR` response all have to map onto AXI's `RRESP`/`BRESP`
  and ready/valid handshakes.

## Status

Work in progress.

- [x] AHB-Lite interface, protocol package, clocking blocks and modports
- [x] AHB slave BFM: word and sub-word transfers, byte-lane masking,
      protocol assertions, wait states and ERROR responses
- [ ] AXI4 interface and protocol package
- [ ] AXI4 manager BFM: write/read channels, WSTRB generation, bursts
- [ ] Bridge RTL
- [ ] Bound SVA protocol checkers, both sides
- [ ] UVM environment (agents, scoreboard, reference model, coverage)
- [ ] FPGA bring-up on Artix-7

## Running the tests

    make -C sim run          # one seed, waves to build/
    make -C sim wave         # open the last run in Visualizer
    make -C sim regress N=50 # 50 seeds with coverage
    make -C sim cov          # merge and report
