--
-- psram_test_top.vhd : board test of src/memory/psram_msx.vhd, with the same
-- clocks as tn9k_top (RATIO 4: memclk 86.4 MHz, LC 3, clk21m 21.6 MHz).
--
-- Die 0 (VRAM port): exactly the VDP pattern, one access per dot (4 clk21m),
-- address registered at E0 with vdp_slot = '1' during the first clk21m, the
-- read word captured at E0 + 6 clk21m, byte lane = address bit 16.
--   A pass writes the 128 KB, then reads and checks them.
-- Die 1 (CPU port): request / acknowledge like emsx_core (registered
-- request, data checked after the acknowledge); a pass writes and checks
-- 256 KB at die address 0x280000 (the ESE-RAM area of the MSX).
-- The data depends on the address and the pass number.
--
-- LEDs (active low, lit = true):
--   0 die 0 (VRAM) error seen        1 die 1 (CPU) error seen
--   2 PSRAM not ready                3 VRAM overrun (controller too slow)
--   4 toggles every 8 passes of die 0 (~2.5 Hz blinking = test running)
--   5 toggles every 8 passes of die 1
-- S1 clears the error flags and counters.
--
-- UART (pins 17 and 32, 115200 8N1), every ~0.8 s:
--   PSRAM P0=pp P1=pp E0=eeee E1=eeee A0=aaaaa G0=gg X0=xx A1=aaaaa G1=gg X1=xx OV=o
--     P0/P1 passes of die 0 / die 1, E0/E1 errors (saturating),
--     A/G/X first failing address, data got, data expected, OV overrun
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity psram_test_top is
  port (
    clk27       : in    std_logic;
    btn_s1_n    : in    std_logic;
    led_n       : out   std_logic_vector(5 downto 0);
    uart_tx     : out   std_logic;
    uart_tx2    : out   std_logic;
    O_psram_ck      : out   std_logic_vector(1 downto 0);
    O_psram_ck_n    : out   std_logic_vector(1 downto 0);
    IO_psram_rwds   : inout std_logic_vector(1 downto 0);
    IO_psram_dq     : inout std_logic_vector(15 downto 0);
    O_psram_reset_n : out   std_logic_vector(1 downto 0);
    O_psram_cs_n    : out   std_logic_vector(1 downto 0)
  );
end entity;

