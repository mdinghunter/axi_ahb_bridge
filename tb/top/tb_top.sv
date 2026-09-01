`timescale 1ns/1ps

module tb_top #(
  parameter int TIMEOUT_NS = 100000,
  parameter int N_TRANS = 1000
) ();
  import ahb_pkg::*;
  import ahb_ref_pkg::*;
  import ahb_txn_pkg::*;

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

  // transaction class
  ahb_txn txn = new();

  initial u_ahb.ahb_idle();

  initial begin
    wait (HRESETn === 1'b1);
    @(posedge HCLK);
    $display("[tb_top] seed=%0d", $urandom());
    // ---- directed smoke tests
    u_ahb.ahb_write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
    ref_model.write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
    u_ahb.ahb_read(32'h0000_0010, HSIZE_WORD, rdata);
    ref_model.check(32'h0000_0010, HSIZE_WORD, rdata);

    // halfword lanes
    u_ahb.ahb_write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
    ref_model.write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
    u_ahb.ahb_write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
    ref_model.write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
    u_ahb.ahb_read(32'h0000_0030, HSIZE_WORD, rdata);
    ref_model.check(32'h0000_0030, HSIZE_WORD, rdata);

    // byte lanes: four byte writes, one word read
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

    // byte read back from a non-zero lane
    u_ahb.ahb_read(32'h0000_0022, HSIZE_BYTE, rdata);
    ref_model.check(32'h0000_0022, HSIZE_BYTE, rdata);

    repeat (N_TRANS) begin
      if (!txn.randomize())
        $fatal(1, "[tb_top] txn randomize failed");

      if (txn.is_write) begin
        u_ahb.ahb_write(txn.addr, txn.size, txn.data);
        ref_model.write(txn.addr, txn.size, txn.data);
      end else begin
        u_ahb.ahb_read(txn.addr, txn.size, rdata);
        ref_model.check(txn.addr, txn.size, rdata);
      end
    end
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
