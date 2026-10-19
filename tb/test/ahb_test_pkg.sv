package ahb_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ahb_pkg::*;
  import ahb_ref_pkg::*;
  import ahb_txn_pkg::*;

  class ahb_base_test extends uvm_test;
    `uvm_component_utils(ahb_base_test)

    virtual ahb_if  vif;
    ahb_ref_model   ref_model;
    ahb_txn         txn;
    int unsigned    n_trans = 1000;

    function new(string name = "ahb_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "no virtual ahb_if in the config db")
      void'(uvm_config_db#(int unsigned)::get(this, "", "n_trans", n_trans));
      ref_model = new();
      txn       = ahb_txn::type_id::create("txn");
    endfunction

    // Directed lane and strobe checks, kept as a smoke test ahead of the random loop.
    task automatic directed_phase();
      hdata_t rdata;

      vif.ahb_write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
      ref_model.write(32'h0000_0010, HSIZE_WORD, 32'hDEAD_BEEF);
      vif.ahb_read(32'h0000_0010, HSIZE_WORD, rdata);
      ref_model.check(32'h0000_0010, HSIZE_WORD, rdata);

      // halfword lanes
      vif.ahb_write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
      ref_model.write(32'h0000_0030, HSIZE_HALFWORD, 32'h0000_1122);
      vif.ahb_write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
      ref_model.write(32'h0000_0032, HSIZE_HALFWORD, 32'h0000_3344);
      vif.ahb_read(32'h0000_0030, HSIZE_WORD, rdata);
      ref_model.check(32'h0000_0030, HSIZE_WORD, rdata);

      // byte lanes: four byte writes, one word read
      vif.ahb_write(32'h0000_0020, HSIZE_BYTE, 32'h0000_00AA);
      ref_model.write(32'h0000_0020, HSIZE_BYTE, 32'h0000_00AA);
      vif.ahb_write(32'h0000_0021, HSIZE_BYTE, 32'h0000_00BB);
      ref_model.write(32'h0000_0021, HSIZE_BYTE, 32'h0000_00BB);
      vif.ahb_write(32'h0000_0022, HSIZE_BYTE, 32'h0000_00CC);
      ref_model.write(32'h0000_0022, HSIZE_BYTE, 32'h0000_00CC);
      vif.ahb_write(32'h0000_0023, HSIZE_BYTE, 32'h0000_00DD);
      ref_model.write(32'h0000_0023, HSIZE_BYTE, 32'h0000_00DD);
      vif.ahb_read(32'h0000_0020, HSIZE_WORD, rdata);
      ref_model.check(32'h0000_0020, HSIZE_WORD, rdata);

      // byte read back from a non-zero lane
      vif.ahb_read(32'h0000_0022, HSIZE_BYTE, rdata);
      ref_model.check(32'h0000_0022, HSIZE_BYTE, rdata);

      // HWSTRB corner cases. Each starts from a known full-word write.
      // sparse word write: only lanes 0 and 2 update
      dir_write(32'h0000_0040, HSIZE_WORD, 32'h1122_3344);
      dir_write(32'h0000_0040, HSIZE_WORD, 32'hAABB_CCDD, 4'b0101);
      dir_expect_word(32'h0000_0040, 32'h11BB_33DD, "sparse word 0101");

      // all-zero strobe on a word: nothing is written
      dir_write(32'h0000_0044, HSIZE_WORD, 32'h5566_7788);
      dir_write(32'h0000_0044, HSIZE_WORD, 32'hFFFF_FFFF, 4'b0000);
      dir_expect_word(32'h0000_0044, 32'h5566_7788, "zero strobe word");

      // halfword at offset 2, strobe covers only the upper byte of the halfword
      dir_write(32'h0000_0048, HSIZE_WORD, 32'hA1A2_A3A4);
      dir_write(32'h0000_004A, HSIZE_HALFWORD, 32'h0000_EEFF, 4'b1000);
      dir_expect_word(32'h0000_0048, 32'hEEA2_A3A4, "halfword strobe 1000");

      // byte at offset 1 with its own strobe low but the inactive lanes' strobes high:
      // inactive-lane strobes must be ignored, so nothing is written
      dir_write(32'h0000_004C, HSIZE_WORD, 32'hB1B2_B3B4);
      dir_write(32'h0000_004D, HSIZE_BYTE, 32'h0000_00EE, 4'b1101);
      dir_expect_word(32'h0000_004C, 32'hB1B2_B3B4, "byte, only inactive strobes set");

      // same byte write with its own strobe high: only that lane changes
      dir_write(32'h0000_004D, HSIZE_BYTE, 32'h0000_00EE, 4'b0010);
      dir_expect_word(32'h0000_004C, 32'hB1B2_EEB4, "byte, own strobe set");
    endtask

    // Write to the DUT and the reference model with the same strobe.
    task automatic dir_write(haddr_t addr, hsize_e size, hdata_t data, hstrb_t strobe = '1);
      vif.ahb_write(addr, size, data, strobe);
      ref_model.write(addr, size, data, strobe);
    endtask

    // Word read-back against a hand-computed value (independent of the model),
    // and against the reference model.
    task automatic dir_expect_word(haddr_t addr, hdata_t expected, string what);
      hdata_t rdata;
      vif.ahb_read(addr, HSIZE_WORD, rdata);
      ref_model.check(addr, HSIZE_WORD, rdata);
      if (rdata !== expected)
        `uvm_error("STRB", $sformatf("%s @%08h: expected %08h got %08h",
                                     what, addr, expected, rdata))
    endtask

    task automatic random_phase();
      hdata_t rdata;

      repeat (n_trans) begin
        if (!txn.randomize())
          `uvm_fatal("RANDFAIL", "txn randomize failed")

        if (txn.is_write) begin
          vif.ahb_write(txn.addr, txn.size, txn.data, txn.strobe);
          ref_model.write(txn.addr, txn.size, txn.data, txn.strobe);
        end else begin
          vif.ahb_read(txn.addr, txn.size, rdata);
          ref_model.check(txn.addr, txn.size, rdata);
        end
      end
    endtask

    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "stimulus");

      wait (vif.HRESETn === 1'b1);
      @(posedge vif.HCLK);
      `uvm_info("SEED", $sformatf("first draw=%0d", $urandom()), UVM_LOW)

      directed_phase();
      random_phase();

      repeat (5) @(posedge vif.HCLK);
      $display("TEST DONE");
      phase.drop_objection(this, "stimulus");
    endtask
  endclass
endpackage
