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
  Date   : Thu, Feb 15, 03:16 PM CST 2024
  Version: v1.0

  Description:
  This module implements the front-end interface to DA-VinCi. It provides
  3 abstract interfaces: FIFO-in, FIFO-out, and status registers. The clock
  domain crossing must be handled outside DA-VinCi, probably at the interface
  inputs.

================================================================================*/

`timescale 1ns/100ps


module davinci_interface # (
  parameter DEBUG = 1,
  parameter DATA_WIDTH = 16     // width of the dataout port
) (
  clk,
  // FIFO-in interface
  instruction,          // instruction input 
  instructionValid,     // instruction valid signal input
  instructionNext,      // fetch next instruction signal output
  // FIFO-out interface
  dataout,              // vector data output
  dataAttrib,           // vector data attributes output
  dataoutValid,         // vector data output valid
  // status signals
  eovInterrupt,         // interrupt output for signaling end-of-vector written to FIFO-out
  clearEOV,             // input signal to clear end-of-vector interrupt

  // interface to submodule: GEMV array 
  gemvarr_instruction,
  gemvarr_inputValid,

  // interface to submodule: vector shift register column
  vveng_instruction,
  vveng_inputValid,
  vveng_parallelOut,    // inputs connected to parallel output from the shift register column
  vveng_statusOut,      // inputs connected output status bits to the shift register column

  // Debug probes
  dbg_clk_enable         // debug clock for stepping
);

  `include "davinci_interface.svh"
  `include "picaso_instruction_decoder.inc.v"
  `include "vvcontroller.svh"
  `include "vecshift_reg.svh"


  // remove scope prefix for short-hand
  localparam GEMVARR_INSTR_WIDTH = PICASO_INSTR_WORD_WIDTH,
             DATA_ATTRIB_WIDTH   = VECREG_STATUS_WIDTH;



  // -- Module IOs
  // front-end interface signals
  input                           clk;
  input [DAVINCI_INSTR_WIDTH-1:0] instruction;
  input                           instructionValid;
  output                          instructionNext;
  output [DATA_WIDTH-1:0]         dataout;
  output [DATA_ATTRIB_WIDTH-1:0]  dataAttrib;
  output                          dataoutValid;
  output                          eovInterrupt;
  input                           clearEOV;

  // Submodule control signals
  output [GEMVARR_INSTR_WIDTH-1:0]     gemvarr_instruction;
  output                               gemvarr_inputValid;
  output [VVENG_INSTRUCTION_WIDTH-1:0] vveng_instruction;
  output                               vveng_inputValid;
  // submodule data signals
  input  [DATA_WIDTH-1:0]           vveng_parallelOut;
  input  [DATA_ATTRIB_WIDTH-1:0]    vveng_statusOut;


  // Debug probes
  input dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)


  // interface to GEMV array
  wire [PICASO_INSTR_WORD_WIDTH-1:0]  gemvIntf_instruction; 
  wire                                gemvIntf_inputValid;
  wire                                gemvIntf_busy;


  gemvarray_interface # (.DEBUG(DEBUG))
    gemvIntf (
      .clk(clk),
      .instruction(gemvIntf_instruction),
      .inputValid(gemvIntf_inputValid),
      .busy(gemvIntf_busy),

      // Debug probes
      .dbg_clk_enable(dbg_clk_enable)
    );


  // interface to Vector-shift register column
  localparam VECREG_WIDTH = DATA_WIDTH;   // AK-NOTE: DATA_WIDTH and VECREG_WIDTH must be equal

  wire  [VVENG_INSTRUCTION_WIDTH-1:0] vectorIntf_instruction;
  wire                                vectorIntf_inputValid;
  wire                                vectorIntf_busy;
  wire  [VECREG_WIDTH-1:0]            vectorIntf_parallelIn;
  wire  [VECREG_WIDTH-1:0]            vectorIntf_parallelOut;
  wire  [VECREG_STATUS_WIDTH-1:0]     vectorIntf_statusIn;
  wire  [VECREG_STATUS_WIDTH-1:0]     vectorIntf_statusOut;
  wire                                vectorIntf_endofvector;

  vveng_interface #(
      .DEBUG(DEBUG)) 
    vectorIntf (
      .clk(clk),
      // control signals
      .instruction(vectorIntf_instruction),
      .inputValid(vectorIntf_inputValid),
      .busy(vectorIntf_busy),

      // data IOs
      .parallelIn(vectorIntf_parallelIn),
      .parallelOut(vectorIntf_parallelOut),
      .statusIn(vectorIntf_statusIn),
      .statusOut(vectorIntf_statusOut),
      .endofvector(vectorIntf_endofvector),

      // Debug probes
      .dbg_clk_enable(dbg_clk_enable)
    );


  // -- FIFO-out interface controller logic
  wire isLastVector, isDataVector;
  assign {isLastVector, isDataVector} = vectorIntf_statusOut;   // unpack shift register status bits
  assign dataout = vectorIntf_parallelOut;    // parallel output goes directly to dataout port
  assign dataoutValid = isDataVector;         // if it is a data vector, we need to push it into the FIFO-out


  // -- endofvector interrupt register
  // AK-NOTE: this srFlop is used to establish a handshake 
  // with the front-end processor.
  wire eovInt_Q;
  wire eovInt_clear;
  wire eovInt_set;

  srFlop #(
      .DEBUG(DEBUG),
      .SET_PRIORITY(0) )     // give "set" higher priority than "clear" (necessary to avoid missing eov interrupts)
    eov_ff (
      .clk(clk),
      .set(eovInt_set),
      .clear(eovInt_clear),
      .outQ(eovInt_Q),

      // debug probes
      .dbg_clk_enable(dbg_clk_enable)   // pass the debug stepper clock
  );


  // -- Fetch and Dispatch unit
  wire [PICASO_INSTR_WORD_WIDTH-1:0]  fdUnit_gemvarr_instruction; 
  wire                                fdUnit_gemvarr_inputValid;
  wire                                fdUnit_gemvarr_busy;
  wire [VVENG_INSTRUCTION_WIDTH-1:0]  fdUnit_vveng_instruction;
  wire                                fdUnit_vveng_inputValid;
  wire                                fdUnit_vveng_busy;

  _davinciIntf_fetchDispatch #(.DEBUG(DEBUG))
    fdUnit (
      // top-level IOs
      .instruction(instruction),
      .instructionValid(instructionValid),
      .instructionNext(instructionNext),
      // signals for gemvarray_interface
      .gemvarr_instruction(fdUnit_gemvarr_instruction),
      .gemvarr_inputValid(fdUnit_gemvarr_inputValid),
      .gemvarr_busy(fdUnit_gemvarr_busy),
      // signals for vveng_interface
      .vveng_instruction(fdUnit_vveng_instruction),
      .vveng_inputValid(fdUnit_vveng_inputValid),
      .vveng_busy(fdUnit_vveng_busy)
    );


  // -- Local interconnect
  // inputs of eovInt register
  assign eovInt_set = vectorIntf_endofvector,    // last element of the the vector (should be a pulse)
         eovInt_clear = clearEOV;      // front-end processor issues clear on eovInt

  // inputs of vectorIntf
  assign vectorIntf_parallelIn = vveng_parallelOut,   // top-level inputs from the register column
         vectorIntf_statusIn = vveng_statusOut,       // top-level inputs from the register column
         vectorIntf_instruction = fdUnit_vveng_instruction,
         vectorIntf_inputValid  = fdUnit_vveng_inputValid;

  // inputs of gemvIntf
  assign gemvIntf_instruction = fdUnit_gemvarr_instruction,
         gemvIntf_inputValid  = fdUnit_gemvarr_inputValid;

  // inputs of fdUnit
  assign fdUnit_gemvarr_busy = gemvIntf_busy,
         fdUnit_vveng_busy  = vectorIntf_busy;

  // Top-level IO
  assign eovInterrupt = eovInt_Q,
         dataAttrib  = {isLastVector, isDataVector};

  assign gemvarr_instruction = fdUnit_gemvarr_instruction,
         gemvarr_inputValid  = fdUnit_gemvarr_inputValid,
         vveng_instruction = fdUnit_vveng_instruction,
         vveng_inputValid  = fdUnit_vveng_inputValid;


  // -- 
  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;
    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule



// This is a submodule of DA-VinCi interface. This is not supposed to be Reusable.
// This module generates signals for fetching instruction from FIFO-in and
// distributing the instruction to the appropriate submodule using ready/valid
// handshake. It maps the incoming instructions (IR3) into appropriate
// instructions for the submodule
module _davinciIntf_fetchDispatch #(
  parameter DEBUG = 1
)  (
  instruction,
  instructionValid,
  instructionNext,
  // signals for gemvarray_interface
  gemvarr_instruction,
  gemvarr_inputValid,
  gemvarr_busy,
  // signals for vveng_interface
  vveng_instruction,
  vveng_inputValid,
  vveng_busy
);


  `include "davinci_interface.svh"
  `include "picaso_instruction_decoder.inc.v"
  `include "vvcontroller.svh"

  // validate assumptions
  `AK_ASSERT2(PICASO_INSTR_WORD_WIDTH == 30, GEMV_tile_instruction_width_mismatch)

  // -- Module IOs
  input  [DAVINCI_INSTR_WIDTH-1:0]      instruction;
  input                                 instructionValid;
  output                                instructionNext;

  output [PICASO_INSTR_WORD_WIDTH-1:0]  gemvarr_instruction; 
  output                                gemvarr_inputValid;
  input                                 gemvarr_busy;

  output [VVENG_INSTRUCTION_WIDTH-1:0]  vveng_instruction;
  output                                vveng_inputValid;
  input                                 vveng_busy;


  // -- Extract instruction fields for submodules
  // instruction fields: 
  // [31:30]  : 2-bit submodule selection code
  // [29: 0]  : GEMV array instruction
  // [29: 0]  : VV-Engine instruction
  localparam SUBMODULE_CODE_WIDTH = DAVINCI_SUBMODULE_CODE_WIDTH;

  localparam [SUBMODULE_CODE_WIDTH-1:0]
             GEMVARR_SELECT = DAVINCI_SUBMODULE_GEMVARR_SELECT,
             VVENG_SELECT = DAVINCI_SUBMODULE_VVENG_SELECT;

  wire [SUBMODULE_CODE_WIDTH-1:0]  submoduleCode;

  assign submoduleCode = instruction[PICASO_INSTR_WORD_WIDTH   +: SUBMODULE_CODE_WIDTH];
  assign gemvarr_instruction = instruction[PICASO_INSTR_WORD_WIDTH-1:0];
  assign vveng_instruction  = instruction[VVENG_INSTRUCTION_WIDTH-1:0];


  // -- Generate valid signals
  wire selectVVeng, selectGEMVarr;
  assign selectVVeng  = (submoduleCode == VVENG_SELECT),
         selectGEMVarr = (submoduleCode == GEMVARR_SELECT);

  // vveng_inputValid will be set if,
  //   - current instruction is valid,
  //   - instruction selects the vvengine submodule,
  //   - and vvengine is not busy
  assign vveng_inputValid = instructionValid && selectVVeng && !vveng_busy;
  
  // gemvarr_inputValid will be set if,
  //   - current instruction is valid,
  //   - instruction selects the GEMV-array submodule,
  //   - and gemvarr is not busy
  assign gemvarr_inputValid = instructionValid && selectGEMVarr && !gemvarr_busy;


  // -- Generate instruction fetch signal
  // Instruction will be fetched if any one of the submodules
  // consumes the current instruction.
  assign instructionNext = vveng_inputValid || gemvarr_inputValid;


endmodule




// This is a submodule of DA-VinCi interface. This is not supposed to be Reusable.
// This module uses parts of the GEMV tile to mimic the controller state and generates
// signals needed for synchronization.
module gemvarray_interface # (
  parameter DEBUG = 1
) (
  clk,
  // Same inputs as gemvtile
  instruction,
  inputValid,
  // these are the signal of interest for DA-VinCi interface
  busy,

  // Debug probes
  dbg_clk_enable         // debug clock for stepping
);

  `include "gemvtile.svh"


  // -- Module IOs
  input                        clk;
  input [CTRL_INSTR_WIDTH-1:0] instruction;
  input                        inputValid;
  output                       busy;

  // Debug probes
  input dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)



  // PiCaSO controller: only the signals related to status are connected.
  // AK-NOTE: Unconnected IOs and related logic will be optimized away in synthesis.
  wire [CTRL_INSTR_WIDTH-1:0] ctrl_instruction;
  wire                        ctrl_inputValid;
  wire                        ctrl_busy;
  wire                        ctrl_nextInstr;


  (* keep_hierarchy = "yes" *)
  picaso_controller #(
      .DEBUG(DEBUG),
      .INSTRUCTION_WIDTH(CTRL_INSTR_WIDTH),
      .NET_LEVEL_WIDTH(NET_LEVEL_WIDTH),
      .OPERAND_WIDTH(PE_OPERAND_WIDTH),
      .PICASO_ID_WIDTH(ID_WIDTH),
      .TOKEN_WIDTH(CTRL_TOKEN_WIDTH),
      .PE_REG_WIDTH(PE_OPERAND_WIDTH),
      .MAX_PRECISION(MAX_PRECISION) )
    controller (
      .clk(clk),
      .instruction(ctrl_instruction),
      .token_in('0),
      .inputValid(ctrl_inputValid),
      .busy(ctrl_busy),
      .nextInstr(ctrl_nextInstr),

      // debug probes
      .dbg_clk_enable(dbg_clk_enable)
    );



  // -- Local interconnect
  // inputs to the controller
  assign ctrl_instruction = instruction,
         ctrl_inputValid  = inputValid;

  // Top-level IO
  assign busy = !ctrl_nextInstr;    // if controller not ready for next instruction, we say it's busy.


  // -- 
  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;
    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule




// This is a submodule of DA-VinCi interface. This is not supposed to be Reusable.
// This module uses parts of the vvtile to mimic the controller state and generates
// signals needed for synchronization.
module vveng_interface #(
  parameter DEBUG = 1
) (
  clk,
  // control signals
  instruction,          // instruction for the tile controller
  inputValid,           // Single-bit input signal, 1: other input signals are valid, 0: other input signals not valid (this is needed to work with shift networks)
  busy,                 // signals if the submodule is busy

  // data IOs
  parallelIn,           // parallel input from bottom tile
  parallelOut,          // parallel output to the above tile
  statusIn,             // input status bits from the bottom tile
  statusOut,            // output status bits to the above tile
  endofvector,          // signals if this is the last element of the vector; will generate a pulse

  // Debug probes
  dbg_clk_enable        // debug clock for stepping
);

  `include "vvcontroller.svh"
  `include "vecshift_reg.svh"
  `include "vvengine_params.vh"


  // remove scope prefix for short-hand
  localparam INSTR_WIDTH  = VVENG_INSTRUCTION_WIDTH,
             CONFIG_WIDTH = VECREG_CONFIG_WIDTH,
             STATUS_WIDTH = VECREG_STATUS_WIDTH,
             RF_WIDTH = VVENG_RF_WIDTH;


  // IO Ports
  input                     clk;
  input  [INSTR_WIDTH-1:0]  instruction;
  input                     inputValid;
  output logic              busy;
  input  [RF_WIDTH-1:0]     parallelIn;
  output [RF_WIDTH-1:0]     parallelOut;
  input  [STATUS_WIDTH-1:0] statusIn;
  output [STATUS_WIDTH-1:0] statusOut;
  output                    endofvector;

  // Debug probes
  input   dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)

  // unpack the top-level status input
  wire statIn_isLast, statIn_isData;
  wire isLastElement;     // indicates if this data is the last valid element of the vector

  assign {statIn_isLast, statIn_isData} = statusIn;
  assign isLastElement = statIn_isLast && statIn_isData;    // this will always generate a pulse, even if isLast stays high beyond the last valid element.

  // unpack instruction opcode
  wire [VVCTRL_OPCODE_WIDTH-1:0] opcode;
  assign opcode = instruction[VVENG_INSTRUCTION_WIDTH-1 -: VVCTRL_OPCODE_WIDTH];


  // We define the busy logic for the front-end interface as follows.
  // The VV-Engine column is busy 
  //   - if executing a multi-cycle instruction, or
  //   - if parallel-shifting in progress


  // -- Instantiate the vvcontroller for nextInstr logic
  wire  [INSTR_WIDTH-1:0]  ctrl_instruction;
  wire                     ctrl_inputValid;
  wire                     ctrl_nextInstr;

  vvcontroller  #(
      .DEBUG(DEBUG),
      .INSTRUCTION_WIDTH(INSTR_WIDTH))
    ctrl_inst (
      .clk(clk),
      .instruction(ctrl_instruction),
      .inputValid(ctrl_inputValid),
      .nextInstr(ctrl_nextInstr),
      // vvblock-array control signals are not needed
      // debug probes
      .dbg_clk_enable(dbg_clk_enable)
    );


  // -- Generate busy signal for parallel shifting
  // The shift register column is busy 
  //   - if parallel-shifting has been requested,
  //   - but the last element of the vector has not been written out to the
  //     FIFO-out interface yet.
  (* extract_enable = "yes", extract_reset = "yes" *)
  reg isPshiftReq = 0;    // tracks if parallel shifting was requested

  always@(posedge clk) begin
    if(opcode == VVCTRL_PARALLEL_EN && inputValid) isPshiftReq <= 1'b1;    // if parallel-shifting instruction is issued, set isPshiftReq
    else if(isLastElement) isPshiftReq <= 1'b0;   // if last element arrived, clear isPshiftReq (the request was served)
    else isPshiftReq <= isPshiftReq;   // otherwise, hold the value
  end




  // ---- Local Interconnect ----
  // inputs of tile controller
  assign ctrl_instruction = instruction,
         ctrl_inputValid  = inputValid;


  // top-level outputs
  assign parallelOut = parallelIn,    // data signals are simply forwarded
         statusOut   = statusIn,      // without registering
         endofvector = isLastElement;

  assign busy = isPshiftReq || !ctrl_nextInstr;  // VV-Engine is busy if executing a multi-cycle instruction, or parallel-shifting in progress


  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;   // connect the debug stepper clock

    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule
