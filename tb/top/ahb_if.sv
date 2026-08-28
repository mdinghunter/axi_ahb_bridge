`timescale 1ns/1ps

interface ahb_if (
  input bit HCLK,
  input logic HRESETn
);

  import ahb_pkg::*;

  // ---------------------------------------------------------------
  // signals
  // ---------------------------------------------------------------

  // master signals
  haddr_t HADDR;
  hburst_e HBURST;
  // logic HMASTLOCK; // locked transfers not needed currently
  hprot_t HPROT; // master drives it to 4'b0011
  hsize_e HSIZE;
  htrans_e HTRANS;
  hdata_t HWDATA;
  logic HWRITE;

  // slave signals
  hdata_t HRDATA;
  logic HREADYOUT;
  hresp_e HRESP; // 1 bit for AHB-lite

  // interconnect signals
  logic HREADY;
  logic HSEL;

  // ---------------------------------------------------------------
  // clocking blocks
  // ---------------------------------------------------------------

  // slave BFM: samples the address/data phase, drives the response
  clocking cb_slave @(posedge HCLK);
    default input #1step output #1ns;
    input  HADDR, HBURST, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
    input  HSEL, HREADY;
    // output HRDATA, HREADYOUT, HRESP; // TODO enable after making UVM driver
  endclocking

  // passive monitor: samples everything, drives nothing
  clocking cb_mon @(posedge HCLK);
    default input #1step;
    input HADDR, HBURST, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
    input HRDATA, HREADYOUT, HRESP;
    input HREADY, HSEL;
  endclocking

  // ---------------------------------------------------------------
  // modports
  // ---------------------------------------------------------------

  // DUT
  modport master (
    input  HCLK, HRESETn,
    output HADDR, HBURST, HPROT, HSIZE, HTRANS, HWDATA, HWRITE,
    input  HRDATA, HRESP, HREADY
  );

  // slave BFM
  modport slave (
    input  HCLK, HRESETn,
    input  HADDR, HBURST, HPROT, HSIZE, HTRANS, HWDATA, HWRITE,
    input  HSEL, HREADY,
    output HRDATA, HREADYOUT, HRESP,
    clocking cb_slave          // unused for now;
  );

  // monitor
  modport monitor (
    clocking cb_mon,
    input HCLK, HRESETn
  );

endinterface
