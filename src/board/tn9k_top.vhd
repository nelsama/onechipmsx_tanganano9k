--
-- tn9k_top.vhd : One Chip MSX (emsx_core) on the Sipeed Tang Nano 9K
--                (GW1NR-LV9QN88PC6/I5).
--
-- Clocks (27 MHz crystal, pin 52)
--   PLL sys : memclk = RATIO x clk21m for the PSRAM, memclk_p = memclk at 90
--             degrees (PSRAM CK), clk21m = 21.6 MHz (27 x 4/5, +0.57 % over
--             the original 21.477 MHz) for the whole MSX. All three from the
--             same VCO, so they are synchronous.
--               RATIO 4 : 27 / 5 x 16 =  86.4 MHz, CLKOUTD / 4, PSRAM LC 3
--               RATIO 5 : 27     x  4 = 108.0 MHz, CLKDIV  / 5, PSRAM LC 5
--   PLL hdmi: 135 MHz (TMDS bit clock / 2, OSER10 FCLK), CLKDIV / 5 =
--             27 MHz pixel clock. 720x480p raster locked to the VDP (see
--             vdp2hdmi.vhd): one VDP VGA line = 684 x clk21m = 855 x 27 MHz.
--
-- Reset: power-on, S1 (pin 4) and "PSRAM not ready" hold the MSX in reset.
-- S1 does not reset the PSRAM (it keeps its configuration).
--
-- Joystick: pins of the pengo_arcade board (up 30, down 33, left 34,
-- right 40, fire 29) + button 2 (pin 35, trigger B) and button 3 (pin 42,
-- SPACE key). Audio: mono PWM on both L (77) and R (76).
--
-- SPI flash: while the MSX is in reset, a 0xAB "release from deep
-- power-down" is sent to the flash (the IPL-ROM reads it with 0x03 only),
-- then the pins go to megasd (former EPCS port).
--
-- LEDs (active low, "lit" = condition true). Boot diagnostics, cleared by
-- the MSX reset and sticky afterwards:
--   0 the flash answered (MISO seen low with CS active)
--   1 VRAM overrun (PSRAM too slow for the VDP)
--   2 PSRAM not ready
--   3 the IPL wrote the BIOS RAM area (ESE-RAM, CPU memory 0x680000)
--   4 the CPU read the main BIOS (the IPL finished and jumped to it)
--   5 heartbeat (~1.5 s)
--
-- Debug UART (pins 17 and 32, 115200 8N1), every ~0.8 s:
--   MSX PC=pppp SL=ss VW=vv F=f RC=rrrr WA=wwww WM=wwww RM=rrrr
--     PC  address of the last opcode fetch (M1)
--     SL  primary slot register (port A8h)
--     VW  CPU writes to the VDP ports 98-9Bh (8-bit counter)
--     F   bit 3 flash answered, 2 IPL wrote the BIOS area, 1 CPU read the
--         main BIOS, 0 VRAM overrun
--     RC  CPU memory accesses (16-bit counter)
--     WA  bytes the IPL wrote at BIOS image offsets 0, 1 (4142 = "AB")
--     WM  bytes the IPL wrote at image offsets 10000h, 10001h (main BIOS,
--         F3C3 for a real one)
--     RM  bytes the CPU read back from the main BIOS 0000h, 0001h
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tn9k_top is
  generic (
    RATIO : integer := 4          -- memclk / clk21m: 4 or 5
  );
  port (
    clk27       : in    std_logic;
    btn_s1_n    : in    std_logic;
    btn_s2_n    : in    std_logic;
    led_n       : out   std_logic_vector(5 downto 0);

    -- HDMI
    tmds_ck_p   : out   std_logic;
    tmds_ck_n   : out   std_logic;
    tmds_d_p    : out   std_logic_vector(2 downto 0);
    tmds_d_n    : out   std_logic_vector(2 downto 0);

    -- microSD (SPI mode)
    sd_sck      : out   std_logic;
    sd_cmd      : out   std_logic;
    sd_cs       : out   std_logic;
    sd_dat0     : in    std_logic;

    -- SPI flash (BIOS)
    flash_cs_n  : out   std_logic;
    flash_clk   : out   std_logic;
    flash_mosi  : out   std_logic;
    flash_miso  : in    std_logic;

    -- PS/2 keyboard
    ps2_clk     : inout std_logic;
    ps2_dat     : inout std_logic;

    -- joystick (MSX port A) and extra buttons, active low with pull-ups
    joy_up      : in    std_logic;
    joy_down    : in    std_logic;
    joy_left    : in    std_logic;
    joy_right   : in    std_logic;
    joy_fire    : in    std_logic;    -- button 1 = trigger A
    joy_btn2    : in    std_logic;    -- button 2 = trigger B
    joy_btn3    : in    std_logic;    -- button 3 = SPACE key

    -- audio (1-bit PWM, RC filter outside): the MSX is mono, same on L and R
    audio_l     : out   std_logic;
    audio_r     : out   std_logic;

    -- debug UART, 115200 8N1 (17 = on-board USB-UART, 32 = external)
    uart_tx     : out   std_logic;
    uart_tx2    : out   std_logic;

    -- embedded PSRAM (fixed names, no .cst entries)
    O_psram_ck      : out   std_logic_vector(1 downto 0);
    O_psram_ck_n    : out   std_logic_vector(1 downto 0);
    IO_psram_rwds   : inout std_logic_vector(1 downto 0);
    IO_psram_dq     : inout std_logic_vector(15 downto 0);
    O_psram_reset_n : out   std_logic_vector(1 downto 0);
    O_psram_cs_n    : out   std_logic_vector(1 downto 0)
  );
