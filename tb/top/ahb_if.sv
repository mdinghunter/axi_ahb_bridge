interface ahb_if (
  input HCLK,
  input HRESETn
);

  // master signals
  logic [31:0] HADDR;
  logic [2:0] HBURST;
  // logic HMASTLOCK; // locked transfers not needed currently
  logic [3:0] HPROT; // master drives it to 4'b0011
  logic [2:0] HSIZE;
  logic [1:0] HTRANS;
  logic [31:0] HWDATA;
  logic HWRITE;

  // slave signals
  logic [31:0] HRDATA;
  logic HREADYOUT;
  logic HRESP; // 1 bit for AHB-lite

  // interconnect signals
  logic HREADY;
  logic HSEL;

endinterface
