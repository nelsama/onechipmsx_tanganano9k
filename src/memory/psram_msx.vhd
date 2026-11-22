--
-- psram_msx.vhd : One Chip MSX memory on the Tang Nano 9K embedded PSRAM.
--
-- Replaces the SD-RAM sequencer of the original emsx_top. Two independent
-- channels (psram_chan), one per die:
--
--   die 0 : VRAM (128 KB) of the VDP     - one access per dot
--   die 1 : CPU memory (mapper RAM, MegaRAM / MegaSD RAM, BIOS ROMs)
--
-- clk is memclk = RATIO x clk21m, from the same PLL (synchronous, rising
-- edges of clk21m coincide with rising edges of clk). All the clk21m-side
-- inputs are clk21m registers, all the outputs are clk registers that change
-- far from the clk21m edges that use them (see below).
--
-- VDP port (die 0)
--   The VDP drives one VRAM access per dot (4 clk21m): the arbiter registers
--   the address at the end of dotState "10" (edge E0) and VideoDHClk =
--   VideoDLClk = '1' during the following "00". The retimed VDP captures the
--   read data at the end of "01" of the NEXT dot (E0 + 6 clk21m), so
--     - an access must start every 4 clk21m = 4*RATIO clk cycles;
--     - its data must be in vdp_dbi before E0 + 6*RATIO clk cycles.
--   The access is started on the first clk edge that sees vdp_slot = '1'
--   (E0 + 1), registered, and accepted by the channel at E0 + 3. With the fixed (2x)
--   latency a read takes 8 + 2*LATENCY cycles (+1 back in IDLE), e.g.
--     RATIO 4, LATENCY 3 : 15 of 16 cycles per dot, data at E0+16 (< E0+24)
--     RATIO 5, LATENCY 5 : 19 of 20 cycles per dot, data at E0+20 (< E0+30)
--   The read word is handed to vdp_dbi at a fixed point, the clk edge that
--   coincides with E0 + 5 clk21m (the "00" -> "01" edge of the next dot),
--   whatever the PSRAM timing: the VDP was verified bit-exact with exactly
--   this delivery (sim/tb_vdp.vhd, LAT = 4), and some captures at "00" rely
--   on the previous word still being there one clk21m earlier.
--   vdp_dbi keeps the last read word until the next delivery.
--   If the channel is still busy when a dot starts, vdp_overrun is set
--   (sticky until reset): the VRAM would be corrupted / mis-read.
--
-- CPU port (die 1)
--   Same handshake as the original RamReq / RamAck: cpu_req is a level;
--   cpu_ack rises when the access is done (read data in cpu_dbi) and falls
--   after cpu_req is released. cpu_adr is a byte address (CpuAdr(21:0)).
--
-- ready = '1' once both dies are configured (~160 us after resetn). Keep the
-- MSX in reset until then.
--
library ieee;
use ieee.std_logic_1164.all;

entity psram_msx is
  generic (
    FREQ    : integer := 85909090;
    LATENCY : integer := 3;
    RATIO   : integer := 4      -- memclk / clk21m
  );
  port (
    clk         : in    std_logic;    -- memclk (RATIO x clk21m)
    clk_p       : in    std_logic;    -- memclk shifted 90 degrees
    resetn      : in    std_logic;
    ready       : out   std_logic;

    -- VDP (die 0)
    vdp_slot    : in    std_logic;    -- VideoDHClk and VideoDLClk
    vdp_adr     : in    std_logic_vector(16 downto 0);  -- bit 16 = byte lane
    vdp_we_n    : in    std_logic;
    vdp_dbo     : in    std_logic_vector(7 downto 0);
    vdp_dbi     : out   std_logic_vector(15 downto 0);
    vdp_overrun : out   std_logic;

    -- CPU (die 1)
    cpu_req     : in    std_logic;
    cpu_wr      : in    std_logic;
    cpu_adr     : in    std_logic_vector(21 downto 0);
    cpu_dbo     : in    std_logic_vector(7 downto 0);
    cpu_dbi     : out   std_logic_vector(7 downto 0);
    cpu_ack     : out   std_logic;

    -- PSRAM pins
    O_psram_ck      : out   std_logic_vector(1 downto 0);
    O_psram_ck_n    : out   std_logic_vector(1 downto 0);
    IO_psram_rwds   : inout std_logic_vector(1 downto 0);
    IO_psram_dq     : inout std_logic_vector(15 downto 0);
    O_psram_reset_n : out   std_logic_vector(1 downto 0);
    O_psram_cs_n    : out   std_logic_vector(1 downto 0)
  );
end entity;

architecture rtl of psram_msx is

  signal busy0, busy1   : std_logic;
  signal rd0, wr0       : std_logic := '0';
  signal rd1, wr1       : std_logic := '0';
  signal adr0, adr1     : std_logic_vector(21 downto 0) := (others => '0');
  signal din0, din1     : std_logic_vector(15 downto 0) := (others => '0');
  signal dout0, dout1   : std_logic_vector(15 downto 0);

  signal slot_d         : std_logic := '0';
  signal start0         : std_logic := '0';
  signal vdp_adr_r      : std_logic_vector(16 downto 0) := (others => '0');
  signal vdp_dbo_r      : std_logic_vector(7 downto 0) := (others => '0');
  signal vdp_we_r       : std_logic := '1';
  signal ph             : integer range 0 to 8 * RATIO := 0;
  signal dbi0           : std_logic_vector(15 downto 0) := (others => '0');
  signal overrun        : std_logic := '0';
  signal ready_i        : std_logic := '0';

  type cpu_st_t is (C_IDLE, C_ISSUE, C_BUSY, C_DONE);
  signal cpu_st         : cpu_st_t := C_IDLE;
  signal cpu_rd         : std_logic := '0';
  signal cpu_req_r, cpu_wr_r : std_logic := '0';
  signal cpu_adr_r      : std_logic_vector(21 downto 0) := (others => '0');
  signal cpu_dbo_r      : std_logic_vector(7 downto 0) := (others => '0');
  signal ack_i          : std_logic := '0';
  signal dbi_i          : std_logic_vector(7 downto 0) := (others => '1');

