--
-- tb_vdp2hdmi.vhd : plays a VDP VGA dump (sim/tb_vdp.vhd format, one frame
-- starting at the VS falling edge) in a loop at 21.6 MHz into vdp2hdmi
-- (27 MHz side) and dumps HDMI frame number FRAMES:
--   one line per clk_pix: RRGGBB HS VS DE
-- and reports every reload of the raster ("locked" falling / not set).
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use std.textio.all;

entity tb_vdp2hdmi is
  generic (
    INFILE  : string  := "in.txt";
    OUTFILE : string  := "out.txt";
    FRAMES  : integer := 3
  );
end entity;

architecture sim of tb_vdp2hdmi is
  -- exact 4:5 ratio (21.6 / 27 MHz)
  constant T21  : time := 46300 ps;
  constant TPIX : time := 37040 ps;

  signal clk21m, clk_pix : std_logic := '0';
  signal done : boolean := false;
  signal r, g, b : std_logic_vector(5 downto 0) := (others => '0');
  signal hs_n, vs_n : std_logic := '1';
  signal hr, hg, hb : std_logic_vector(7 downto 0);
  signal hhs, hvs, hde, locked : std_logic;

  function hexval(c : character) return integer is
  begin
    case c is
      when '0' to '9' => return character'pos(c) - character'pos('0');
      when 'A' to 'F' => return character'pos(c) - character'pos('A') + 10;
      when 'a' to 'f' => return character'pos(c) - character'pos('a') + 10;
      when others => return 0;
    end case;
  end function;

  function hex2(v : std_logic_vector(7 downto 0)) return string is
    constant d : string(1 to 16) := "0123456789ABCDEF";
    variable s : string(1 to 2);
  begin
    s(1) := d(conv_integer(v(7 downto 4)) + 1);
    s(2) := d(conv_integer(v(3 downto 0)) + 1);
    return s;
  end function;

  function bc(x : std_logic) return character is
  begin
    if x = '1' then return '1'; else return '0'; end if;
  end function;

begin

  clk21m  <= not clk21m  after T21 / 2  when not done else '0';
  clk_pix <= not clk_pix after TPIX / 2 when not done else '0';

  dut : entity work.vdp2hdmi
    port map (clk21m, r, g, b, hs_n, vs_n, clk_pix, '0',
              hr, hg, hb, hhs, hvs, hde, open, open, locked);

  -- stimulus: the dump, looped
  process
    file f : text;
    variable l : line;
    variable c : character;
    variable v : integer;
    variable n : integer := 0;
    type mem_t is array (0 to 400000) of std_logic_vector(19 downto 0);
    variable m : mem_t;
    variable w : std_logic_vector(19 downto 0);
    variable s : string(1 to 9);
  begin
    file_open(f, INFILE, read_mode);
    while not endfile(f) loop
      readline(f, l);
      read(l, s);
      for k in 0 to 2 loop
        v := hexval(s(2*k + 1)) * 16 + hexval(s(2*k + 2));
        w(17 - 6*k downto 12 - 6*k) := conv_std_logic_vector(v mod 64, 6);
      end loop;
      if s(8) = '1' then w(19) := '1'; else w(19) := '0'; end if;
      if s(9) = '1' then w(18) := '1'; else w(18) := '0'; end if;
      m(n) := w;
      n := n + 1;
    end loop;
    file_close(f);
    for i in 1 to 10 loop wait until rising_edge(clk21m); end loop;
    while not done loop
      for i in 0 to n - 1 loop
        wait until rising_edge(clk21m);
        r <= m(i)(17 downto 12);
        g <= m(i)(11 downto 6);
        b <= m(i)(5 downto 0);
        hs_n <= m(i)(19);
        vs_n <= m(i)(18);
        exit when done;
      end loop;
    end loop;
    wait;
  end process;

  -- HDMI dump of frame FRAMES (counted on the HDMI VS falling edge)
  process(clk_pix)
    file f : text;
    variable l : line;
    variable frame : integer := 0;
    variable vs_d : std_logic := '1';
    variable opened : boolean := false;
    variable lk_d : std_logic := '0';
    variable reloads : integer := 0;
  begin
    if rising_edge(clk_pix) then
      if vs_d = '1' and hvs = '0' then
        frame := frame + 1;
        if frame = FRAMES then
          file_open(f, OUTFILE, write_mode);
          opened := true;
        elsif frame = FRAMES + 1 then
          file_close(f);
          opened := false;
          write(l, string'("frames: ")); write(l, frame);
          write(l, string'("  locked: ")); write(l, bc(locked));
          writeline(output, l);
          done <= true;
        end if;
      end if;
      if opened then
        write(l, hex2(hr) & hex2(hg) & hex2(hb));
        write(l, ' '); write(l, bc(hhs)); write(l, bc(hvs)); write(l, bc(hde));
        writeline(f, l);
      end if;
      if lk_d = '1' and locked = '0' then
        reloads := reloads + 1;
        write(l, string'("RELOCK at ")); write(l, now); writeline(output, l);
      end if;
      lk_d := locked;
      vs_d := hvs;
    end if;
  end process;

end architecture;
