# Contraints
set period 10  ;# ns
create_clock -period $period -name clk [get_ports clk]

set_input_delay  -clock clk 0.1 [all_inputs]
set_output_delay -clock clk 0.1 [all_outputs]

