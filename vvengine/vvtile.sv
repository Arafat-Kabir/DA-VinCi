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
  Date   : Wed, Jun 12, 11:51 AM CST 2024

  Version: v0.1

  Description:  <Change it>
  This is a buildling block of the VV-Engine. Each tile has an array of VV-Block
  with a controller. An array of these tiles can be connected together to 
  build the VV-Engine.

================================================================================*/
`timescale 1ns/100ps
`include "ak_macros.v"


module vvtile #(
  parameter DEBUG = 1,
  parameter ID_WIDTH = 8,      // width of the block-ID
  parameter START_ID = -1,     // ID of the first block-ID (must initialize with a non-negative number of ID_WIDTH size)
  parameter RF_WIDTH = 16,     // Register-file port width
  parameter RF_DEPTH = 1024,   // Depth of the register-file
  parameter TILE_HEIGHT = -1,  // Number of VV-Block() in the tile
  parameter ISLAST_TILE = 0    // Set this to 1 to enable last-of-column register behavior
) (
  clk,
  // control signals
  instruction,          // instruction for the tile controller
  inputValid,           // Single-bit input signal, 1: other input signals are valid, 0: other input signals not valid (this is needed to work with shift networks)
  nextInstr,            // next instruction request (this signal is exposed for simulation tests purposes only)
  // data IOs
  serialIn,             // serial data input array
  serialIn_valid,       // indicates if the serial input data is valid (array)
  parallelIn,           // parallel input from bottom tile
  parallelOut,          // parallel output to the above tile
  parStatusIn,          // input status bits from the bottom tile
  parStatusOut,         // output status bits to the above tile

  // Debug probes
  dbg_clk_enable        // debug clock for stepping
);

  `include "vvcontroller.svh"
  `include "vecshift_reg.svh"
  `include "clogb2_func.v"
  `include "vvalu.svh"
  `include "vvblock.svh"

  // validate module parameters
  `AK_ASSERT2(ID_WIDTH > 0, ID_WIDTH_needs_to_be_large_enough)
  `AK_ASSERT2(TILE_HEIGHT > 0, TILE_HEIGHT_needs_to_be_set)
  `AK_ASSERT2(START_ID >= 0, START_ID_needs_to_be_set)
  `AK_ASSERT2(START_ID+TILE_HEIGHT-1 < (1<<ID_WIDTH), START_ID_too_big)
  `AK_ASSERT2(ISLAST_TILE >= 0, ISLAST_TILE_must_be_0_or_1)
  `AK_ASSERT2(ISLAST_TILE <= 1, ISLAST_TILE_must_be_0_or_1)

  // remove scope prefix for short-hand
  localparam INSTR_WIDTH  = VVENG_INSTRUCTION_WIDTH,
             VECREG_WIDTH = RF_WIDTH,
             RF_ADDR_WIDTH = clogb2(RF_DEPTH-1),
             ACTCODE_WIDTH = VV_ACTCODE_WIDTH,
             ALUOP_WIDTH = VVALU_OPCODE_WIDTH,
             STATUS_WIDTH = VECREG_STATUS_WIDTH;


  // IO Ports
  input                     clk;
  input  [INSTR_WIDTH-1:0]  instruction;
  input                     inputValid;
  output                    nextInstr;
  input  [TILE_HEIGHT-1:0]  serialIn;         // array of serial input
  input  [TILE_HEIGHT-1:0]  serialIn_valid;   // array of serial input valid signals
  input  [VECREG_WIDTH-1:0] parallelIn;
  output [VECREG_WIDTH-1:0] parallelOut;
  input  [STATUS_WIDTH-1:0] parStatusIn;
  output [STATUS_WIDTH-1:0] parStatusOut;

  // Debug probes
  input   dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)


  // ---- Fanout tree
  // Control Signal Pipeline
  `include "vvtile.svh"
  localparam  CTRL_STAGES   = 2;    // no. of pipeline stages to use

  wire ctrlsigs_t ctrlsigs_sigsIn;
  wire ctrlsigs_t ctrlsigs_sigsOut;


  _vvtile_ctrlsig_pipe #(
    .STAGE_CNT(CTRL_STAGES),
    .ID_WIDTH(ID_WIDTH),
    .RF_WIDTH(RF_WIDTH),
    .RF_DEPTH(RF_DEPTH))
    ctrlsigs (
      .clk(clk),
      .sigsIn(ctrlsigs_sigsIn),
      .sigsOut(ctrlsigs_sigsOut)
    );



  // -- Instantiate vvblock-array
  wire                  arr_extDataSave;
  wire  [RF_WIDTH-1:0]  arr_extDataIn; 

  wire    arr_intRegSave;
  wire    arr_intRegSel;

  wire  [RF_ADDR_WIDTH-1:0] arr_addrA;
  wire  [RF_ADDR_WIDTH-1:0] arr_addrB;

  wire  [ACTCODE_WIDTH-1:0] arr_actCode;
  wire                      arr_actlookupEn;
  wire                      arr_actregInsel;
  wire                      arr_actregEn;

  wire  [ID_WIDTH-1:0]       arr_selID;
  wire                       arr_selAll;
  wire                       arr_selEn;
  wire                       arr_selOp;

  wire [ALUOP_WIDTH-1:0]     arr_aluOp;
  wire                       arr_oregEn;

  wire [VECREG_CONFIG_WIDTH-1:0] arr_vecregConf;
  wire                           arr_vecregLoadSel;
  wire                           arr_vecregLoadEn;

  wire [TILE_HEIGHT-1:0]  arr_serialIn;         // array of serial input
  wire [TILE_HEIGHT-1:0]  arr_serialIn_valid;   // array of serial input valid signals
  wire [VECREG_WIDTH-1:0] arr_parallelIn;
  wire [VECREG_WIDTH-1:0] arr_parallelOut;
  wire [STATUS_WIDTH-1:0] arr_parStatusIn;
  wire [STATUS_WIDTH-1:0] arr_parStatusOut;

  vvblock_array #(
      .DEBUG(DEBUG),
      .ID_WIDTH(ID_WIDTH),
      .START_ID(START_ID),
      .RF_WIDTH(RF_WIDTH),
      .RF_DEPTH(RF_DEPTH),
      .ARR_HEIGHT(TILE_HEIGHT),
      .ISLAST_BLK(ISLAST_TILE))
    blkArr (
      .clk(clk),

      // control signals
      .extDataSave(ctrlsigs_sigsOut.extDataSave),
      .extDataIn(ctrlsigs_sigsOut.extDataIn),

      .intRegSave(ctrlsigs_sigsOut.intRegSave),
      .intRegSel(ctrlsigs_sigsOut.intRegSel),

      .addrA(ctrlsigs_sigsOut.addrA),
      .addrB(ctrlsigs_sigsOut.addrB),

      .actCode(ctrlsigs_sigsOut.actCode),
      .actlookupEn(ctrlsigs_sigsOut.actlookupEn),
      .actregInsel(ctrlsigs_sigsOut.actregInsel),
      .actregEn(ctrlsigs_sigsOut.actregEn),

      .selID(ctrlsigs_sigsOut.selID),
      .selAll(ctrlsigs_sigsOut.selAll),
      .selEn(ctrlsigs_sigsOut.selEn),
      .selOp(ctrlsigs_sigsOut.selOp),

      .aluOp(ctrlsigs_sigsOut.aluOp),
      .oregEn(ctrlsigs_sigsOut.oregEn),

      .vecregConf(ctrlsigs_sigsOut.vecregConf),
      .vecregLoadSel(ctrlsigs_sigsOut.vecregLoadSel),
      .vecregLoadEn(ctrlsigs_sigsOut.vecregLoadEn),

      // tiling IOs
      .serialIn(arr_serialIn),
      .serialIn_valid(arr_serialIn_valid),
      .parallelIn(arr_parallelIn),
      .parallelOut(arr_parallelOut),
      .parStatusIn(arr_parStatusIn),
      .parStatusOut(arr_parStatusOut),

      // debug probes
      .dbg_clk_enable(1'b1)
    );


  // -- Instantiate the vvcontroller
  wire  [INSTR_WIDTH-1:0]  ctrl_instruction;
  wire                     ctrl_inputValid;
  wire                     ctrl_nextInstr;

  (* keep_hierarchy = "yes" *)
  vvcontroller  #(
      .DEBUG(0),
      .INSTRUCTION_WIDTH(INSTR_WIDTH))
    ctrl_inst (
      .clk(clk),
      .instruction(ctrl_instruction),
      .inputValid(ctrl_inputValid),
      .nextInstr(ctrl_nextInstr),
      // vvblock-array control signals
      .vvblk_extDataSave(ctrlsigs_sigsIn.extDataSave),
      .vvblk_extDataIn(ctrlsigs_sigsIn.extDataIn), 
      .vvblk_intRegSave(ctrlsigs_sigsIn.intRegSave),
      .vvblk_intRegSel(ctrlsigs_sigsIn.intRegSel),
      .vvblk_addrA(ctrlsigs_sigsIn.addrA),
      .vvblk_addrB(ctrlsigs_sigsIn.addrB),
      .vvblk_actCode(ctrlsigs_sigsIn.actCode),
      .vvblk_actlookupEn(ctrlsigs_sigsIn.actlookupEn),
      .vvblk_actregInsel(ctrlsigs_sigsIn.actregInsel),
      .vvblk_actregEn(ctrlsigs_sigsIn.actregEn),
      .vvblk_selID(ctrlsigs_sigsIn.selID),
      .vvblk_selAll(ctrlsigs_sigsIn.selAll),
      .vvblk_selEn(ctrlsigs_sigsIn.selEn),
      .vvblk_selOp(ctrlsigs_sigsIn.selOp),
      .vvblk_aluOp(ctrlsigs_sigsIn.aluOp),
      .vvblk_oregEn(ctrlsigs_sigsIn.oregEn),
      .vvblk_vecregConf(ctrlsigs_sigsIn.vecregConf),
      .vvblk_vecregLoadSel(ctrlsigs_sigsIn.vecregLoadSel),
      .vvblk_vecregLoadEn(ctrlsigs_sigsIn.vecregLoadEn),
      // debug probes
      .dbg_clk_enable(1'b1)
    );




  // ---- Local Interconnect ----
  // inputs of tile controller
  assign ctrl_instruction = instruction,
         ctrl_inputValid  = inputValid;

  // inputs of vvblock array
  assign arr_serialIn = serialIn,
         arr_serialIn_valid = serialIn_valid,
         arr_parallelIn = parallelIn,
         arr_parStatusIn = parStatusIn;

  // top-level outputs
  assign parallelOut  = arr_parallelOut,
         parStatusOut = arr_parStatusOut,
         nextInstr = ctrl_nextInstr;




  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;   // connect the debug stepper clock

    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule




// Auxiliary module used for pipelining control signals from controller to VVBlock Array
module _vvtile_ctrlsig_pipe #(
  parameter STAGE_CNT = -1,      // how many register stages to use, should be >= 0
  parameter ID_WIDTH = -1,
  parameter RF_WIDTH = -1,
  parameter RF_DEPTH = -1
) (
  clk,
  sigsIn,
  sigsOut
);

  `include "clogb2_func.v"
  `include "vecshift_reg.svh"
  `include "vvalu.svh"
  `include "vvblock.svh"

  // Validate parameters
  `AK_ASSERT2(STAGE_CNT>=0, STAGE_CNT__not_valid)
  `AK_ASSERT2(ID_WIDTH>=0, ID_WIDTH__not_valid)
  `AK_ASSERT2(RF_WIDTH>=0, RF_WIDTH__not_valid)
  `AK_ASSERT2(RF_DEPTH>=0, RF_DEPTH__not_valid)

  // remove scope prefix for short-hand
  localparam RF_ADDR_WIDTH = clogb2(RF_DEPTH-1),
             ACTCODE_WIDTH = VV_ACTCODE_WIDTH,
             ALUOP_WIDTH = VVALU_OPCODE_WIDTH;


  // following header needs to be included after the required parameters defined
  `include "vvtile.svh"


  // IO signals
  input  wire              clk;
  input  wire ctrlsigs_t   sigsIn;
  output wire ctrlsigs_t   sigsOut;


  // Pipeline stages
  (* max_fanout = 4 *)
  ctrlsigs_t stages[STAGE_CNT+1];     // input is stage-0, output is stage-N (total N+1)

  assign stages[0] = sigsIn;
  assign sigsOut   = stages[STAGE_CNT];

  always@(posedge clk) begin
    for(int i=1; i<=STAGE_CNT; ++i) begin
      stages[i] <= stages[i-1];
    end
  end


endmodule




// Instantiates and array of vvblock
module vvblock_array #(
  parameter DEBUG = 1,
  parameter ID_WIDTH = 8,      // width of the block-ID
  parameter START_ID = -1,     // ID of the first block-ID (must initialize with a non-negative number of ID_WIDTH size)
  parameter RF_WIDTH = 16,     // Register-file port width
  parameter RF_DEPTH = 1024,   // Depth of the register-file
  parameter ARR_HEIGHT = -1,  // Number of VV-Block() in the tile
  parameter ISLAST_BLK = 0     // Set this to 1 to enable last-of-column register behavior
) (
  clk,

  // control signals
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

  vecregConf,    // configuration for the vecshift register 
  vecregLoadSel, // selects the load input to the vecshift register
  vecregLoadEn,  // loads the selected input into the vecshift register

  // tiling IOs
  serialIn,             // serial data input array
  serialIn_valid,       // indicates if the serial input data is valid (array)
  parallelIn,           // parallel input from bottom
  parallelOut,          // parallel output to above
  parStatusIn,          // input status bits from bottom
  parStatusOut,         // output status bits to above

  // Debug probes
  dbg_clk_enable        // debug clock for stepping
);

  // `include "vvcontroller.svh"
  `include "vecshift_reg.svh"
  `include "clogb2_func.v"
  `include "vvblock.svh"
  `include "vvalu.svh"

  // validate module parameters
  `AK_ASSERT2(ID_WIDTH > 0, ID_WIDTH_needs_to_be_large_enough)
  `AK_ASSERT2(ARR_HEIGHT > 0, ARR_HEIGHT_needs_to_be_set)
  `AK_ASSERT2(START_ID >= 0, START_ID_needs_to_be_set)
  `AK_ASSERT2(START_ID+ARR_HEIGHT-1 < (1<<ID_WIDTH), START_ID_too_big)
  `AK_ASSERT2(ISLAST_BLK >= 0, ISLAST_BLK_must_be_0_or_1)
  `AK_ASSERT2(ISLAST_BLK <= 1, ISLAST_BLK_must_be_0_or_1)


  // remove scope prefix for short-hand
  localparam VECREG_WIDTH = RF_WIDTH,
             RF_ADDR_WIDTH = clogb2(RF_DEPTH-1),
             STATUS_WIDTH = VECREG_STATUS_WIDTH,
             ACTCODE_WIDTH = VV_ACTCODE_WIDTH,
             ALUOP_WIDTH = VVALU_OPCODE_WIDTH;


  // IO Ports
  input                     clk;

  input                  extDataSave;
  input  [RF_WIDTH-1:0]  extDataIn; 

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

  input [ALUOP_WIDTH-1:0]     aluOp;
  input                       oregEn;

  input  [VECREG_CONFIG_WIDTH-1:0] vecregConf;
  input                            vecregLoadSel;
  input                            vecregLoadEn;


  input  [ARR_HEIGHT-1:0]  serialIn;         // array of serial input
  input  [ARR_HEIGHT-1:0]  serialIn_valid;   // array of serial input valid signals
  input  [VECREG_WIDTH-1:0] parallelIn;
  output [VECREG_WIDTH-1:0] parallelOut;
  input  [STATUS_WIDTH-1:0] parStatusIn;
  output [STATUS_WIDTH-1:0] parStatusOut;

  // Debug probes
  input   dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)


  // define per block signals
  typedef struct packed {
    logic                 extDataSave;
    logic [RF_WIDTH-1:0]  extDataIn; 
    logic [RF_WIDTH-1:0]  extDataOut;

    logic    intRegSave;
    logic    intRegSel;

    logic [RF_ADDR_WIDTH-1:0] addrA;
    logic [RF_ADDR_WIDTH-1:0] addrB;

    logic [ACTCODE_WIDTH-1:0] actCode;
    logic                     actlookupEn;
    logic                     actregInsel;
    logic                     actregEn;

    logic [ID_WIDTH-1:0]      selID;
    logic                     selAll;
    logic                     selEn;
    logic                     selOp;
    logic                     selActive;

    logic [ALUOP_WIDTH-1:0]     aluOp;
    logic                       oregEn;

    logic [VECREG_CONFIG_WIDTH-1:0] vecregConf;
    logic                           vecregLoadSel;
    logic                           vecregLoadEn;

    logic                    serialIn;
    logic                    serialIn_valid;
    logic [VECREG_WIDTH-1:0] parallelIn;
    logic [VECREG_WIDTH-1:0] parallelOut;
    logic [STATUS_WIDTH-1:0] parStatusIn;
    logic [STATUS_WIDTH-1:0] parStatusOut;

    logic                    _dummy;   // to avoid a bug in xsim
  } blockIO_t;


  wire blockIO_t blk_sigs[0:ARR_HEIGHT-1];
  genvar gi;


  // ---- Register instances
  generate
    for(gi=0; gi<ARR_HEIGHT; ++gi) begin: blkinst
      (* keep_hierarchy = "yes" *)
      vvblock  #(
          .DEBUG(DEBUG),
          .ID_WIDTH(ID_WIDTH),
          .BLOCK_ID(START_ID+gi),
          .RF_WIDTH(RF_WIDTH),
          .RF_DEPTH(RF_DEPTH),
          .ISLAST_BLK( gi==ARR_HEIGHT-1 ? ISLAST_BLK : 0) )   // pass on the ISLAST_BLK parameter to the last block instance
        vvblk_inst (
          .clk(clk),
          .extDataSave(blk_sigs[gi].extDataSave),
          .extDataIn(blk_sigs[gi].extDataIn), 
          .intRegSave(blk_sigs[gi].intRegSave),
          .intRegSel(blk_sigs[gi].intRegSel),
          .addrA(blk_sigs[gi].addrA),
          .addrB(blk_sigs[gi].addrB),
          .actCode(blk_sigs[gi].actCode),
          .actlookupEn(blk_sigs[gi].actlookupEn),
          .actregInsel(blk_sigs[gi].actregInsel),
          .actregEn(blk_sigs[gi].actregEn),
          .selID(blk_sigs[gi].selID),
          .selAll(blk_sigs[gi].selAll),
          .selEn(blk_sigs[gi].selEn),
          .selOp(blk_sigs[gi].selOp),
          .aluOp(blk_sigs[gi].aluOp),
          .oregEn(blk_sigs[gi].oregEn),
          .vecregConf(blk_sigs[gi].vecregConf),
          .vecregLoadSel(blk_sigs[gi].vecregLoadSel),
          .vecregLoadEn(blk_sigs[gi].vecregLoadEn),
          .serialIn(blk_sigs[gi].serialIn),
          .serialIn_valid(blk_sigs[gi].serialIn_valid),
          .parallelIn(blk_sigs[gi].parallelIn),
          .parStatusIn(blk_sigs[gi].parStatusIn),
          .parallelOut(blk_sigs[gi].parallelOut),
          .parStatusOut(blk_sigs[gi].parStatusOut),
          // debug probes
          .dbg_clk_enable(dbg_clk_enable)
        );
    end
  endgenerate


  // ----  interconnect
  generate
    for(gi=0; gi<ARR_HEIGHT; ++gi) begin
      assign blk_sigs[gi].serialIn = serialIn[gi];
      assign blk_sigs[gi].serialIn_valid = serialIn_valid[gi];
      if(gi<ARR_HEIGHT-1) begin
        assign blk_sigs[gi].parallelIn = blk_sigs[gi+1].parallelOut;
        assign blk_sigs[gi].parStatusIn = blk_sigs[gi+1].parStatusOut;
      end
      // broadcast control signals
      assign 
        blk_sigs[gi].extDataSave = extDataSave,
        blk_sigs[gi].extDataIn = extDataIn, 
        blk_sigs[gi].intRegSave = intRegSave,
        blk_sigs[gi].intRegSel = intRegSel,
        blk_sigs[gi].addrA = addrA,
        blk_sigs[gi].addrB = addrB,
        blk_sigs[gi].actCode = actCode,
        blk_sigs[gi].actlookupEn = actlookupEn,
        blk_sigs[gi].actregInsel = actregInsel,
        blk_sigs[gi].actregEn = actregEn,
        blk_sigs[gi].selID = selID,
        blk_sigs[gi].selAll = selAll,
        blk_sigs[gi].selEn = selEn,
        blk_sigs[gi].selOp = selOp,
        blk_sigs[gi].aluOp = aluOp,
        blk_sigs[gi].oregEn = oregEn,
        blk_sigs[gi].vecregConf = vecregConf,
        blk_sigs[gi].vecregLoadSel = vecregLoadSel,
        blk_sigs[gi].vecregLoadEn = vecregLoadEn;
    end

    // outputs of first register are top-level outputs
    assign parallelOut  = blk_sigs[0].parallelOut;
    assign parStatusOut = blk_sigs[0].parStatusOut;

    // inputs to last register are top-level inputs
    assign blk_sigs[ARR_HEIGHT-1].parallelIn  = parallelIn;
    assign blk_sigs[ARR_HEIGHT-1].parStatusIn = parStatusIn;
  endgenerate



endmodule
