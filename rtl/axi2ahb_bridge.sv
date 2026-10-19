`timescale 1ns/1ps

// AXI4 subordinate -> AHB5 manager bridge.
// v1: single outstanding, AxLEN=0, OKAY/SLVERR only. One clock, sync reset.
module axi2ahb_bridge #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W   = 4
) (
  // ---------------------------------------------------------------
  // clock and reset (ACLK drives both sides; HCLK = ACLK)
  // ---------------------------------------------------------------
  input  logic                  ACLK,
  input  logic                  ARESETn,

  // ---------------------------------------------------------------
  // AXI4 subordinate: write address channel (AW)
  // ---------------------------------------------------------------
  input  logic [ID_W-1:0]       AWID,
  input  logic [ADDR_W-1:0]     AWADDR,
  input  logic [7:0]            AWLEN,
  input  logic [2:0]            AWSIZE,
  input  logic [1:0]            AWBURST,
  input  logic                  AWVALID,
  output logic                  AWREADY,

  // write data channel (W)
  input  logic [DATA_W-1:0]     WDATA,
  input  logic [DATA_W/8-1:0]   WSTRB,
  input  logic                  WLAST,
  input  logic                  WVALID,
  output logic                  WREADY,

  // write response channel (B)
  output logic [ID_W-1:0]       BID,
  output logic [1:0]            BRESP,
  output logic                  BVALID,
  input  logic                  BREADY,

  // read address channel (AR)
  input  logic [ID_W-1:0]       ARID,
  input  logic [ADDR_W-1:0]     ARADDR,
  input  logic [7:0]            ARLEN,
  input  logic [2:0]            ARSIZE,
  input  logic [1:0]            ARBURST,
  input  logic                  ARVALID,
  output logic                  ARREADY,

  // read data channel (R)
  output logic [ID_W-1:0]       RID,
  output logic [DATA_W-1:0]     RDATA,
  output logic [1:0]            RRESP,
  output logic                  RLAST,
  output logic                  RVALID,
  input  logic                  RREADY,

  // ---------------------------------------------------------------
  // AHB5 manager (properties: Write_Strobes=True; Secure_Transfers,
  // Exclusive_Transfers, Extended_Memory_Types = False)
  // ---------------------------------------------------------------
  output logic [ADDR_W-1:0]     HADDR,
  output logic [2:0]            HBURST,
  output logic [3:0]            HPROT,
  output logic [2:0]            HSIZE,
  output logic [1:0]            HTRANS,
  output logic [DATA_W-1:0]     HWDATA,
  output logic [DATA_W/8-1:0]   HWSTRB,
  output logic                  HWRITE,
  input  logic [DATA_W-1:0]     HRDATA,
  input  logic                  HREADY,
  input  logic                  HRESP
);

endmodule
