package ahb_pkg;

  localparam int AHB_ADDR_W  = 32;
  localparam int AHB_DATA_W  = 32;
  localparam int AHB_BYTES   = AHB_DATA_W / 8;   // lanes per transfer

  typedef logic [AHB_ADDR_W-1:0] haddr_t;
  typedef logic [AHB_DATA_W-1:0] hdata_t;
  typedef logic [3:0]            hprot_t;

  typedef enum logic [2:0] {
    HBURST_SINGLE = 3'b000,
    HBURST_INCR   = 3'b001,
    HBURST_WRAP4  = 3'b010,
    HBURST_INCR4  = 3'b011,
    HBURST_WRAP8  = 3'b100,
    HBURST_INCR8  = 3'b101,
    HBURST_WRAP16 = 3'b110,
    HBURST_INCR16 = 3'b111
  } hburst_e;

  typedef enum logic [2:0] {
    HSIZE_BYTE     = 3'b000,  //    8 bits
    HSIZE_HALFWORD = 3'b001,  //   16
    HSIZE_WORD     = 3'b010,  //   32
    HSIZE_2WORD    = 3'b011,  //   64
    HSIZE_4WORD    = 3'b100,  //  128
    HSIZE_8WORD    = 3'b101,  //  256
    HSIZE_16WORD   = 3'b110,  //  512
    HSIZE_32WORD   = 3'b111   // 1024
  } hsize_e;

  localparam logic [3:0] BE_LUT [16] = '{
    // HADDR[1:0] =  00       01       10       11
    /* BYTE     */ 4'b0001, 4'b0010, 4'b0100, 4'b1000,
    /* HALFWORD */ 4'b0011, 4'bxxxx, 4'b1100, 4'bxxxx,
    /* WORD     */ 4'b1111, 4'bxxxx, 4'bxxxx, 4'bxxxx,
    /* unused   */ 4'bxxxx, 4'bxxxx, 4'bxxxx, 4'bxxxx
  };

  typedef enum logic [1:0] {
    HTRANS_IDLE   = 2'b00,
    HTRANS_BUSY   = 2'b01,
    HTRANS_NONSEQ = 2'b10,
    HTRANS_SEQ    = 2'b11
  } htrans_e;

  typedef enum logic {
    HRESP_OKAY  = 1'b0,
    HRESP_ERROR = 1'b1
  } hresp_e;

endpackage
