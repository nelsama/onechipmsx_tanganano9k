--
-- tb_vdp.vhd : VDP testbench with a VRAM model of configurable latency.
--
-- Generics
--   SCREEN   : 0=TEXT1 1=G1 2=G2 3=MC 4=G3 5=G4 6=G5 7=G6 8=G7 80=TEXT2
--   LAT      : 0 = "ideal" VRAM (timing of the original SD-RAM sequencer:
--                  read data valid from the end of dotState "00")
--              N = read data valid N clk21m edges later; until then the bus
--                  keeps the previous word, so an early sample shows up as a
--                  wrong pixel. 4 = data valid from the start of dotState "01"
--                  of the NEXT dot (the budget of the retimed VDP).
--   DUMPFILE : per-clock dump of the VGA output of frame FRAMES
--              (one line per clk21m: RRGGBB in hex, then HS VS)
--   USE_PSRAM: 0 = the VRAM model below (latency LAT)
--              1 = src/memory/psram_msx with sim/psram_chan_model (the
--                  PSRAM controller as it will be on the board: memclk =
--                  RATIO x clk21m, latency code LC, fixed 2x latency)
--   CMDTEST  : run a VDP command (LMMV + HMMM) and a CPU VRAM write/read test
--              before the dumped frame; VRAM is dumped to DUMPFILE & ".vram"
--
-- The VRAM model behaves like the emsx SD-RAM controller: one access per dot
-- in the VDP slot (dotState "00"/"01", VideoDHClk = VideoDLClk = '1' during "00"),
-- 64K x 16 bit words, pRamAdr(16) selects the byte lane on writes.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use std.textio.all;
use work.psram_sim_pkg.all;

entity tb_vdp is
  generic(
    SCREEN   : integer := 5;
    LAT      : integer := 0;
    FRAMES   : integer := 3;
    CMDTEST  : integer := 0;
    USE_PSRAM: integer := 0;
    RATIO    : integer := 4;
    LC       : integer := 3;
    DUMPFILE : string  := "vdp.dump"
  );
end tb_vdp;

