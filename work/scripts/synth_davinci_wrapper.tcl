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
                 davinci_wrapper_modparam.sv"
set top_module  davinci_wrapper
set incdirs     "$top_dir/lib  $top_dir/tb  $top_dir/DA-VinCi $top_dir/vvengine"
set constraints "$scripts_dir/all_constr.xdc"

set device      xczu7ev-ffvc1156-2-e          ;# ZCU-104
set chkp_name   $top_module\_postsynth.dcp     ;# check-point name
set timing_rpt  $top_module\_synth_timing
set util_rpt    $top_module\_synth_util
set out_netlist $top_module\_synth_netlist
set out_sdf     $top_module\_synth_delay
set jobs        10


# ---- Execution
set_param general.maxThreads  $jobs

# Set up the design project (non-project)
set_part      $device     ;# This must be set before read_verilog and synth_ip
read_verilog  $sources
read_xdc      $constraints

# Synthesize IPs
# read_ip $ipfiles
# synth_ip [get_ips]

# Elaborate design
synth_design  -include_dirs $incdirs \
              -top $top_module  -part $device \
              -mode out_of_context
 
write_checkpoint -force $chkp_name
write_verilog    -mode design  -force $out_netlist\_dsn.v
write_verilog    -mode funcsim -force $out_netlist\_func.v
write_verilog    -mode timesim \
                 -sdf_anno true  -sdf_file $out_sdf.sdf \
                 -force $out_netlist\_time.v 
write_sdf -force $out_sdf.sdf


report_timing_summary -file $timing_rpt.rpt
report_utilization    -file $util_rpt.rpt

