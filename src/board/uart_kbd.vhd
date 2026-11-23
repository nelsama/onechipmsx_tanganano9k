--
-- uart_kbd.vhd : MSX keyboard over the UART.
--
-- Receives 8N1 characters (115200 baud at 21.6 MHz) and presses the
-- matching key of the MSX keyboard matrix for ~50 ms, then releases it for
-- ~50 ms (the BIOS scans the keyboard at 60 Hz). Characters that arrive
-- while a key is being pressed are dropped (typed by hand that never
-- happens; pasted text would lose characters).
--
-- Layout: MSX international (rows 0-2 for digits and symbols, rows 2-5 for
-- letters, 6-8 for the special keys). Upper case letters and the shifted
-- symbols press SHIFT too. Control characters:
--   CR -> RETURN, BS / DEL -> BS, TAB -> TAB, ESC -> ESC,
--   ESC [ A/B/C/D (ANSI cursor keys) -> UP/DOWN/RIGHT/LEFT,
--   ^C -> CTRL+STOP
-- A lone ESC is pressed when no '[' follows within ~5 ms.
--
-- Output to emsx_core: key_valid, key_row (matrix row 0-8), key_col (bit),
-- key_shift, key_ctrl.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_kbd is
  generic (
    CLKS_PER_BIT : integer := 188       -- 21.6 MHz / 115200
  );
  port (
    clk       : in  std_logic;
    rx        : in  std_logic;
    key_valid : out std_logic;
    key_row   : out std_logic_vector(3 downto 0);
    key_col   : out std_logic_vector(2 downto 0);
    key_shift : out std_logic;
    key_ctrl  : out std_logic
  );
end entity;

architecture rtl of uart_kbd is

  -- receiver
  signal rx_s     : std_logic_vector(2 downto 0) := (others => '1');
  signal rx_busy  : std_logic := '0';
  signal rx_cnt   : integer range 0 to CLKS_PER_BIT * 3 / 2 := 0;
  signal rx_bit   : integer range 0 to 9 := 0;
  signal rx_sh    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_stb   : std_logic := '0';
  signal rx_dat   : std_logic_vector(7 downto 0) := (others => '0');

  -- key presser
  constant T_PRESS : integer := 1080000;   -- 50 ms at 21.6 MHz
  constant T_ESC   : integer := 108000;    -- 5 ms
  type st_t is (S_IDLE, S_ESC, S_CSI, S_DOWN, S_UP);
  signal st       : st_t := S_IDLE;
  signal tmr      : integer range 0 to T_PRESS := 0;
  signal k_row    : std_logic_vector(3 downto 0) := (others => '0');
  signal k_col    : std_logic_vector(2 downto 0) := (others => '0');
  signal k_shift  : std_logic := '0';
  signal k_ctrl   : std_logic := '0';

  -- ASCII (0x20-0x7E) -> shift & row(4) & col(3); "1111" & ... = no key
  function lookup(c : integer) return std_logic_vector is
    variable r : std_logic_vector(7 downto 0);
  begin
    -- r(7) = shift, r(6 downto 3) = row, r(2 downto 0) = column
    case c is
      when 16#20# => r := "0" & "1000" & "000";   -- space
      when 16#30# to 16#37# => r := "0" & "0000" & std_logic_vector(to_unsigned(c - 16#30#, 3));
      when 16#38# => r := "0" & "0001" & "000";   -- 8
      when 16#39# => r := "0" & "0001" & "001";   -- 9
      when 16#2D# => r := "0" & "0001" & "010";   -- -
      when 16#3D# => r := "0" & "0001" & "011";   -- =
      when 16#5C# => r := "0" & "0001" & "100";   -- \
      when 16#5B# => r := "0" & "0001" & "101";   -- [
      when 16#5D# => r := "0" & "0001" & "110";   -- ]
      when 16#3B# => r := "0" & "0001" & "111";   -- ;
      when 16#27# => r := "0" & "0010" & "000";   -- '
      when 16#60# => r := "0" & "0010" & "001";   -- `
      when 16#2C# => r := "0" & "0010" & "010";   -- ,
      when 16#2E# => r := "0" & "0010" & "011";   -- .
      when 16#2F# => r := "0" & "0010" & "100";   -- /
      -- shifted symbols
      when 16#29# => r := "1" & "0000" & "000";   -- )  (shift 0)
      when 16#21# => r := "1" & "0000" & "001";   -- !
      when 16#40# => r := "1" & "0000" & "010";   -- @
      when 16#23# => r := "1" & "0000" & "011";   -- #
      when 16#24# => r := "1" & "0000" & "100";   -- $
      when 16#25# => r := "1" & "0000" & "101";   -- %
      when 16#5E# => r := "1" & "0000" & "110";   -- ^
      when 16#26# => r := "1" & "0000" & "111";   -- &
      when 16#2A# => r := "1" & "0001" & "000";   -- *
      when 16#28# => r := "1" & "0001" & "001";   -- (
      when 16#5F# => r := "1" & "0001" & "010";   -- _
      when 16#2B# => r := "1" & "0001" & "011";   -- +
      when 16#7C# => r := "1" & "0001" & "100";   -- |
      when 16#7B# => r := "1" & "0001" & "101";   -- {
      when 16#7D# => r := "1" & "0001" & "110";   -- }
      when 16#3A# => r := "1" & "0001" & "111";   -- :
      when 16#22# => r := "1" & "0010" & "000";   -- "
      when 16#7E# => r := "1" & "0010" & "001";   -- ~
      when 16#3C# => r := "1" & "0010" & "010";   -- <
      when 16#3E# => r := "1" & "0010" & "011";   -- >
      when 16#3F# => r := "1" & "0010" & "100";   -- ?
      -- letters: a..z = row 2 col 6 .. row 5 col 7
      when 16#61# to 16#7A# =>
        r := "0" & std_logic_vector(to_unsigned((c - 16#61# + 22) / 8, 4))
                 & std_logic_vector(to_unsigned((c - 16#61# + 22) mod 8, 3));
      when 16#41# to 16#5A# =>
        r := "1" & std_logic_vector(to_unsigned((c - 16#41# + 22) / 8, 4))
                 & std_logic_vector(to_unsigned((c - 16#41# + 22) mod 8, 3));
      when others => r := "0" & "1111" & "000";   -- no key
    end case;
    return r;
  end function;

  -- the table in a block ROM (saves LUTs): registered read of the last
  -- received character, used one clock after the strobe
  type tbl_t is array (0 to 127) of std_logic_vector(7 downto 0);
  function mk_tbl return tbl_t is
    variable t : tbl_t;
  begin
    for i in 0 to 127 loop
      t(i) := lookup(i);
    end loop;
    return t;
  end function;
  constant TBL : tbl_t := mk_tbl;
  signal tbl_q    : std_logic_vector(7 downto 0) := (others => '0');
  attribute syn_romstyle : string;
  attribute syn_romstyle of tbl_q : signal is "block_rom";
  signal stb_d    : std_logic := '0';

begin

  -- UART receiver (8N1, sampled in the middle of each bit)
  process(clk)
  begin
    if rising_edge(clk) then
      rx_s <= rx_s(1 downto 0) & rx;
      rx_stb <= '0';
      if rx_busy = '0' then
        if rx_s(2) = '1' and rx_s(1) = '0' then          -- start bit
          rx_busy <= '1';
          rx_cnt  <= CLKS_PER_BIT * 3 / 2;               -- middle of bit 0
          rx_bit  <= 0;
        end if;
      elsif rx_cnt /= 0 then
        rx_cnt <= rx_cnt - 1;
      else
        if rx_bit = 8 then                               -- stop bit
          rx_busy <= '0';
          if rx_s(1) = '1' then
            rx_dat <= rx_sh;
            rx_stb <= '1';
          end if;
        else
          rx_sh  <= rx_s(1) & rx_sh(7 downto 1);         -- LSB first
          rx_bit <= rx_bit + 1;
          rx_cnt <= CLKS_PER_BIT - 1;
        end if;
      end if;
    end if;
  end process;

  -- key presser
  process(clk)
    variable c : integer range 0 to 255;
    variable e : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      tbl_q <= TBL(to_integer(unsigned(rx_dat(6 downto 0))));
      stb_d <= rx_stb;
      c := to_integer(unsigned(rx_dat));
      if tmr /= 0 then
        tmr <= tmr - 1;
      end if;
      case st is
        when S_IDLE =>
          if stb_d = '1' then
            k_shift <= '0';
            k_ctrl  <= '0';
            tmr <= T_PRESS;
            st  <= S_DOWN;
            case c is
              when 16#0D# => k_row <= "0111"; k_col <= "111";     -- RETURN
              when 16#08# | 16#7F# => k_row <= "0111"; k_col <= "101";  -- BS
              when 16#09# => k_row <= "0111"; k_col <= "011";     -- TAB
              when 16#03# => k_row <= "0111"; k_col <= "100"; k_ctrl <= '1';  -- CTRL+STOP
              when 16#1B# => st <= S_ESC; tmr <= T_ESC;           -- ESC or ESC [ x
              when others =>
                e := tbl_q;
                if e(6 downto 3) = "1111" or c > 127 then
                  st <= S_IDLE;                                   -- unknown: ignore
                else
                  k_shift <= e(7);
                  k_row   <= e(6 downto 3);
                  k_col   <= e(2 downto 0);
                end if;
            end case;
          end if;
        when S_ESC =>
          if rx_stb = '1' and c = 16#5B# then                     -- '['
            st <= S_CSI;
          elsif rx_stb = '1' or tmr = 0 then                      -- lone ESC
            k_row <= "0111"; k_col <= "010";
            tmr <= T_PRESS;
            st  <= S_DOWN;
          end if;
        when S_CSI =>
          if rx_stb = '1' then
            tmr <= T_PRESS;
            st  <= S_DOWN;
            k_row <= "1000";
            case c is
              when 16#41# => k_col <= "101";                      -- A: UP
              when 16#42# => k_col <= "110";                      -- B: DOWN
              when 16#43# => k_col <= "111";                      -- C: RIGHT
              when 16#44# => k_col <= "100";                      -- D: LEFT
              when others => st <= S_IDLE;
            end case;
          end if;
        when S_DOWN =>
          if tmr = 0 then
            tmr <= T_PRESS;
            st  <= S_UP;
          end if;
        when S_UP =>
          if tmr = 0 then
            st <= S_IDLE;
          end if;
      end case;
    end if;
  end process;

  key_valid <= '1' when st = S_DOWN else '0';
  key_row   <= k_row;
  key_col   <= k_col;
  key_shift <= k_shift;
  key_ctrl  <= k_ctrl;

end architecture;
