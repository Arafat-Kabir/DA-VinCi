// defines the parameters of vecshift_reg module
localparam VECREG_CONFIG_WIDTH = 2;
localparam VECREG_STATUS_WIDTH = 2;

// vecshift_tile configuration codes
localparam [VECREG_CONFIG_WIDTH-1:0]
  VECREG_IDLE        = 0,   // don't change anything (rest mode value)
  VECREG_SERIAL_EN   = 1,   // enable serial-shift mode
  VECREG_PARALLEL_EN = 2,   // enable parallel-shift mode
  VECREG_DISABLE     = 3;   // disable shifting


// vecshift_reg internal configuration output port
typedef struct packed {
  logic shiftSerialEn;
  logic shiftParallelEn;
  logic _dummy;   // to avoid a bug in xvlog
} vecreg_intConfig_t;
