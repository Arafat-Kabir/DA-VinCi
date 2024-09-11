// defines the parameters of vvalu module
localparam VVALU_OPCODE_WIDTH = 4;

// ALU output selection codes
localparam [1:0] 
  VVALU_SEL_OPY    = 0,   // select intp opY; also considered NOP
  VVALU_SEL_ADDSUB = 1,   // select add/subtract output
  VVALU_SEL_MULT   = 2,   // select multiplier output
  VVALU_SEL_RELU   = 3;   // select relu output

// ALU opcodes
localparam [VVALU_OPCODE_WIDTH-1:0]
  VVALU_ADDXS = {VVALU_SEL_ADDSUB, 2'b00},
  VVALU_ADDXY = {VVALU_SEL_ADDSUB, 2'b01},
  VVALU_SUBXS = {VVALU_SEL_ADDSUB, 2'b10},
  VVALU_SUBXY = {VVALU_SEL_ADDSUB, 2'b11},
  VVALU_MULXS = {VVALU_SEL_MULT, 2'b00},
  VVALU_MULXY = {VVALU_SEL_MULT, 2'b01},
  VVALU_RELU  = {VVALU_SEL_RELU, 2'b00},
  VVALU_PASY  = {VVALU_SEL_OPY,  2'b00},
  VVALU_NOP   = VVALU_PASY;
