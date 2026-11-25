--
-- vdp2hdmi.vhd : VDP VGA output (31 kHz) -> 720x480p raster for HDMI.
--
-- The VDP "vga" upscan output (src/video/vga.vhd) has 684 clk21m per line
-- and 524 lines per frame (NTSC, non interlaced). The board runs clk21m at
-- 21.6 MHz = 27 MHz * 4/5, so one VDP line lasts exactly 855 pixels of
-- 27 MHz: the HDMI raster is a 720x480p one with a total of 855 x 524
-- (CEA-861 480p is 858 x 525; 60.27 Hz instead of 59.94 Hz) that stays
-- locked to the VDP with no frame buffer, only a 2-line buffer.
--
-- Write side (clk21m): pixels 121 .. 682 after the falling edge of HS
--   (562 = border 30 + 512 + border 20) of each line go to line slot
--   (line mod 2). Lines are counted from the falling edge of VS (line 0).
-- Read side (clk_pix): HDMI active line y (0..479) shows VDP line y + 39
--   (the border spans VDP lines 37..520, the picture 67..490), read during
--   VDP line y + 40, i.e. one line late. Horizontally the 562 VDP pixels are
--   scaled by 5/4 to 702 HDMI pixels, starting at x = 9 (VDP pixel
--   p = floor((x - 9) * 4 / 5)).
-- Lock: at each VS falling edge of the VDP (synchronised) the HDMI raster
--   must be at line VLOCK, pixel HLOCK; if it is more than 2 pixels away the
--   counters are reloaded (first frame, mode changes). Otherwise nothing is
--   touched, so the HDMI timing is exactly periodic.
-- PAL (626 lines) and interlace are not handled: the raster then reloads
--   every frame (the picture still shows, the TV may not like it).
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vdp2hdmi is
  port (
    -- VDP side
    clk21m   : in  std_logic;
    vdp_r    : in  std_logic_vector(5 downto 0);
    vdp_g    : in  std_logic_vector(5 downto 0);
    vdp_b    : in  std_logic_vector(5 downto 0);
    vdp_hs_n : in  std_logic;
    vdp_vs_n : in  std_logic;
    -- HDMI side (27 MHz, the PCLK of the TMDS serialisers)
    clk_pix  : in  std_logic;
    rst_pix  : in  std_logic;
    hdmi_r   : out std_logic_vector(7 downto 0);
    hdmi_g   : out std_logic_vector(7 downto 0);
    hdmi_b   : out std_logic_vector(7 downto 0);
    hdmi_hs  : out std_logic;     -- sync levels for the TMDS control symbols
    hdmi_vs  : out std_logic;     -- (480p: negative polarity, '0' = pulse)
    hdmi_de  : out std_logic;
    -- raster position, 2 clocks ahead of the outputs above (for hdmi_tx)
    h_cnt    : out unsigned(9 downto 0);
    v_cnt    : out unsigned(9 downto 0);
    locked   : out std_logic      -- '1' when the last VS needed no reload
  );
end entity;

architecture rtl of vdp2hdmi is

  -- VDP line layout
  constant VDP_X0    : integer := 121;   -- first pixel after HS falling edge
  constant VDP_W     : integer := 562;
  constant VDP_LINE0 : integer := 39;    -- VDP line shown on HDMI line 0

  -- HDMI raster (720x480p, 855 x 524)
  constant H_ACT   : integer := 720;
  constant H_SYNC0 : integer := 736;     -- front porch 16
  constant H_SYNC1 : integer := 798;     -- sync 62, back porch 57
  constant H_TOT   : integer := 855;
  constant V_ACT   : integer := 480;
  constant V_SYNC0 : integer := 489;     -- front porch 9
  constant V_SYNC1 : integer := 495;     -- sync 6, back porch 29
  constant V_TOT   : integer := 524;
  constant X_OFF   : integer := 9;       -- (720 - 702) / 2

  -- HDMI position at the (synchronised) VDP VS falling edge: VDP line 0
  -- begins, HDMI is one line behind VDP line - VDP_LINE0
  constant VLOCK : integer := V_TOT - VDP_LINE0 - 1;    -- 484
  constant HLOCK : integer := 4;                        -- sync latency

  -- 2 lines x 1024 x 18 bit line buffer (dual clock BSRAM)
  type buf_t is array (0 to 2047) of std_logic_vector(17 downto 0);
  signal buf : buf_t;

  -- write side
  signal hs_d, vs_d : std_logic := '1';
  signal hc         : integer range 0 to 1023 := 0;
  signal wl         : integer range 0 to 1023 := 0;
  signal vs_t       : std_logic := '0';

  -- read side
  signal vs_s       : std_logic_vector(2 downto 0) := (others => '0');
  signal hcnt       : integer range 0 to H_TOT - 1 := 0;
  signal vcnt       : integer range 0 to V_TOT - 1 := 0;
  signal ph5        : integer range 0 to 4 := 0;
  signal px         : integer range 0 to 1023 := 0;   -- VDP pixel
  signal rd_adr     : integer range 0 to 2047 := 0;
  signal q          : std_logic_vector(17 downto 0);
  signal vis1, de1, hs1, vs1 : std_logic := '0';
  signal vis2, de2, hs2, vs2 : std_logic := '0';
  signal lock_i     : std_logic := '0';

  function x8(c : std_logic_vector(5 downto 0)) return std_logic_vector is
  begin
    return c & c(5 downto 4);
  end function;

begin

  ----------------------------------------------------------------
  -- write side
  ----------------------------------------------------------------
  process(clk21m)
    variable line : integer range 0 to 1023;
  begin
    if rising_edge(clk21m) then
      hs_d <= vdp_hs_n;
      vs_d <= vdp_vs_n;
      line := wl;
      if hs_d = '1' and vdp_hs_n = '0' then
        hc <= 1;
        if vs_d = '1' and vdp_vs_n = '0' then
          line := 0;
          vs_t <= not vs_t;
        elsif wl /= 1023 then
          line := wl + 1;
        end if;
        wl <= line;
        -- sample index 0 of the line: not written
      else
        if hc /= 1023 then
          hc <= hc + 1;
        end if;
        if hc >= VDP_X0 and hc < VDP_X0 + VDP_W then
          buf((line mod 2) * 1024 + (hc - VDP_X0)) <= vdp_r & vdp_g & vdp_b;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- read side
  --   stage 0: hcnt / vcnt / px (the pixel being generated)
  --   stage 1: rd_adr, vis1, de1, hs1, vs1
  --   stage 2: q (buffer data), vis2, de2, hs2, vs2
  --   output : hdmi_*
  ----------------------------------------------------------------
  process(clk_pix)
    variable hn     : integer range 0 to H_TOT - 1;
    variable vl     : integer range 0 to 1023;
  begin
    if rising_edge(clk_pix) then
      vs_s <= vs_s(1 downto 0) & vs_t;

      -- raster counters
      if hcnt = H_TOT - 1 then
        hn := 0;
        if vcnt = V_TOT - 1 then vcnt <= 0; else vcnt <= vcnt + 1; end if;
      else
        hn := hcnt + 1;
      end if;
      hcnt <= hn;

      -- horizontal scaler: px = floor((hcnt - X_OFF) * 4 / 5),
      -- ph5 = (hcnt - X_OFF) mod 5
      if hn <= X_OFF then
        px <= 0;
        ph5 <= 0;
      else
        if ph5 /= 0 then px <= px + 1; end if;
        if ph5 = 4 then ph5 <= 0; else ph5 <= ph5 + 1; end if;
      end if;

      -- lock to the VDP
      if vs_s(2) /= vs_s(1) then
        if vcnt = VLOCK and hcnt >= HLOCK - 2 and hcnt <= HLOCK + 2 then
          lock_i <= '1';
        else
          vcnt <= VLOCK;
          hcnt <= HLOCK + 1;
          px <= 0;
          ph5 <= 0;
          lock_i <= '0';
        end if;
      end if;

      -- stage 1
      vl := (vcnt + VDP_LINE0) mod 1024;
      rd_adr <= (vl mod 2) * 1024 + px;
      vis1 <= '0';
      if hcnt >= X_OFF and hcnt < X_OFF + 703 and vcnt < V_ACT then
        vis1 <= '1';
      end if;
      de1 <= '0';
      if hcnt < H_ACT and vcnt < V_ACT then de1 <= '1'; end if;
      hs1 <= '1';
      if hcnt >= H_SYNC0 and hcnt < H_SYNC1 then hs1 <= '0'; end if;
      vs1 <= '1';
      if (vcnt = V_SYNC0 and hcnt >= H_SYNC0) or
         (vcnt > V_SYNC0 and vcnt < V_SYNC1) or
         (vcnt = V_SYNC1 and hcnt < H_SYNC0) then
        vs1 <= '0';
      end if;

      -- stage 2
      q <= buf(rd_adr);
      vis2 <= vis1; de2 <= de1; hs2 <= hs1; vs2 <= vs1;

      -- output (3 clocks after hcnt / vcnt)
      h_cnt <= to_unsigned(hcnt, 10);
      v_cnt <= to_unsigned(vcnt, 10);
      hdmi_de <= de2;
      hdmi_hs <= hs2;
      hdmi_vs <= vs2;
      if vis2 = '1' then
        hdmi_r <= x8(q(17 downto 12));
        hdmi_g <= x8(q(11 downto 6));
        hdmi_b <= x8(q(5 downto 0));
      else
        hdmi_r <= (others => '0');
        hdmi_g <= (others => '0');
        hdmi_b <= (others => '0');
      end if;

      if rst_pix = '1' then
        lock_i <= '0';
      end if;
    end if;
  end process;

  locked <= lock_i;

end architecture;
