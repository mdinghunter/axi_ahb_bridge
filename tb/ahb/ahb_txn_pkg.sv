package ahb_txn_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ahb_pkg::*;

  class ahb_txn extends uvm_sequence_item;
    rand haddr_t addr;
    rand hsize_e size;
    rand bit is_write;
    rand hdata_t data;

    // observed only
    hresp_e resp = HRESP_OKAY;

    // used for genearation
    int unsigned window_bytes = 256;

    `uvm_object_utils_begin(ahb_txn)
      `uvm_field_int (addr, UVM_ALL_ON | UVM_HEX)
      `uvm_field_enum(hsize_e, size, UVM_ALL_ON)
      `uvm_field_int (is_write, UVM_ALL_ON)
      `uvm_field_int (data, UVM_ALL_ON | UVM_HEX)
      `uvm_field_enum(hresp_e, resp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "ahb_txn");
      super.new(name);
    endfunction

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
