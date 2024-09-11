set_param general.maxThreads  10
report_param

# returns the slack of current design
proc get_slack {} {
  return [get_property SLACK [get_timing_paths]]
}


# Iterative optimization
set itercnt 5
for {set i 0} {$i < $itercnt} {incr i} {
  puts "AK-INFO: post-route iteration $i"
  place_design -post_place_opt
  phys_opt_design
  route_design
  if {[get_slack]>=0} break   ;# no more iteration needed if slack met
}

write_checkpoint      -force ./step04.3-iteropt.dcp
report_timing_summary -file  step04.3-iteropt-timing.rpt
report_utilization    -file  step04.3-iteropt-util.rpt



