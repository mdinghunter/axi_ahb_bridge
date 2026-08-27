`timescale 1ns/1ps

module tb_top ();
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
  assign u_ahb.HREADY = u_ahb.HREADYOUT; // single slave tie

  initial begin
    wait (HRESETn === 1'b1);
    @(posedge HCLK);
    $display("[tb_top] seed=%0d", $urandom());
    repeat (20) @(posedge HCLK);
    $finish;
  end
endmodule
