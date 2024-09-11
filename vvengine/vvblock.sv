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
  Date   : Sun, May 26, 09:32 PM CST 2024
  Version: v0.1

  Description:
  The core building block of the vector-vector engine (VV-Engine)

================================================================================*/


`timescale 1ns/100ps
`include "ak_macros.v"


module vvblock #(
  parameter DEBUG = 1,
  parameter ID_WIDTH = 8,    // width of the block-ID
  parameter BLOCK_ID = -1,   // default block-ID (must initialize with a non-negative number of ID_WIDTH size)
  parameter RF_WIDTH = 16,   // Register-file port width
  parameter RF_DEPTH = 1024, // Depth of the register-file
  parameter ISLAST_BLK = 0   // Set this to 1 to enable last-of-column shift-register behavior
) (
  clk,

  extDataSave,   // save external data into BRAM (uses addrA)
  extDataIn,     // external data input port
  extDataOut,    // external data output port

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
  selActive,     // if this block is currently selected (active selection output)

  aluOp,         // opcode for the alu
  oregEn,        // load the OREG register with the ALU output

  vecregConf,      // configuration for the vecshift register 
  vecregLoadSel,   // selects the load input to the vecshift register
  vecregLoadEn,    // loads the selected input into the vecshift register

  serialIn,        // serial data input
  serialIn_valid,  // indicates if the serial input data is valid
  parallelIn,      // parallel input from bottom block
  parallelOut,     // parallel output to the above block
  parStatusIn,     // parallel input status bits from the bottom tile
  parStatusOut,    // parallel output status bits to the above tile

  // Debug probes
  dbg_clk_enable     // debug clock for stepping
);


  // ---- Design assumptions
  `AK_ASSERT2(BLOCK_ID >=0, BLOCK_ID_needs_to_be_set)
  `AK_ASSERT2(BLOCK_ID < (1<<ID_WIDTH), BLOCK_ID_too_big)
  `AK_ASSERT2(ISLAST_BLK >= 0, ISLAST_BLK_must_be_0_or_1)
  `AK_ASSERT2(ISLAST_BLK <= 1, ISLAST_BLK_must_be_0_or_1)


  `include "clogb2_func.v"
  `include "vvblock.svh"
  `include "vecshift_reg.svh"
  `include "vvalu.svh"


  // Local parameter declarations for IO ports and submodules
  localparam RF_ADDR_WIDTH = clogb2(RF_DEPTH-1),
             ACTCODE_WIDTH = VV_ACTCODE_WIDTH;

  localparam OREG_WIDTH    = RF_WIDTH,
             ACTREG_WIDTH  = RF_WIDTH,
             VECREG_WIDTH  = RF_WIDTH;

  localparam ALUOPND_WIDTH = RF_WIDTH,
             ALUOP_WIDTH   = VVALU_OPCODE_WIDTH;




  // IO Ports
  input wire clk;

  input                  extDataSave;
  input  [RF_WIDTH-1:0]  extDataIn; 
  output [RF_WIDTH-1:0]  extDataOut;

  input    intRegSave;
  input    intRegSel;

  input  [RF_ADDR_WIDTH-1:0] addrA;
  input  [RF_ADDR_WIDTH-1:0] addrB;

  input  [ACTCODE_WIDTH-1:0] actCode;
  input                      actlookupEn;
  input                      actregInsel;
  input                      actregEn;

  input  [ID_WIDTH-1:0]       selID;
  input                       selAll;
  input                       selEn;
  input                       selOp;
  output                      selActive;

  input [ALUOP_WIDTH-1:0]     aluOp;
  input                       oregEn;

  input  [VECREG_CONFIG_WIDTH-1:0] vecregConf;
  input                            vecregLoadSel;
  input                            vecregLoadEn;

  input                            serialIn;
  input                            serialIn_valid;
  input  [VECREG_WIDTH-1:0]        parallelIn;
  output [VECREG_WIDTH-1:0]        parallelOut;
  input  [VECREG_STATUS_WIDTH-1:0] parStatusIn;
  output [VECREG_STATUS_WIDTH-1:0] parStatusOut;


  // Debug probes
  input  dbg_clk_enable;

  // internal wires
  wire local_ce;    // for debugging



  // ---- Module Instantiation ----
  /* NOTE:   
  *   - Modules are instantiated independently
  *   - Each module has wires connected to them with a prefix same as their names
  *   - These wires will be connected together at a later section
  *   - This helps with easier management of the source file
  */


  // Register-File
  wire                       regfile_wea, regfile_web;
  wire  [RF_ADDR_WIDTH-1:0]  regfile_addra, regfile_addrb;
  wire  [RF_WIDTH-1 :0]      regfile_dia, regfile_dib;
  wire  [RF_WIDTH-1 :0]      regfile_doa, regfile_dob;

  // bram_wrfirst_ff #(
  //     .DEBUG(DEBUG),
  //     .RAM_WIDTH(RF_WIDTH),
  //     .RAM_DEPTH(RF_DEPTH)  )
  //   regfile (
  //     .clk(clk),
  //     .wea(regfile_wea),
  //     .web(regfile_web),
  //     .addra(regfile_addra),
  //     .addrb(regfile_addrb),
  //     .dia(regfile_dia),
  //     .dib(regfile_dib),
  //     .doa(regfile_doa),
  //     .dob(regfile_dob)
  //   );

  bram_wrfirst_ff #(
      .DEBUG(DEBUG),
      .RAM_WIDTH(RF_WIDTH),
      .RAM_DEPTH(RF_DEPTH*2)  )   // *2 to force use of RAMB36 for 100% BRAM utilization
      // .RAM_DEPTH(RF_DEPTH)  )
    regfile (
      .clk(clk),
      .wea(regfile_wea),
      .web(regfile_web),
      .addra({1'b0,regfile_addra}),
      .addrb({1'b0,regfile_addrb}),
      .dia(regfile_dia),
      .dib(regfile_dib),
      .doa(regfile_doa),
      .dob(regfile_dob)
    );


  // ALU Output Register: OREG
  wire                  oreg_en;
  wire [OREG_WIDTH-1:0] oreg_inp;
  wire [OREG_WIDTH-1:0] oreg_val;

  (* extract_enable = "yes" *)
  reg [OREG_WIDTH-1:0] oreg_reg = 0;

  always@(posedge clk) begin
    if(oreg_en) oreg_reg <= oreg_inp;
    else oreg_reg <= oreg_reg;
  end

  assign oreg_val = oreg_reg;   // just for consistency, we could simply use oreg_reg instead of oreg_val


  // Activation function's input Register: ACTREG
  wire                    actreg_en;
  wire [ACTREG_WIDTH-1:0] actreg_inp;
  wire [ACTREG_WIDTH-1:0] actreg_val;

  (* extract_enable = "yes" *)
  reg [ACTREG_WIDTH-1:0] actreg_reg = 0;

  always@(posedge clk) begin
    if(actreg_en) actreg_reg <= actreg_inp;
    else actreg_reg <= actreg_reg;
  end

  assign actreg_val = actreg_reg;   // just for consistency, we could simply use actreg_reg instead of actreg_val


  // Activation value to activation table row converter
  localparam ACTBL_ADDR_WIDTH = 8;    // width of the activation table row address

  wire  [ACTREG_WIDTH-1:0]     actlookup_actinp;
  wire  [ACTBL_ADDR_WIDTH-1:0] actlookup_tbladdr;

  vvact2table #(
      .DEBUG(DEBUG),
      .ACT_WIDTH(ACTREG_WIDTH),
      .ADDR_WIDTH(ACTBL_ADDR_WIDTH))
    actlookup (
      .actinp(actlookup_actinp),
      .tbladdr(actlookup_tbladdr)
    );


  // Active selection-bit register
  wire [ID_WIDTH-1:0] selreg_inp;
  wire                selreg_en;
  wire                selreg_val;

  (* extract_enable = "yes", extract_reset = "yes" *)
  reg selreg_reg = 1'b1;        // on reset, all blocks are selected

  always@(posedge clk) begin
    if(selreg_en)  selreg_reg <= selreg_inp;
    else selreg_reg <= selreg_reg;
  end

  assign selreg_inp = selAll ? 1'b1 : (selID == BLOCK_ID[ID_WIDTH-1:0]);  // if selAll is set, select the block, otherwise, use the given block-ID
  assign selreg_val = selreg_reg;   // just for consistency, we could simply use selreg_reg instead of selreg_val


  // vector-shift register for serial and parallel shifting
  wire                           vecreg_serialIn;
  wire                           vecreg_serialIn_valid;
  wire [VECREG_WIDTH-1:0]        vecreg_parallelIn;
  wire [VECREG_WIDTH-1:0]        vecreg_parallelOut;
  wire [VECREG_STATUS_WIDTH-1:0] vecreg_statusIn;
  wire [VECREG_STATUS_WIDTH-1:0] vecreg_statusOut;
  wire [VECREG_CONFIG_WIDTH-1:0] vecreg_confSig;
  wire [VECREG_WIDTH-1:0]        vecreg_loadVal;
  wire                           vecreg_loadEn;

  vecshift_reg #(
      .DEBUG(DEBUG),
      .REG_WIDTH(VECREG_WIDTH),
      .ISLAST_REG(ISLAST_BLK) )
    vecreg (
      .clk(clk),

      .serialIn(vecreg_serialIn),
      .serialIn_valid(vecreg_serialIn_valid),
      .parallelIn(vecreg_parallelIn),
      .parallelOut(vecreg_parallelOut),
      .statusIn(vecreg_statusIn),
      .statusOut(vecreg_statusOut),

      .confSig(vecreg_confSig),
      .loadVal(vecreg_loadVal),
      .loadEn(vecreg_loadEn),

      // debug probes
      .dbg_clk_enable(dbg_clk_enable)
  );


  // vector-shift register for serial and parallel shifting
  wire [ALUOPND_WIDTH-1:0]   alu_opX;
  wire [ALUOPND_WIDTH-1:0]   alu_opY;
  wire [ALUOPND_WIDTH-1:0]   alu_opA;
  wire [ALUOPND_WIDTH-1:0]   alu_opS;
  wire [ALUOPND_WIDTH-1:0]   alu_out;
  wire [ALUOP_WIDTH-1:0]     alu_opcode;

  (* keep_hierarchy = "yes" *)
  vvalu #(
      .DEBUG(DEBUG),
      .OPND_WIDTH(ALUOPND_WIDTH) )
    alu (
      .clk(clk),
      .opX(alu_opX),
      .opY(alu_opY),
      .opA(alu_opA),
      .opS(alu_opS),
      .opcode(alu_opcode),
      .out(alu_out),
      // debug probes
      .dbg_clk_enable(dbg_clk_enable)
    );


  // ---- Local Interconnect: Connecting Modules ----
  /* NOTE:
  *   - Connections are grouped by modules and top-level ports
  *   - In a connection-group, only input ports are connected
  *   - Output ports of one module are input to other modules, 
  *     or top-level output port
  */

  // Registerfile input port connections
  assign regfile_addra = addrA;
  assign regfile_addrb = (actlookupEn) ? {actCode, actlookup_tbladdr} : addrB;   // if actlookupEn set, use the lookup address
  // External data uses port-A. Here is how the selection logic works for regfile_wea,
  //   - If selective operation not requested, regfile_wea is directly controlled by extDataSave.
  //   - if selective operation requested, regfile_wea will be set by extDataSave if the selection register is set.
  assign regfile_wea = (selOp == 1'b0) ? extDataSave : extDataSave && selreg_val;
  assign regfile_dia = extDataIn;
  // Internal registers are saved using port-B. Here are the register selection codes.
  //  0: OREG
  //  1: SREG (vecreg_parallelOut)
  assign regfile_web = intRegSave;
  assign regfile_dib = intRegSel ? vecreg_parallelOut : oreg_val;

  // actlookup input port connections
  assign actlookup_actinp = actreg_val;

  // activation input register (ACT) input connections
  assign actreg_en  = actregEn,
         actreg_inp = actregInsel ? regfile_doa : oreg_val;  // 0: OREG, 1: Rx (RF-DOA)

  // selection-bit register input port connections
  assign selreg_en = selEn,
         selreg_id = selID;

  // alu input port connections
  assign alu_opX = regfile_doa,
         alu_opY = regfile_dob,
         alu_opA = actreg_val,
         alu_opS = vecreg_parallelOut,
         alu_opcode = aluOp;

  // OREG register inputs
  assign oreg_inp = alu_out,
         oreg_en  = oregEn;

  // vecreg inputs
  assign vecreg_serialIn = serialIn,
         vecreg_serialIn_valid = serialIn_valid,
         vecreg_parallelIn = parallelIn,
         vecreg_confSig  = vecregConf,
         vecreg_statusIn = parStatusIn,
         vecreg_loadVal  = vecregLoadSel ? regfile_dob : oreg_val,  // 0: OREG, 1: Ry (RF-DOB)
         vecreg_loadEn   = vecregLoadEn;

  // Top-level output ports
  assign parStatusOut = vecreg_statusOut,
         parallelOut = vecreg_parallelOut;



  // connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;
    end else begin
      assign local_ce = 1'b1;   // local debug clock is always enabled if not in DEBUG mode
    end
  endgenerate


endmodule




// Implements the activation input value to activation-table row conversion.
module vvact2table #(
  parameter DEBUG=1,
  parameter ACT_WIDTH=16,   // width of the activation input
  parameter ADDR_WIDTH=8    // width of the activation table row address
) (
  actinp,   // activation input value
  tbladdr   // address of the table row
);

  `AK_ASSERT2(ACT_WIDTH==16, ACT_WIDTH_of_16_only_valid)    // safe-guard for the future
  `AK_ASSERT2(ADDR_WIDTH==8, ADDR_WIDTH_of_8_only_valid)

  // IO Ports
  input   [ACT_WIDTH-1:0]  actinp;
  output  [ADDR_WIDTH-1:0] tbladdr;


  // Activation table row address algorithm for Q8.8 fixed-point number
  //  - Check 5 Msb's to determine the value range: non-linear, +ve
  //    saturation, -ve saturation.
  //  - If saturation, generate saturation address
  //  - else, middle 8-bits are used as the lookup address
  function automatic [ADDR_WIDTH-1:0] getTblAddr;
    input reg [ACT_WIDTH-1:0] _actinp;
    // local variables
    localparam DISCARD_COUNT = 4,                 // no. of lower bits of the activation input to be discarded
               NS_ADDR = (1 << (ADDR_WIDTH-1)),   // address of -ve saturation value; min N-bit 2's complement number (-ve)
               PS_ADDR = NS_ADDR - 1;             // address of +ve saturation value; max N-bit 2's complement number (+ve)
    reg [ADDR_WIDTH-1:0] outVal = _actinp[DISCARD_COUNT +: ADDR_WIDTH];   // for non-linear region, middle bits of the activation input is used as the address
    reg [4:0] msb5 = _actinp[ACT_WIDTH-1 -: 5];    // get the 5 MSbs for region detection
    // region detection and address computation
    if(msb5 == 0 || msb5 == '1) begin
      // non-linear region: gets the middle bits, the initial value of outVal.
    end else if (msb5[4]) begin
      // -ve saturation region
      outVal = NS_ADDR;   // use the -ve saturation address
    end else begin
      // +ve saturation region
      outVal = PS_ADDR;   // use the +ve saturation address
    end
    getTblAddr = outVal;  // return value
  endfunction
  
  assign tbladdr = getTblAddr(actinp);


endmodule
