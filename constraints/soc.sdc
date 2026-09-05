create_clock -name clk  -period 10 [get_ports clk]
create_clock -name mclk -period 10 [get_ports mclk]
create_generated_clock -name sdram_clk -source [get_ports mclk] -divide_by 1 [get_ports sdram_clk]
set_clock_uncertainty 0.25 [all_clocks]

# clock domain crossings: bounded delay, no phase relationship
set_max_delay 10 -ignore_clock_latency -from [get_clocks clk] -to [get_clocks mclk]
set_max_delay 10 -ignore_clock_latency -from [get_clocks mclk] -to [get_clocks clk]
set_false_path -hold -from [get_clocks clk] -to [get_clocks {mclk sdram_clk}]
set_false_path -hold -from [get_clocks {mclk sdram_clk}] -to [get_clocks clk]

# board: 1 ns edges into the pads, 5 pF on every output pad
set_input_transition 1.0 [all_inputs]
set_load 5 [all_outputs]

# system I/O
set_input_delay  4 -clock clk [get_ports {rst_n uart_rx gpio[*] spi_miso}]
set_output_delay 4 -clock clk [get_ports {uart_tx gpio[*] spi_cs_n spi_sclk spi_mosi}]
set_false_path -from [get_ports {rst_n uart_rx gpio[*]}]

# SDRAM I/O against the forwarded clock: MT48LC16M16A2-75 tIS 1.5, tIH 0.8, tAC 5.4, tOH 2.7, 1 ns board round trip
set sdram_out [get_ports {sdram_cke sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_ba[*] sdram_a[*]
                          sdram_dqm[*] sdram_dq[*]}]
set_output_delay -clock sdram_clk -max  1.5 $sdram_out
set_output_delay -clock sdram_clk -min -0.8 $sdram_out
set_input_delay  -clock sdram_clk -max  6.4 [get_ports {sdram_dq[*]}]
set_input_delay  -clock sdram_clk -min  3.7 [get_ports {sdram_dq[*]}]
# read data is captured on the falling edge of mclk a cycle and a half after the SDRAM clock edge
set_multicycle_path -setup 2 -from [get_ports {sdram_dq[*]}] -to [get_clocks mclk]

