--
-- tb_hdmi.vhd : synthetic VDP (684 x 524) -> vdp2hdmi -> hdmi_tx, as connected
-- in tn9k_top. Writes the TMDS symbols with the expected sync / de / rgb
-- (q.txt) and the audio samples sent (au.txt) for receptor.js.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is end;

architecture t of tb is
  signal c21, c : std_logic := '0';
  signal stop : boolean := false;
  signal x : integer range 0 to 683 := 0;
  signal y : integer range 0 to 523 := 400;
  signal r, g, b : std_logic_vector(5 downto 0);
  signal hs_n, vs_n : std_logic;
  signal hr, hg, hb : std_logic_vector(7 downto 0);
  signal hhs, hvs, hde, locked : std_logic;
  signal h, v : unsigned(9 downto 0);
  signal rgb : std_logic_vector(23 downto 0);
  signal req, rq : std_logic := '0';
  signal au : std_logic_vector(15 downto 0) := (others => '0');
  signal q0, q1, q2 : std_logic_vector(9 downto 0);
  signal n : integer := 0;
  file f : text open write_mode is "q.txt";
  file ga : text open write_mode is "au.txt";
begin
  c21 <= not c21 after 23150 ps when not stop else '0';
  c   <= not c   after 18520 ps when not stop else '0';

  process(c21) begin
    if rising_edge(c21) then
      if x = 683 then
        x <= 0;
        if y = 523 then y <= 0; else y <= y + 1; end if;
      else
        x <= x + 1;
      end if;
    end if;
  end process;
  hs_n <= '0' when x < 80 else '1';
  vs_n <= '0' when y < 3 else '1';
  r <= std_logic_vector(to_unsigned((x * 3 + y) mod 64, 6));
  g <= std_logic_vector(to_unsigned((x + y * 5) mod 64, 6));
  b <= std_logic_vector(to_unsigned((x * y) mod 64, 6));

  u1 : entity work.vdp2hdmi port map (c21, r, g, b, hs_n, vs_n, c, '0',
         hr, hg, hb, hhs, hvs, hde, h, v, locked);
  rgb <= hr & hg & hb;
  u2 : entity work.hdmi_tx generic map (FULL => true, H_TOT => 855, V_TOT => 524)
    port map (c, h, v, hhs, hvs, hde, rgb, req, au, q0, q1, q2);

  process(c)
    variable l : line;
    variable a : unsigned(15 downto 0) := x"1234";
    variable skip : integer := 1000000;
  begin
    if rising_edge(c) then
      rq <= req;
      if rq /= req then
        a := a(14 downto 0) & (a(15) xor a(13) xor a(12) xor a(10));
        au <= std_logic_vector(a);
        if locked = '1' then write(l, to_integer(a)); writeline(ga, l); end if;
      end if;
      -- record once locked (locked rises at the 2nd VS, line 484)
      if locked = '1' then
        write(l, q0); write(l, ' '); write(l, q1); write(l, ' '); write(l, q2); write(l, ' ');
        write(l, hhs); write(l, hvs); write(l, hde); write(l, ' '); hwrite(l, rgb);
        writeline(f, l);
        n <= n + 1;
        if n = 1000000 then stop <= true; end if;
      end if;
    end if;
  end process;
end;
