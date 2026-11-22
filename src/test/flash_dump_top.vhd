--
-- flash_dump_top.vhd : reads the SPI flash of the Tang Nano 9K and reports
-- over the UART (pins 17 and 32, 115200 8N1), every ~1.2 s:
--
--   FL ID=iiiiii Z=zzzzzzzzzzzzzzzz A=aaaaaaaaaaaaaaaa M=mmmmmmmmmmmmmmmm S=ssssssss
--     ID  JEDEC ID (P25Q32: 856016)
--     Z   8 bytes at 0x000000
--     A   8 bytes at 0x040000 (BIOS image: 41 42 00 ...)
--     M   8 bytes at 0x050000 (main BIOS: F3 C3 ...)
--     S   32-bit sum of the 256 KB at 0x040000
--
-- SPI mode 0, SCK = 27 MHz / 4. Sequence per loop: 0xAB (wake up), 0x9F,
-- 0x03 @ 0x000000 (8 bytes), 0x03 @ 0x040000 (256 KB).
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity flash_dump_top is
  port (
    clk27      : in  std_logic;
    led_n      : out std_logic_vector(5 downto 0);
    uart_tx    : out std_logic;
    uart_tx2   : out std_logic;
    flash_cs_n : out std_logic;
    flash_clk  : out std_logic;
    flash_mosi : out std_logic;
    flash_miso : in  std_logic
  );
end entity;

architecture rtl of flash_dump_top is
  -- byte engine
  signal b_start, b_busy : std_logic := '0';
  signal b_tx, b_rx, sh  : std_logic_vector(7 downto 0) := (others => '0');
  signal b_cnt           : integer range 0 to 31 := 0;
  signal sck, mosi       : std_logic := '0';
  signal miso_s          : std_logic_vector(1 downto 0) := (others => '1');

  type st_t is (S_GAP, S_WAKE, S_WAKE_E, S_ID_CMD, S_ID, S_Z_CMD, S_Z, S_B_CMD, S_B, S_END);
  signal st     : st_t := S_GAP;
  signal cs_n   : std_logic := '1';
  signal n      : unsigned(18 downto 0) := (others => '0');
  signal gap    : unsigned(24 downto 0) := (others => '0');
  signal waitb  : std_logic := '0';
  signal cmd    : std_logic_vector(31 downto 0);

  signal id, id_r     : std_logic_vector(23 downto 0) := (others => '0');
  signal z, z_r       : std_logic_vector(63 downto 0) := (others => '0');
  signal a, a_r       : std_logic_vector(63 downto 0) := (others => '0');
  signal m, m_r       : std_logic_vector(63 downto 0) := (others => '0');
  signal sum, sum_r   : unsigned(31 downto 0) := (others => '0');
  signal utx          : std_logic;

  function abyte(c : std_logic_vector(31 downto 0); i : unsigned) return std_logic_vector is
  begin
    if i = 0 then return c(23 downto 16);
    elsif i = 1 then return c(15 downto 8);
    else return c(7 downto 0); end if;
  end function;
begin

  flash_cs_n <= cs_n;
  flash_clk  <= sck;
  flash_mosi <= mosi;

  -- one byte, MSB first, SPI mode 0, 4 clk27 per bit
  process(clk27)
  begin
    if rising_edge(clk27) then
      miso_s <= miso_s(0) & flash_miso;
      if b_busy = '0' then
        if b_start = '1' then
          b_busy <= '1';
          sh     <= b_tx;
          b_cnt  <= 0;
        end if;
      else
        case b_cnt mod 4 is
          when 0 => mosi <= sh(7); sck <= '0';
          when 2 => sck <= '1';
          when 3 => sh <= sh(6 downto 0) & flash_miso;   -- sampled 1 clk after the rising edge
          when others => null;
        end case;
        if b_cnt = 31 then
          b_busy <= '0';
          sck    <= '0';
        else
          b_cnt <= b_cnt + 1;
        end if;
      end if;
    end if;
  end process;
  b_rx <= sh;

  process(clk27)
    procedure send(v : std_logic_vector(7 downto 0)) is
    begin
      b_tx <= v; b_start <= '1'; waitb <= '1';
    end procedure;
  begin
    if rising_edge(clk27) then
      b_start <= '0';
      if waitb = '1' then
        if b_start = '0' and b_busy = '0' then
          waitb <= '0';
        end if;
      else
        case st is
          when S_GAP =>
            cs_n <= '1';
            gap <= gap + 1;
            if gap = 2**24 then
              gap <= (others => '0');
              cs_n <= '0';
              send(x"AB");
              st <= S_WAKE;
            end if;
          when S_WAKE =>
            cs_n <= '1';
            st <= S_WAKE_E;
            n <= (others => '0');
          when S_WAKE_E =>                       -- tRES1 3 us
            n <= n + 1;
            if n = 200 then
              cs_n <= '0';
              send(x"9F");
              n <= (others => '0');
              st <= S_ID_CMD;
            end if;
          when S_ID_CMD =>
            if n /= 0 then id <= id(15 downto 0) & b_rx; end if;
            if n = 3 then
              cs_n <= '1';
              n <= (others => '0');
              st <= S_Z_CMD;
            else
              n <= n + 1;
              send(x"00");
            end if;
          when S_Z_CMD =>
            cs_n <= '0';
            cmd <= x"03000000";
            n <= (others => '0');
            st <= S_Z;
            send(x"03");
          when S_Z =>                            -- 3 address bytes, then 8 data
            if n >= 4 then z <= z(55 downto 0) & b_rx; end if;
            if n = 11 then
              cs_n <= '1';
              st <= S_B_CMD;
            else
              if n < 3 then send(abyte(cmd, n));
              else send(x"00"); end if;
              n <= n + 1;
            end if;
          when S_B_CMD =>
            cs_n <= '0';
            cmd <= x"03040000";
            n <= (others => '0');
            sum <= (others => '0');
            st <= S_B;
            send(x"03");
          when S_B =>                            -- 3 address bytes, then 256 KB
            if n >= 4 then
              sum <= sum + unsigned(b_rx);
              if n < 12 then a <= a(55 downto 0) & b_rx; end if;
              if n >= 4 + 16#10000# and n < 12 + 16#10000# then m <= m(55 downto 0) & b_rx; end if;
            end if;
            if n = 3 + 16#40000# then
              cs_n <= '1';
              st <= S_END;
            else
              if n < 3 then send(abyte(cmd, n));
              else send(x"00"); end if;
              n <= n + 1;
            end if;
          when S_END =>
            id_r <= id; z_r <= z; a_r <= a; m_r <= m; sum_r <= sum;
            st <= S_GAP;
        end case;
      end if;
    end if;
  end process;

  u_uart : entity work.uart_report
    generic map (
      TPL => "FL ID=###### Z=################ A=################ M=################ S=########" & CR & LF,
      NNIB => 6 + 16 + 16 + 16 + 8, CLKS_PER_BIT => 234, PERIOD_BITS => 25)
    port map (clk => clk27,
              snap => id_r & z_r & a_r & m_r & std_logic_vector(sum_r),
              tx => utx);
  uart_tx  <= utx;
  uart_tx2 <= utx;

  led_n <= (others => '1');
end architecture;
