/*********************************************************************************
* Copyright (c) 2024, Computer Systems Design Lab, University of Arkansas        *
*                                                                                *
* All rights reserved.                                                           *
*                                                                                *
* Permission is hereby granted, free of charge, to any person obtaining a copy   *
* of this software and associated documentation files (the "Software"), to deal  *
* in the Software without restriction, including without limitation the rights   *
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell      *
* copies of the Software, and to permit persons to whom the Software is          *
* furnished to do so, subject to the following conditions:                       *
*                                                                                *
* The above copyright notice and this permission notice shall be included in all *
* copies or substantial portions of the Software.                                *
*                                                                                *
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR     *
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,       *
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE    *
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER         *
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,  *
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE  *
* SOFTWARE.                                                                      *
**********************************************************************************

==================================================================================

  Author : MD Arafat Kabir
  Email  : arafat.sun@gmail.com
  Date   : Wed, Jun 05, 12:29 PM CST 2024
  Version: v0.1

  Description:
  This module provides an instruction word-based control interface to an array
  of vvblocks. The controller is modeled based on picaso_controller.

================================================================================*/
`timescale 1ns/100ps
`include "ak_macros.v"


module vvcontroller #(
  parameter DEBUG = 0,
  parameter INSTRUCTION_WIDTH = -1   // this is only used to cross-verify the instruction word width
) (
  clk,
  instruction,         // instruction word
  inputValid,          // Single-bit input signal, 1: other input signals are valid, 0: other input signals not valid (this is needed to work with shift networks)
  nextInstr,           // Requesting next instruction (used in the front-end interface)

  // VVBlock control signals
  vvblk_extDataSave,   // save external data into BRAM (uses addrA)
  vvblk_extDataIn,     // external data input port

  vvblk_intRegSave,    // save an internal register into BRAM (uses addrB)
  vvblk_intRegSel,     // selection code of the internal register to save

  vvblk_addrA,         // address for port-A
  vvblk_addrB,         // address for port-B

  vvblk_actCode,       // activation table selection code
  vvblk_actlookupEn,   // uses the activation-table lookup address to read from BRAM
  vvblk_actregInsel,   // selection code for the activation register (ACT) input
  vvblk_actregEn,      // loads the selected input into the activation register (ACT)

  vvblk_selID,         // currently selected block ID
  vvblk_selAll,        // set this signal to select all block irrespective of selID
  vvblk_selEn,         // set the clock-enable of the selection register (value is set based on selID)
  vvblk_selOp,         // 1: perform op if selected, 0: perform op irrespective of selID. NOTE: Only specific operations can be performed selectively.

  vvblk_aluOp,         // opcode for the alu
  vvblk_oregEn,        // load the OREG register with the ALU output

  vvblk_vecregConf,      // configuration for the vecshift register 
  vvblk_vecregLoadSel,   // selects the load input to the vecshift register
  vvblk_vecregLoadEn,    // loads the selected input into the vecshift register

  // Debug probes
  dbg_clk_enable         // debug clock for stepping
);

  `include "vvcontroller.svh"
  `include "vvengine_params.vh"
  `include "vvblock.svh"
  `include "vvalu.svh"
  `include "vecshift_reg.svh"
  `include "clogb2_func.v"

  // ---- Design assumptions
  `AK_ASSERT2(INSTRUCTION_WIDTH==VVENG_INSTRUCTION_WIDTH, INSTRUCTION_WIDTH_inconsistent)

  // Define module local constants (remove scope prefix for short-hand)
  localparam RF_WIDTH = VVENG_RF_WIDTH,
             RF_DEPTH = VVENG_RF_DEPTH,
             RF_ADDR_WIDTH = clogb2(RF_DEPTH-1),
             ACTCODE_WIDTH = VV_ACTCODE_WIDTH,
             ID_WIDTH = VVENG_ID_WIDTH,
             ALUOP_WIDTH = VVALU_OPCODE_WIDTH,
             VECREG_WIDTH = RF_WIDTH;

  localparam OPCODE_WIDTH = VVCTRL_OPCODE_WIDTH,
             FLD_RS_WIDTH = VVCTRL_INSTR_RS_WIDTH;


  // IO ports
  input                           clk; 
  input  [INSTRUCTION_WIDTH-1:0]  instruction;
  input                           inputValid;
  output                          nextInstr;

  output                      vvblk_extDataSave;
  output  [RF_WIDTH-1:0]      vvblk_extDataIn; 

  output                      vvblk_intRegSave;
  output                      vvblk_intRegSel;

  output  [RF_ADDR_WIDTH-1:0] vvblk_addrA;
  output  [RF_ADDR_WIDTH-1:0] vvblk_addrB;

  output  [ACTCODE_WIDTH-1:0] vvblk_actCode;
  output                      vvblk_actlookupEn;
  output                      vvblk_actregInsel;
  output                      vvblk_actregEn;

  output  [ID_WIDTH-1:0]      vvblk_selID;
  output                      vvblk_selAll;
  output                      vvblk_selEn;
  output                      vvblk_selOp;

  output [ALUOP_WIDTH-1:0]    vvblk_aluOp;
  output                      vvblk_oregEn;

  output  [VECREG_CONFIG_WIDTH-1:0] vvblk_vecregConf;
  output                            vvblk_vecregLoadSel;
  output                            vvblk_vecregLoadEn;


  // Debug probes
  input  dbg_clk_enable;

  // internal wires
  wire local_ce;    // for debugging


  // ---- instruction storage
  (* extract_enable = "yes" *)
  reg  [INSTRUCTION_WIDTH-1:0]  instruction_reg = VVCTRL_NOP;    // to hold the instruction word (initially set to NOP)

  // instruction_reg behavior
  always @(posedge clk) begin
    if(local_ce) begin
      if(inputValid) instruction_reg <= instruction;    // record the instruction word when inputValid signal is set
      else instruction_reg <= instruction_reg;          // otherwise, hold the value
    end else begin
      instruction_reg <= instruction_reg;   // hold the state
    end
  end



  // ---- Use set/reset flop to keep track of new instructions
  wire instr_new;                 // this signal indicates if current contents of the insturction_reg is valid
  wire instr_new_ff_clear;
  wire instr_new_ff_set;

  srFlop #(
      .DEBUG(DEBUG),
      .SET_PRIORITY(0) )     // give "set" higher priority than "clear"
    instr_new_ff (
      .clk(clk),
      .set(instr_new_ff_set),
      .clear(instr_new_ff_clear),
      .outQ(instr_new),

      // debug probes
      .dbg_clk_enable(dbg_clk_enable)   // pass the debug stepper clock
  );


  // ---- Wait cycle counter
  localparam CNTR_WIDTH = 3;

  (* extract_enable = "yes" *)
  reg  [CNTR_WIDTH-1:0] cntr_reg = 0;
  wire [CNTR_WIDTH-1:0] cntr_loadVal;    // value to be loaded on the next cycle
  wire                  cntr_loadEn;     // set it to 1 to load loadVal into the counter
  wire [CNTR_WIDTH-1:0] cntr_cntVal;     // current counter value

  // counter behavior
  always@(posedge clk) begin
    if(local_ce) begin
      if(cntr_loadEn) cntr_reg <= cntr_loadVal;
      else begin
        // coun-down to 0
        if(cntr_reg > 0) cntr_reg <= cntr_reg - 1;
        else cntr_reg <= cntr_reg;  // don't change if 0
      end
    end else begin
      cntr_reg <= cntr_reg;   // hold the state
    end
  end

  assign cntr_cntVal = cntr_reg;    // for consistency; we could have simply read cntr_reg to get the current count value.


  // instruction decoder block
  wire [OPCODE_WIDTH-1:0]    instr_opcode;
  wire [RF_ADDR_WIDTH-1:0]   instr_addr;
  wire [RF_WIDTH-1:0]        instr_data;
  wire [FLD_RS_WIDTH-1:0]    instr_rs1, instr_rs2;
  wire [ID_WIDTH-1:0]        instr_id;
  wire [ACTCODE_WIDTH-1:0 ]  instr_actcode;

  wire                       instr_isSingleCycle;
  wire [CNTR_WIDTH-1:0]      instr_waitCycles;

  vvctrl_instruction_decoder #(
      .WAITCYCLE_WIDTH(CNTR_WIDTH))
    instrDecoder (
      .instruction(instruction_reg),
      // fields
      .opcode(instr_opcode),
      .addr(instr_addr),
      .data(instr_data),
      .rs1(instr_rs1),
      .rs2(instr_rs2),
      .id(instr_id),
      .actcode(instr_actcode),
      // attribues
      .isSingleCycle(instr_isSingleCycle),
      .waitCycles(instr_waitCycles)
    );


  // ---- Next instruction request logic for handshaking
  wire nextInstr_req;

  vvctrl_requestNextInstr #(
      .CNTR_WIDTH(CNTR_WIDTH))
    genNextRequest (
      .isSingleCycle(instr_isSingleCycle),
      .isNewInstr(instr_new),
      .cntVal(cntr_cntVal),
      .reqNext(nextInstr_req)
    );


  // ---- VVBlock control signal generator module
  // AK-NOTE: outputs directly connected to the top-level outputs
  vvctrl_blkSignalGen blkSigGen (
      .clk(clk),
      .instruction(instruction_reg),

      // VVBlock control signals
      .extDataSave(vvblk_extDataSave),
      .extDataIn(vvblk_extDataIn),
      .intRegSave(vvblk_intRegSave),
      .intRegSel(vvblk_intRegSel),
      .addrA(vvblk_addrA),
      .addrB(vvblk_addrB),
      .actCode(vvblk_actCode),
      .actlookupEn(vvblk_actlookupEn),
      .actregInsel(vvblk_actregInsel),
      .actregEn(vvblk_actregEn),
      .selID(vvblk_selID),
      .selAll(vvblk_selAll),
      .selEn(vvblk_selEn),
      .selOp(vvblk_selOp),
      .aluOp(vvblk_aluOp),
      .oregEn(vvblk_oregEn),
      .vecregConf(vvblk_vecregConf),
      .vecregLoadSel(vvblk_vecregLoadSel),
      .vecregLoadEn(vvblk_vecregLoadEn),

      // debug probes
      .dbg_clk_enable(dbg_clk_enable)   // pass the debug stepper clock
    );




  // ---- Local Interconnect: Connecting Signals and Modules ----
  // instr_new inputs
  assign instr_new_ff_set = inputValid,
         instr_new_ff_clear = 1'b1;   // always clear on next cycle (AK-NOTE: clear has lower priority than set)

  // wait-cycle counter cntr inputs
  assign cntr_loadVal = instr_waitCycles,
         cntr_loadEn  = instr_new;    // counter is reloaded every time a new instruction arrives

  // top-level output ports
  assign nextInstr = nextInstr_req;




  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;
    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule



// Given the instruction, it separates the fields and computes
// some useful attributes of the instruction word. It is a purely
// combinatorial block.
module vvctrl_instruction_decoder #(
  parameter WAITCYCLE_WIDTH = 3
) (
  instruction,

  // fields
  opcode,
  addr,
  data,
  rs1,
  rs2,
  id,
  actcode,

  // attribues
  isSingleCycle,    // is this instruction a single-cycle instruction
  waitCycles        // how many cycles to wait for this instruction if multicycle, always 0 for single-cycle instructions
);

  `include "clogb2_func.v"
  `include "vvcontroller.svh"
  `include "vvengine_params.vh"

  localparam INSTRUCTION_WIDTH = VVENG_INSTRUCTION_WIDTH,
             OPCODE_WIDTH = VVCTRL_OPCODE_WIDTH,
             DATA_WIDTH = VVENG_RF_WIDTH,
             ADDR_WIDTH = clogb2(VVENG_RF_DEPTH-1),
             RS_WIDTH = VVCTRL_INSTR_RS_WIDTH,
             ID_WIDTH = VVCTRL_INSTR_ID_WIDTH,
             ACTCODE_WIDTH = VVCTRL_INSTR_ACT_WIDTH;


  input  [INSTRUCTION_WIDTH-1:0]  instruction;

  output [OPCODE_WIDTH-1:0]       opcode;
  output [ADDR_WIDTH-1:0]         addr;
  output [DATA_WIDTH-1:0]         data;
  output [RS_WIDTH-1:0]           rs1, rs2;
  output [ID_WIDTH-1:0]           id;
  output [ACTCODE_WIDTH-1:0 ]     actcode;

  output                          isSingleCycle;
  output [WAITCYCLE_WIDTH-1:0]    waitCycles;


  // Separate the instruction fields
  assign opcode = instruction[INSTRUCTION_WIDTH-1 -: OPCODE_WIDTH],   // MSbs are opcode bits
         data   = instruction[DATA_WIDTH-1:0],            // seg0
         addr   = instruction[DATA_WIDTH +: ADDR_WIDTH];  // seg1

  assign rs1 = data[RS_WIDTH-1:0],
         rs2 = data[RS_WIDTH +: RS_WIDTH];

  assign actcode = rs1[ACTCODE_WIDTH-1:0],
         id      = rs2;
        

  // ---- Instruction type detection function
  localparam [0:0] INSTR_SINGLECYCLE = 1,
                   INSTR_MULTICYCLE  = 0;

  function automatic getInstrType;
    input [OPCODE_WIDTH-1:0] opcode;
    reg instrType = INSTR_SINGLECYCLE;    // by default, assume it's single-cycle

    (* full_case, parallel_case*)
    case(opcode) 
      VVCTRL_ADD_XY    : instrType = INSTR_MULTICYCLE;
      VVCTRL_SUB_XY    : instrType = INSTR_MULTICYCLE;
      VVCTRL_MULT_XY   : instrType = INSTR_MULTICYCLE;
      VVCTRL_ADD_XSREG : instrType = INSTR_MULTICYCLE;
      VVCTRL_SUB_XSREG : instrType = INSTR_MULTICYCLE;
      VVCTRL_MULT_XSREG: instrType = INSTR_MULTICYCLE;
      VVCTRL_ACTLOOKUP : instrType = INSTR_MULTICYCLE;
      VVCTRL_MOV_Y2SREG: instrType = INSTR_MULTICYCLE;
      VVCTRL_MOV_Y2OREG: instrType = INSTR_MULTICYCLE;
      VVCTRL_MOV_X2ACT : instrType = INSTR_MULTICYCLE;
      default: instrType = INSTR_SINGLECYCLE;
    endcase
    return instrType;
  endfunction


  // ---- wait cycle count table
  // single-cycle: 0
  // multicycle  : instruction cycle count - 2
  function automatic [WAITCYCLE_WIDTH-1:0] getWaitCycles;
    input [OPCODE_WIDTH-1:0] opcode;
    reg [WAITCYCLE_WIDTH-1:0] cycleCnt = 0;

    (* full_case, parallel_case*)
    case(opcode) 
      VVCTRL_ADD_XY    : cycleCnt = 4 - 2;    // RF -> RF -> ADD -> OREG
      VVCTRL_SUB_XY    : cycleCnt = 4 - 2;    // RF -> RF -> ADD -> OREG
      VVCTRL_MULT_XY   : cycleCnt = 6 - 2;    // RF -> RF -> MULT -> MULT -> MULT -> OREG
      VVCTRL_ADD_XSREG : cycleCnt = 4 - 2;    // RF -> RF -> ADD -> OREG
      VVCTRL_SUB_XSREG : cycleCnt = 4 - 2;    // RF -> RF -> ADD -> OREG
      VVCTRL_MULT_XSREG: cycleCnt = 6 - 2;    // RF -> RF -> MULT -> MULT -> MULT -> OREG
      VVCTRL_ACTLOOKUP : cycleCnt = 3 - 2;    // RF -> RF -> OREG
      VVCTRL_MOV_Y2SREG: cycleCnt = 3 - 2;    // RF -> RF -> SREG
      VVCTRL_MOV_Y2OREG: cycleCnt = 3 - 2;    // RF -> RF -> OREG
      VVCTRL_MOV_X2ACT : cycleCnt = 3 - 2;    // RF -> RF -> ACT
      default: cycleCnt = 0;
    endcase
    return cycleCnt;
  endfunction



  assign isSingleCycle = getInstrType(opcode),
         waitCycles    = getWaitCycles(opcode);

