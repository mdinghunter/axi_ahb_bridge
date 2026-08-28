module ahb_slave_bfm #(parameter int MEM_WORDS = 1024) (ahb_if.slave bus);
  import ahb_pkg::*;

  hburst_e HBURST_reg;
  hprot_t HPROT_reg;
  hsize_e HSIZE_reg;
  htrans_e HTRANS_reg;
  logic HWRITE_reg;

  logic addr_phase;
  logic valid_reg;
  hdata_t mem [MEM_WORDS];

  // convert HADDR into mem_addr
  logic [$clog2(MEM_WORDS)-1:0] mem_addr, mem_addr_reg;
  assign mem_addr = bus.HADDR[$clog2(MEM_WORDS) + 1 : 2];

  always_ff @(posedge bus.HCLK or negedge bus.HRESETn) begin
    if (!bus.HRESETn) begin
      mem_addr_reg <= '0;
      // HBURST_reg <= '0;
      // HPROT_reg <= '0;
      // HSIZE_reg <= '0;
      // HTRANS_reg <= '0;
      HWRITE_reg <= 1'b0;
      valid_reg <= 1'b0;
    end else begin
      valid_reg <= addr_phase;
      if (addr_phase) begin
        mem_addr_reg <= mem_addr;
        // HBURST_reg <= HBURST;
        // HPROT_reg <= HPROT;
        // HSIZE_reg <= HSIZE;
        // HTRANS_reg <= HTRANS;
        HWRITE_reg <= bus.HWRITE;
      end
    end
  end

  always_ff @(posedge bus.HCLK) begin
    if (valid_reg && HWRITE_reg)
      mem[mem_addr_reg] <= bus.HWDATA;
  end

  assign addr_phase = bus.HSEL && bus.HREADY &&
                  (bus.HTRANS == HTRANS_NONSEQ || bus.HTRANS == HTRANS_SEQ);

  assign bus.HRDATA = (valid_reg && !HWRITE_reg) ? mem[mem_addr_reg] : 'x;

  assign bus.HREADYOUT = 1'b1; // TODO temp tie
  assign bus.HRESP = HRESP_OKAY; // TODO temp tie

  property p_hsize_valid;
    @(posedge bus.HCLK) disable iff (!bus.HRESETn)
      addr_phase |-> (bus.HSIZE inside {HSIZE_BYTE, HSIZE_HALFWORD, HSIZE_WORD});
  endproperty

  a_hsize_valid : assert property (p_hsize_valid)
    else $error("BFM: HSIZE=%s unsupported", bus.HSIZE.name());
endmodule
