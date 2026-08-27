package ahb_pkg;

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
    // anything beyond this is illegal for 32-bit data bus, TODO write assertion
    HSIZE_DWORD    = 3'b011,  //   64
    HSIZE_4WORD    = 3'b100,  //  128
    HSIZE_8WORD    = 3'b101,  //  256
    HSIZE_16WORD   = 3'b110,  //  512
    HSIZE_32WORD   = 3'b111   // 1024
  } hsize_e;

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
