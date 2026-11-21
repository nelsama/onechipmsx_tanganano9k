--
-- psram_chan_model.vhd : behavioural model of src/memory/psram_chan.vhd
-- (simulation only; compile it INSTEAD of the real channel).
--
-- Same entity and ports. The pins are not modelled; the model reproduces
-- the read/write/busy/dout interface and its timing in clk cycles, as
-- measured on the board with the zf3 controller (pengo_arcade psram_test):
--   - busy = '1' for INIT_CYCLES after resetn (160 us on the real one);
--   - a read/write pulse is accepted on an edge with busy = '0';
--     busy is '1' from that edge until the end of the access;
--   - with FIXED latency every access takes the 2x latency:
--       read  : dout and busy = '0' at the accepting edge + 8 + 2*LATENCY
--       write : memory written, busy = '0' at the accepting edge + 2 + 2*LATENCY
--     (without FIXED the 1x durations are used: 8 + LATENCY / 2 + LATENCY).
--
-- The memory lives in psram_sim_pkg, one array per die (generic DIE), so
-- the testbench can preload and dump it.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package psram_sim_pkg is
  constant DIE0_WORDS : integer := 65536;       -- VRAM: 128 KB
  constant DIE1_WORDS : integer := 2097152;     -- CPU : 4 MB
  type die0_t is array (0 to DIE0_WORDS - 1) of integer range 0 to 65535;
  type die1_t is array (0 to DIE1_WORDS - 1) of integer range 0 to 65535;
  shared variable die0 : die0_t;
  shared variable die1 : die1_t;

  procedure psram_write(die : integer; word : integer; v : std_logic_vector(15 downto 0));
  impure function psram_read(die : integer; word : integer) return std_logic_vector;
end package;

package body psram_sim_pkg is
  procedure psram_write(die : integer; word : integer; v : std_logic_vector(15 downto 0)) is
  begin
    if die = 0 then
      die0(word mod DIE0_WORDS) := to_integer(unsigned(v));
    else
      die1(word mod DIE1_WORDS) := to_integer(unsigned(v));
    end if;
  end procedure;

  impure function psram_read(die : integer; word : integer) return std_logic_vector is
  begin
    if die = 0 then
      return std_logic_vector(to_unsigned(die0(word mod DIE0_WORDS), 16));
    else
      return std_logic_vector(to_unsigned(die1(word mod DIE1_WORDS), 16));
    end if;
  end function;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.psram_sim_pkg.all;

entity psram_chan is
  generic (
    FREQ    : integer := 85909090;
    LATENCY : integer := 3;
    FIXED   : boolean := true;
    DIE     : integer := 0
  );
  port (
    clk        : in    std_logic;
    clk_p      : in    std_logic;
    resetn     : in    std_logic;
    read       : in    std_logic;
    write      : in    std_logic;
    addr       : in    std_logic_vector(21 downto 0);
    din        : in    std_logic_vector(15 downto 0);
    byte_write : in    std_logic;
    dout       : out   std_logic_vector(15 downto 0);
    busy       : out   std_logic;
    psram_ck   : out   std_logic;
    psram_cs_n : out   std_logic;
    psram_rwds : inout std_logic;
    psram_dq   : inout std_logic_vector(7 downto 0)
  );
end entity;

architecture sim of psram_chan is

  -- short init in simulation (the real one waits 160 us)
  constant INIT_CYCLES : integer := 64;

  function rd_cycles return integer is
  begin
    if FIXED then return 8 + 2 * LATENCY; else return 8 + LATENCY; end if;
  end function;
  function wr_cycles return integer is
  begin
    if FIXED then return 2 + 2 * LATENCY; else return 2 + LATENCY; end if;
  end function;

  type st_t is (INIT_ST, IDLE_ST, READ_ST, WRITE_ST);
  signal st : st_t := INIT_ST;

begin

  psram_ck   <= '0';
  psram_cs_n <= '1';
  psram_rwds <= 'Z';
  psram_dq   <= (others => 'Z');

  busy <= '0' when st = IDLE_ST else '1';

  process(clk)
    variable cnt : integer := 0;
    variable a   : std_logic_vector(21 downto 0);
    variable d   : std_logic_vector(15 downto 0);
    variable bw  : std_logic;
    variable w   : integer;
    variable m   : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        st <= INIT_ST;
        cnt := 0;
      else
        case st is
          when INIT_ST =>
            cnt := cnt + 1;
            if cnt >= INIT_CYCLES then
              st <= IDLE_ST;
            end if;
          when IDLE_ST =>
            if read = '1' or write = '1' then
              a := addr; d := din; bw := byte_write;
              cnt := 0;
              if write = '1' then st <= WRITE_ST; else st <= READ_ST; end if;
            end if;
          when READ_ST =>
            cnt := cnt + 1;
            if cnt >= rd_cycles then
              dout <= psram_read(DIE, to_integer(unsigned(a(21 downto 1))));
              st <= IDLE_ST;
            end if;
          when WRITE_ST =>
            cnt := cnt + 1;
            if cnt >= wr_cycles then
              w := to_integer(unsigned(a(21 downto 1)));
              m := psram_read(DIE, w);
              if bw = '0' then
                m := d;
              elsif a(0) = '1' then
                m(15 downto 8) := d(15 downto 8);
              else
                m(7 downto 0) := d(7 downto 0);
              end if;
              psram_write(DIE, w, m);
              st <= IDLE_ST;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture;
