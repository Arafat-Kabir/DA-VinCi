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
  Date   : Tue, May 28, 02:41 PM CST 2024
  Version: v1.0

  Description:
  This is a building block of the vector-shift column of IMAGine.
  There may be some changes for the VV-Engine from the control perspective.

================================================================================*/
`timescale 1ns/100ps
`include "ak_macros.v"


module vecshift_reg #(
  parameter DEBUG = 1,
  parameter REG_WIDTH = -1,
  parameter ISLAST_REG = 0        // Set this to 1 to enable last-of-column register behavior
) ( 
  clk,

  serialIn,             // serial data input
  serialIn_valid,       // indicates if the serial input data is valid
  parallelIn,           // parallel input 
  parallelOut,          // parallel output
  statusIn,             // input status bits
  statusOut,            // output status bits

  confSig,              // configuration signals to change behavior
  curConfig,            // outputs the current internal configuration (Needed for the top-level interface logic)
  loadVal,              // value to load into the register
  loadEn,               // load the given value (parallel-shifting mode has higher priority)

  // Debug probes
  dbg_clk_enable,       // debug clock for stepping

  dbg_shiftSerialEn,
  dbg_shiftParallelEn
);


  `include "vecshift_reg.svh"


  // validate module parameters
  `AK_ASSERT2(REG_WIDTH > 0, REG_WIDTH_must_be_set)
  `AK_ASSERT2(ISLAST_REG >= 0, ISLAST_REG_must_be_0_or_1)
  `AK_ASSERT2(ISLAST_REG <= 1, ISLAST_REG_must_be_0_or_1)

  // remove scope prefix for short-hand
  localparam CONFIG_WIDTH = VECREG_CONFIG_WIDTH,
             STATUS_WIDTH = VECREG_STATUS_WIDTH;

  // This constant is used to conditionally make "untouched" internal debug probes
  localparam dbg_yn = DEBUG ? "yes" : "no";   // internal debug probes becomes "dont_touch" if DEBUG==True


  // IO Ports
  input                     clk;

  input                     serialIn;
  input                     serialIn_valid;
  input  [REG_WIDTH-1:0]    parallelIn;
  output [REG_WIDTH-1:0]    parallelOut;
  input  [STATUS_WIDTH-1:0] statusIn;
  output [STATUS_WIDTH-1:0] statusOut;

  input  [CONFIG_WIDTH-1:0] confSig;
  output vecreg_intConfig_t curConfig;
  input  [REG_WIDTH-1:0]    loadVal;
  input                     loadEn;

  // Debug probes
                            input   dbg_clk_enable;
  (* mark_debug = dbg_yn *) output  dbg_shiftSerialEn;
  (* mark_debug = dbg_yn *) output  dbg_shiftParallelEn;


  // internal signals
  wire local_ce;    // for module-level clock-enable (isn't passed to submodules)


  // ---- Shift register
  wire                 shreg_serialIn;
  wire [REG_WIDTH-1:0] shreg_parallelIn;
  wire                 shreg_serialOut;
  wire [REG_WIDTH-1:0] shreg_parallelOut;
  wire                 shreg_shiftEn;
  wire                 shreg_loadEn;

  shiftReg #(
      .DEBUG(DEBUG),
      .REG_WIDTH(REG_WIDTH),
      .MSB_IN(1) )
    shreg (
      .clk(clk),
      .serialIn(shreg_serialIn),
      .parallelIn(shreg_parallelIn),
      .serialOut(shreg_serialOut),
      .parallelOut(shreg_parallelOut),
      .shiftEn(shreg_shiftEn),
      .loadEn(shreg_loadEn),

      // Debug probes
      .dbg_clk_enable(dbg_clk_enable)    // pass the debug stepper clock
    );


  // ---- Control state registers
  (* extract_enable = "yes" *)
  reg shiftSerialEn = 0,        // controls serial shifting operation
      shiftParallelEn = 0;       // controls parallel shifting (higher priority over shiftSerialEn)

  // control state registers behavior
  always@(posedge clk) begin
    if (local_ce) begin
      // select the next state based on confSig
      (* full_case, parallel_case *)
      case(confSig)
        VECREG_IDLE: begin
          // Change nothing
        end
        VECREG_SERIAL_EN: begin
          shiftSerialEn  <= 1;
          shiftParallelEn <= 0;
        end
        VECREG_PARALLEL_EN: begin
          shiftSerialEn  <= 0;
          shiftParallelEn <= 1;
        end
        VECREG_DISABLE: begin
          shiftSerialEn  <= 0;
          shiftParallelEn <= 0;
        end
        default: $display("WARN: invalid confSig for vecshift-reg, confSig: b%0b (%s:%0d)  %0t", confSig, `__FILE__, `__LINE__, $time);
      endcase

    // hold state for debugging (local_ce == 0) 
    end else begin
      shiftSerialEn  <= shiftSerialEn;
      shiftParallelEn <= shiftParallelEn;
    end
  end


  // ---- Status registers
  (* extract_enable = "yes" *)
  reg isData = 0,        // indicates if the data in shift-register is a valid data during column shifting (parallel shift)
      isLast = 0;        // indicates if the data in shift-register is the last data during column shifting (parallel shift)

  // pack-unpack status inputs
  wire isData_inp, isLast_inp;
  assign {isLast_inp, isData_inp} = statusIn;   // unpack input status vector
  assign statusOut = {isLast, isData};          // pack output status vector

  // AK-NOTE: Behavior of isData and isLast status registers
  //   if parallel-shifting is enabled, 
  //       Simply shift-in the status bits
  //   if shifting is about to be enabled in the next cycle,
  //       Set the status bits for parallel shifting.
  //       The status and shiftParallelEn will be set on the next posedge.
  //       Shifting will start in the subsequent edge.
  //  otherwise,
  //       Set them to zeros.
  always@(posedge clk) begin
    if (local_ce) begin
      // Read the above note for explanation
      if(shiftParallelEn) begin
        isData <= isData_inp;
        isLast <= isLast_inp;
      end else begin
        // shiftParallelEn == 0
        if(confSig == VECREG_PARALLEL_EN) begin    // shiftParallelEn will be set to 1 on the next posedge
          isData <= 1;
          isLast <= ISLAST_REG[0];      // ISLAST_REG = 1 for the last instance of the column shift reg
        end else begin
          isData <= 0;
          isLast <= 0;
        end
      end

    // hold state for debugging (local_ce == 0) 
    end else begin
      isData <= isData;
    end

  end




  // ---- Local Interconnect ----
  // inputs of shreg shift-register
  assign shreg_serialIn   = serialIn,
         shreg_parallelIn = shiftParallelEn ? parallelIn : loadVal,  // load parallel-shifting input if parallel-shifting, otherwise, load the given value
         shreg_loadEn     = shiftParallelEn || loadEn,               // load into the shift-register if explicit load or parallel-shifting requested
         shreg_shiftEn    = shiftSerialEn && serialIn_valid;         // Shift-in the serial input if the input is valid and serial-shifting is enabled
        
  // module top-level outputs
  assign parallelOut = shreg_parallelOut,
         curConfig.shiftSerialEn = shiftSerialEn,
         curConfig.shiftParallelEn = shiftParallelEn;
  


  // ---- connect debug probes
  generate
    if(DEBUG) begin
      assign local_ce = dbg_clk_enable;   // connect the debug stepper clock

      assign dbg_shiftSerialEn   = shiftSerialEn;
      assign dbg_shiftParallelEn = shiftParallelEn;

    end else begin
      assign local_ce = 1;   // there is no top-level clock enable control
    end
  endgenerate


endmodule