endmodule




// Given the inputs, this module generates the next instruction
// request for handshake with front-end insterface. The function
// is wrapped inside a module for better code organization
// and visualization in the elaborated design.
module vvctrl_requestNextInstr #(
  parameter CNTR_WIDTH = 3
) (
  input isSingleCycle,
  input isNewInstr,
  input [CNTR_WIDTH-1:0] cntVal,
  output reqNext
);


  // ---- Next instruction logic
  // Next instruction is requested based on the instruction type,
  // if a new instruction just arrived, and counter value.
  //   - if new instruction arrived this cycle
  //       - if the instruction is single-cycle, request next instruction
  //       - if it is multicycle, don't request next instruction
  //   - if not a new instruction (holding the old instruction)
  //       - if count == 0, request next instruction
  //       - else, don't request next instruction
  function automatic getRequestNext;
    input isSingleCycle;
    input isNewInstr;
    input [CNTR_WIDTH-1:0] cntVal;
    reg getNext = 1'b0;   // by default, don't request next
    if(isNewInstr && isSingleCycle) getNext = 1'b1;
    else if(!isNewInstr && cntVal == 0) getNext = 1'b1;
    return getNext;
  endfunction

  assign reqNext = getRequestNext(isSingleCycle, isNewInstr, cntVal);

endmodule

