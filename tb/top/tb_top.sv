`timescale 1ns/1ps

module tb_top #(
  parameter int TIMEOUT_NS = 100000,
  parameter int N_TRANS = 1000
) ();
  import uvm_pkg::*;
  import ahb_pkg::*;
  import ahb_test_pkg::*;

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

  initial u_ahb.ahb_idle();

  initial begin
    uvm_config_db#(virtual ahb_if)::set(null, "*", "vif", u_ahb);
    uvm_config_db#(int unsigned)::set(null, "*", "n_trans", N_TRANS);
    run_test();
  end

  // fires only if the test never finishes
  initial begin
    #(TIMEOUT_NS * 1ns);
    $fatal(1, "[tb_top] TIMEOUT after %0d ns", TIMEOUT_NS);
  end
endmodule
