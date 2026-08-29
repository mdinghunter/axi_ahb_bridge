module ahb_slave_bfm #(parameter int MEM_WORDS = 1024) (ahb_if.slave bus);
  import ahb_pkg::*;

  logic HWRITE_reg;
  logic addr_phase;
  logic valid_reg;
  hdata_t mem [MEM_WORDS];

  // byte-enable logic for non-word-sized transfers
  logic [AHB_BYTES-1:0] byte_enable, byte_enable_reg;
  assign byte_enable = (bus.HSIZE > HSIZE_WORD) ? 'x
                      : BE_LUT[{bus.HSIZE[1:0], bus.HADDR[1:0]}];

  // convert HADDR into mem_addr
  logic [$clog2(MEM_WORDS)-1:0] mem_addr, mem_addr_reg;
  assign mem_addr = bus.HADDR[$clog2(MEM_WORDS)+1:2];

  always_ff @(posedge bus.HCLK or negedge bus.HRESETn) begin
    if (!bus.HRESETn) begin
      byte_enable_reg <= '0;
      mem_addr_reg <= '0;
      HWRITE_reg <= 1'b0;
      valid_reg <= 1'b0;
    end else begin
      valid_reg <= addr_phase;
      if (addr_phase) begin
        byte_enable_reg <= byte_enable;
        mem_addr_reg <= mem_addr;
        HWRITE_reg <= bus.HWRITE;
      end
    end
  end

  always_ff @(posedge bus.HCLK) begin
    if (valid_reg && HWRITE_reg) begin
      for (int i = 0; i < AHB_BYTES; i++) begin
        if (byte_enable_reg[i])
          mem[mem_addr_reg][i*8+:8] <= bus.HWDATA[i*8+:8];
      end
    end
  end

  assign addr_phase = bus.HSEL && bus.HREADY &&
                  (bus.HTRANS == HTRANS_NONSEQ || bus.HTRANS == HTRANS_SEQ);

  always_comb begin
    bus.HRDATA = 'x;
    if (valid_reg && !HWRITE_reg)
      for (int i = 0; i < AHB_BYTES; i++)
        if (byte_enable_reg[i])
          bus.HRDATA[i*8 +: 8] = mem[mem_addr_reg][i*8 +: 8];
  end

  assign bus.HREADYOUT = 1'b1; // TODO temp tie
  assign bus.HRESP = HRESP_OKAY; // TODO temp tie

  property p_hsize_valid;
    @(posedge bus.HCLK) disable iff (!bus.HRESETn)
      addr_phase |-> (bus.HSIZE inside {HSIZE_BYTE, HSIZE_HALFWORD, HSIZE_WORD});
  endproperty

  property p_haddr_aligned;
    @(posedge bus.HCLK) disable iff (!bus.HRESETn)
      addr_phase |-> ((bus.HSIZE == HSIZE_BYTE)                          ||
                      (bus.HSIZE == HSIZE_HALFWORD && bus.HADDR[0] == 0) ||
                      (bus.HSIZE == HSIZE_WORD     && bus.HADDR[1:0] == 0));
  endproperty

  a_hsize_valid : assert property (p_hsize_valid)
    else $error("BFM: HSIZE=%s unsupported", bus.HSIZE.name());

  a_haddr_aligned : assert property (p_haddr_aligned)
    else $error("BFM: HADDR=%08h not aligned, HSIZE=%s", bus.HADDR, bus.HSIZE.name());
endmodule
