--
-- tb_sys.vhd : whole-system simulation of the boot: emsx_core (Z80, IPL-ROM,
-- megasd, VDP, ...) + psram_msx (sim/psram_chan_model.vhd) + an SPI flash
-- model holding the BIOS image + no SD card.
--
-- Reports every CPU write to the BIOS image area (ESE-RAM, die address
-- 0x280000..) for the first WRITES writes and at every 16 KB block start,
-- and the opcode-fetch address every PCSTEP.
--
-- Generics
--   IMAGE   BIOS image (256 KB, tools/make_bios.py), at flash address 0
--   WRITES  number of image writes reported one by one
--   SIMTIME_MS how long to simulate, in ms
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.psram_sim_pkg.all;

entity tb_sys is
  generic (
    IMAGE   : string := "OCM-BIOS.DAT";
    WRITES  : integer := 16;
    SIMTIME_MS : integer := 20;
    FASTBOOT   : integer := 0      -- 1: image preloaded in the PSRAM model
                                   -- (use with sim/iplrom_fastboot.vhd)
  );
end entity;

architecture sim of tb_sys is
  constant T21  : time := 46300 ps;      -- 21.6 MHz
  constant TMEM : time := T21 / 4;

  signal clk21m, memclk : std_logic := '0';
  signal done : boolean := false;
  signal reset_n : std_logic := '0';
  signal ready : std_logic;

  signal vram_slot, vram_we_n : std_logic;
  signal vram_adr  : std_logic_vector(16 downto 0);
  signal vram_dbo  : std_logic_vector(7 downto 0);
  signal vram_dbi  : std_logic_vector(15 downto 0);
  signal ram_req, ram_wr, ram_ack : std_logic;
  signal ram_adr   : std_logic_vector(21 downto 0);
  signal ram_dbo, ram_dbi : std_logic_vector(7 downto 0);
  signal overrun   : std_logic;

  signal fl_cs, fl_ck, fl_di, fl_do : std_logic := '1';
  signal sd_ck, sd_cm, sd_cs : std_logic;
  signal ps2c, ps2d : std_logic := 'H';
  signal vr, vg, vb : std_logic_vector(5 downto 0);
  signal hs, vs, aud, led : std_logic;
  signal dbg : std_logic_vector(31 downto 0);
  signal dbus : std_logic_vector(32 downto 0);

  signal ps_ck, ps_ckn, ps_rstn, ps_csn, ps_rwds : std_logic_vector(1 downto 0);
  signal ps_dq : std_logic_vector(15 downto 0);

  function hex(v : std_logic_vector) return string is
    constant d : string(1 to 16) := "0123456789ABCDEF";
    variable r : string(1 to (v'length + 3) / 4);
    variable x : unsigned(((v'length + 3) / 4) * 4 - 1 downto 0) := (others => '0');
  begin
    x(v'length - 1 downto 0) := unsigned(v);
    for i in r'range loop
      r(i) := d(to_integer(x((r'length - i) * 4 + 3 downto (r'length - i) * 4)) + 1);
    end loop;
    return r;
  end function;
begin
  clk21m <= not clk21m after T21 / 2 when not done else '0';
  memclk <= not memclk after TMEM / 2 when not done else '0';

  u_core : entity work.emsx_core
    port map (
      clk21m => clk21m, reset_n => reset_n,
      pVramSlot => vram_slot, pVramAdr => vram_adr, pVramWe_n => vram_we_n,
      pVramDbo => vram_dbo, pVramDbi => vram_dbi,
      pRamReq => ram_req, pRamWr => ram_wr, pRamAdr => ram_adr,
      pRamDbo => ram_dbo, pRamDbi => ram_dbi, pRamAck => ram_ack,
      pPs2Clk => ps2c, pPs2Dat => ps2d,
      pJoyA => (others => '1'), pStrA => open, pJoyB => (others => '1'), pStrB => open,
      pKeySpace_n => '1',
      pSd_Ck => sd_ck, pSd_Cm => sd_cm, pSd_Cs => sd_cs, pSd_Do => '1',
      pEpc_Ck => fl_ck, pEpc_Cs => fl_cs, pEpc_Di => fl_di, pEpc_Do => fl_do,
      pLedSd => led, pVideoR => vr, pVideoG => vg, pVideoB => vb,
      pVideoHS_n => hs, pVideoVS_n => vs, pAudio => aud, pDbg => dbg, pDbgBus => dbus);

  u_mem : entity work.psram_msx
    generic map (FREQ => 86400000, LATENCY => 3, RATIO => 4)
    port map (
      clk => memclk, clk_p => memclk, resetn => '1', ready => ready,
      vdp_slot => vram_slot, vdp_adr => vram_adr, vdp_we_n => vram_we_n,
      vdp_dbo => vram_dbo, vdp_dbi => vram_dbi, vdp_overrun => overrun,
      cpu_req => ram_req, cpu_wr => ram_wr, cpu_adr => ram_adr,
      cpu_dbo => ram_dbo, cpu_dbi => ram_dbi, cpu_ack => ram_ack,
      O_psram_ck => ps_ck, O_psram_ck_n => ps_ckn, IO_psram_rwds => ps_rwds,
      IO_psram_dq => ps_dq, O_psram_reset_n => ps_rstn, O_psram_cs_n => ps_csn);

  -- reset: released 20 clk21m after the PSRAM is ready
  process
  begin
    reset_n <= '0';
    wait until ready = '1';
    for i in 1 to 20 loop wait until rising_edge(clk21m); end loop;
    reset_n <= '1';
    wait;
  end process;

  -- SPI flash model (mode 0/3): MOSI sampled on rising SCK, MISO shifted
  -- out on falling SCK. 0x03 READ (24-bit address), 0xAB, 0x9F.
  process
    type img_t is array (0 to 262143) of std_logic_vector(7 downto 0);
    type char_file_t is file of character;
    file f : char_file_t;
    variable img : img_t := (others => x"FF");
    variable c : character;
    variable n : integer := 0;
    variable st : file_open_status;
    variable cmd, a : integer;
    variable sh : std_logic_vector(7 downto 0);
    variable bitn, byten : integer;
    variable obyte : std_logic_vector(7 downto 0);
    variable l : line;
  begin
    file_open(st, f, IMAGE, read_mode);
    assert st = open_ok report "cannot open " & IMAGE severity failure;
    while not endfile(f) and n < 262144 loop
      read(f, c);
      img(n) := std_logic_vector(to_unsigned(character'pos(c), 8));
      n := n + 1;
    end loop;
    file_close(f);
    write(l, string'("flash model: ") & integer'image(n) & " bytes"); writeline(output, l);
    if FASTBOOT = 1 then
      -- the IPL copy, done here: ESE-RAM = die 1, byte 0x280000 = word 0x140000
      for i in 0 to 131071 loop
        psram_write(1, 16#140000# + i, img(2 * i + 1) & img(2 * i));
      end loop;
      write(l, string'("image preloaded in the PSRAM model (FASTBOOT)")); writeline(output, l);
    end if;
    loop
      fl_do <= 'Z';
      wait until fl_cs = '0';
      bitn := 0; byten := 0; cmd := -1; a := 0; obyte := x"FF";
      while fl_cs = '0' loop
        wait until rising_edge(fl_ck) or fl_cs = '1';
        exit when fl_cs = '1';
        sh := sh(6 downto 0) & fl_di;
        bitn := bitn + 1;
        if bitn = 8 then
          bitn := 0;
          if byten = 0 then
            cmd := to_integer(unsigned(sh));
          elsif byten <= 3 and cmd = 3 then
            a := a * 256 + to_integer(unsigned(sh));
          end if;
          byten := byten + 1;
          if cmd = 3 and byten >= 4 then
            obyte := img((a + byten - 4) mod 262144);
          elsif cmd = 16#9F# and byten >= 1 then
            case byten is
              when 1 => obyte := x"85";
              when 2 => obyte := x"60";
              when others => obyte := x"16";
            end case;
          else
            obyte := x"FF";
          end if;
        end if;
        wait until falling_edge(fl_ck) or fl_cs = '1';
        exit when fl_cs = '1';
        if (cmd = 3 and byten >= 4) or (cmd = 16#9F# and byten >= 1) then
          fl_do <= obyte(7 - bitn);
        else
          fl_do <= '1';
        end if;
      end loop;
    end loop;
  end process;

  -- bus probe: writes to the ESE-RAM bank registers (slot 3-2, 6000-7FFFh)
  -- and to the slot registers
  process(clk21m)
    variable l : line;
    variable req_d : std_logic := '0';
    variable a : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk21m) then
      a := dbus(32 downto 17);
      if dbus(6) = '1' and req_d = '0' and dbus(8) = '1' and dbus(7) = '1' then   -- memory write
        if a(15 downto 13) = "011" and dbus(5 downto 4) = "11" and dbus(1 downto 0) = "10" then
          write(l, time'image(now) & "  ERM BANK " & hex(a) & " <= " & hex(dbus(16 downto 9))
                   & "  PC=" & hex(dbg(31 downto 16))); writeline(output, l);
        end if;
        if a = x"FFFF" then
          write(l, time'image(now) & "  SUBSLOT " & hex(dbus(16 downto 9)) & " (prim " & hex(dbus(5 downto 4)) & ")"
                   & "  PC=" & hex(dbg(31 downto 16))); writeline(output, l);
        end if;
      end if;
      req_d := dbus(6);
    end if;
  end process;

  -- monitor
  process(clk21m)
    variable l : line;
    variable nw : integer := 0;
    variable ack_d : std_logic := '0';
    variable a : integer;
    variable last_pc : std_logic_vector(15 downto 0) := (others => '0');
    variable tick : integer := 0;
  begin
    if rising_edge(clk21m) then
      if ram_ack = '1' and ack_d = '0' and ram_wr = '1' and ram_req = '1' then
        a := to_integer(unsigned(ram_adr));
        if a >= 16#280000# and a < 16#2C0000# then
          if nw < WRITES or (a - 16#280000#) mod 16384 < 2 then
            write(l, time'image(now) & "  W " & hex(ram_adr) & " = " & hex(ram_dbo)
                     & "   (image " & hex(std_logic_vector(to_unsigned(a - 16#280000#, 20))) & ")");
            writeline(output, l);
          end if;
          nw := nw + 1;
        end if;
      end if;
      ack_d := ram_ack;
      tick := tick + 1;
      if tick mod 21600 = 0 then           -- every ~1 ms
        write(l, time'image(now) & "  PC=" & hex(dbg(31 downto 16)) & " SL=" & hex(dbg(15 downto 8))
                 & " VW=" & hex(dbg(7 downto 0)) & " writes=" & integer'image(nw)
                 & " rst_n=" & std_logic'image(reset_n) & " rdy=" & std_logic'image(ready)
                 & " req=" & std_logic'image(ram_req) & " ack=" & std_logic'image(ram_ack)
                 & " adr=" & hex(ram_adr));
        writeline(output, l);
      end if;
      if now > SIMTIME_MS * 1 ms then
        done <= true;
      end if;
    end if;
  end process;
end architecture;
