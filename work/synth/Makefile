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
#  Date  : Fri, Jun 14, 01:05 PM CST 2024
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
SIM_DIR     := ../sim
SYNTH_DIR   := .
IMPL_DIR    := ../impl
SCRIPT_DIR  := ../scripts


# ---- Targets ----
default: .list-commands


# list of command targets
.PHONY: .list-commands list-all clean clean-all


# lists command targets
.list-commands:
	@echo Select a command target
	@grep '#.\+<command>' $(MAKEFILE) | grep -v 'grep' | cut -f1 -d: | sed 's/^/    /'


# lists all targets
list-all:				# <command>
	@echo List of all targets
	@egrep '^(\w|\.|-)+:' $(MAKEFILE) | cut -f1 -d: | sed 's/^/    /'


# Clean up routines
clean:   # clean garbage files only  # <command>
	rm -f *.jou  *.log  *.str

clean-all: clean   # cleans everything   # <command>
	rm -f  *.rpt  *.v *.sv  *.dcp  *.sdf
	rm -rf .Xil/



# ---- Main Targets ----
davinci_wrapper_elab:  $(TOP_DIR)/DA-VinCi/davinci_wrapper.sv  $(TOP_DIR)/tb/tb_davinci_wrapper.sv   # <command>
	vivado -mode tcl -source $(SCRIPT_DIR)/elab_davinci_wrapper.tcl

davinci_wrapper_synth: davinci_wrapper_modparam.v    # <command>
	vivado -mode tcl -source $(SCRIPT_DIR)/synth_davinci_wrapper.tcl

davinci_wrapper_modparam.v: $(TOP_DIR)/DA-VinCi/davinci_wrapper.sv  # <command>
	@DEBUG=0; \
		BLK_ROW_CNT=16; \
		BLK_COL_CNT=4;  \
		TILE_ROW_CNT=4; \
		TILE_COL_CNT=2; \
		DATAOUT_WIDTH=16; \
		sed -e "1,100s/parameter \+DEBUG.\+/parameter DEBUG = $$DEBUG,/"  \
        -e "1,100s/parameter \+BLK_ROW_CNT.\+/parameter BLK_ROW_CNT = $$BLK_ROW_CNT,/" \
        -e "1,100s/parameter \+BLK_COL_CNT.\+/parameter BLK_COL_CNT = $$BLK_COL_CNT,/" \
        -e "1,100s/parameter \+TILE_ROW_CNT.\+/parameter TILE_ROW_CNT = $$TILE_ROW_CNT,/" \
        -e "1,100s/parameter \+TILE_COL_CNT.\+/parameter TILE_COL_CNT = $$TILE_COL_CNT,/" \
        -e "1,100s/parameter \+DATAOUT_WIDTH.\+/parameter DATAOUT_WIDTH = $$DATAOUT_WIDTH/" \
	       $(TOP_DIR)/DA-VinCi/davinci_wrapper.sv > davinci_wrapper_modparam.sv
	@diff $(TOP_DIR)/DA-VinCi/davinci_wrapper.sv davinci_wrapper_modparam.sv -y --suppress-common-lines || true   # diff returns 1, true makes it 0 to avoid make error

