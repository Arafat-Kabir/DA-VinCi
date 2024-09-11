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
  Date   : Tue, May 28, 03:44 PM CST 2024
  Version: v0.1

  Description:
  This module serves as the ALU for the VV-Engine block. This is a 
  custom ALU and is not supposed to be reusable.

================================================================================*/


`timescale 1ns/100ps
`include "ak_macros.v"


module vvalu #(
  parameter DEBUG = 0,
  parameter OPND_WIDTH = 16,   // operand width
  parameter FXPFRAC_WIDTH = 8  // factional bits for Fixed-point interpretation
) (
  clk,
  opX,      // operand-X
  opY,      // operand-Y
  opA,      // operand-A, ACT register content
  opS,      // operand-S, Shift register content
  out,      // computed output
  opcode,   // opcode for the operation requested

  // Debug probes
  dbg_clk_enable     // debug clock for stepping
);


  // ---- Design assumptions
  `AK_ASSERT2(OPND_WIDTH > 0, OPND_WIDTH_needs_to_be_greater_than_0)


  `include "vvalu.svh"

  localparam OPCODE_WIDTH = VVALU_OPCODE_WIDTH;


  // IO Ports
  input wire clk;

  input  [OPND_WIDTH-1:0]   opX;
  input  [OPND_WIDTH-1:0]   opY;
  input  [OPND_WIDTH-1:0]   opA;
  input  [OPND_WIDTH-1:0]   opS;
  input  [OPCODE_WIDTH-1:0] opcode;
  output [OPND_WIDTH-1:0]   out;

  // Debug probes
  input  dbg_clk_enable;

  // internal wires
  wire local_ce;    // for debugging




  // Decoding opcode fields
  // opcode: [outmux:2] [add/sub:1] [SREG/Ry:1]
  wire [1:0] fld_outsel   = opcode[3:2];
  wire       fld_opaddsub = opcode[1];    // add:0, sub:1
  wire       fld_opnSY    = opcode[0];    // operand SREG/Ry; 0:SREG, 1:Ry


  // operand muxing: selects the input operands to the submodules
  wire [OPND_WIDTH-1:0] opmux_p;
  wire [OPND_WIDTH-1:0] opmux_q;

  assign opmux_p = opX;   // operand-P is directly connected to input opX
  assign opmux_q = fld_opnSY ? opY : opS;   // operand-Q selection: 0: SREG, 1: Ry


  // Adder-subtractor
  wire                  addsub_op;
  wire [OPND_WIDTH-1:0] addsub_opX;
  wire [OPND_WIDTH-1:0] addsub_opY;
  wire [OPND_WIDTH-1:0] addsub_out;

  vvalu_addsub #(
      .DEBUG(DEBUG),
      .OPND_WIDTH(OPND_WIDTH) )
    addsub (
      .clk(clk),
      .op(addsub_op),
      .opX(addsub_opX),
      .opY(addsub_opY),
      .out(addsub_out)
    );


  // Multiplier
  wire [OPND_WIDTH-1:0]   mult_opX;
  wire [OPND_WIDTH-1:0]   mult_opY;
  wire [2*OPND_WIDTH-1:0] mult_prod;

  (* keep_hierarchy = "yes" *)
  vvalu_mult #(
      .DEBUG(DEBUG),
      .OPND_WIDTH(OPND_WIDTH) )
    mult (
      .clk(clk),
      .opX(mult_opX),
      .opY(mult_opY),
      .prod(mult_prod)
    );


  // ReLU activation function of opA
  // Algorithm:
  //  - check the sign-bit
  //  - if negative, output is 0, 
  //  - otherwise, output is unchanged input
  wire [OPND_WIDTH-1:0] actrelu_out;

  assign actrelu_out = opA[OPND_WIDTH-1] ? 0 : opA;


  // output mux
  reg [OPND_WIDTH-1:0]  omux_val;

  localparam PROD_SLICE_LOW  = FXPFRAC_WIDTH,    // LSb index of the product for fixed-point conversion
             PROD_SLICE_HIGH = PROD_SLICE_LOW + OPND_WIDTH - 1; // MSb index for the fixed-point product conversion

  always@* begin
    omux_val = opX;   // NOP value
    (* full_case, parallel_case *)
    case(fld_outsel)
      VVALU_SEL_OPY   : omux_val = opY;
      VVALU_SEL_ADDSUB: omux_val = addsub_out; 
      VVALU_SEL_MULT  : omux_val = mult_prod[PROD_SLICE_HIGH:PROD_SLICE_LOW];   // mult_prod is 2*OPND_WIDTH; for fixed-point multiplication, the scaling-down is performed via this slice selection
      VVALU_SEL_RELU  : omux_val = actrelu_out;
    endcase
  end


  // ---- Local Interconnect ----
  // adder-subtractor inputs
  assign addsub_opX = opmux_p,
         addsub_opY = opmux_q,
         addsub_op  = fld_opaddsub;

  // multiplier inputs
  assign mult_opX = opmux_p,
         mult_opY = opmux_q;


  // top-level outputs
  assign out = omux_val;



endmodule




// Adder-Subtractor module for vvalu
module vvalu_addsub #(
  parameter DEBUG = 1,
  parameter OPND_WIDTH = 16
) (
  clk,
  op,     // opcode for add/subtract
  opX,    // operand X
  opY,    // operand Y
  out     // out = X op Y  
);

  `AK_ASSERT2(OPND_WIDTH > 0, OPND_WIDTH_needs_to_be_greater_than_0)

  `include "vvalu.svh"

  input                   clk;
  input                   op;
  input  [OPND_WIDTH-1:0] opX;
  input  [OPND_WIDTH-1:0] opY;
  output [OPND_WIDTH-1:0] out;

  reg [OPND_WIDTH-1:0] out_reg = 0;

  // opcode: 0: add, 1: sub
  always@(posedge clk) begin
    if(op) out_reg <= opX - opY;
    else   out_reg <= opX + opY;
  end

  assign out = out_reg;

endmodule




// multiplier module for vvalu
(* USE_DSP= "yes" *)
module vvalu_mult #(
  parameter DEBUG = 1,
  parameter OPND_WIDTH = 16
) (
  clk,
  opX,
  opY,
  prod
);

  input                            clk;
  input  signed [OPND_WIDTH-1:0]   opX;
  input  signed [OPND_WIDTH-1:0]   opY;
  output signed [2*OPND_WIDTH-1:0] prod;

  reg [2*OPND_WIDTH-1:0] preg, mreg, oreg;    // pipelining registers

  always@(posedge clk) begin
    mreg <= opX * opY;
    preg <= mreg;
    oreg <= preg;
  end


  assign prod = oreg;

endmodule
