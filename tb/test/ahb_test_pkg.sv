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

    // Directed lane checks, kept as a smoke test ahead of the random loop.
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
    endtask

    task automatic random_phase();
      hdata_t rdata;

      repeat (n_trans) begin
        if (!txn.randomize())
          `uvm_fatal("RANDFAIL", "txn randomize failed")

        if (txn.is_write) begin
          vif.ahb_write(txn.addr, txn.size, txn.data);
          ref_model.write(txn.addr, txn.size, txn.data);
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
