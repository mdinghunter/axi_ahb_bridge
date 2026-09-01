package ahb_txn_pkg;
  import ahb_pkg::*;

  class ahb_txn;
    rand haddr_t addr;
    rand hsize_e size;
    rand bit is_write;
    rand hdata_t data;

    int unsigned window_bytes = 256;

    constraint size_c {
      size dist {HSIZE_WORD := 50, HSIZE_HALFWORD := 25, HSIZE_BYTE := 25};
    }
    constraint align_c {
      (size == HSIZE_HALFWORD) -> addr[0]   == 1'b0;
      (size == HSIZE_WORD)     -> addr[1:0] == 2'b00;
    }
    constraint window_c {
      addr < window_bytes;
      addr < AHB_MEM_BYTES;
    }
    constraint is_write_c {
      is_write dist {1 := 60, 0 := 40};
    }
  endclass
endpackage