end entity;

architecture rtl of tn9k_top is

  function lc_of(r : integer) return integer is
  begin
    if r = 5 then return 5; else return 3; end if;
  end function;
  constant LC   : integer := lc_of(RATIO);
  constant FMEM : integer := 21600000 * RATIO;

  component CLKDIV
    generic (
      DIV_MODE : string := "2";
      GSREN    : string := "false"
    );
    port (
      CLKOUT : out std_logic;
      HCLKIN : in  std_logic;
      RESETN : in  std_logic;
      CALIB  : in  std_logic
    );
  end component;

  -- clocks
  signal memclk, memclk_p, clk21m, clk21m_d : std_logic;
  signal sys_lock : std_logic;
  signal clk135, clk_pix, hdmi_lock : std_logic;

  -- reset
  signal por_cnt    : unsigned(15 downto 0) := (others => '0');
  signal s1_sync    : std_logic_vector(2 downto 0) := (others => '1');
  signal msx_rst_n  : std_logic := '0';
  signal ps_ready   : std_logic;
  signal ps_overrun : std_logic;
  signal pix_rst_sr : std_logic_vector(3 downto 0) := (others => '1');
  signal pix_rst    : std_logic;

  -- core <-> memory
  signal vram_slot, vram_we_n : std_logic;
  signal vram_adr  : std_logic_vector(16 downto 0);
  signal vram_dbo  : std_logic_vector(7 downto 0);
  signal vram_dbi  : std_logic_vector(15 downto 0);
  signal ram_req, ram_wr, ram_ack : std_logic;
  signal ram_adr   : std_logic_vector(21 downto 0);
  signal ram_dbo, ram_dbi : std_logic_vector(7 downto 0);

  -- video
  signal vr, vg, vb : std_logic_vector(5 downto 0);
  signal vhs_n, vvs_n : std_logic;
  signal hr, hg, hb : std_logic_vector(7 downto 0);
  signal hhs, hvs, hde, hlocked : std_logic;

  signal led_sd : std_logic;
  -- flash wake-up and boot diagnostics
  signal fl_cs_c, fl_ck_c, fl_di_c : std_logic;     -- from the core
  signal fl_cs_w, fl_ck_w, fl_di_w : std_logic := '1';
  signal miso_s : std_logic_vector(1 downto 0) := (others => '1');
  signal dg_flash, dg_eram, dg_main : std_logic := '0';
  signal dbg      : std_logic_vector(31 downto 0);
  signal dg_wa, dg_wm, dg_rm : std_logic_vector(15 downto 0) := (others => '0');
  signal dg_rc    : unsigned(15 downto 0) := (others => '0');
  signal ack_d    : std_logic := '0';
  signal utx      : std_logic;
  signal audio  : std_logic;
  -- joystick: bit 0 up, 1 down, 2 left, 3 right, 4 trigger A, 5 trigger B
  signal joy_s1, joy_s2 : std_logic_vector(6 downto 0) := (others => '1');
  signal beat   : unsigned(24 downto 0) := (others => '0');

