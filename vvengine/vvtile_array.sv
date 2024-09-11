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
  Date   : Wed, Jun 12, 02:24 PM CST 2024
  Version: v0.1

  Description:
  A 1D vvtile array is created. It'll probably require pipeline stages to
  fanout the input signals to the tile inputs. The dimensions of the tiles and
  the tile-array can be varied to study the performance numbers for a given size.

================================================================================*/
`timescale 1ns/100ps
`include "ak_macros.v"


module vvtile_array #(
  parameter DEBUG = 1,
  parameter ID_WIDTH = 8,        // width of the block-ID
  parameter RF_WIDTH = 16,       // Register-file port width
  parameter RF_DEPTH = 1024,     // Depth of the register-file
  parameter BLOCK_COUNT = -1,    // Total no. of vvblocks in the whole array
  parameter TILE_HEIGHT = -1,    // Number of vvblocks in a tile
  parameter INTERTILE_STAGE = 0  // Number of pipeline stages between consecutive tiles
) (
  clk,
  // control signals
  instruction,          // instruction for the tile controller
  inputValid,           // Single-bit input signal, 1: other input signals are valid, 0: other input signals not valid (this is needed to work with shift networks)
  nextInstr,            // This output is meant to be used for testbench simulation tests only
  // data IOs
  serialIn,             // serial data input array
  serialIn_valid,       // indicates if the serial input data is valid (array)
  parallelOut,          // parallel output to the above tile
  parStatusOut,         // output status bits to the above tile

  // Debug probes
  dbg_clk_enable        // debug clock for stepping
);

  `include "vvcontroller.svh"
  `include "vecshift_reg.svh"

  // validate module parameters
  `AK_ASSERT2(ID_WIDTH > 0, ID_WIDTH_needs_to_be_large_enough)
  `AK_ASSERT2(BLOCK_COUNT > 0, BLOCK_COUNT_needs_to_be_set)
  `AK_ASSERT2(TILE_HEIGHT > 0, TILE_HEIGHT_needs_to_be_set)

  // remove scope prefix for short-hand
  localparam INSTR_WIDTH  = VVENG_INSTRUCTION_WIDTH,
             VECREG_WIDTH = RF_WIDTH,
             STATUS_WIDTH = VECREG_STATUS_WIDTH;


  // IO Ports
  input                     clk;
  input  [INSTR_WIDTH-1:0]  instruction;
  input                     inputValid;
  output                    nextInstr;
  input  [BLOCK_COUNT-1:0]  serialIn;         // array of serial input
  input  [BLOCK_COUNT-1:0]  serialIn_valid;   // array of serial input valid signals
  output [VECREG_WIDTH-1:0] parallelOut;
  output [STATUS_WIDTH-1:0] parStatusOut;

  // Debug probes
  input   dbg_clk_enable;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)


  // -- Tile array instantiation
  localparam TOT_TILE  = `DIV_CEIL(BLOCK_COUNT, TILE_HEIGHT),   // total no. of tiles (full + partial)
             FULL_CNT  = BLOCK_COUNT/TILE_HEIGHT,               // no. of full-tiles
             PART_BLK_CNT = BLOCK_COUNT%TILE_HEIGHT;            // no. of blocks in the partial-tile

  // Signal arrays connecting to each tile
  logic                    tile_nextInstr[TOT_TILE];
  logic [TILE_HEIGHT-1:0]  tile_serialIn[TOT_TILE];
  logic [TILE_HEIGHT-1:0]  tile_serialIn_valid[TOT_TILE];
  logic [RF_WIDTH-1:0]     tile_parallelIn[TOT_TILE];
  logic [RF_WIDTH-1:0]     tile_parallelOut[TOT_TILE];
  logic [STATUS_WIDTH-1:0] tile_parStatusIn[TOT_TILE];
  logic [STATUS_WIDTH-1:0] tile_parStatusOut[TOT_TILE];


  genvar g_tile, gi;

  // tile instantiation loop 
  `define SEL_TILE_HEIGHT(tile_id) (tile_id<FULL_CNT ? TILE_HEIGHT : PART_BLK_CNT)    // selects the tile height based on ID

  generate
    for(g_tile = 0; g_tile < TOT_TILE; ++g_tile) begin: tile
      (* keep_hierarchy = "yes" *)
      vvtile #(
          .DEBUG(DEBUG),
          .ID_WIDTH(ID_WIDTH),
          .START_ID(g_tile * TILE_HEIGHT),
          .RF_WIDTH(RF_WIDTH),
          .RF_DEPTH(RF_DEPTH),
          .TILE_HEIGHT(`SEL_TILE_HEIGHT(g_tile)),
          .ISLAST_TILE(g_tile==TOT_TILE-1 ? 1 : 0) )
        vectile (
          .clk(clk),
          // control signals are broadcasted
          .instruction(instruction),
          .inputValid(inputValid),
          .nextInstr(tile_nextInstr[g_tile]),
          // data IOs are distributed
          .serialIn(tile_serialIn[g_tile][`SEL_TILE_HEIGHT(g_tile)-1:0]),   // select partial bit-vector for partial tile
          .serialIn_valid(tile_serialIn_valid[g_tile][`SEL_TILE_HEIGHT(g_tile)-1:0]),
          .parallelIn(tile_parallelIn[g_tile]),
          .parallelOut(tile_parallelOut[g_tile]),
          .parStatusIn(tile_parStatusIn[g_tile]),
          .parStatusOut(tile_parStatusOut[g_tile]),

          // Debug probes
          .dbg_clk_enable(dbg_clk_enable)
      );

    end
  endgenerate

  // clean up local macros
  `undef SEL_TILE_HEIGHT


  // -- Interconnect
  generate
    // inter-tile connection: bottom-out -> top-in
    for(g_tile = 0; g_tile < TOT_TILE; ++g_tile) begin
      if(g_tile != TOT_TILE-1) begin
        assign tile_parallelIn[g_tile] = tile_parallelOut[g_tile+1];
        assign tile_parStatusIn[g_tile]   = tile_parStatusOut[g_tile+1];
      end else begin
        // the last tile
        assign tile_parallelIn[g_tile] = '0;
        assign tile_parStatusIn[g_tile]   = '0;   // not isData, not isLast
      end
    end

    // top-level serial input singals
    for(gi = 0; gi < BLOCK_COUNT; ++gi) begin
      // tile_id = gi / TILE_HEIGHT,   tile_block = gi % TILE_HEIGHT
      assign tile_serialIn[gi/TILE_HEIGHT] [gi%TILE_HEIGHT] = serialIn[gi];
      assign tile_serialIn_valid[gi/TILE_HEIGHT] [gi%TILE_HEIGHT] = serialIn_valid[gi];
    end
  
    // top-level output signals
    assign parallelOut  = tile_parallelOut[0];
    assign parStatusOut = tile_parStatusOut[0];
    assign nextInstr    = tile_nextInstr[0];    // only for simulation tests
  endgenerate




  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;   // connect the debug stepper clock

    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule
