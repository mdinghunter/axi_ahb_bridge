package ahb_ref_pkg;
  import ahb_pkg::*;

  class ahb_ref_model;
    logic [7:0] mem [int unsigned]; // byte-addressable storage

    local function int check_addr(haddr_t addr, hsize_e size);
      int bytes = 1 << size;
      if ($isunknown(addr)) // addr x/z guard
        $fatal(1, "[ref] HADDR contains x/z: %h", addr);
      if (addr >= AHB_MEM_BYTES) // range guard
        $fatal(1, "[ref] HADDR %08h beyond modeled memory (%0d bytes)",
               addr, AHB_MEM_BYTES);
      if (size > HSIZE_WORD) // size guard
        $fatal(1, "[ref] unsupported HSIZE=%s", size.name());
      if (addr[1:0] % bytes != 0) // alignment guard
        $fatal(1, "[ref] HADDR %08h misaligned for %s", addr, size.name());
      return bytes;
    endfunction

    function void write(haddr_t addr, hsize_e size, hdata_t data);
      int bytes = check_addr(addr, size);
      for (int i = 0; i < bytes; i++) begin
        mem[addr+i] = data[8*i+:8];
      end
    endfunction

    function void check(haddr_t addr, hsize_e size, hdata_t got);
      hdata_t exp, got_bytes;
      int bytes = check_addr(addr, size);
      for (int i = 0; i < bytes; i++) begin
        exp[8*i+:8] = mem.exists(addr+i) ? mem[addr+i] : 8'hxx;
        got_bytes[8*i+:8] = got[8*i+:8];
      end
      if (exp !== got_bytes)
        $error("[ref] HRDATA mismatch @%08h %s: expected %08h got %08h",
        addr, size.name(), exp, got_bytes);
    endfunction
  endclass

endpackage
