create_clock -name clk -period 20 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks clk]

set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
set_load 0.033 [all_outputs]

set_input_delay  4 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 4 -clock clk [all_outputs]

# synchronized inputs
set_false_path -from [get_ports {rst_n uart_rx gpio_in[*]}]
