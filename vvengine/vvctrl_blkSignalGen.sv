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
  Date   : Wed, Jun 05, 06:30 PM CST 2024
  Version: v0.1

  Description:
  It is a submodule of vvcontroller(). Given the instruction word, generates
  the control signals for VVBlock module. This module has 2 stages of registers
  to match the pipeline depth of picaso_controller.

================================================================================*/
`timescale 1ns/100ps
`include "ak_macros.v"


module vvctrl_blkSignalGen (
  clk,
  instruction,   // instruction word

  // VVBlock control signals
  extDataSave,   // save external data into BRAM (uses addrA)
  extDataIn,     // external data input port

  intRegSave,    // save an internal register into BRAM (uses addrB)
  intRegSel,     // selection code of the internal register to save

  addrA,         // address for port-A
  addrB,         // address for port-B

  actCode,       // activation table selection code
  actlookupEn,   // uses the activation-table lookup address to read from BRAM
  actregInsel,   // selection code for the activation register (ACT) input
  actregEn,      // loads the selected input into the activation register (ACT)

  selID,         // currently selected block ID
  selAll,        // set this signal to select all block irrespective of selID
  selEn,         // set the clock-enable of the selection register (value is set based on selID)
  selOp,         // 1: perform op if selected, 0: perform op irrespective of selID. NOTE: Only specific operations can be performed selectively.

  aluOp,         // opcode for the alu
  oregEn,        // load the OREG register with the ALU output

  vecregConf,      // configuration for the vecshift register 
  vecregLoadSel,   // selects the load input to the vecshift register
  vecregLoadEn,    // loads the selected input into the vecshift register

  // Debug probes
  dbg_clk_enable         // debug clock for stepping
);


  `include "vvengine_params.vh"
  `include "vvblock.svh"
  `include "vvalu.svh"
  `include "vvcontroller.svh"
  `include "vecshift_reg.svh"
  `include "clogb2_func.v"


  // Define module local constants (remove scope prefix for short-hand)
  localparam INSTRUCTION_WIDTH = VVENG_INSTRUCTION_WIDTH,
             RF_WIDTH = VVENG_RF_WIDTH,
             RF_DEPTH = VVENG_RF_DEPTH,
             RF_ADDR_WIDTH = clogb2(RF_DEPTH-1),
             ACTCODE_WIDTH = VV_ACTCODE_WIDTH,
             ID_WIDTH = VVENG_ID_WIDTH,
             ALUOP_WIDTH = VVALU_OPCODE_WIDTH,
             VECREG_WIDTH = RF_WIDTH;

  localparam OPCODE_WIDTH = VVCTRL_OPCODE_WIDTH,
             FLD_RS_WIDTH = VVCTRL_INSTR_RS_WIDTH;


  // IO Ports
  input                           clk;
  input  [INSTRUCTION_WIDTH-1:0]  instruction;

  output reg                      extDataSave = 0;
  output reg  [RF_WIDTH-1:0]      extDataIn; 

  output reg                      intRegSave = 0;
  output reg                      intRegSel;

  output reg  [RF_ADDR_WIDTH-1:0] addrA;
  output reg  [RF_ADDR_WIDTH-1:0] addrB;

  output reg  [ACTCODE_WIDTH-1:0] actCode;
  output reg                      actlookupEn;
  output reg                      actregInsel;
  output reg                      actregEn = 0;

  output reg  [ID_WIDTH-1:0]      selID;
  output reg                      selAll = 0;
  output reg                      selEn = 0;
  output reg                      selOp;

  output reg [ALUOP_WIDTH-1:0]    aluOp;
  output reg                      oregEn = 0;

  output reg  [VECREG_CONFIG_WIDTH-1:0] vecregConf = 0;
  output reg                            vecregLoadSel;
  output reg                            vecregLoadEn = 0;

  // Debug probes
  input  dbg_clk_enable;

  // internal wires
  wire local_ce;    // for debugging


  // Internal variables
  reg                      i_extDataSave = 0;
  reg  [RF_WIDTH-1:0]      i_extDataIn; 

  reg                      i_intRegSave = 0;
  reg                      i_intRegSel;

  reg  [RF_ADDR_WIDTH-1:0] i_addrA;
  reg  [RF_ADDR_WIDTH-1:0] i_addrB;

  reg  [ACTCODE_WIDTH-1:0] i_actCode;
  reg                      i_actlookupEn;
  reg                      i_actregInsel;
  reg                      i_actregEn = 0;

  reg  [ID_WIDTH-1:0]      i_selID;
  reg                      i_selAll = 0;
  reg                      i_selEn = 0;
  reg                      i_selOp;

  reg [ALUOP_WIDTH-1:0]    i_aluOp;
  reg                      i_oregEn = 0;

  reg  [VECREG_CONFIG_WIDTH-1:0] i_vecregConf = 0;
  reg                            i_vecregLoadSel;
  reg                            i_vecregLoadEn = 0;


  // instruction decoder block
  wire [OPCODE_WIDTH-1:0]    instr_opcode;
  wire [RF_ADDR_WIDTH-1:0]   instr_addr;
  wire [RF_WIDTH-1:0]        instr_data;
  wire [FLD_RS_WIDTH-1:0]    instr_rs1, instr_rs2;
  wire [ID_WIDTH-1:0]        instr_id;
  wire [ACTCODE_WIDTH-1:0 ]  instr_actcode;

  vvctrl_instruction_decoder #(
      .WAITCYCLE_WIDTH(3))    // The width does not matter, we'll not be using the related output
    instrDecoder (
      .instruction(instruction),
      // fields
      .opcode(instr_opcode),
      .addr(instr_addr),
      .data(instr_data),
      .rs1(instr_rs1),
      .rs2(instr_rs2),
      .id(instr_id),
      .actcode(instr_actcode)
    );



    // must be included here
    `include "vvctrl_blkSignalGen.svh"



  // Control signal generator logic
  always@(posedge clk) begin
    setNOP;   // This task call is essential because, following tasks set ONLY the relevant signals.
    (* full_case, parallel_case *)
    case(instr_opcode)
      VVCTRL_NOP: setNOP;
      VVCTRL_ADD_XY: setADD_XY;
      VVCTRL_SUB_XY: setSUB_XY;
      VVCTRL_MULT_XY: setMULT_XY;
      VVCTRL_ADD_XSREG: setADD_XSREG;
      VVCTRL_SUB_XSREG: setSUB_XSREG;
      VVCTRL_MULT_XSREG: setMULT_XSREG;
      VVCTRL_RELU: setRELU;
      VVCTRL_ACTLOOKUP: setACTLOOKUP;
      VVCTRL_SHIFTOFF: setSHIFTOFF;
      VVCTRL_SERIAL_EN: setSERIAL_EN;
      VVCTRL_PARALLEL_EN: setPARALLEL_EN;
      VVCTRL_SELECTBLK: setSELECTBLK;
      VVCTRL_MOV_O2SREG: setMOV_O2SREG;
      VVCTRL_MOV_Y2SREG: setMOV_Y2SREG;
      VVCTRL_MOV_SREG2R: setMOV_SREG2R;
      VVCTRL_MOV_OREG2R: setMOV_OREG2R;
      VVCTRL_MOV_Y2OREG: setMOV_Y2OREG;
      VVCTRL_MOV_OREG2ACT: setMOV_OREG2ACT;
      VVCTRL_MOV_X2ACT: setMOV_X2ACT;
      VVCTRL_SELECTALL: setSELECTALL;
      VVCTR_WRITE0: setWRITE;
      VVCTR_WRITE1: setWRITE;
      default: setNOP;    // to make it full-case
    endcase
  end


  // output register stage
  always@(posedge clk) begin
    extDataSave <= i_extDataSave;
    extDataIn <= i_extDataIn; 
    intRegSave <= i_intRegSave;
    intRegSel <= i_intRegSel;
    addrA <= i_addrA;
    addrB <= i_addrB;
    actCode <= i_actCode;
    actlookupEn <= i_actlookupEn;
    actregInsel <= i_actregInsel;
    actregEn <= i_actregEn;
    selID <= i_selID;
    selAll <= i_selAll;
    selEn <= i_selEn;
    selOp <= i_selOp;
    aluOp <= i_aluOp;
    oregEn <= i_oregEn;
    vecregConf <= i_vecregConf;
    vecregLoadSel <= i_vecregLoadSel;
    vecregLoadEn <= i_vecregLoadEn;
  end


endmodule
