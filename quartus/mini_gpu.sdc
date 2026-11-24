create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
create_generated_clock -name clk_lento -source [get_ports {CLOCK_50}] -divide_by 4 [get_registers {div[1]}]
derive_clock_uncertainty
