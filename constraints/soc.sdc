create_clock -name clk  -period 10 [get_ports clk]
create_clock -name mclk -period 10 [get_ports mclk]
create_generated_clock -name sdram_clk -source [get_ports mclk] -divide_by 1 [get_ports sdram_clk]
create_clock -name pclk -period 16 [get_ports pclk]
set_clock_uncertainty 0.25 [all_clocks]

# clock domain crossings: bounded delay, no phase relationship
set_max_delay 10 -ignore_clock_latency -from [get_clocks clk] -to [get_clocks mclk]
set_max_delay 10 -ignore_clock_latency -from [get_clocks mclk] -to [get_clocks clk]
set_false_path -hold -from [get_clocks clk] -to [get_clocks {mclk sdram_clk}]
set_false_path -hold -from [get_clocks {mclk sdram_clk}] -to [get_clocks clk]
set_max_delay 10 -ignore_clock_latency -from [get_clocks clk] -to [get_clocks pclk]
set_max_delay 10 -ignore_clock_latency -from [get_clocks pclk] -to [get_clocks clk]
set_false_path -hold -from [get_clocks clk] -to [get_clocks pclk]
set_false_path -hold -from [get_clocks pclk] -to [get_clocks clk]

# board: 1 ns edges into the pads, 5 pF on every output pad
set_input_transition 1.0 [all_inputs]
set_load 5 [all_outputs]

# reset, UART and GPIO are asynchronous
set_false_path -from [get_ports {rst_n uart_rx gpio[*]}]
set_false_path -to [get_ports {uart_tx gpio[*]}]

# SPI flash in mode 0 at clk/2: 2 ns setup, 3 ns hold, 7 ns clock to output, 0.5 ns of board each way
create_generated_clock -name spi_clk -source [get_ports clk] -divide_by 2 [get_ports spi_sclk]
set_output_delay -clock spi_clk -max  2.5 [get_ports {spi_mosi spi_cs_n}]
set_output_delay -clock spi_clk -min -2.5 [get_ports {spi_mosi spi_cs_n}]
set_input_delay  -clock spi_clk -clock_fall -max 8.0 [get_ports spi_miso]
set_input_delay  -clock spi_clk -clock_fall -min 0.0 [get_ports spi_miso]
# MOSI and CS change on the falling SCLK edge; MISO is sampled on the next falling edge
set_multicycle_path -hold 1 -end -from [get_clocks clk] -to [get_clocks spi_clk]
set_multicycle_path -setup 2 -from [get_ports spi_miso]
set_multicycle_path -hold 1 -end -from [get_ports spi_miso]

# SDRAM I/O against the forwarded clock: MT48LC16M16A2-75 tIS 1.5, tIH 0.8, tAC 5.4, tOH 2.7, 1 ns board round trip
set sdram_out [get_ports {sdram_cke sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_ba[*] sdram_a[*]
                          sdram_dqm[*] sdram_dq[*]}]
set_output_delay -clock sdram_clk -max  1.5 $sdram_out
set_output_delay -clock sdram_clk -min -0.8 $sdram_out
set_input_delay  -clock sdram_clk -max  6.4 [get_ports {sdram_dq[*]}]
set_input_delay  -clock sdram_clk -min  3.7 [get_ports {sdram_dq[*]}]
# read data is captured on the falling edge of mclk a cycle and a half after the SDRAM clock edge
set_multicycle_path -setup 2 -from [get_ports {sdram_dq[*]}] -to [get_clocks mclk]

# PIPE against PCLK, assumed PHY budget: 3 ns setup, 1 ns input hold, 0.5 ns output hold
set pipe_in  [get_ports {pipe_rx_data[*] pipe_rx_datak[*] pipe_rx_elecidle[*] pipe_rx_status[*] pipe_phy_status}]
set pipe_out [get_ports {pipe_tx_data[*] pipe_tx_datak[*] pipe_tx_elecidle pipe_tx_detect_rx pipe_power_down[*]}]
set_input_delay  -clock pclk -max  3.0 $pipe_in
set_input_delay  -clock pclk -min  1.0 $pipe_in
set_output_delay -clock pclk -max  3.0 $pipe_out
set_output_delay -clock pclk -min -0.5 $pipe_out

