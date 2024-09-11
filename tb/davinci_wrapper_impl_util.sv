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
  Date   : Tue, Feb 27, 01:38 PM CST 2024
  Version: v1.0

  Description:
  This is the top-level wrapper for DA-VinCi. It instantiates and connectes the
  submodules of DA-VinCi: interface, GEMV-tile array, and vector-shift-reg array.
  It does not instantiates the FIFOs. However, this can be directly connected
  to the FIFOs to build the DA-VinCi IP.
  This copy is used for implementation study and performanc optimization.

================================================================================*/

`timescale 1ns/100ps


module davinci_wrapper # (
  parameter DEBUG = 0,
  parameter BLK_ROW_CNT   = 256,  // No. of PiCaSO rows in the entire array
  parameter BLK_COL_CNT   = 16,   // No. of PiCaSO columns in the entire array
  parameter TILE_ROW_CNT  = 12,   // No. of PiCaSO rows in a tile
  parameter TILE_COL_CNT  =  2,   // No. of PiCaSO columns in a tile
  parameter DATAOUT_WIDTH = 16    // width of the vector dataout port (also decides the width of the vector shift registers)
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

  // -- IOs connected to davinci-interface module
  gemvArr_instruction,
  gemvArr_inputValid,
  vvtArr_instruction,
  vvtArr_inputValid,
  vvtArr_parallelOut,
  vvtArr_parStatusOut,

  // Debug probes
  dbg_clk_enable         // debug clock for stepping
);

  `include "davinci_interface.svh"
  `include "picaso_instruction_decoder.inc.v"
  `include "vvcontroller.svh"
  `include "vecshift_reg.svh"



  // remove scope prefix for short-hand
  localparam DATA_ATTRIB_WIDTH   = VECREG_STATUS_WIDTH,
             GEMVARR_INSTR_WIDTH = PICASO_INSTR_WORD_WIDTH;


  // -- Module IOs
  // front-end interface signals
  input                            clk;
  input  [DAVINCI_INSTR_WIDTH-1:0] instruction;
  input                            instructionValid;
  output                           instructionNext;
  output [DATAOUT_WIDTH-1:0]       dataout;
  output [DATA_ATTRIB_WIDTH-1:0]   dataAttrib;
  output                           dataoutValid;
  output                           eovInterrupt;
  input                            clearEOV;


  // Debug probes
  input dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)




  // -- GEMV tile array
  // wire  [PICASO_INSTR_WORD_WIDTH-1:0]  gemvArr_instruction;
  // wire                                 gemvArr_inputValid;
  input  [PICASO_INSTR_WORD_WIDTH-1:0]  gemvArr_instruction;    // IOs connected to davinci-interface
  input                                 gemvArr_inputValid;     // IOs connected to davinci-interface
  wire                                  gemvArr_serialOut[BLK_ROW_CNT];
  wire                                  gemvArr_serialOutValid[BLK_ROW_CNT];


  // (* keep_hierarchy = "yes" *)     // We want to keep hierarchy of the tiles, but not the array itsel
  gemvtile_array #(
      .DEBUG(DEBUG),
      .BLK_ROW_CNT(BLK_ROW_CNT),      // No. of PiCaSO rows in the entire array
      .BLK_COL_CNT(BLK_COL_CNT),      // No. of PiCaSO columns in the entire array
      .TILE_ROW_CNT(TILE_ROW_CNT),    // No. of PiCaSO rows in a tile
      .TILE_COL_CNT(TILE_COL_CNT))    // No. of PiCaSO columns in a tile
    gemvArr (
      .clk(clk),
      .instruction(gemvArr_instruction),
      .inputValid(gemvArr_inputValid),
      .serialOut(gemvArr_serialOut),
      .serialOutValid(gemvArr_serialOutValid)
  );


  // -- Instantiating a vvtile_array
  localparam VV_RF_DEPTH = 1024,
             VV_INTERTILE_STAGE = 0,
             VV_ID_WIDTH = 8,
             VV_INSTRUCTION_WIDTH = VVENG_INSTRUCTION_WIDTH,
             VV_BLOCK_COUNT = BLK_ROW_CNT,
             VV_VECREG_WIDTH = DATAOUT_WIDTH,  // vvengine provides the dataout stream
             VV_STATUS_WIDTH = VECREG_STATUS_WIDTH;

  // wire [VV_INSTRUCTION_WIDTH-1:0] vvtArr_instruction;
  // wire                            vvtArr_inputValid;
  input  [VV_INSTRUCTION_WIDTH-1:0]  vvtArr_instruction;   // IOs connected to davinci-interface
  input                              vvtArr_inputValid;    // IOs connected to davinci-interface
  wire                            vvtArr_nextInstr;
  wire [VV_BLOCK_COUNT-1:0]       vvtArr_serialIn;         // array of serial input
  wire [VV_BLOCK_COUNT-1:0]       vvtArr_serialIn_valid;   // array of serial input valid signals
  // wire [VV_VECREG_WIDTH-1:0]      vvtArr_parallelOut;
  // wire [VV_STATUS_WIDTH-1:0]      vvtArr_parStatusOut;
  output [VV_VECREG_WIDTH-1:0]      vvtArr_parallelOut;    // IOs connected to davinci-interface
  output [VV_STATUS_WIDTH-1:0]      vvtArr_parStatusOut;   // IOs connected to davinci-interface

  vvtile_array  #(
      .DEBUG(DEBUG),
      .ID_WIDTH(VV_ID_WIDTH),
      .RF_WIDTH(VV_VECREG_WIDTH),
      .RF_DEPTH(VV_RF_DEPTH),
      .BLOCK_COUNT(BLK_ROW_CNT),
      .TILE_HEIGHT(TILE_ROW_CNT),
      .INTERTILE_STAGE(VV_INTERTILE_STAGE))
    vvtArr (
      .clk(clk),
      // control signals
      .instruction(vvtArr_instruction),
      .inputValid(vvtArr_inputValid),
      .nextInstr(vvtArr_nextInstr),
      // data IOs
      .serialIn(vvtArr_serialIn),
      .serialIn_valid(vvtArr_serialIn_valid),
      .parallelOut(vvtArr_parallelOut),
      .parStatusOut(vvtArr_parStatusOut),

      // debug probes
      .dbg_clk_enable(1'b1)
    );



  // ---- Local interconnect
  // inputs to vvtile_array
  generate
    genvar gi;
    for(gi=0; gi<BLK_ROW_CNT; ++gi) begin
      // this generate block is needed for unpacked-array to packed-array conversion
      assign vvtArr_serialIn[gi] = gemvArr_serialOut[gi],
             vvtArr_serialIn_valid[gi] = gemvArr_serialOutValid[gi];
    end
  endgenerate




  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;
    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule



