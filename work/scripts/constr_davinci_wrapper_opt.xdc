# Contraints
set period 1.356  ;# ns
create_clock -period $period -name clk [get_ports clk]

set_input_delay  -clock clk 0.2 [all_inputs]
set_output_delay -clock clk 0.2 [all_outputs]