architecture rtl of psram_test_top is
  signal memclk, memclk_p, clk21m, sys_lock : std_logic;
  signal ready, overrun : std_logic;

  -- VDP-like port
  signal slot, we_n : std_logic := '0';
  signal adr        : std_logic_vector(16 downto 0) := (others => '0');
  signal dbo        : std_logic_vector(7 downto 0) := (others => '0');
  signal dbi        : std_logic_vector(15 downto 0);
  signal ph         : unsigned(1 downto 0) := "00";
  signal v_idx      : unsigned(16 downto 0) := (others => '0');
  signal v_rd       : std_logic := '0';               -- 0 write half, 1 read half
  signal v_pass     : unsigned(7 downto 0) := (others => '0');
  signal p_valid    : std_logic := '0';               -- previous dot was a read
  signal p_adr      : std_logic_vector(16 downto 0);
  signal p_exp      : std_logic_vector(7 downto 0);
  signal q_valid    : std_logic := '0';               -- access of the previous dot
  signal q_adr      : std_logic_vector(16 downto 0);
  signal q_exp      : std_logic_vector(7 downto 0);
  signal err0       : std_logic := '0';

  -- CPU-like port
  signal c_req, c_wr, c_ack : std_logic := '0';
  signal c_adr      : std_logic_vector(21 downto 0) := (others => '0');
  signal c_dbo, c_dbi : std_logic_vector(7 downto 0);
  signal c_idx      : unsigned(17 downto 0) := (others => '0');
  signal c_rd       : std_logic := '0';
  signal c_pass     : unsigned(7 downto 0) := (others => '0');
  type c_st_t is (C_GO, C_WAIT, C_REL);
  signal c_st       : c_st_t := C_GO;
  signal err1       : std_logic := '0';

  signal s1         : std_logic_vector(2 downto 0) := (others => '1');
  signal e0n, e1n   : unsigned(15 downto 0) := (others => '0');
  signal f0a        : std_logic_vector(19 downto 0) := (others => '0');
  signal f0g, f0x   : std_logic_vector(7 downto 0) := (others => '0');
  signal f1a        : std_logic_vector(19 downto 0) := (others => '0');
  signal f1g, f1x   : std_logic_vector(7 downto 0) := (others => '0');
  signal utx        : std_logic;
  signal rdy        : std_logic := '0';

  function pat(a : unsigned; pass : unsigned(7 downto 0)) return std_logic_vector is
    variable x : unsigned(7 downto 0);
  begin
    x := a(7 downto 0) xor a(15 downto 8) xor pass xor ("0000000" & a(a'high));
    return std_logic_vector(x);
  end function;
begin

  u_pll : entity work.gw_rpll
    generic map (FCLKIN => "27", IDIV => 4, FBDIV => 15, ODIV => 8,
                 PSDA => "0100", SDIV => 4)
    port map (clkin => clk27, clkout => memclk, clkoutp => memclk_p,
              clkoutd => clk21m, lock => sys_lock);

  u_mem : entity work.psram_msx
    generic map (FREQ => 86400000, LATENCY => 3, RATIO => 4)
    port map (
      clk => memclk, clk_p => memclk_p, resetn => sys_lock, ready => ready,
      vdp_slot => slot, vdp_adr => adr, vdp_we_n => we_n,
      vdp_dbo => dbo, vdp_dbi => dbi, vdp_overrun => overrun,
      cpu_req => c_req, cpu_wr => c_wr, cpu_adr => c_adr,
      cpu_dbo => c_dbo, cpu_dbi => c_dbi, cpu_ack => c_ack,
      O_psram_ck => O_psram_ck, O_psram_ck_n => O_psram_ck_n,
      IO_psram_rwds => IO_psram_rwds, IO_psram_dq => IO_psram_dq,
      O_psram_reset_n => O_psram_reset_n, O_psram_cs_n => O_psram_cs_n);

  ----------------------------------------------------------------
  -- die 0: VDP pattern. ph = 0 is the dot's first clk21m (slot = '1').
  ----------------------------------------------------------------
  process(clk21m)
    variable lane : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk21m) then
      s1 <= s1(1 downto 0) & btn_s1_n;
      rdy <= ready;
      ph <= ph + 1;
      slot <= '0';
      if rdy = '1' then
        if ph = 3 then
          -- edge E0 of the next dot: new access
          slot <= '1';
          adr  <= std_logic_vector(v_idx);
          dbo  <= pat(v_idx, v_pass);
          we_n <= v_rd;
          q_valid <= p_valid;
          q_adr <= p_adr;
          q_exp <= p_exp;
          p_valid <= v_rd;
          p_adr <= std_logic_vector(v_idx);
          p_exp <= pat(v_idx, v_pass);
          if v_idx = 2**17 - 1 then
            v_rd <= not v_rd;
            if v_rd = '1' then v_pass <= v_pass + 1; end if;
          end if;
          v_idx <= v_idx + 1;
        end if;
        -- edge E0 + 6 of an access = the edge entering ph = 2 of the next
        -- dot; at E0 + 4 its p_* moved to q_*
        if ph = 1 and q_valid = '1' then
          if q_adr(16) = '1' then lane := dbi(15 downto 8); else lane := dbi(7 downto 0); end if;
          if lane /= q_exp then
            if err0 = '0' then
              f0a <= "000" & q_adr; f0g <= lane; f0x <= q_exp;
            end if;
            err0 <= '1';
            if e0n /= x"FFFF" then e0n <= e0n + 1; end if;
          end if;
        end if;
      end if;
      if s1(2) = '0' then err0 <= '0'; e0n <= (others => '0'); end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- die 1: CPU pattern (registered request, check after acknowledge)
  ----------------------------------------------------------------
  process(clk21m)
  begin
    if rising_edge(clk21m) then
      case c_st is
        when C_GO =>
          if rdy = '1' then
            c_req <= '1';
            c_wr  <= not c_rd;
            c_adr <= "1010" & std_logic_vector(c_idx);
            c_dbo <= pat(c_idx, c_pass);
            c_st  <= C_WAIT;
          end if;
        when C_WAIT =>
          if c_ack = '1' then
            if c_rd = '1' and c_dbi /= pat(c_idx, c_pass) then
              if err1 = '0' then
                f1a <= "00" & std_logic_vector(c_idx); f1g <= c_dbi; f1x <= pat(c_idx, c_pass);
              end if;
              err1 <= '1';
              if e1n /= x"FFFF" then e1n <= e1n + 1; end if;
            end if;
            c_req <= '0';
            c_st  <= C_REL;
          end if;
        when C_REL =>
          if c_ack = '0' then
            if c_idx = 2**18 - 1 then
              c_rd <= not c_rd;
              if c_rd = '1' then c_pass <= c_pass + 1; end if;
            end if;
            c_idx <= c_idx + 1;
            c_st  <= C_GO;
          end if;
      end case;
      if s1(2) = '0' then err1 <= '0'; e1n <= (others => '0'); end if;
    end if;
  end process;

  u_uart : entity work.uart_report
    generic map (
      TPL => "PSRAM P0=## P1=## E0=#### E1=#### A0=##### G0=## X0=## A1=##### G1=## X1=## OV=#" & CR & LF,
      NNIB => 2+2+4+4+5+2+2+5+2+2+1, CLKS_PER_BIT => 188, PERIOD_BITS => 24)
    port map (
      clk  => clk21m,
      snap => std_logic_vector(v_pass) & std_logic_vector(c_pass)
              & std_logic_vector(e0n) & std_logic_vector(e1n)
              & f0a & f0g & f0x & f1a & f1g & f1x & "000" & overrun,
      tx   => utx);
  uart_tx  <= utx;
  uart_tx2 <= utx;

  led_n(0) <= not err0;
  led_n(1) <= not err1;
  led_n(2) <= ready;
  led_n(3) <= not overrun;
  led_n(4) <= v_pass(3);
  led_n(5) <= c_pass(3);

end architecture;
