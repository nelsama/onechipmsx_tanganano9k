// One Chip MSX on the Tang Nano 9K - timing constraints (tn9k_top, RATIO 4)
//
//   clk27     27 MHz     crystal, only feeds the two rPLLs
//   memclk    86.4 MHz   PLL sys CLKOUT (PSRAM controller)
//   memclk_p  86.4 MHz   PLL sys CLKOUTP, 90 degrees (PSRAM CK)
//   clk21m    21.6 MHz   PLL sys CLKOUTD /4 (MSX)
//   cpuclk    3.6 MHz    clk21m / 6, made by a register in emsx_core (the
//                        Z80 and its wait logic run on it)
//   clk135    135 MHz    PLL hdmi (OSER10 FCLK)
//   clk_pix   27 MHz     CLKDIV /5 of clk135 (raster, OSER10 PCLK)
//
// memclk / clk21m / cpuclk come from the same VCO and are synchronous
// (psram_msx and vdp2hdmi's write side cross between them with plain
// registers). clk_pix is only related to them through the dual-clock line
// buffer of vdp2hdmi and the VS toggle synchroniser.
//
// For RATIO 5 (108 MHz): memclk/memclk_p period 9.259, waveform of
// memclk_p {2.315 6.944}, clk21m = CLKDIV /5 of memclk (same period).

create_clock -name clk27    -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
create_clock -name memclk   -period 11.574 -waveform {0 5.787}     [get_nets {memclk}]
create_clock -name memclk_p -period 11.574 -waveform {2.894 8.681} [get_nets {memclk_p}]
create_clock -name clk21m   -period 46.296 -waveform {0 23.148}    [get_nets {clk21m}]
create_generated_clock -name cpuclk -source [get_nets {clk21m}] -master_clock clk21m -divide_by 6 [get_nets {u_core/cpuclk}]
create_clock -name clk135   -period 7.407  -waveform {0 3.704}     [get_nets {clk135}]
create_clock -name clk_pix  -period 37.037 -waveform {0 18.518}    [get_nets {clk_pix}]

set_clock_groups -asynchronous -group [get_clocks {clk27}] -group [get_clocks {memclk memclk_p clk21m cpuclk}] -group [get_clocks {clk135 clk_pix}]

// asynchronous inputs (sampled / synchronised)
set_false_path -from [get_ports {btn_s1_n btn_s2_n sd_dat0 flash_miso ps2_clk ps2_dat}]
set_false_path -from [get_ports {joy_up joy_down joy_left joy_right joy_fire joy_btn2 joy_btn3}]

// psram_msx hands the VRAM read word to the VDP (dbi0) only on the memclk
// edge that coincides with a clk21m edge (E0 + 5 clk21m), and the VDP
// captures it one clk21m later: a full clk21m (RATIO memclk) for the path.
set_multicycle_path -from [get_regs {u_mem/dbi0*}] -setup -start 4
set_multicycle_path -from [get_regs {u_mem/dbi0*}] -hold -start 3

// CPU read data: psram_msx updates dbi_i once per access, ~335 ns after the
// Z80 starts the memory cycle; the Z80 samples it at ~417 ns (T3 rising).
// It is stable for more than one clk21m before being used. (Written in
// cycles of the capturing clock: "-start" is not applied by Gowin towards
// the generated cpuclk; one more cpuclk is looser than the real ~80 ns
// margin, the data path itself is ~12 ns.)
set_multicycle_path -from [get_regs {u_mem/dbi_i*}] -to [get_clocks {cpuclk}] -setup -end 2
set_multicycle_path -from [get_regs {u_mem/dbi_i*}] -to [get_clocks {cpuclk}] -hold -end 1
// (the same CPU read data also reaches clk21m registers, e.g. the bus latch)
set_multicycle_path -from [get_regs {u_mem/dbi_i*}] -to [get_clocks {clk21m}] -setup -start 4
set_multicycle_path -from [get_regs {u_mem/dbi_i*}] -to [get_clocks {clk21m}] -hold -start 3
