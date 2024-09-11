# Script parameters

# This script is supposed to be run under work/synth directory,
# Following relative paths reflects this fact.
set top_dir  ../..
set work_dir ..
set scripts_dir ../scripts

# synthesis parameters
# set ipfiles "$top_dir/tb/xil_ip/fifo_generator_0/xci/fifo_generator_0.xci"
set alu_sources       "$top_dir/lib/alu_serial_ff.v  $top_dir/lib/alu_serial_unit.v  $top_dir/lib/boothR2_serial_alu.v"
set datanet_sources   "$top_dir/lib/datanet_node.v  $top_dir/lib/datanet_txMux.v"
set picasoff_sources  "$top_dir/lib/picaso_ff.v  \
                       $top_dir/lib/bram_wrfirst_ff.v  \
                       $top_dir/lib/opmux_ff.v  \
                       $alu_sources \
                       $datanet_sources"
set vvtilearr_sources "$top_dir/vvengine/vvblock.sv  \
                       $top_dir/vvengine/vvalu.sv \
                       $top_dir/vvengine/vecshift_reg.sv \
                       $top_dir/vvengine/shiftReg.sv \
                       $top_dir/vvengine/vvcontroller.sv  \
                       $top_dir/vvengine/vvctrl_blkSignalGen.sv \
                       $top_dir/vvengine/vvtile.sv  \
                       $top_dir/vvengine/vvtile_array.sv"
set picasoCtrl_sources "$top_dir/lib/picaso_controller.v \
                        $top_dir/lib/srFlop.v \
                        $top_dir/lib/picaso_fsm_vars.v \
                        $top_dir/lib/picaso_singlecycle_driver.v \
                        $top_dir/lib/picaso_multicycle_driver.v \
                        $top_dir/lib/picaso_instruction_fsm.v \
                        $top_dir/lib/picaso_algorithm_fsm.v \
                        $top_dir/lib/loop_counter.v \
                        $top_dir/lib/up_counter.v \
                        $top_dir/lib/picaso_algorithm_decoder.v \
                        $top_dir/lib/picaso_instruction_decoder.v \
                        $top_dir/lib/transition_aluop.v \
                        $top_dir/lib/transition_updatepp.v \
                        $top_dir/lib/transition_stream.v \
                        $top_dir/lib/transition_accumrow.v"
set gemvArr_sources "$top_dir/DA-VinCi/gemv_picaso_array.sv \
                     $top_dir/DA-VinCi/gemvtile.sv \
                     $top_dir/DA-VinCi/gemvtile_array.sv"
set sources     "$picasoCtrl_sources \
                 $vvtilearr_sources \
                 $gemvArr_sources \
                 $picasoff_sources \
                 $top_dir/DA-VinCi/davinci_interface.sv  \
                 $top_dir/tb/davinci_wrapper_impl_util.sv"
set top_module  davinci_wrapper
set incdirs     "$top_dir/lib  $top_dir/tb  $top_dir/DA-VinCi $top_dir/vvengine"
set constraints "$scripts_dir/all_constr.xdc"

set device      xcvu29p-figd2104-2L-e    ;# Virtex UltraScale+ VU29P with 2688 RAMB36 (5376 RAMB18)
set jobs        [expr [exec nproc]-2]    ;# Use all threads, leaving only 2 for interactive use




# ---- Execution
# Set up the design project (non-project)
set_param     general.maxThreads  $jobs
set_part      $device     ;# This must be set before read_verilog and synth_ip
read_verilog  $sources
read_xdc      $constraints


# Synthesis
synth_design  -include_dirs $incdirs \
              -top $top_module  -part $device \
              -mode out_of_context
opt_design

write_checkpoint      -force step01-synth.dcp
report_timing_summary -file  step01-synth-timing.rpt
report_utilization    -file  step01-synth-util.rpt


# Floorplanning and placement
place_design
place_design -post_place_opt

write_checkpoint      -force step02-placed.dcp
report_timing_summary -file  step02-placed-timing.rpt
report_utilization    -file  step02-placed-util.rpt


# Physical optimization and routing
phys_opt_design
route_design
write_checkpoint      -force step03-route.dcp
report_timing_summary -file  step03-route-timing.rpt
report_utilization    -file  step03-route-util.rpt

