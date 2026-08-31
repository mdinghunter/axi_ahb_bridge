module ahb_slave_bfm import ahb_pkg::*; #(
  parameter int MAX_WAIT = 3
) (ahb_if.slave bus);

  logic HWRITE_reg;
  logic addr_phase;
  logic valid_reg;
  logic [$clog2(MAX_WAIT+1)-1:0] HREADYOUT_counter;
  hdata_t mem [AHB_MEM_WORDS];

  // byte-enable logic for non-word-sized transfers
  logic [AHB_BYTES-1:0] byte_enable, byte_enable_reg;
  assign byte_enable = (bus.HSIZE > HSIZE_WORD) ? 'x
                      : BE_LUT[{bus.HSIZE[1:0], bus.HADDR[1:0]}];

  // convert HADDR into mem_addr
  logic [$clog2(AHB_MEM_WORDS)-1:0] mem_addr, mem_addr_reg;
  assign mem_addr = bus.HADDR[$clog2(AHB_MEM_WORDS)+1:2];

  always_ff @(posedge bus.HCLK or negedge bus.HRESETn) begin
    if (!bus.HRESETn) begin
      byte_enable_reg <= '0;
      mem_addr_reg <= '0;
      HWRITE_reg <= 1'b0;
      valid_reg <= 1'b0;
    end else if (bus.HREADY) begin
      valid_reg <= addr_phase;
      if (addr_phase) begin
        byte_enable_reg <= byte_enable;
        mem_addr_reg <= mem_addr;
        HWRITE_reg <= bus.HWRITE;
      end
    end
  end

  always_ff @(posedge bus.HCLK) begin
    if (valid_reg && HWRITE_reg && bus.HREADY) begin
      for (int i = 0; i < AHB_BYTES; i++) begin
        if (byte_enable_reg[i])
          mem[mem_addr_reg][i*8+:8] <= bus.HWDATA[i*8+:8];
      end
    end
  end

  always_ff @(posedge bus.HCLK or negedge bus.HRESETn) begin
    if (!bus.HRESETn) begin
      HREADYOUT_counter <= '0;
    end else begin
      if (addr_phase) begin
        HREADYOUT_counter <= stall_len();
      end else if (HREADYOUT_counter != 0) begin
        HREADYOUT_counter <= HREADYOUT_counter - 1;
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

  assign bus.HREADYOUT = (HREADYOUT_counter == 0);
  assign bus.HRESP = HRESP_OKAY; // TODO temp tie

  function automatic int stall_len();
    if (MAX_WAIT == 0) return 0;
    else if ($urandom_range(0,1) == 0) return 0;
    else return ($urandom_range(1, MAX_WAIT));
  endfunction

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

  property p_stall_no_accept;
    @(posedge bus.HCLK) disable iff (!bus.HRESETn)
      addr_phase |-> (HREADYOUT_counter == 0);
  endproperty

  a_hsize_valid : assert property (p_hsize_valid)
    else $error("AHB BFM: HSIZE=%s unsupported", bus.HSIZE.name());

  a_haddr_aligned : assert property (p_haddr_aligned)
    else $error("AHB BFM: HADDR=%08h not aligned, HSIZE=%s", bus.HADDR, bus.HSIZE.name());

  a_stall_no_accept : assert property (p_stall_no_accept)
    else $error("AHB BFM: Started new addr phase during stall, not allowed");
endmodule
