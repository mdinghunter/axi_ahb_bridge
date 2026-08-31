`timescale 1ns/1ps

module tb_top #(parameter int TIMEOUT_NS = 1000) ();
  import ahb_pkg::*;
  import ahb_ref_pkg::*;

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
  ahb_slave_bfm u_slave (.bus(u_ahb));
  hdata_t rdata;

  // reference model
  ahb_ref_model ref_model = new();

  initial u_ahb.ahb_idle();

  initial begin
    wait (HRESETn === 1'b1);
    @(posedge HCLK);
    $display("[tb_top] seed=%0d", $urandom());
    // ---- word write / read ----------------------------------------
    u_ahb.ahb_write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
    ref_model.write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
    u_ahb.ahb_read(32'h0000_0010, HSIZE_WORD, rdata);
    ref_model.check(32'h0000_0010, HSIZE_WORD, rdata);
    if (rdata !== 32'hDEAD_BEEF)
      $error("word read got %08h, expected DEADBEEF", rdata);
    else
      $display("[tb_top] word write/read PASS");

    // ---- halfword lanes -------------------------------------------
    u_ahb.ahb_write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
    ref_model.write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
    u_ahb.ahb_write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
    ref_model.write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
    u_ahb.ahb_read(32'h0000_0030, HSIZE_WORD, rdata);
    ref_model.check(32'h0000_0030, HSIZE_WORD, rdata);
    if (rdata !== 32'h3344_1122)
      $error("halfword-lane read got %08h, expected 33441122", rdata);
    else
      $display("[tb_top] halfword-lane write/read PASS");

    // ---- byte lanes: four byte writes, one word read ---------------
    u_ahb.ahb_write(32'h0000_0020, HSIZE_BYTE, 32'h0000_00AA);
    ref_model.write(32'h0000_0020, HSIZE_BYTE, 32'h0000_00AA);
    u_ahb.ahb_write(32'h0000_0021, HSIZE_BYTE, 32'h0000_00BB);
    ref_model.write(32'h0000_0021, HSIZE_BYTE, 32'h0000_00BB);
    u_ahb.ahb_write(32'h0000_0022, HSIZE_BYTE, 32'h0000_00CC);
    ref_model.write(32'h0000_0022, HSIZE_BYTE, 32'h0000_00CC);
    u_ahb.ahb_write(32'h0000_0023, HSIZE_BYTE, 32'h0000_00DD);
    ref_model.write(32'h0000_0023, HSIZE_BYTE, 32'h0000_00DD);
    u_ahb.ahb_read(32'h0000_0020, HSIZE_WORD, rdata);
    ref_model.check(32'h0000_0020, HSIZE_WORD, rdata);
    if (rdata !== 32'hDDCC_BBAA)
      $error("byte-lane read got %08h, expected DDCCBBAA", rdata);
    else
      $display("[tb_top] byte-lane write PASS");

    // ---- byte read back from a non-zero lane -----------------------
    u_ahb.ahb_read(32'h0000_0022, HSIZE_BYTE, rdata);
    ref_model.check(32'h0000_0022, HSIZE_BYTE, rdata);
    if (rdata[7:0] !== 8'hCC)
      $error("byte read of 0x22 got %02h, expected CC", rdata[7:0]);
    else
      $display("[tb_top] byte read PASS");
    repeat (5) @(posedge HCLK);
    $display("TEST DONE");
    $finish;
  end

  // fires only if the stimulus block never reaches $finish
  initial begin
    #(TIMEOUT_NS * 1ns);
    $fatal(1, "[tb_top] TIMEOUT after %0d ns", TIMEOUT_NS);
  end
endmodule
