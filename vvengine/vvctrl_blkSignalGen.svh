// This file is technically a part of the vvctrl_blkSignalGen module.
// This section of the code is extracted into a separate file to 
// maintain readability.


// Task to set the control signals to NOP state.
// The non-control signals are set to their most common value
// to reduce the muxing logic generation.
task automatic setNOP;
  i_extDataSave = 0;
  i_extDataIn = instr_data; 
  i_intRegSave = 0;
  i_intRegSel = 0;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_addrB = {2'h0, instr_rs1};    // address of RY
  i_actCode = instr_actcode;
  i_actlookupEn = 0;
  i_actregInsel = 0;
  i_actregEn = 0;
  i_selID = instr_id;
  i_selAll = 0;
  i_selEn = 0;
  i_selOp = 0;
  i_aluOp = VVALU_NOP;
  i_oregEn = 0;
  i_vecregConf = VECREG_IDLE;
  i_vecregLoadSel = 0;
  i_vecregLoadEn = 0;
endtask


// control signals for ADD-XY
task automatic setADD_XY;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_addrB = {2'h0, instr_rs1};    // address of RY
  i_aluOp = VVALU_ADDXY;
  i_oregEn = 1'b1;
endtask


// control signals for SUB-XY
task automatic setSUB_XY;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_addrB = {2'h0, instr_rs1};    // address of RY
  i_aluOp = VVALU_SUBXY;
  i_oregEn = 1'b1;
endtask


// control signals for MULT-XY
task automatic setMULT_XY;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_addrB = {2'h0, instr_rs1};    // address of RY
  i_aluOp = VVALU_MULXY;
  i_oregEn = 1'b1;
endtask


// control signals for ADD-XSREG
task automatic setADD_XSREG;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_aluOp = VVALU_ADDXS;  // ALU automatically selects the SREG operand
  i_oregEn = 1'b1;
endtask


// control signals for SUB-XSREG
task automatic setSUB_XSREG;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_aluOp = VVALU_SUBXS;  // ALU automatically selects the SREG operand
  i_oregEn = 1'b1;
endtask


// control signals for MULT-XSREG
task automatic setMULT_XSREG;
  i_addrA = {2'h0, instr_rs2};    // address of RX
  i_aluOp = VVALU_MULXS;  // ALU automatically selects the SREG operand
  i_oregEn = 1'b1;
endtask


// control signals for RELU
task automatic setRELU;
  i_aluOp = VVALU_RELU;  // ALU automatically selects the ACT register
  i_oregEn = 1'b1;
endtask


// control signals for activation lookup ACTLOOKUP
task automatic setACTLOOKUP;
  i_actCode = instr_actcode;
  i_actlookupEn = 1'b1;   // use the lookup address
  i_aluOp = VVALU_PASY;   // activation value is read through port-RY
  i_oregEn = 1'b1;
endtask


// control signals for SHIFTOFF
task automatic setSHIFTOFF;
  i_vecregConf = VECREG_DISABLE;
endtask


// control signals for SERIAL_EN
task automatic setSERIAL_EN;
  i_vecregConf = VECREG_SERIAL_EN;
endtask


// control signals for PARALLEL_EN
task automatic setPARALLEL_EN;
  i_vecregConf = VECREG_PARALLEL_EN;
endtask


// control signals for SELECTBLK
task automatic setSELECTBLK;
  i_selID = instr_id;
  i_selEn = 1'b1;
endtask


// control signals for SELECTALL
task automatic setSELECTALL;
  i_selAll = 1'b1;
  i_selEn = 1'b1;
endtask


// control signals for MOV_O2SREG
task automatic setMOV_O2SREG;
  i_vecregLoadSel = 0;      // 0: OREG, 1: RY
  i_vecregLoadEn  = 1'b1;
endtask


// control signals for MOV_Y2SREG
task automatic setMOV_Y2SREG;
  i_vecregLoadSel = 1;          // 0: OREG, 1: RY
  i_vecregLoadEn  = 1'b1;
  i_addrB = {2'h0, instr_rs1};  // address of RY
endtask


// control signals for MOV_SREG2R
task automatic setMOV_SREG2R;
  i_intRegSave = 1'b1;
  i_intRegSel = 1;                  // 1: SREG, 0: OREG
  i_addrB = {2'h0, instr_rs1};      // port-B is used to save internal registers, encode RD in rs1 using 8-bits.
endtask


// control signals for MOV_OREG2R
task automatic setMOV_OREG2R;
  i_intRegSave = 1'b1;
  i_intRegSel = 0;                  // 1: SREG, 0: OREG
  i_addrB = {2'h0, instr_rs1};      // port-B is used to save internal registers, encode RD in rs1 using 8-bits.
endtask


// control signals for MOV_Y2OREG
task automatic setMOV_Y2OREG;
  i_addrB = {2'h0, instr_rs1};    // encode RY in rs1 using 8-bits
  i_aluOp = VVALU_PASY;
  i_oregEn = 1'b1;
endtask


// control signals for MOV_OREG2ACT
task automatic setMOV_OREG2ACT;
  i_actregInsel = 0;    // 0: OREG, 1: Rx (RF-DOA)
  i_actregEn = 1'b1;
endtask


// control signals for MOV_X2ACT
task automatic setMOV_X2ACT;
  i_addrA = {2'h0, instr_rs2};  // encode RX in rs2 using 8-bits
  i_actregInsel = 1;    // 0: OREG, 1: Rx (RF-DOA)
  i_actregEn = 1'b1;
endtask


// control signals for WRITE
task automatic setWRITE;
  i_extDataSave = 1'b1;
  i_extDataIn = instr_data; 
  i_addrA = instr_addr;   // external data is written through port-A
  i_selOp = 1'b1;         // WRITE is a selective OP
endtask