begin

  ----------------------------------------------------------------
  -- clocks
  ----------------------------------------------------------------
  g_r4 : if RATIO = 4 generate
    u_pll_sys : entity work.gw_rpll
      generic map (FCLKIN => "27", IDIV => 4, FBDIV => 15, ODIV => 8,
                   PSDA => "0100", SDIV => 4)
      port map (clkin => clk27, clkout => memclk, clkoutp => memclk_p,
                clkoutd => clk21m, lock => sys_lock);
  end generate;

  g_r5 : if RATIO = 5 generate
    u_pll_sys : entity work.gw_rpll
      generic map (FCLKIN => "27", IDIV => 0, FBDIV => 3, ODIV => 8,
                   PSDA => "0100", SDIV => 2)
      port map (clkin => clk27, clkout => memclk, clkoutp => memclk_p,
                clkoutd => open, lock => sys_lock);
    u_div21 : CLKDIV
      generic map (DIV_MODE => "5", GSREN => "false")
      port map (CLKOUT => clk21m, HCLKIN => memclk, RESETN => sys_lock, CALIB => '0');
  end generate;

  u_pll_hdmi : entity work.gw_rpll
    generic map (FCLKIN => "27", IDIV => 0, FBDIV => 4, ODIV => 4,
                 PSDA => "0000", SDIV => 2)
    port map (clkin => clk27, clkout => clk135, clkoutp => open,
              clkoutd => open, lock => hdmi_lock);

  u_div_pix : CLKDIV
    generic map (DIV_MODE => "5", GSREN => "false")
    port map (CLKOUT => clk_pix, HCLKIN => clk135, RESETN => hdmi_lock, CALIB => '0');

  ----------------------------------------------------------------
  -- reset
  ----------------------------------------------------------------
  process(clk21m)
  begin
    if rising_edge(clk21m) then
      s1_sync <= s1_sync(1 downto 0) & btn_s1_n;
      if sys_lock = '0' or ps_ready = '0' or s1_sync(2) = '0' then
        por_cnt <= (others => '0');
        msx_rst_n <= '0';
      elsif por_cnt /= x"FFFF" then          -- ~3 ms
        por_cnt <= por_cnt + 1;
        msx_rst_n <= '0';
      else
        msx_rst_n <= '1';
      end if;
    end if;
  end process;

  process(clk_pix, hdmi_lock)
  begin
    if hdmi_lock = '0' then
      pix_rst_sr <= (others => '1');
    elsif rising_edge(clk_pix) then
      pix_rst_sr <= pix_rst_sr(2 downto 0) & '0';
    end if;
  end process;
  pix_rst <= pix_rst_sr(3);

  -- flash wake-up (SPI mode 3, SCK = clk21m / 4) during the MSX reset:
  -- por_cnt 256 .. 291 -> CS low, 8 bits of 0xAB, CS high; tRES1 = 3 us is
  -- far shorter than the rest of the reset (~3 ms)
  process(clk21m)
    constant CMD : std_logic_vector(7 downto 0) := x"AB";
    variable w : integer range 0 to 65535;
  begin
    if rising_edge(clk21m) then
      w := to_integer(por_cnt);
      fl_cs_w <= '1'; fl_ck_w <= '1'; fl_di_w <= '1';
      if w >= 256 and w < 256 + 36 then
        fl_cs_w <= '0';
        if w < 256 + 32 then
          fl_di_w <= CMD(7 - (w - 256) / 4);
          if ((w - 256) mod 4) < 2 then fl_ck_w <= '0'; end if;
        end if;
      end if;
    end if;
  end process;

  flash_cs_n <= fl_cs_w when msx_rst_n = '0' else fl_cs_c;
  flash_clk  <= fl_ck_w when msx_rst_n = '0' else fl_ck_c;
  flash_mosi <= fl_di_w when msx_rst_n = '0' else fl_di_c;

  -- boot diagnostics
  process(clk21m)
  begin
    if rising_edge(clk21m) then
      miso_s <= miso_s(0) & flash_miso;
      if msx_rst_n = '0' then
        dg_flash <= '0'; dg_eram <= '0'; dg_main <= '0';
        dg_rc <= (others => '0');
      else
        if fl_cs_c = '0' and miso_s(1) = '0' then
          dg_flash <= '1';
        end if;
        -- ESE-RAM 0x680000-0x6BFFFF -> die address 0x280000-0x2BFFFF
        if ram_req = '1' and ram_wr = '1' and ram_adr(21 downto 18) = "1010" then
          dg_eram <= '1';
        end if;
        -- main BIOS 0x690000-0x697FFF -> die address 0x290000-0x297FFF
        if ram_req = '1' and ram_wr = '0' and ram_adr(21 downto 15) = "1010010" then
          dg_main <= '1';
          if ram_ack = '1' and ack_d = '0' then
            if ram_adr = "10" & x"90000" then dg_rm(15 downto 8) <= ram_dbi; end if;
            if ram_adr = "10" & x"90001" then dg_rm(7 downto 0)  <= ram_dbi; end if;
          end if;
        end if;
        if ram_req = '1' and ram_wr = '1' and ram_ack = '1' and ack_d = '0' then
          if ram_adr = "10" & x"80000" then dg_wa(15 downto 8) <= ram_dbo; end if;
          if ram_adr = "10" & x"80001" then dg_wa(7 downto 0)  <= ram_dbo; end if;
          if ram_adr = "10" & x"90000" then dg_wm(15 downto 8) <= ram_dbo; end if;
          if ram_adr = "10" & x"90001" then dg_wm(7 downto 0)  <= ram_dbo; end if;
        end if;
        ack_d <= ram_ack;
        if ram_ack = '1' and ack_d = '0' then
          dg_rc <= dg_rc + 1;
        end if;
      end if;
    end if;
  end process;

  u_uart : entity work.uart_report
    generic map (
      TPL => "MSX PC=#### SL=## VW=## F=# RC=#### WA=#### WM=#### RM=####" & CR & LF,
      NNIB => 25, CLKS_PER_BIT => 188, PERIOD_BITS => 24)
    port map (
      clk  => clk21m,
      snap => dbg(31 downto 16) & dbg(15 downto 8) & dbg(7 downto 0)
              & dg_flash & dg_eram & dg_main & ps_overrun & std_logic_vector(dg_rc)
              & dg_wa & dg_wm & dg_rm,
      tx   => utx);
  uart_tx  <= utx;
  uart_tx2 <= utx;

  -- joystick / buttons synchronised to clk21m
  process(clk21m)
  begin
    if rising_edge(clk21m) then
      joy_s1 <= joy_btn3 & joy_btn2 & joy_fire & joy_right & joy_left & joy_down & joy_up;
      joy_s2 <= joy_s1;
    end if;
  end process;

  audio_l <= audio;
  audio_r <= audio;

  ----------------------------------------------------------------
  -- MSX
  ----------------------------------------------------------------
  u_core : entity work.emsx_core
    port map (
      clk21m    => clk21m,
      reset_n   => msx_rst_n,
      pVramSlot => vram_slot,
      pVramAdr  => vram_adr,
      pVramWe_n => vram_we_n,
      pVramDbo  => vram_dbo,
      pVramDbi  => vram_dbi,
      pRamReq   => ram_req,
      pRamWr    => ram_wr,
      pRamAdr   => ram_adr,
      pRamDbo   => ram_dbo,
      pRamDbi   => ram_dbi,
      pRamAck   => ram_ack,
      pPs2Clk   => ps2_clk,
      pPs2Dat   => ps2_dat,
      pJoyA     => joy_s2(5 downto 0),
      pStrA     => open,
      pJoyB     => (others => '1'),
      pStrB     => open,
      pKeySpace_n => joy_s2(6),
      pSd_Ck    => sd_sck,
      pSd_Cm    => sd_cmd,
      pSd_Cs    => sd_cs,
      pSd_Do    => sd_dat0,
      pEpc_Ck   => fl_ck_c,
      pEpc_Cs   => fl_cs_c,
      pEpc_Di   => fl_di_c,
      pEpc_Do   => flash_miso,
      pLedSd    => led_sd,
      pVideoR   => vr,
      pVideoG   => vg,
      pVideoB   => vb,
      pVideoHS_n => vhs_n,
      pVideoVS_n => vvs_n,
      pAudio    => audio,
      pDbg      => dbg
    );

  u_mem : entity work.psram_msx
    generic map (FREQ => FMEM, LATENCY => LC, RATIO => RATIO)
    port map (
      clk => memclk, clk_p => memclk_p, resetn => sys_lock, ready => ps_ready,
      vdp_slot => vram_slot, vdp_adr => vram_adr, vdp_we_n => vram_we_n,
      vdp_dbo => vram_dbo, vdp_dbi => vram_dbi, vdp_overrun => ps_overrun,
      cpu_req => ram_req, cpu_wr => ram_wr, cpu_adr => ram_adr,
      cpu_dbo => ram_dbo, cpu_dbi => ram_dbi, cpu_ack => ram_ack,
      O_psram_ck => O_psram_ck, O_psram_ck_n => O_psram_ck_n,
      IO_psram_rwds => IO_psram_rwds, IO_psram_dq => IO_psram_dq,
      O_psram_reset_n => O_psram_reset_n, O_psram_cs_n => O_psram_cs_n);

  ----------------------------------------------------------------
  -- video
  ----------------------------------------------------------------
  u_v2h : entity work.vdp2hdmi
    port map (
      clk21m => clk21m, vdp_r => vr, vdp_g => vg, vdp_b => vb,
      vdp_hs_n => vhs_n, vdp_vs_n => vvs_n,
      clk_pix => clk_pix, rst_pix => pix_rst,
      hdmi_r => hr, hdmi_g => hg, hdmi_b => hb,
      hdmi_hs => hhs, hdmi_vs => hvs, hdmi_de => hde, locked => hlocked);

  u_hdmi : entity work.hdmi_module
    port map (
      vga_clk_x5 => clk135, vga_clk => clk_pix, rst => pix_rst,
      vga_red_in => hr, vga_green_in => hg, vga_blue_in => hb,
      vga_hsync_in => hhs, vga_vsync_in => hvs, vga_disp_ena_in => hde,
      tmds_c0_p_out => tmds_d_p(0), tmds_c0_n_out => tmds_d_n(0),
      tmds_c1_p_out => tmds_d_p(1), tmds_c1_n_out => tmds_d_n(1),
      tmds_c2_p_out => tmds_d_p(2), tmds_c2_n_out => tmds_d_n(2),
      tmds_ck_p_out => tmds_ck_p, tmds_ck_n_out => tmds_ck_n);

  ----------------------------------------------------------------
  -- LEDs (active low)
  ----------------------------------------------------------------
  process(clk21m)
  begin
    if rising_edge(clk21m) then
      beat <= beat + 1;
    end if;
  end process;

  led_n(0) <= not dg_flash;
  led_n(1) <= not ps_overrun;
  led_n(2) <= ps_ready;
  led_n(3) <= not dg_eram;
  led_n(4) <= not dg_main;
  led_n(5) <= beat(24);

end architecture;
