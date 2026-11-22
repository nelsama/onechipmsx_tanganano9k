// psram_test_top: same PLL as tn9k_top RATIO 4
create_clock -name clk27    -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
create_clock -name memclk   -period 11.574 -waveform {0 5.787}     [get_nets {memclk}]
create_clock -name memclk_p -period 11.574 -waveform {2.894 8.681} [get_nets {memclk_p}]
create_clock -name clk21m   -period 46.296 -waveform {0 23.148}    [get_nets {clk21m}]
set_clock_groups -asynchronous -group [get_clocks {clk27}] -group [get_clocks {memclk memclk_p clk21m}]
set_false_path -from [get_ports {btn_s1_n}]
set_multicycle_path -from [get_regs {u_mem/dbi0*}] -setup -start 4
set_multicycle_path -from [get_regs {u_mem/dbi0*}] -hold -start 3
set_multicycle_path -from [get_regs {u_mem/dbi_i*}] -setup -start 4
set_multicycle_path -from [get_regs {u_mem/dbi_i*}] -hold -start 3
