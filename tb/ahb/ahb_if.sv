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

  // ---------------------------------------------------------------
  // master stimulus tasks
  // ---------------------------------------------------------------

  task automatic ahb_idle();
    HTRANS = HTRANS_IDLE;
    HWRITE = 1'b0;
    HSIZE  = HSIZE_WORD;
    HBURST = HBURST_SINGLE;
    HPROT  = 4'b0011;
    HADDR  = '0;
    HWDATA = '0;
  endtask

  // Data is right-justified: the task places it on the byte lane the address selects
  task automatic ahb_write(input haddr_t addr, input hsize_e size = HSIZE_WORD,
                           input hdata_t data);
    // address phase
    @(posedge HCLK);
    HADDR  <= addr;
    HTRANS <= HTRANS_NONSEQ;
    HWRITE <= 1'b1;
    HSIZE  <= size;
    HBURST <= HBURST_SINGLE;
    do @(posedge HCLK); while (!HREADY);

    // data phase
    HTRANS <= HTRANS_IDLE;
    HWDATA <= data << (8 * addr[1:0]);
    do @(posedge HCLK); while (!HREADY);
  endtask

  // Returns right-justified data
  task automatic ahb_read(input haddr_t addr, input hsize_e size = HSIZE_WORD,
                          output hdata_t data);
    // address phase
    @(posedge HCLK);
    HADDR  <= addr;
    HTRANS <= HTRANS_NONSEQ;
    HWRITE <= 1'b0;
    HSIZE  <= size;
    HBURST <= HBURST_SINGLE;
    do @(posedge HCLK); while (!HREADY);

    // data phase
    HTRANS <= HTRANS_IDLE;
    do @(posedge HCLK); while (!HREADY);

    // HRDATA valid
    data = HRDATA >> (8 * addr[1:0]);

  endtask

endinterface
