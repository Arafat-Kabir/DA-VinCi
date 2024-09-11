#*********************************************************************************
# Copyright (c) 2024, Computer Systems Design Lab, University of Arkansas        *
#                                                                                *
# All rights reserved.                                                           *
#                                                                                *
# Permission is hereby granted, free of charge, to any person obtaining a copy   *
# of this software and associated documentation files (the "Software"), to deal  *
# in the Software without restriction, including without limitation the rights   *
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell      *
# copies of the Software, and to permit persons to whom the Software is          *
# furnished to do so, subject to the following conditions:                       *
#                                                                                *
# The above copyright notice and this permission notice shall be included in all *
# copies or substantial portions of the Software.                                *
#                                                                                *
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR     *
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,       *
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE    *
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER         *
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,  *
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE  *
# SOFTWARE.                                                                      *
#*********************************************************************************

#==================================================================================
#
#  Author: MD Arafat Kabir
#  Email : arafat.sun@gmail.com
#  Date  : Fri, Jun 14, 12:23 PM CST 2024
#
#================================================================================*/


# Environment setup
MAKEFILE := $(lastword $(MAKEFILE_LIST))
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c


# Different directory w.r.t this Makefile location, avoid trailing '/'
TOP_DIR     := ../..
LIB_DIR     := ../../lib
TB_DIR      := ../../tb
WORK_DIR    := ..
SIM_DIR     := .
SYNTH_DIR   := ../synth
IMPL_DIR    := ../impl
SCRIPT_DIR  := ../scripts



# ---- Targets ----
default: list-commands


# list of command targets
.PHONY: list-commands list-all clean clean-all


# lists command targets
list-commands:
	@echo Select a command target
	@grep '#.\+<command>' $(MAKEFILE) | grep -v 'grep' | cut -f1 -d: | sed 's/^/    /'


# lists all targets
list-all:				# <command>
	@echo List of all targets
	@egrep '^(\w|\.|-)+:' $(MAKEFILE) | cut -f1 -d: | sed 's/^/    /'


# Clean up routines
clean:     # clean up garbage files   # <command>
	rm -f  *.log  *.pb  *.jou  *.out *.str


clean-all: clean    # clean up everything  # <command>
	rm -f  *.out  *.wcfg  *.wdb
	rm -f  *.sdf  *.vcd
	rm -f  *.v    *.sv
	rm -rf xsim.dir
	rm -f  *.pe *.data *.bin
	rm -f  *.c *.h *.npz



# ---- Main Targets ----
# This target builds the simulation primitives
work.glbl: $(XILINX_VIVADO)/data/verilog/src/glbl.v
	xvlog $(XILINX_VIVADO)/data/verilog/src/glbl.v


# -- picaso_ff
ALU_MODULES    :=	$(TOP_DIR)/lib/alu_serial_ff.v  $(TOP_DIR)/lib/alu_serial_unit.v  $(TOP_DIR)/lib/boothR2_serial_alu.v
PICASO_MODULES := $(TOP_DIR)/lib/bram_wrfirst_ff.v \
									$(TOP_DIR)/lib/opmux_ff.v  \
									$(TOP_DIR)/lib/up_counter.v \
									$(ALU_MODULES) \
									$(TOP_DIR)/lib/datanet_node.v  $(TOP_DIR)/lib/datanet_txMux.v


# -- picaso_algorithm_fsm
ALGO_FSM_MODULES := $(TOP_DIR)/lib/transition_aluop.v \
								    $(TOP_DIR)/lib/transition_updatepp.v \
								    $(TOP_DIR)/lib/transition_stream.v \
								    $(TOP_DIR)/lib/transition_accumrow.v \
										$(TOP_DIR)/lib/loop_counter.v


# -- picaso_multicycle_driver
PICASO_MULTICYCLE_DRIVER_MODULES := $(TOP_DIR)/lib/picaso_fsm_vars.v \
																		$(TOP_DIR)/lib/picaso_algorithm_fsm.v \
																		$(TOP_DIR)/lib/picaso_algorithm_decoder.v \
																		$(TOP_DIR)/lib/loop_counter.v \
																		$(TOP_DIR)/lib/up_counter.v \
																		$(TOP_DIR)/lib/srFlop.v \
																		$(TOP_DIR)/lib/transition_aluop.v \
																		$(TOP_DIR)/lib/transition_updatepp.v \
																		$(TOP_DIR)/lib/transition_stream.v \
																		$(TOP_DIR)/lib/transition_accumrow.v 


