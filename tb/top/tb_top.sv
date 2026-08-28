`timescale 1ns/1ps

module tb_top ();
  import ahb_pkg::*;

  // HCLK generation
  bit HCLK = 0;
  always #5 HCLK = ~HCLK;

  // HRESETn generation
  logic HRESETn;
  initial begin
    HRESETn = 1'b0;
    repeat (5) @(posedge HCLK);
    HRESETn <= 1'b1;
  end

  // AHB interface instantiation
  ahb_if u_ahb (.HCLK, .HRESETn);
  assign u_ahb.HSEL = 1'b1;      // single slave, always selected
  assign u_ahb.HREADY = u_ahb.HREADYOUT; // single slave tie

  // AHB BFM instantiation
  ahb_slave_bfm #(.MEM_WORDS(1024)) u_slave (.bus(u_ahb));

  hdata_t rdata;

  initial ahb_idle();

  initial begin
    wait (HRESETn === 1'b1);
    @(posedge HCLK);
    $display("[tb_top] seed=%0d", $urandom());
    ahb_write(32'h0000_0010, 32'hDEAD_BEEF);
    ahb_read(32'h0000_0010, rdata);
    if (rdata !== 32'hDEAD_BEEF)
      $error("read got %08h, expected DEADBEEF", rdata);
    else
      $display("[tb_top] write/read PASS");
    repeat (5) @(posedge HCLK);
    $finish;
  end


  task automatic ahb_idle();
    u_ahb.HTRANS = HTRANS_IDLE;
    u_ahb.HWRITE = 1'b0;
    u_ahb.HSIZE  = HSIZE_WORD;
    u_ahb.HBURST = HBURST_SINGLE;
    u_ahb.HPROT  = 4'b0011;
    u_ahb.HADDR  = '0;
    u_ahb.HWDATA = '0;
  endtask

  task automatic ahb_write(input haddr_t addr, input hdata_t data);
    // address phase
    @(posedge HCLK);
    u_ahb.HADDR  <= addr;
    u_ahb.HTRANS <= HTRANS_NONSEQ;
    u_ahb.HWRITE <= 1'b1;
    u_ahb.HSIZE  <= HSIZE_WORD;
    u_ahb.HBURST <= HBURST_SINGLE;

    // data phase
    @(posedge HCLK);
    u_ahb.HTRANS <= HTRANS_IDLE;
    u_ahb.HWDATA <= data;

    // TODO wait while HREADY low
  endtask

  task automatic ahb_read(input haddr_t addr, output hdata_t data);
    // address phase
    @(posedge HCLK);
    u_ahb.HADDR  <= addr;
    u_ahb.HTRANS <= HTRANS_NONSEQ;
    u_ahb.HWRITE <= 1'b0;
    u_ahb.HSIZE  <= HSIZE_WORD;
    u_ahb.HBURST <= HBURST_SINGLE;

    // data phase
    @(posedge HCLK);
    u_ahb.HTRANS <= HTRANS_IDLE;

    // HRDATA valid
    @(posedge HCLK);
    data = u_ahb.HRDATA;

    // TODO wait while HREADY low
  endtask
endmodule
