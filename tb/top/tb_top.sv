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
    // ---- word write / read ----------------------------------------
    ahb_write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
    ahb_read (32'h0000_0010, HSIZE_WORD, rdata);
    if (rdata !== 32'hDEAD_BEEF)
      $error("word read got %08h, expected DEADBEEF", rdata);
    else
      $display("[tb_top] word write/read PASS");

    // ---- halfword lanes -------------------------------------------
    ahb_write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
    ahb_write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
    ahb_read (32'h0000_0030, HSIZE_WORD, rdata);
    if (rdata !== 32'h3344_1122)
      $error("halfword-lane read got %08h, expected 33441122", rdata);

    // ---- byte lanes: four byte writes, one word read ---------------
    ahb_write(32'h0000_0020, HSIZE_BYTE, 32'h0000_00AA);
    ahb_write(32'h0000_0021, HSIZE_BYTE, 32'h0000_00BB);
    ahb_write(32'h0000_0022, HSIZE_BYTE, 32'h0000_00CC);
    ahb_write(32'h0000_0023, HSIZE_BYTE, 32'h0000_00DD);
    ahb_read (32'h0000_0020, HSIZE_WORD, rdata);
    if (rdata !== 32'hDDCC_BBAA)
      $error("byte-lane read got %08h, expected DDCCBBAA", rdata);
    else
      $display("[tb_top] byte-lane write PASS");

    // ---- byte read back from a non-zero lane -----------------------
    ahb_read (32'h0000_0022, HSIZE_BYTE, rdata);
    if (rdata[7:0] !== 8'hCC)
      $error("byte read of 0x22 got %02h, expected CC", rdata[7:0]);
    else
      $display("[tb_top] byte read PASS");
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

  // Data is right-justified: the task places it on the byte lane the address selects
  task automatic ahb_write(input haddr_t addr, input hsize_e size = HSIZE_WORD,
                           input hdata_t data);
    // address phase
    @(posedge HCLK);
    u_ahb.HADDR  <= addr;
    u_ahb.HTRANS <= HTRANS_NONSEQ;
    u_ahb.HWRITE <= 1'b1;
    u_ahb.HSIZE  <= size;
    u_ahb.HBURST <= HBURST_SINGLE;

    // data phase
    @(posedge HCLK);
    u_ahb.HTRANS <= HTRANS_IDLE;
    u_ahb.HWDATA <= data << (8 * addr[1:0]);

    // TODO wait while HREADY low
  endtask

  // Returns right-justified data
  task automatic ahb_read(input haddr_t addr, input hsize_e size = HSIZE_WORD,
                          output hdata_t data);
    // address phase
    @(posedge HCLK);
    u_ahb.HADDR  <= addr;
    u_ahb.HTRANS <= HTRANS_NONSEQ;
    u_ahb.HWRITE <= 1'b0;
    u_ahb.HSIZE  <= size;
    u_ahb.HBURST <= HBURST_SINGLE;

    // data phase
    @(posedge HCLK);
    u_ahb.HTRANS <= HTRANS_IDLE;

    // HRDATA valid
    @(posedge HCLK);
    data = u_ahb.HRDATA >> (8 * addr[1:0]);

    // TODO wait while HREADY low
  endtask
endmodule
