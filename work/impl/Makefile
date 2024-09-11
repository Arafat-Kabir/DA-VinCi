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
#  Date  : Fri, Jun 21, 03:07 PM CST 2024
#
#================================================================================*/


# Environment setup
MAKEFILE := $(lastword $(MAKEFILE_LIST))
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c


# Different directory w.r.t this Makefile location, avoid trailing '/'
TOP_DIR     := ../..
WORK_DIR    := ..
SIM_DIR     := ../sim
SYNTH_DIR   := ../synth
IMPL_DIR    := .
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
	rm -f *.jou  *.log

clean-all: clean   # cleans everything   # <command>
	rm -f  *.rpt  *.dcp  *.pb
	rm -f  *.v  *.sdf


# ---- Main Targets ----
davinci_wrapper_pnr:  $(SYNTH_DIR)/davinci_wrapper_postsynth.dcp  # <command>
	vivado -mode batch  -source $(SCRIPT_DIR)/pnr_davinci_wrapper.tcl


davinci_wrapper_impl_opt: $(TOP_DIR)/tb/davinci_wrapper_impl_opt.sv   # <command>
	time vivado -mode batch  -source $(SCRIPT_DIR)/impl_davinci_wrapper_opt.tcl


davinci_wrapper_impl_util: $(TOP_DIR)/tb/davinci_wrapper_impl_util.sv   # <command>
	time vivado -mode batch  -source $(SCRIPT_DIR)/impl_davinci_wrapper_util.tcl