architecture sim of tb_vdp is

  component vdp
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0);
      dbo     : in std_logic_vector(7 downto 0);
      int_n   : out std_logic;
      pRamOe_n: out std_logic;
      pRamWe_n: out std_logic;
      pRamAdr : out std_logic_vector(16 downto 0);
      pRamDbi : in  std_logic_vector(15 downto 0);
      pRamDbo : out std_logic_vector(7 downto 0);
      pVideoR : out std_logic_vector( 5 downto 0);
      pVideoG : out std_logic_vector( 5 downto 0);
      pVideoB : out std_logic_vector( 5 downto 0);
      pVideoHS_n : out std_logic;
      pVideoVS_n : out std_logic;
      pVideoDHClk : out std_logic;
      pVideoDLClk : out std_logic
    );
  end component;

  constant TCLK : time := 46560 ps;              -- 21.477 MHz

  signal clk21m  : std_logic := '0';
  signal reset   : std_logic := '1';
  signal req     : std_logic := '0';
  signal ack     : std_logic;
  signal wrt     : std_logic := '0';
  signal adr     : std_logic_vector(15 downto 0) := (others => '0');
  signal dbi     : std_logic_vector(7 downto 0);
  signal dbo     : std_logic_vector(7 downto 0) := (others => '0');
  signal int_n   : std_logic;
  signal RamOe_n, RamWe_n : std_logic;
  signal RamAdr  : std_logic_vector(16 downto 0);
  signal RamDbi  : std_logic_vector(15 downto 0) := (others => '0');
  signal RamDbo  : std_logic_vector(7 downto 0);
  signal VideoR, VideoG, VideoB : std_logic_vector(5 downto 0);
  signal VideoHS_n, VideoVS_n, DHClk, DLClk : std_logic;

  -- PSRAM controller (USE_PSRAM = 1)
  signal memclk    : std_logic := '0';
  signal RamDbiM   : std_logic_vector(15 downto 0) := (others => '0');
  signal RamDbiP   : std_logic_vector(15 downto 0);
  signal VdpSlot   : std_logic;
  signal psReady   : std_logic;
  signal psOverrun : std_logic;
  signal ps_ck, ps_ckn, ps_rstn, ps_csn : std_logic_vector(1 downto 0);
  signal ps_rwds   : std_logic_vector(1 downto 0);
  signal ps_dq     : std_logic_vector(15 downto 0);
  signal ps_cpudbi : std_logic_vector(7 downto 0);
  signal ps_cpuack : std_logic;

  signal setup_done : boolean := false;
  signal sim_done   : boolean := false;
  signal dump_vram  : boolean := false;
  signal vram_dumped: boolean := false;

  type mem_t is array (0 to 65535) of std_logic_vector(15 downto 0);

  function hex(v : std_logic_vector) return string is
    constant digits : string(1 to 16) := "0123456789ABCDEF";
    variable r      : string(1 to (v'length + 3) / 4);
    variable x      : std_logic_vector(((v'length + 3) / 4) * 4 - 1 downto 0) := (others => '0');
    variable d      : integer;
  begin
    x(v'length - 1 downto 0) := v;
    for i in r'range loop
      d := 0;
      for b in 3 downto 0 loop
        d := d * 2;
        if x((r'length - i) * 4 + b) = '1' then d := d + 1; end if;
      end loop;
      r(i) := digits(d + 1);
    end loop;
    return r;
  end function;

  function bit_char(b : std_logic) return character is
  begin
    if b = '1' then return '1'; elsif b = '0' then return '0'; else return 'X'; end if;
  end function;

begin

  clk21m <= not clk21m after TCLK/2 when not sim_done else '0';
  -- memclk edges coincide with the clk21m edges (same PLL on the board)
  memclk <= not memclk after TCLK/(2*RATIO) when not sim_done and USE_PSRAM = 1 else '0';

  RamDbi  <= RamDbiP when USE_PSRAM = 1 else RamDbiM;
  VdpSlot <= DHClk and DLClk;

  U_PSRAM : entity work.psram_msx
    generic map (FREQ => 21477270 * RATIO, LATENCY => LC, RATIO => RATIO)
    port map (
      clk => memclk, clk_p => memclk, resetn => '1', ready => psReady,
      vdp_slot => VdpSlot, vdp_adr => RamAdr, vdp_we_n => RamWe_n,
      vdp_dbo => RamDbo, vdp_dbi => RamDbiP, vdp_overrun => psOverrun,
      cpu_req => '0', cpu_wr => '0', cpu_adr => (others => '0'),
      cpu_dbo => (others => '0'), cpu_dbi => ps_cpudbi, cpu_ack => ps_cpuack,
      O_psram_ck => ps_ck, O_psram_ck_n => ps_ckn, IO_psram_rwds => ps_rwds,
      IO_psram_dq => ps_dq, O_psram_reset_n => ps_rstn, O_psram_cs_n => ps_csn);

  U_VDP : vdp port map(
    clk21m, reset, req, ack, wrt, adr, dbi, dbo, int_n,
    RamOe_n, RamWe_n, RamAdr, RamDbi, RamDbo,
    VideoR, VideoG, VideoB, VideoHS_n, VideoVS_n, DHClk, DLClk);

  ----------------------------------------------------------------
  -- VRAM model
  ----------------------------------------------------------------
  process(clk21m)
    variable mem     : mem_t;
    variable inited  : boolean := false;
    variable lfsr    : std_logic_vector(31 downto 0) := X"1234ABCD";
    variable pend    : std_logic_vector(15 downto 0);
    variable cnt     : integer := -1;
    variable a       : integer;
    variable sa, n   : integer;
    variable l       : line;
    file     vf      : text;

    procedure poke(addr : integer; v : std_logic_vector(7 downto 0)) is
      -- byte address in VDP linear space (bit16 = byte lane)
      variable w : integer := addr mod 65536;
    begin
      if addr >= 65536 then
        mem(w)(15 downto 8) := v;
      else
        mem(w)(7 downto 0) := v;
      end if;
    end procedure;

  begin
    if not inited then
      for i in 0 to 65535 loop
        for k in 0 to 15 loop
          lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
        end loop;
        mem(i) := lfsr(15 downto 0);
      end loop;
      -- Sprite attribute tables (see setup process for the bases):
      --  mode 1 at 0x1B00 (R5=0x36), mode 2 at 0x1E00 (R5=0x3F, R11=0, color table 0x1C00)
      for s in 0 to 31 loop
        if s < 12 then
          n := 16 + s * 14;                   -- Y
        else
          n := 208;                           -- terminator (mode 1) ...
        end if;
        poke(16#1B00# + s*4 + 0, conv_std_logic_vector(n mod 256, 8));
        poke(16#1B00# + s*4 + 1, conv_std_logic_vector((s * 37 + 8) mod 256, 8));   -- X
        poke(16#1B00# + s*4 + 2, conv_std_logic_vector(s * 4, 8));                  -- pattern
        poke(16#1B00# + s*4 + 3, conv_std_logic_vector(((s mod 15) + 1) + (s mod 2) * 128, 8)); -- color (EC on odd)
        if s < 12 then
          n := 16 + s * 14;
        else
          n := 216;                           -- ... and mode 2
        end if;
        -- mode 2 entries for the 128K (G4+: R5=0x3F,R11=0 -> 0x1E00) and G3 (0x1E00 too)
        poke(16#1E00# + s*4 + 0, conv_std_logic_vector(n mod 256, 8));
        poke(16#1E00# + s*4 + 1, conv_std_logic_vector((s * 41 + 20) mod 256, 8));
        poke(16#1E00# + s*4 + 2, conv_std_logic_vector(s * 4, 8));
        poke(16#1E00# + s*4 + 3, X"00");
      end loop;
      if USE_PSRAM = 1 then
        for i in 0 to 65535 loop
          psram_write(0, i, mem(i));
        end loop;
      end if;
      inited := true;
    end if;

    if rising_edge(clk21m) then
      -- delayed read data
      if cnt > 0 then
        cnt := cnt - 1;
      end if;
      if cnt = 0 then
        RamDbiM <= pend;
        cnt := -1;
      end if;
      -- one VDP access per dot, taken at the edge that ends dotState "00"
      if DHClk = '1' and DLClk = '1' and USE_PSRAM = 0 then
        a := conv_integer(RamAdr(15 downto 0));
        if RamWe_n = '0' then
          if RamAdr(16) = '0' then
            mem(a)(7 downto 0) := RamDbo;
          else
            mem(a)(15 downto 8) := RamDbo;
          end if;
        else
          if LAT = 0 then
            RamDbiM <= mem(a);
          else
            -- the bus keeps the previous word until this one "arrives"
            -- (a real controller holds its output register), so an early
            -- sample reads the previous access' data
            pend := mem(a);
            cnt := LAT;
          end if;
        end if;
      end if;
    end if;

    if dump_vram and not vram_dumped and rising_edge(clk21m) then
      file_open(vf, DUMPFILE & ".vram", write_mode);
      for i in 0 to 65535 loop
        if USE_PSRAM = 1 then
          write(l, hex(psram_read(0, i)));
        else
          write(l, hex(mem(i)));
        end if;
        writeline(vf, l);
      end loop;
      file_close(vf);
      vram_dumped <= true;
    end if;
  end process;

  ----------------------------------------------------------------
  -- CPU side: register setup, optional command / CPU VRAM tests
  ----------------------------------------------------------------
  process
    procedure io_wr(port_n : integer; v : integer) is
    begin
      wait until falling_edge(clk21m);
      adr <= conv_std_logic_vector(port_n, 16);
      dbo <= conv_std_logic_vector(v mod 256, 8);
      wrt <= '1';
      req <= '1';
      wait until falling_edge(clk21m);
      req <= '0';
      wrt <= '0';
      for i in 1 to 64 loop                   -- ~3us between I/O accesses
        wait until falling_edge(clk21m);
      end loop;
    end procedure;

    procedure io_rd(port_n : integer; v : out std_logic_vector(7 downto 0)) is
    begin
      wait until falling_edge(clk21m);
      adr <= conv_std_logic_vector(port_n, 16);
      wrt <= '0';
      req <= '1';
      wait until falling_edge(clk21m);
      req <= '0';
      v := dbi;
      for i in 1 to 64 loop
        wait until falling_edge(clk21m);
      end loop;
    end procedure;

    procedure wreg(r : integer; v : integer) is
    begin
      io_wr(16#99#, v);
      io_wr(16#99#, 16#80# + r);
    end procedure;

    procedure vaddr(a : integer; write : boolean) is
    begin
      wreg(14, (a / 16384) mod 8);
      io_wr(16#99#, a mod 256);
      if write then
        io_wr(16#99#, 16#40# + (a / 256) mod 64);
      else
        io_wr(16#99#, (a / 256) mod 64);
      end if;
    end procedure;

    variable r0, r1 : integer;
    variable v      : std_logic_vector(7 downto 0);
    variable st     : std_logic_vector(7 downto 0);
    variable errors : integer := 0;
    variable l      : line;
  begin
    reset <= '1';
    for i in 1 to 20 loop wait until falling_edge(clk21m); end loop;
    if USE_PSRAM = 1 then
      while psReady /= '1' loop wait until falling_edge(clk21m); end loop;
    end if;
    reset <= '0';
    for i in 1 to 20 loop wait until falling_edge(clk21m); end loop;

    case SCREEN is
      when 0  => r0 := 16#00#; r1 := 16#50#;   -- TEXT1
      when 80 => r0 := 16#04#; r1 := 16#50#;   -- TEXT2
      when 1  => r0 := 16#00#; r1 := 16#42#;   -- G1   (16x16 sprites)
      when 2  => r0 := 16#02#; r1 := 16#42#;   -- G2
      when 3  => r0 := 16#00#; r1 := 16#4B#;   -- MC   (16x16, magnified)
      when 4  => r0 := 16#04#; r1 := 16#42#;   -- G3
      when 5  => r0 := 16#06#; r1 := 16#42#;   -- G4
      when 6  => r0 := 16#08#; r1 := 16#42#;   -- G5
      when 7  => r0 := 16#0A#; r1 := 16#42#;   -- G6
      when 8  => r0 := 16#0E#; r1 := 16#42#;   -- G7
      when others => r0 := 16#06#; r1 := 16#42#;
    end case;

    -- palette: 16 distinct colours
    wreg(16, 0);
    for c in 0 to 15 loop
      io_wr(16#9A#, ((c mod 8) * 16) + ((c * 3) mod 8));   -- 0RRR0BBB
      io_wr(16#9A#, (c * 5) mod 8);                       -- 00000GGG
    end loop;

    wreg(0, r0);
    wreg(1, r1);
    -- table bases (any value is fine: VRAM is random, this only spreads accesses)
    if SCREEN = 2 or SCREEN = 4 then
      wreg(2, 16#06#);  -- name  0x1800
      wreg(3, 16#FF#);  -- color 0x2000 (masked)
      wreg(10, 16#00#);
      wreg(4, 16#03#);  -- pattern 0x0000 (masked)
    elsif SCREEN = 80 then
      wreg(2, 16#03#);  -- name 0x0000 (TEXT2 mask)
      wreg(3, 16#2F#);  -- blink table 0x0800
      wreg(10, 16#00#);
      wreg(4, 16#02#);  -- pattern 0x1000
    elsif SCREEN >= 5 and SCREEN <= 8 then
      wreg(2, 16#1F#);  -- page 0
    else
      wreg(2, 16#06#);  -- name 0x1800
      wreg(3, 16#80#);  -- color 0x2000
      wreg(10, 16#00#);
      wreg(4, 16#00#);  -- pattern 0x0000
    end if;
    if SCREEN = 1 or SCREEN = 2 or SCREEN = 3 then
      wreg(5, 16#36#);  -- sprite attr 0x1B00 (mode 1)
      wreg(11, 16#00#);
    else
      wreg(5, 16#3F#);  -- sprite attr 0x1E00 (mode 2), colours at 0x1C00
      wreg(11, 16#00#);
    end if;
    wreg(6, 16#07#);    -- sprite patterns 0x3800
    wreg(7, 16#F4#);    -- text colours / border
    wreg(8, 16#08#);    -- sprites on (SPD=0)
    wreg(9, 16#80#);    -- 212 lines, NTSC
    wreg(12, 16#1E#);   -- blink colours (TEXT2)
    wreg(13, 16#33#);   -- blink period

    if CMDTEST /= 0 then
      -- CPU VRAM write / read-back of 256 bytes at 0x10000-0x100FF (lane 1)
      vaddr(16#10000#, true);
      for i in 0 to 255 loop
        io_wr(16#98#, (i * 7 + 3) mod 256);
      end loop;
      vaddr(16#10000#, false);
      for i in 0 to 255 loop
        io_rd(16#98#, v);
        if conv_integer(v) /= (i * 7 + 3) mod 256 then
          errors := errors + 1;
        end if;
      end loop;
      write(l, string'("CPU VRAM read-back errors: ")); write(l, errors); writeline(output, l);

      -- LMMV: fill (10,20) 60x30 with colour 5, logical op XOR (only in G4..G7 coordinates)
      wreg(17, 36);                         -- indirect from R36
      io_wr(16#9B#, 10);  io_wr(16#9B#, 0);  -- DX
      io_wr(16#9B#, 20);  io_wr(16#9B#, 0);  -- DY
      io_wr(16#9B#, 0);   io_wr(16#9B#, 0);  -- SX (unused)
      io_wr(16#9B#, 0);   io_wr(16#9B#, 0);  -- SY (unused)
      wreg(40, 60); wreg(41, 0);            -- NX
      wreg(42, 30); wreg(43, 0);            -- NY
      wreg(44, 5);                          -- CLR
      wreg(45, 0);                          -- ARG
      wreg(46, 16#83#);                     -- LMMV, XOR
      -- wait CE
      wreg(15, 2);
      loop
        io_rd(16#99#, st);
        exit when st(0) = '0';
      end loop;
      -- HMMM: copy (0,0) 64x40 -> (100,60)
      wreg(32, 0); wreg(33, 0); wreg(34, 0); wreg(35, 0);
      wreg(36, 100); wreg(37, 0); wreg(38, 60); wreg(39, 0);
      wreg(40, 64); wreg(41, 0); wreg(42, 40); wreg(43, 0);
      wreg(45, 0);
      wreg(46, 16#D0#);                     -- HMMM
      loop
        io_rd(16#99#, st);
        exit when st(0) = '0';
      end loop;
      -- LMCM read-back through R7 would need the TR handshake; the CPU read test above covers reads.
      wreg(15, 0);
      write(l, string'("VDP commands done")); writeline(output, l);
    end if;

    setup_done <= true;
    wait;
  end process;

  ----------------------------------------------------------------
  -- VGA output dump of frame number FRAMES (counted from setup_done)
  ----------------------------------------------------------------
  process(clk21m)
    file     df      : text;
    variable l       : line;
    variable opened  : boolean := false;
    variable frame   : integer := 0;
    variable vs_d    : std_logic := '1';
    variable rgb     : std_logic_vector(23 downto 0);
  begin
    if rising_edge(clk21m) then
      if setup_done and vs_d = '1' and VideoVS_n = '0' then
        frame := frame + 1;
        if frame = FRAMES then
          file_open(df, DUMPFILE, write_mode);
          opened := true;
        elsif frame = FRAMES + 1 then
          file_close(df);
          if USE_PSRAM = 1 then
            write(l, string'("VRAM overrun: ")); write(l, bit_char(psOverrun)); writeline(output, l);
          end if;
          opened := false;
          if CMDTEST /= 0 then
            dump_vram <= true;
          else
            sim_done <= true;
          end if;
        end if;
      end if;
      if opened then
        rgb := "00" & VideoR & "00" & VideoG & "00" & VideoB;
        write(l, hex(rgb));
        write(l, ' ');
        write(l, bit_char(VideoHS_n));
        write(l, bit_char(VideoVS_n));
        writeline(df, l);
      end if;
      vs_d := VideoVS_n;
      if vram_dumped then
        sim_done <= true;
      end if;
    end if;
  end process;

end sim;