# -- picaso_controller
PICASO_CONTROLLER_MODULES := $(TOP_DIR)/lib/picaso_ff.v \
														 $(PICASO_MODULES)  \
														 $(TOP_DIR)/lib/srFlop.v \
														 $(TOP_DIR)/lib/picaso_instruction_fsm.v \
														 $(TOP_DIR)/lib/picaso_algorithm_fsm.v \
														 $(TOP_DIR)/lib/loop_counter.v \
														 $(TOP_DIR)/lib/picaso_instruction_decoder.v \
														 $(TOP_DIR)/lib/picaso_algorithm_decoder.v \
														 $(TOP_DIR)/lib/picaso_fsm_vars.v \
														 $(TOP_DIR)/lib/picaso_singlecycle_driver.v \
														 $(TOP_DIR)/lib/picaso_multicycle_driver.v \
														 $(TOP_DIR)/lib/transition_aluop.v \
														 $(TOP_DIR)/lib/transition_updatepp.v \
														 $(TOP_DIR)/lib/transition_stream.v \
														 $(TOP_DIR)/lib/transition_accumrow.v 

# -- IMAGine vecshift-reg tile
VECSHIFT_TILE_MODULES := $(TOP_DIR)/IMAGine/vecshift_tile.sv  \
												 $(TOP_DIR)/IMAGine/shiftReg.sv \
												 $(TOP_DIR)/lib/srFlop.v


# -- IMAGine GEMV tile
GEMV_TILE_MODULES := $(TOP_DIR)/IMAGine/gemvtile.sv  \
										 $(TOP_DIR)/IMAGine/gemv_picaso_array.sv \
										 $(PICASO_CONTROLLER_MODULES) \
										 $(TOP_DIR)/lib/picaso_controller.v


FIFOGEN01_IP_DIR := $(TOP_DIR)/tb/xil_ip/fifo_generator_0


# This target was used wile setting up the DA-VinCi workspace (ws) based on IMAGine
tb_davinci_wrapper_wsprog_xil: $(TOP_DIR)/DA-VinCi/davinci_wrapper.sv  $(TOP_DIR)/tb/tb_davinci_wrapper.sv   # <command>
	$(SCRIPT_DIR)/tb_davinci_wrapper_sim.sh  -p ../scripts/imagine_prog03.bin   -e ../scripts/imagine_prog03_exp.bin -f   $(NO_ELAB)	# set NO_ELAB=-n to skip elaboration


# This target can be used to run any davinci program with the tb_davinci_wrapper testbench
tb_davinci_wrapper_prog_xil: $(TOP_DIR)/DA-VinCi/davinci_wrapper.sv  $(TOP_DIR)/tb/tb_davinci_wrapper.sv   # <command>
	@[ -n "$(PROG_FILE)" ] || { echo "EROR: Specify PROG_FILE variable"; false; }
	python3 $(SCRIPT_DIR)/$(PROG_FILE).py > xsim_py.log && echo "----" >> xsim_py.log		# should generate $(PROG_FILE).bin and $(PROG_FILE)_exp.bin
	$(SCRIPT_DIR)/tb_davinci_wrapper_sim.sh  -p  $(PROG_FILE).bin   -e $(PROG_FILE)_exp.bin  -f  $(NO_ELAB)	# set NO_ELAB=-n to skip elaboration


tb_davinci_wrapper_prog_synth_func: $(SYNTH_DIR)/davinci_wrapper_synth_netlist_func.v  $(TOP_DIR)/tb/tb_davinci_wrapper_synth.sv   # <command>
	@[ -n "$(PROG_FILE)" ] || { echo "EROR: Specify PROG_FILE variable"; false; }
	python3 $(SCRIPT_DIR)/$(PROG_FILE).py > xsim_py.log && echo "----" >> xsim_py.log		# should generate $(PROG_FILE).bin and $(PROG_FILE)_exp.bin
	$(SCRIPT_DIR)/tb_davinci_wrapper_sim_synth.sh -m synth  -p  $(PROG_FILE).bin   -e $(PROG_FILE)_exp.bin
	# $(SCRIPT_DIR)/tb_davinci_wrapper_sim_synth.sh -m routed  -p  $(PROG_FILE).bin   -e $(PROG_FILE)_exp.bin


