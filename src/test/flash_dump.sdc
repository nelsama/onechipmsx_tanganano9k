create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
set_false_path -from [get_ports {flash_miso}]