begin

  O_psram_ck_n    <= (others => '0');   -- single-ended clock (as zf3)
  O_psram_reset_n <= (others => resetn);

  ready       <= ready_i;
  vdp_dbi     <= dbi0;
  vdp_overrun <= overrun;
  cpu_dbi     <= dbi_i;
  cpu_ack     <= ack_i;

  ----------------------------------------------------------------
  -- VDP port
  ----------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      rd0 <= '0';
      wr0 <= '0';
      slot_d <= vdp_slot;
      -- ph = 0 on the first clk edge after E0 (slot seen), so ph = RATIO - 1
      -- is the edge E1 of this dot = E0 + 5 clk21m of the previous access
      if ph /= 8 * RATIO then
        ph <= ph + 1;
      end if;
      if ph = RATIO - 1 then
        dbi0 <= dout0;
      end if;
      if vdp_slot = '1' and slot_d = '0' then
        ph <= 1;
      end if;
      -- two stages (timing: the decision fans out to the address / data
      -- registers): the VDP inputs and the start are registered first, the
      -- access is issued one clk later (accepted at E0 + 3, done at E0 + 17,
      -- delivered at E0 + 20 for RATIO 4)
      vdp_adr_r <= vdp_adr;
      vdp_dbo_r <= vdp_dbo;
      vdp_we_r  <= vdp_we_n;
      start0 <= '0';
      if vdp_slot = '1' and slot_d = '0' and ready_i = '1' then
        start0 <= '1';
      end if;
      if start0 = '1' then
        if busy0 = '1' then
          overrun <= '1';
        end if;
        adr0 <= "00000" & vdp_adr_r(15 downto 0) & vdp_adr_r(16);
        din0 <= vdp_dbo_r & vdp_dbo_r;
        if vdp_we_r = '0' then
          wr0 <= '1';
        else
          rd0 <= '1';
        end if;
      end if;
      if busy0 = '0' and busy1 = '0' then
        ready_i <= '1';
      end if;
      if resetn = '0' then
        overrun <= '0';
        ready_i <= '0';
      end if;
    end if;
  end process;

  -- synthesis translate_off
  process(clk)
  begin
    if rising_edge(clk) then
      assert not (rd0 = '1' or wr0 = '1') or busy0 = '0'
        report "psram_msx: VRAM access overrun (channel still busy at the next dot)"
        severity error;
    end if;
  end process;
  -- synthesis translate_on

  ----------------------------------------------------------------
  -- CPU port
  ----------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      rd1 <= '0';
      wr1 <= '0';
      -- the clk21m inputs are registered first (timing)
      cpu_req_r <= cpu_req;
      cpu_wr_r  <= cpu_wr;
      cpu_adr_r <= cpu_adr;
      cpu_dbo_r <= cpu_dbo;
      case cpu_st is
        when C_IDLE =>
          if cpu_req_r = '1' and ack_i = '0' and ready_i = '1' and busy1 = '0' then
            adr1 <= cpu_adr_r;
            din1 <= cpu_dbo_r & cpu_dbo_r;
            cpu_rd <= not cpu_wr_r;
            if cpu_wr_r = '1' then
              wr1 <= '1';
            else
              rd1 <= '1';
            end if;
            cpu_st <= C_ISSUE;
          end if;
        when C_ISSUE =>               -- channel accepted at this edge
          cpu_st <= C_BUSY;
        when C_BUSY =>
          if busy1 = '0' then
            cpu_st <= C_DONE;
          end if;
        when C_DONE =>
          if cpu_rd = '1' then
            if adr1(0) = '0' then
              dbi_i <= dout1(7 downto 0);
            else
              dbi_i <= dout1(15 downto 8);
            end if;
          end if;
          ack_i <= '1';
          cpu_st <= C_IDLE;
      end case;
      if cpu_req = '0' then
        ack_i <= '0';
      end if;
      if resetn = '0' then
        cpu_st <= C_IDLE;
        ack_i <= '0';
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- channels
  ----------------------------------------------------------------
  u_die0 : entity work.psram_chan
    generic map (FREQ => FREQ, LATENCY => LATENCY, FIXED => true, DIE => 0)
    port map (
      clk => clk, clk_p => clk_p, resetn => resetn,
      read => rd0, write => wr0, addr => adr0, din => din0, byte_write => '1',
      dout => dout0, busy => busy0,
      psram_ck => O_psram_ck(0), psram_cs_n => O_psram_cs_n(0),
      psram_rwds => IO_psram_rwds(0), psram_dq => IO_psram_dq(7 downto 0));

  u_die1 : entity work.psram_chan
    generic map (FREQ => FREQ, LATENCY => LATENCY, FIXED => true, DIE => 1)
    port map (
      clk => clk, clk_p => clk_p, resetn => resetn,
      read => rd1, write => wr1, addr => adr1, din => din1, byte_write => '1',
      dout => dout1, busy => busy1,
      psram_ck => O_psram_ck(1), psram_cs_n => O_psram_cs_n(1),
      psram_rwds => IO_psram_rwds(1), psram_dq => IO_psram_dq(15 downto 8));

end architecture;
