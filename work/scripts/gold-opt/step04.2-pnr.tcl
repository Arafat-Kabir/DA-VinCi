set_param general.maxThreads  10
report_param

# AK-NOTE: Source the pblock-troubled.tcl first

place_design
place_design -post_place_opt
phys_opt_design 

route_design
phys_opt_design

write_checkpoint  -force ./step04.2-pnr.dcp
