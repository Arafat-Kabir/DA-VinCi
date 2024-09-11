// Defines the parameters of vvcontroller module
localparam VVENG_INSTRUCTION_WIDTH = 30;

/* VVBlock controller instruction word is made of 3 segments: [SEG2] [SEG1] [SEG0]
*                                                             |---5b--|
*  The segments are used as follows,
*    SEG0:  DATA, {RS2, RS1}, {ID, xx}, {xx, Act-Code}
*    SEG1:  ADDR
*    SEG2:  OPCODE (SEG2 overlaps with MSb of SEG1)
*/
localparam VVCTRL_INSTR_SEG0_WIDTH = 16,
           VVCTRL_INSTR_SEG1_WIDTH = 10,
           VVCTRL_INSTR_SEG2_WIDTH = 5;

// instruction field widths
localparam VVCTRL_INSTR_RS_WIDTH = 8,
           VVCTRL_INSTR_ID_WIDTH = 8,
           VVCTRL_INSTR_ACT_WIDTH = 2;

// instruction opcodes
localparam VVCTRL_OPCODE_WIDTH = VVCTRL_INSTR_SEG2_WIDTH;
localparam [VVCTRL_OPCODE_WIDTH-1:0]
  VVCTRL_NOP          = 0,
  VVCTRL_ADD_XY       = 1,
  VVCTRL_SUB_XY       = 2,
  VVCTRL_MULT_XY      = 3,
  VVCTRL_ADD_XSREG    = 4,
  VVCTRL_SUB_XSREG    = 5,
  VVCTRL_MULT_XSREG   = 6,
  VVCTRL_RELU         = 7,
  VVCTRL_ACTLOOKUP    = 8,
  VVCTRL_SHIFTOFF     = 9,
  VVCTRL_SERIAL_EN    = 10,
  VVCTRL_PARALLEL_EN  = 11,
  VVCTRL_SELECTBLK    = 12,
  VVCTRL_MOV_O2SREG   = 13,
  VVCTRL_MOV_Y2SREG   = 14,
  VVCTRL_MOV_SREG2R   = 15,
  VVCTRL_MOV_OREG2R   = 16,
  VVCTRL_MOV_Y2OREG   = 17,
  VVCTRL_MOV_OREG2ACT = 18,
  VVCTRL_MOV_X2ACT    = 19,
  VVCTRL_SELECTALL    = 20,
  VVCTR_WRITE0        = 30,   // both 30 and 31 is for WRITE
  VVCTR_WRITE1        = 31;   // due to overlap with addr field



