# Script parameters

# This script is supposed to be run under work/impl directory,
# Following relative paths reflects this fact.
set top_dir     ../..
set work_dir    ..
set scripts_dir ../scripts
set synth_dir   ../synth

# placement parameters
set top_module         davinci_wrapper

set synth_chkp         $synth_dir/$top_module\_postsynth.dcp
set placed_chkp_name   $top_module\_postplace.dcp   ;# post-placement check-point name to save
set placed_timing_rpt  $top_module\_placed_timing
set placed_util_rpt    $top_module\_placed_util

# routing parameters
set routed_chkp_name   $top_module\_postroute.dcp          ;# post-routing check-point name to save
set routed_out_netlist $top_module\_routed_netlist
set routed_out_sdf     $top_module\_routed_delay
set routed_status_rpt  $top_module\_routed_status
set routed_drc_rpt     $top_module\_routed_drc
set routed_timing_rpt  $top_module\_routed_timing
set routed_power_rpt   $top_module\_routed_power

set jobs        10


# ---- Execution 
set_param general.maxThreads  $jobs
file copy  -force  $synth_chkp  synth_chkp.tmp.dcp   ;# copy synthesis checkpoint to prevent modification to it


# Place design
open_checkpoint  synth_chkp.tmp.dcp
opt_design
place_design
write_checkpoint -force $placed_chkp_name

report_timing_summary -file $placed_timing_rpt.rpt
report_utilization    -file $placed_util_rpt.rpt

# Route design
route_design
write_checkpoint -force $routed_chkp_name

# Save post-routing simulation netlists
write_verilog    -mode funcsim -force $routed_out_netlist\_func.v
write_verilog    -mode timesim \
                 -sdf_anno true  -sdf_file $routed_out_sdf.sdf \
                 -force $routed_out_netlist\_time.v 
write_sdf        -force $routed_out_sdf.sdf

# Save reports
report_route_status   -file $routed_status_rpt.rpt
report_drc            -file $routed_drc_rpt.rpt
report_timing_summary -file $routed_timing_rpt.rpt
report_power          -file $routed_power_rpt.rpt
