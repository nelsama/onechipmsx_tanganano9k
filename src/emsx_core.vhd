-- 
-- emsx_top.vhd
--   ESE MSX-SYSTEM3 / MSX clone on a Cyclone FPGA (ALTERA)
--   Revision 1.00
-- 
-- Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
-- All rights reserved.
-- 
-- Redistribution and use of this source code or any derivative works, are 
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, 
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright 
--    notice, this list of conditions and the following disclaimer in the 
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial 
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED 
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-- 

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.vdp_package.all;

entity emsx_core is
  generic(
    -- TN9K: optional blocks (to fit the GW1NR-9). Disabled blocks answer
    -- their I/O ports with FFh and acknowledge immediately.
    ENABLE_OPLL  : boolean := true;   -- MSX-MUSIC (YM2413)
    ENABLE_SCC   : boolean := true;   -- ESE-SCC / MegaRAM in slot 2
    ENABLE_RTC   : boolean := true;   -- RP5C01 clock
    ENABLE_KANJI : boolean := false;  -- Kanji ROM I/O (D8-DBh); TN9K: off (font not in the image)
    -- Former DIP switches (1 = ON)
    CFG_MEGTYPE  : std_logic_vector(1 downto 0) := "10";  -- slot2: "00"=none, "10"=SCC+, "01"=ASC8K, "11"=ASC16K (megaram decodes bit0=0 as SCC)
    CFG_MMC      : std_logic := '1';  -- SD card drive enabled
    CFG_KMAP_US  : std_logic := '1'   -- PS/2 layout: '0'=Japanese-106, '1'=English-101
  );
  port(
    -- Clocks / reset (from board top)
    clk21m      : in std_logic;                         -- 21.48MHz (VDP / system)
    reset_n     : in std_logic;                         -- synchronous to clk21m, active low

    -- Memory (TN9K: PSRAM through src/memory/psram_msx.vhd)
    --   VRAM, one access per dot (die 0)
    pVramSlot   : out std_logic;                        -- VideoDHClk and VideoDLClk
    pVramAdr    : out std_logic_vector(16 downto 0);    -- bit 16 = byte lane
    pVramWe_n   : out std_logic;
    pVramDbo    : out std_logic_vector(7 downto 0);
    pVramDbi    : in  std_logic_vector(15 downto 0);
    --   CPU memory, request / acknowledge (die 1)
    pRamReq     : out std_logic;
    pRamWr      : out std_logic;
    pRamAdr     : out std_logic_vector(21 downto 0);    -- byte address
    pRamDbo     : out std_logic_vector(7 downto 0);
    pRamDbi     : in  std_logic_vector(7 downto 0);
    pRamAck     : in  std_logic;

    -- PS/2 keyboard ports
    pPs2Clk     : inout std_logic;
    pPs2Dat     : inout std_logic;

    -- Joystick ports (Port_A, Port_B), inputs only ('1' = released)
    pJoyA       : in  std_logic_vector( 5 downto 0);
    pStrA       : out std_logic;
    pJoyB       : in  std_logic_vector( 5 downto 0);
    pStrB       : out std_logic;
    -- TN9K: extra button pressed = SPACE key ('0' = pressed)
    pKeySpace_n : in  std_logic;
    -- TN9K: injected key (UART keyboard): matrix row / column, + SHIFT, CTRL
    pKeyInj     : in  std_logic;                        -- '1' = pressed
    pKeyInjRow  : in  std_logic_vector(3 downto 0);
    pKeyInjCol  : in  std_logic_vector(2 downto 0);
    pKeyInjShift: in  std_logic;
    pKeyInjCtrl : in  std_logic;

    -- SD card (SPI mode)
    pSd_Ck      : out std_logic;                        -- CLK
    pSd_Cm      : out std_logic;                        -- CMD / MOSI
    pSd_Cs      : out std_logic;                        -- DAT3 / CS
    pSd_Do      : in  std_logic;                        -- DAT0 / MISO

    -- BIOS flash (SPI, former EPCS)
    pEpc_Ck     : out std_logic;
    pEpc_Cs     : out std_logic;
    pEpc_Di     : out std_logic;                        -- FPGA -> flash
    pEpc_Do     : in  std_logic;                        -- flash -> FPGA

    -- Lamp
    pLedSd      : out std_logic;                        -- 1 = SD card access

    -- Video (VGA 31kHz timing, 6 bits per channel)
    pVideoR     : out std_logic_vector( 5 downto 0);
    pVideoG     : out std_logic_vector( 5 downto 0);
    pVideoB     : out std_logic_vector( 5 downto 0);
    pVideoHS_n  : out std_logic;
    pVideoVS_n  : out std_logic;

    -- Audio (1-bit PWM, needs an RC low-pass filter)
    pAudio      : out std_logic;

    -- TN9K debug: address of the last opcode fetch (M1) & primary slot
    -- register (port A8h) & count of CPU writes to the VDP ports 98-9Bh
    pDbg        : out std_logic_vector(31 downto 0);
    -- TN9K simulation probe of the internal CPU bus (unconnected on the board):
    -- adr(15:0) & dbo(7:0) & mem & wrt & req & PriSltNum(1:0) & ExpSltNum0(1:0)
    -- & ExpSltNum3(1:0)
    pDbgBus     : out std_logic_vector(32 downto 0)
  );
end emsx_core;

architecture rtl of emsx_core is

  component t80a
    port(
      RESET_n : in std_logic;
      CLK_n   : in std_logic;
      WAIT_n  : in std_logic;
      INT_n   : in std_logic;
      NMI_n   : in std_logic;
      BUSRQ_n : in std_logic;
      M1_n    : out std_logic;
      MREQ_n  : out std_logic;
      IORQ_n  : out std_logic;
      RD_n    : out std_logic;
      WR_n    : out std_logic;
      RFSH_n  : out std_logic;
      HALT_n  : out std_logic;
      BUSAK_n : out std_logic;
      A       : out std_logic_vector(15 downto 0);
      DI      : in  std_logic_vector(7 downto 0);
      DO      : out std_logic_vector(7 downto 0);
      DOE     : out std_logic
    );
  end component;

  component iplrom
    port(
      clk     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0)
    );
  end component;

  component megasd
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      clkena  : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0);
      dbo     : in std_logic_vector(7 downto 0);

      ramreq  : out std_logic;
      ramwrt  : out std_logic;
      ramadr  : out std_logic_vector(19 downto 0);
      ramdbi  : in std_logic_vector(7 downto 0);
      ramdbo  : out std_logic_vector(7 downto 0);

      mmcdbi  : out std_logic_vector(7 downto 0);
      mmcena  : out std_logic;
      mmcact  : out std_logic;

      mmc_ck  : out std_logic;
      mmc_cs  : out std_logic;
      mmc_di  : out std_logic;
      mmc_do  : in std_logic;

      epc_ck  : out std_logic;
      epc_cs  : out std_logic;
      epc_oe  : out std_logic;
      epc_di  : out std_logic;
      epc_do  : in std_logic
    );
  end component;

  component mapper
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      clkena  : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      mem     : in std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0);
      dbo     : in std_logic_vector(7 downto 0);

      ramreq  : out std_logic;
      ramwrt  : out std_logic;
      ramadr  : out std_logic_vector(21 downto 0);
      ramdbi  : in std_logic_vector(7 downto 0);
      ramdbo  : out std_logic_vector(7 downto 0)
    );
  end component;

  component eseps2 is
  port (
    clk21m : in std_logic;
    reset  : in std_logic;
    clkena : in std_logic;

    Kmap   : in std_logic;
    
    Caps    : inout std_logic;
    Kana    : inout std_logic;
    Paus    : inout std_logic;
    Scro    : inout std_logic;
    Reso    : inout std_logic;
    
    FKeys   : out std_logic_vector(7 downto 0);

    pPs2Clk  : inout std_logic;
    pPs2Dat  : inout std_logic;
    PpiPortC : in  std_logic_vector(7 downto 0);
    pKeyX    : out std_logic_vector(7 downto 0)
  );
  end component;

  component rtc
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      clkena  : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0);
      dbo     : in std_logic_vector(7 downto 0)
    );
  end component;

  component kanji is
  port (
    clk21m  : in std_logic;
    reset   : in std_logic;
    clkena  : in std_logic;
    req     : in std_logic;
    ack     : out std_logic;
    wrt     : in std_logic;
    adr     : in std_logic_vector(15 downto 0);
    dbi     : out std_logic_vector(7 downto 0);
    dbo     : in std_logic_vector(7 downto 0);

    ramreq  : out std_logic;
    ramadr  : out std_logic_vector(17 downto 0);
    ramdbi  : in std_logic_vector(7 downto 0);
    ramdbo  : out std_logic_vector(7 downto 0)
  );
  end component;

  component vdp
  port(
    -- VDP clock ... 21.477MHz
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

    -- Video Output
    pVideoR : out std_logic_vector( 5 downto 0);
    pVideoG : out std_logic_vector( 5 downto 0);
    pVideoB : out std_logic_vector( 5 downto 0);

    pVideoHS_n : out std_logic;
    pVideoVS_n : out std_logic;

    pVideoDHClk : out std_logic;
    pVideoDLClk : out std_logic
  );
  end component;

  component psg
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      clkena  : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0);
      dbo     : in std_logic_vector(7 downto 0);

      joya    : in  std_logic_vector(5 downto 0);
      stra    : out std_logic;
      joyb    : in  std_logic_vector(5 downto 0);
      strb    : out std_logic;

      kana    : out std_logic;
      cmtin   : in std_logic;
      keymode : in std_logic;

      wave    : out std_logic_vector(7 downto 0)
    );
  end component;

  component megaram
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      clkena  : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbi     : out std_logic_vector(7 downto 0);
      dbo     : in std_logic_vector(7 downto 0);

      ramreq  : out std_logic;
      ramwrt  : out std_logic;
      ramadr  : out std_logic_vector(19 downto 0);
      ramdbi  : in std_logic_vector(7 downto 0);
      ramdbo  : out std_logic_vector(7 downto 0);

      mapsel  : in std_logic_vector(1 downto 0);  -- "0-":SCC+, "10":ASC8K, "11":ASC16K

      wavl    : out std_logic_vector(7 downto 0);
      wavr    : out std_logic_vector(7 downto 0)
    );
  end component;

  component eseopll
    port(
      clk21m  : in std_logic;
      reset   : in std_logic;
      clkena  : in std_logic;
      enawait : in std_logic;
      req     : in std_logic;
      ack     : out std_logic;
      wrt     : in std_logic;
      adr     : in std_logic_vector(15 downto 0);
      dbo     : in std_logic_vector(7 downto 0);
      wav     : out std_logic_vector(9 downto 0)
      );
  end component;

  component esepwm
    generic (
      MSBI : integer
    );
    port(
      clk     : in std_logic;
      reset   : in std_logic;
      DACin   : in std_logic_vector(MSBI downto 0);
      DACout  : out std_logic
    );
  end component;

  -- Operation mode
  -- TN9K: always master mode (internal CPU); former DIP switches are generics.
  constant SelfMode  : std_logic := '1';        -- Operation mode        : 0=slave, 1=master
  signal KeyMode     : std_logic;               -- Kana key board layout : 1=JIS layout
  function megsel(en : boolean; t : std_logic_vector(1 downto 0)) return std_logic_vector is
  begin
    if en then return t; else return "00"; end if;
  end function;
  constant iDipLed   : std_logic_vector(7 downto 0) :=
                         megsel(ENABLE_SCC, CFG_MEGTYPE) & '0' & CFG_MMC & CFG_KMAP_US & "000";
  alias  MegType     : std_logic_vector(1 downto 0) is iDipLed(7 downto 6);
  alias  RedMode     : std_logic is iDipLed(5); -- '0': CPU_3.58MHz,    '1': CPU_10.74MHz
  alias  MmcMode     : std_logic is iDipLed(4); -- '0': disable SD/MMC, '1': enable SD/MMC
  alias  Kmap        : std_logic is iDipLed(3); -- '0': Japanese-106,   '1': English-101
  alias  RchMode     : std_logic is iDipLed(2); -- '0': RCA(red)=CMT,   '1': RCA(red)=Rch_sound

  -- Clock, Reset control signals
  signal cpuclk      : std_logic;
  signal clkena      : std_logic;
  constant clksel    : std_logic_vector(1 downto 0) := "00";  -- TN9K: 3.58MHz only (no turbo)
  signal reset       : std_logic;

  -- MSX cartridge slot control signals
  signal BusDir      : std_logic;
  signal iSltSltsl_n : std_logic;
  signal iSltRfsh_n  : std_logic;
  signal iSltMerq_n  : std_logic;
  signal iSltIorq_n  : std_logic;
  signal iSltRd_n    : std_logic;
  signal iSltWr_n    : std_logic;
  signal xSltRd_n    : std_logic;
  signal xSltWr_n    : std_logic;
  signal iSltAdr     : std_logic_vector(15 downto 0);
  signal iSltDat     : std_logic_vector(7 downto 0);
  signal dlydbi      : std_logic_vector(7 downto 0);
  signal BusReq_n    : std_logic;
  signal CpuM1_n     : std_logic;
  signal CpuRfsh_n   : std_logic;

  -- TN9K: internal CPU bus (was the external cartridge slot bus pSlt*)
  signal BusMerq_n   : std_logic;
  signal BusIorq_n   : std_logic;
  signal BusRd_n     : std_logic;
  signal BusWr_n     : std_logic;
  signal BusWait_n   : std_logic;
  signal BusAdr      : std_logic_vector(15 downto 0);
  signal BusDat      : std_logic_vector(7 downto 0);   -- resolved data bus
  signal CpuDo       : std_logic_vector(7 downto 0);
  signal CpuDoe      : std_logic;

  -- Internal bus signals (common)
  signal req, ireq   : std_logic;
  signal ack, iack   : std_logic;
  signal mem         : std_logic;
  signal wrt         : std_logic;
  signal adr         : std_logic_vector(15 downto 0);
  signal dbi         : std_logic_vector(7 downto 0);
  signal dbo         : std_logic_vector(7 downto 0);

  -- Primary, Expansion slot signals
  signal ExpDbi      : std_logic_vector(7 downto 0);
  signal ExpSlot0    : std_logic_vector(7 downto 0);
  signal ExpSlot3    : std_logic_vector(7 downto 0);
  signal ExpSlotX    : std_logic_vector(7 downto 0);
  signal PriSltNum   : std_logic_vector(1 downto 0);
  signal ExpSltNum0  : std_logic_vector(1 downto 0);
  signal ExpSltNum3  : std_logic_vector(1 downto 0);
  signal ExpSltNumX  : std_logic_vector(1 downto 0);

  -- Slot decode signals
  signal iSltBot     : std_logic;
  signal iSltMap     : std_logic;
  signal jSltMem     : std_logic;
  signal iSltScc     : std_logic;
  signal jSltScc     : std_logic;
  signal iSltErm     : std_logic;

  -- BIOS-ROM decode signals
  signal RomReq      : std_logic;
  signal rom_main    : std_logic;
  signal rom_opll    : std_logic;
  signal rom_extr    : std_logic;
  signal rom_kbas    : std_logic;
  signal rom_kanj    : std_logic;

  -- IPL-ROM signals
  signal RomDbi      : std_logic_vector(7 downto 0);

  -- ESE-RAM signals
  signal ErmReq      : std_logic;
  signal ErmAck      : std_logic;
  signal ErmDbi      : std_logic_vector(7 downto 0);
  signal ErmRam      : std_logic;
  signal ErmWrt      : std_logic;
  signal ErmDbo      : std_logic_vector(7 downto 0);
  signal ErmAdr      : std_logic_vector(19 downto 0);

  -- SD/MMC signals
  signal MmcEna      : std_logic;
  signal MmcAct      : std_logic;
  signal MmcDbi      : std_logic_vector(7 downto 0);

  -- EPCS/ASMI signals
  signal EPC_CK      : std_logic;
  signal EPC_CS      : std_logic;
  signal EPC_OE      : std_logic;
  signal EPC_DI      : std_logic;
  signal EPC_DO      : std_logic;

  -- Mapper RAM signals
  signal MapReq      : std_logic;
  signal MapAck      : std_logic;
  signal MapDbi      : std_logic_vector(7 downto 0);
  signal MapRam      : std_logic;
  signal MapWrt      : std_logic;
  signal MapDbo      : std_logic_vector(7 downto 0);
  signal MapAdr      : std_logic_vector(21 downto 0);

  -- PPI(8255) signals
  signal PpiReq      : std_logic;
  signal PpiAck      : std_logic;
  signal PpiDbi      : std_logic_vector(7 downto 0);
  signal PpiPortA    : std_logic_vector(7 downto 0);
  signal PpiPortB    : std_logic_vector(7 downto 0);
  signal KbdKeyX     : std_logic_vector(7 downto 0);
  signal PpiPortC    : std_logic_vector(7 downto 0);

  -- PS/2 signals
  signal Paus        : std_logic;
  signal Reso        : std_logic;
  signal Kana        : std_logic;
  signal Caps        : std_logic;
  signal Fkeys       : std_logic_vector(7 downto 0);

  -- CMT signals
  signal CmtIn       : std_logic;
  alias  CmtOut      : std_logic is PpiPortC(5);

  -- 1 bit sound port signal
  alias  KeyClick    : std_logic is PpiPortC(7);

  -- RTC signals
  signal RtcReq      : std_logic;
  signal RtcAck      : std_logic;
  signal RtcDbi      : std_logic_vector(7 downto 0);

  -- Kanji ROM signals
  signal KanReq      : std_logic;
  signal KanAck      : std_logic;
  signal KanDbi      : std_logic_vector(7 downto 0);
  signal KanRom      : std_logic;
  signal KanDbo      : std_logic_vector(7 downto 0);
  signal KanAdr      : std_logic_vector(17 downto 0);

  -- VDP signals
  signal VdpReq      : std_logic;
  signal VdpAck      : std_logic;
  signal VdpDbi      : std_logic_vector(7 downto 0);
  signal VideoSC     : std_logic;
  signal VideoDLClk  : std_logic;
  signal VideoDHClk  : std_logic;
  signal OeVdp_n     : std_logic;
  signal WeVdp_n     : std_logic;
  signal VdpAdr      : std_logic_vector(16 downto 0);
  signal VrmDbo      : std_logic_vector(7 downto 0);
  signal VrmDbi      : std_logic_vector(15 downto 0);
  signal pVdpInt_n   : std_logic;

  -- Video signals
  signal VideoR      : std_logic_vector( 5 downto 0);   -- RGB_Red
  signal VideoG      : std_logic_vector( 5 downto 0);   -- RGB_Green
  signal VideoB      : std_logic_vector( 5 downto 0);   -- RGB_Blue
  signal VideoHS_n   : std_logic;                       -- Holizontal Sync
  signal VideoVS_n   : std_logic;                       -- Vertical Sync

  -- PSG signals
  signal PsgReq      : std_logic;
  signal PsgAck      : std_logic;
  signal PsgDbi      : std_logic_vector(7 downto 0);
  signal PsgAmp      : std_logic_vector(7 downto 0);
--signal JoyA        : std_logic_vector(5 downto 0);
--signal StrA        : std_logic;
--signal JoyB        : std_logic_vector(5 downto 0);
--signal StrB        : std_logic;

  -- SCC signals
  signal SccReq      : std_logic;
  signal SccAck      : std_logic;
  signal SccDbi      : std_logic_vector(7 downto 0);
  signal SccRam      : std_logic;
  signal SccWrt      : std_logic;
  signal SccAdr      : std_logic_vector(19 downto 0);
  signal SccDbo      : std_logic_vector(7 downto 0);
  signal SccAmpL     : std_logic_vector(7 downto 0);
  signal SccAmpR     : std_logic_vector(7 downto 0);

  -- Opll signals
  signal OpllReq     : std_logic;
  signal OpllAck     : std_logic;
  signal OpllAmp     : std_logic_vector(9 downto 0);
  signal OpllEnaWait : std_logic;

  -- Sound signals
  constant DAC_MSBI  : integer := 11;
  signal DACin       : std_logic_vector(DAC_MSBI downto 0);
  signal DACout      : std_logic;

  signal PsgVol      : std_logic_vector(2 downto 0);
  signal SccVol      : std_logic_vector(2 downto 0);
  signal OpllVol     : std_logic_vector(2 downto 0);
  signal MstrVol     : std_logic_vector(2 downto 0);

  -- Exernal memory signals
  signal RamReq      : std_logic;
  signal RamAck      : std_logic;
  signal RamDbi      : std_logic_vector(7 downto 0);
  signal CpuAdr      : std_logic_vector(22 downto 0);

  signal SdPaus      : std_logic;
  signal DbgPc       : std_logic_vector(15 downto 0) := (others => '0');
  signal DbgVdpW     : std_logic_vector(7 downto 0);


begin

  ----------------------------------------------------------------
  -- Clock generator (21.48MHz > 3.58MHz)
  -- pCpuClk should be independent from reset
  ----------------------------------------------------------------
  process(clk21m)

    variable jc : std_logic_vector(4 downto 0) := (others => '0');  -- (initial value for simulation)

  begin

    if (clk21m'event and clk21m = '1') then

      jc(3) := jc(2);
      jc(2) := jc(1);
      jc(1) := jc(0);

      if (jc(3 downto 1) = "010" or jc(3 downto 1) = "101") then
        jc(0) := jc(3);
      else
        jc(0) := not jc(3);
      end if;

      -- CPUCLK : 3.58MHz = 21.48MHz / 6
      if (jc(3 downto 2) = "10") then
        clkena <= '1';
      else
        clkena <= '0';
      end if;
      cpuclk <= jc(3);

    end if;

  end process;

  -- TN9K: clock selector (turbo 10.74/21.48MHz) removed, clksel is constant "00".
  -- The Z80 runs on cpuclk directly (it used to leave the FPGA as pCpuClk and
  -- come back through the slot connector as pSltClk).


  ----------------------------------------------------------------
  -- Reset control
  ----------------------------------------------------------------
  -- TN9K: reset comes from the board top (power-on + button), already
  -- synchronised to clk21m. The unused CpuRst_n generator was removed.
  reset     <= not reset_n;


  ----------------------------------------------------------------
  -- SD access lamp (TN9K: DIP switch / LED scanner removed)
  ----------------------------------------------------------------
  process(clk21m)
  begin
    if (clk21m'event and clk21m = '1') then
      pLedSd <= not MmcEna;
    end if;
  end process;

  KeyMode   <= '1';     -- Kana key board layout  : 1=JIS layout


  ----------------------------------------------------------------
  -- Internal CPU data bus (TN9K: replaces the tri-stated slot bus)
  --   CPU write cycle      : CPU data
  --   read of an internal device : dbi
  --   read of an empty slot (1/2) : FFh (slot pull-ups)
  ----------------------------------------------------------------
  BusDat <= CpuDo when CpuDoe = '1' else
            dbi   when BusRd_n = '0' and BusIorq_n = '0' and BusDir = '1' else
            dbi   when BusRd_n = '0' and BusMerq_n = '0' and PriSltNum = "00" else
            dbi   when BusRd_n = '0' and BusMerq_n = '0' and PriSltNum = "11" else
            dbi   when BusRd_n = '0' and BusMerq_n = '0' and PriSltNum = "10" and MegType /= "00" else
            (others => '1');


  ----------------------------------------------------------------
  -- Z80 CPU wait control
  ----------------------------------------------------------------
  process(cpuclk, reset)

    variable iCpuM1_n : std_logic;
    variable jSltMerq_n : std_logic;
    variable jSltIorq_n : std_logic;
    variable count : std_logic_vector(3 downto 0);

  begin

    if (reset = '1') then
      iCpuM1_n   := '1';
      jSltIorq_n := '1';
      jSltMerq_n := '1';
      count      := (others => '0');
      BusWait_n <= '1';
    elsif (cpuclk'event and cpuclk = '1') then

      if (BusMerq_n = '0' and jSltMerq_n = '1') then
        if (clksel = "11" and VideoDLClk = '0' and VideoDHClk = '1') then
          count := "0101";
        elsif (clksel = "11" and iSltScc = '1') then
          count := "0111";
        elsif (clksel = "11") then
          count := "0100";
        elsif (clksel = "01") then
          count := "0010";
        end if;
      elsif (BusIorq_n = '0' and jSltIorq_n = '1') then
        if (clksel = "11") then
          count := "0111";
        elsif (clksel = "01") then
          count := "0011";
        end if;
      elsif (count /= "0000") then
        count := count - 1;
      end if;

      if (SelfMode = '0') then
        BusWait_n <= '1';
      elsif (CpuM1_n = '0' and iCpuM1_n = '1') then
        BusWait_n <= '0';
      elsif (count /= "0000") then
        BusWait_n <= '0';
      elsif (clksel /= "00" and OpllReq = '1' and OpllAck = '0') then
        BusWait_n <= '0';
--    elsif (clksel /= "00" and iSltErm = '1' and MmcAct = '1') then
--      BusWait_n <= '0';
      elsif (ErmReq = '1' and adr(15 downto 13) = "010" and MmcAct = '1') then
        BusWait_n <= '0';
      elsif (SdPaus = '1') then
        BusWait_n <= '0';
      else
        BusWait_n <= '1';
      end if;

      iCpuM1_n := CpuM1_n;
      jSltIorq_n := BusIorq_n;
      jSltMerq_n := BusMerq_n;

    end if;

  end process;


  ----------------------------------------------------------------
  -- On chip internal bus control
  ----------------------------------------------------------------
  process(clk21m, reset)

    variable ExpDec : std_logic;

  begin

    if (reset = '1') then

      iSltSltsl_n <= '1';
      iSltRfsh_n  <= '1';
      iSltMerq_n  <= '1';
      iSltIorq_n  <= '1';
      iSltRd_n    <= '1';
      iSltWr_n    <= '1';
      xSltRd_n    <= '1';
      xSltWr_n    <= '1';
      iSltAdr     <= (others => '1');
      iSltDat     <= (others => '1');

      iack        <= '0';

      dlydbi      <= (others => '1');
      ExpDec      := '0';

    elsif (clk21m'event and clk21m = '1') then

      -- MSX slot signals
      iSltSltsl_n <= '1';                 -- TN9K: master mode only
      iSltRfsh_n  <= CpuRfsh_n;
      iSltMerq_n  <= BusMerq_n;
      iSltIorq_n  <= BusIorq_n;
      iSltRd_n    <= BusRd_n;
      iSltWr_n    <= BusWr_n;
      if (clksel = "11") then
        xSltRd_n    <= iSltRd_n;
        xSltWr_n    <= iSltWr_n;
      else
        xSltRd_n    <= BusRd_n;
        xSltWr_n    <= BusWr_n;
      end if;
      iSltAdr     <= BusAdr;
      iSltDat     <= BusDat;

      if (iSltSltsl_n = '1' and iSltMerq_n  = '1' and iSltIorq_n = '1') then
        iack <= '0';
      elsif (ack = '1') then
        iack <= '1';
      end if;

      if (mem = '1' and ExpDec = '1') then
        dlydbi <= ExpDbi;
      elsif (mem = '1' and iSltBot = '1') then
        dlydbi <= RomDbi;
      elsif (mem = '1' and iSltErm = '1' and MmcEna = '1') then
        dlydbi <= MmcDbi;
      elsif (mem = '0' and adr(6 downto 2)  = "00010") then
        dlydbi <= VdpDbi;
      elsif (mem = '0' and adr(6 downto 2)  = "00110") then
        dlydbi <= VdpDbi;
      elsif (mem = '0' and adr(6 downto 2)  = "01000") then
        dlydbi <= PsgDbi;
      elsif (mem = '0' and adr(6 downto 2)  = "01010") then
        dlydbi <= PpiDbi;
      elsif (mem = '0' and adr(6 downto 2)  = "11111") then
        dlydbi <= MapDbi;
      elsif (mem = '0' and adr(6 downto 1)  = "011010") then
        dlydbi <= RtcDbi;
      elsif (mem = '0' and adr(6 downto 2)  = "10110") then
        dlydbi <= KanDbi;
      else
        dlydbi <= (others => '1');
      end if;

      if (adr = X"FFFF") then
        ExpDec := '1';
      else
        ExpDec := '0';
      end if;

    end if;

  end process;

  ----------------------------------------------------------------
  process(clk21m, reset)

  begin

    if (reset = '1') then

      jSltScc   <= '0';
      jSltMem   <= '0';

      wrt <= '0';

    elsif (clk21m'event and clk21m = '0') then

      if (mem = '1' and iSltScc = '1') then
        jSltScc <= '1';
      else
        jSltScc <= '0';
      end if;

      if (mem = '1' and iSltErm = '1') then
        if (MmcEna = '1' and adr(15 downto 13) = "010") then
          jSltMem <= '0';
        elsif (MmcMode = '1') then      -- enable SD/MMC drive
          jSltMem <= '1';
        else                            -- disable SD/MMC drive
          jSltMem <= '0';
        end if;
      elsif (mem = '1' and (iSltMap = '1' or rom_main = '1' or rom_opll = '1' or rom_extr = '1' or rom_kbas = '1')) then
          jSltMem <= '1';
--    elsif (mem = '0' and (rom_kanj = '1')) then
--        jSltMem <= '1';
      else
          jSltMem <= '0';
      end if;

      if (req = '0') then
        wrt <= not BusWr_n;   -- 1=write, 0=read
      end if;

      ireq <= req;

    end if;

  end process;

  -- access request, CPU > Components
  req <= '1' when (((iSltMerq_n = '0' and SelfMode = '1') or
                    iSltSltsl_n = '0' or iSltIorq_n = '0') and
                    (xSltRd_n = '0' or xSltWr_n = '0') and iack = '0') else '0';
  mem <= iSltIorq_n; -- 1=memory area, 0=i/o area
  dbo <= iSltDat;    -- CPU data (CPU > device)
  adr <= iSltAdr;    -- CPU address (CPU > device)

  -- access acknowledge, Components > CPU
  ack     <= RamAck when                RamReq = '1' else       -- ErmAck, MapAck, KanAck;
             SccAck when mem = '1' and iSltScc = '1' else       -- SccAck
             OpllAck when OpllReq = '1' else                    -- OpllAck
             req;                                               -- PsgAck, PpiAck, MapAck, VdpAck, RtcAck
  dbi     <= SccDbi when jSltScc = '1' else
             RamDbi when jSltMem = '1' else
             dlydbi;


  ----------------------------------------------------------------
  -- PPI(8255) / primary-slot, keyboard, 1 bit sound port
  ----------------------------------------------------------------
  process(clk21m, reset)

  begin

    if (reset = '1') then

      PpiPortA <= "11111111"; -- primary slot : page 0 => boot-rom, page 1/2 => ese-mmc, page 3 => mapper
--    PpiPortB <= (others => '1');
      PpiPortC <= (others => '0');

    elsif (clk21m'event and clk21m = '1') then

      -- I/O port access on A8-ABh ... PPI(8255) access
      if (PpiReq = '1') then
        if (wrt = '1' and adr(1 downto 0) = "00") then
          PpiPortA <= dbo;
        elsif (wrt = '1' and adr(1 downto 0) = "10") then
          PpiPortC <= dbo;
        elsif (wrt = '1' and adr(1 downto 0) = "11" and dbo(7) = '0') then
          case dbo(3 downto 1) is
            when "000"  => PpiPortC(0) <= dbo(0); -- key_matrix Y(0)
            when "001"  => PpiPortC(1) <= dbo(0); -- key_matrix Y(1)
            when "010"  => PpiPortC(2) <= dbo(0); -- key_matrix Y(2)
            when "011"  => PpiPortC(3) <= dbo(0); -- key_matrix Y(3)
            when "100"  => PpiPortC(4) <= dbo(0); -- cassete motor on (0=ON,1=OFF)
            when "101"  => PpiPortC(5) <= dbo(0); -- cassete audio out
            when "110"  => PpiPortC(6) <= dbo(0); -- CAPS lamp (0=ON,1=OFF)
            when others => PpiPortC(7) <= dbo(0); -- 1 bit sound port
          end case;
        end if;
      end if;

      PpiAck <= PpiReq;

    end if;

  end process;

  Caps <= PpiPortC(6);

  -- I/O port access on A8-ABh ... PPI(8255) register read
  PpiDbi <= PpiPortA when adr(1 downto 0) = "00" else
            PpiPortB when adr(1 downto 0) = "01" else
            PpiPortC when adr(1 downto 0) = "10" else
            (others => '1');


  ----------------------------------------------------------------
  -- Expansion slot
  ----------------------------------------------------------------
  process(clk21m, reset)

  begin

    if (reset = '1') then

      ExpSlot0 <= (others => '0');
      ExpSlot3 <= "00101011";      -- primary slot : page 0 => iplrom, page 1/2 => megasd, page 3 => mapper
      ExpSlotX <= (others => '0');

    elsif (clk21m'event and clk21m = '1') then

      -- Memory mapped I/O port access on FFFFh ... expansion slot register (master mode)
      if (req = '1' and iSltMerq_n = '0'  and wrt = '1' and adr = X"FFFF") then
        if (PpiPortA(7 downto 6) = "00") then
          ExpSlot0 <= dbo;
        elsif (PpiPortA(7 downto 6) = "11") then
          ExpSlot3 <= dbo;
        end if;
      end if;
      -- Memory mapped I/O port access on FFFFh ... expansion slot register (slave mode)
      if (req = '1' and iSltSltsl_n = '0' and wrt = '1' and adr = X"FFFF") then
        ExpSlotX <= dbo;
      end if;

    end if;

  end process;

  -- primary slot number (master mode)
  PriSltNum  <= PpiPortA(1 downto 0) when adr(15 downto 14) = "00" else
                PpiPortA(3 downto 2) when adr(15 downto 14) = "01" else
                PpiPortA(5 downto 4) when adr(15 downto 14) = "10" else
                PpiPortA(7 downto 6);

  -- expansion slot number : slot 0 (master mode)
  ExpSltNum0 <= ExpSlot0(1 downto 0) when adr(15 downto 14) = "00" else
                ExpSlot0(3 downto 2) when adr(15 downto 14) = "01" else
                ExpSlot0(5 downto 4) when adr(15 downto 14) = "10" else
                ExpSlot0(7 downto 6);

  -- expansion slot number : slot 3 (master mode)
  ExpSltNum3 <= ExpSlot3(1 downto 0) when adr(15 downto 14) = "00" else
                ExpSlot3(3 downto 2) when adr(15 downto 14) = "01" else
                ExpSlot3(5 downto 4) when adr(15 downto 14) = "10" else
                ExpSlot3(7 downto 6);

  -- expansion slot number : slot X (slave mode)
  ExpSltNumX <= ExpSlotX(1 downto 0) when adr(15 downto 14) = "00" else
                ExpSlotX(3 downto 2) when adr(15 downto 14) = "01" else
                ExpSlotX(5 downto 4) when adr(15 downto 14) = "10" else
                ExpSlotX(7 downto 6);

  -- expansion slot register read
  ExpDbi <= not ExpSlot0 when SelfMode = '1' and PpiPortA(7 downto 6) = "00" else
            not ExpSlot3 when SelfMode = '1' and PpiPortA(7 downto 6) = "11" else
            not ExpSlotX;


  ----------------------------------------------------------------
  -- slot / address decode
  ----------------------------------------------------------------
  iSltScc <= '0' when MegType = "00" else
             '0' when adr(15 downto 14) = "00" or adr(15 downto 14) = "11" else
             mem when PriSltNum  = "10" and SelfMode = '1'                 else
             mem when ExpSltNumX = "00" and SelfMode = '0'                 else '0';
  iSltMap <= '0' when adr = X"FFFF"                                        else
             mem when PriSltNum  = "11" and
                      ExpSltNum3 = "00" and SelfMode = '1'                 else
             '1' when ExpSltNumX = "10" and SelfMode = '0'                 else '0';
  iSltErm <= '0' when adr(15 downto 14) = "00" or adr(15 downto 14) = "11" else
             mem when PriSltNum  = "11" and
                      ExpSltNum3 = "10" and SelfMode = '1'                 else
             '1' when ExpSltNumX = "01" and SelfMode = '0'                 else '0';
  iSltBot <= '0' when adr(15 downto 14) = "01" or adr(15 downto 14) = "10" else
             mem when PriSltNum  = "11" and
                      ExpSltNum3 = "11" and SelfMode = '1'                 else '0';

  rom_main <= '0' when adr(15) /= '0'                                      else      -- MAIN-ROM
              mem when PriSltNum  = "00" and
                       ExpSltNum0 = "00" and SelfMode = '1'                else '0';
  rom_opll <= '0' when adr(15 downto 14) /= "01"                           else      -- OPLL
              mem when PriSltNum  = "00" and
                       ExpSltNum0 = "10" and SelfMode = '1'                else '0';
  rom_extr <= '0' when adr(15 downto 14) /= "00"                           else      -- SUB-ROM
              mem when PriSltNum  = "11" and
                       ExpSltNum3 = "01" and SelfMode = '1'                else '0';
  -- TN9K: Kanji BASIC (32 KB) in slot 3-1, pages 1-2, like every Japanese
  -- MSX2+: the SUB-ROM calls it at boot (7A00h of its own slot) for the
  -- scrolling MSX2+ logo. Image offset 0x20000 (the kanji font area).
  rom_kbas <= '0' when adr(15 downto 14) /= "01" and adr(15 downto 14) /= "10" else
              mem when PriSltNum  = "11" and
                       ExpSltNum3 = "01" and SelfMode = '1'                else '0';
  rom_kanj <= '0' when mem = '1'                                           else      -- Kanji-ROM
              '1' when adr(7 downto 2) = "110110" and SelfMode = '1'       else '0';

  -- RamX / RamY access request
  RamReq <= SccRam or ErmRam or MapRam or RomReq or KanRom;

  -- access request to components
  VdpReq <= req when mem = '0' and adr(7 downto 2) = "100010" and SelfMode = '0' else  -- I/O:88-8Bh / VDP(V9958)
            req when mem = '0' and adr(7 downto 2) = "100110" and SelfMode = '1' else  -- I/O:98-9Bh / VDP(V9958)
            '0';
  PsgReq <= req when mem = '0' and adr(7 downto 2) = "101000" else '0'; -- I/O:A0-A3h / PSG(AY-3-8910)
  PpiReq <= req when mem = '0' and adr(7 downto 2) = "101010" else '0'; -- I/O:A8-ABh / PPI(8255)
  OpllReq<= req when mem = '0' and adr(7 downto 2) = "011111" else '0'; -- I/O:7C-7Fh / OPLL(YM2413)
  KanReq <= req when mem = '0' and adr(7 downto 2) = "110110" else '0'; -- I/O:D8-DBh / Kanji
  RomReq <= req when mem = '1' and (rom_main = '1' or rom_opll = '1' or rom_extr = '1' or rom_kbas = '1') else '0';
  MapReq <= req when mem = '0' and adr(7 downto 2) = "111111" else      -- I/O:FC-FFh / Memory-mapper
            req when mem = '1' and iSltMap = '1'              else '0'; -- MEM        / Memory-mapper
  SccReq <= req when mem = '1' and iSltScc = '1'              else '0'; -- MEM:       / ESE-SCC
  ErmReq <= req when mem = '1' and iSltErm = '1'              else '0'; -- MEM:       / ESE-RAM, MegaSD
  RtcReq <= req when mem = '0' and adr(7 downto 1) = "1011010" else '0';-- I/O:B4-B5h / RTC(RP-5C01)

  BusDir <= '1' when BusAdr(7 downto 2) = "100010"  and SelfMode = '0' else  -- I/O:88-8Bh / VDP(V9958)
            '1' when BusAdr(7 downto 2) = "100110"  and SelfMode = '1' else  -- I/O:98-9Bh / VDP(V9958)
            '1' when BusAdr(7 downto 2) = "101000"  and SelfMode = '1' else  -- I/O:A0-A3h / PSG(AY-3-8910)
            '1' when BusAdr(7 downto 2) = "101010"  and SelfMode = '1' else  -- I/O:A8-ABh / PPI(8255)
            '1' when BusAdr(7 downto 2) = "110110"  and SelfMode = '1' else  -- I/O:D8-DBh / Kanji
            '1' when BusAdr(7 downto 2) = "111111"  and SelfMode = '1' else  -- I/O:FC-FFh / Memory-mapper
            '1' when BusAdr(7 downto 1) = "1011010" and SelfMode = '1' else  -- I/O:B4-B5h / RTC(RP-5C01)
            '0';




  ----------------------------------------------------------------
  -- Video output (TN9K: VGA 31kHz, full amplitude, fixed)
  ----------------------------------------------------------------
  pVideoR    <= VideoR;
  pVideoG    <= VideoG;
  pVideoB    <= VideoB;
  pVideoHS_n <= VideoHS_n;
  pVideoVS_n <= VideoVS_n;


  ----------------------------------------------------------------
  -- Sound output
  ----------------------------------------------------------------
  process (clk21m)

    variable Amp : std_logic_vector(DACin'high + 4 downto DACin'low);
    constant OPLL_ZERO : std_logic_vector(OpllAmp'range) := (OpllAmp'high=>'1', others=>'0');
    variable vFKeys : std_logic_vector(7 downto 0);
    variable chAmp : std_logic_vector(Amp'range);

  begin

    if (clk21m'event and clk21m = '1') then

      if (reset = '1') then
        MstrVol <= "000";
      elsif Fkeys(5) /= vFkeys(5) then -- Master Volume Up
        if "000" < MstrVol then MstrVol <= MstrVol-'1'; end if;        
      elsif Fkeys(4) /= vFkeys(4) then -- Master Volume Down
        if MstrVol < "111" then MstrVol <= MstrVol+'1'; end if;        
      end if;

      if (reset = '1') then
        PsgVol <= "011";
      elsif Fkeys(3) /= vFKeys(3) then -- PSG
        if Fkeys(7) = '1' then
          if "000" < PsgVol then PsgVol <= PsgVol-'1'; end if;
        else
          if PsgVol < "111" then PsgVol <= PsgVol+'1'; end if;
        end if;
      end if;

      if (reset = '1') then
        SccVol <= "110";
      elsif Fkeys(2) /= vFKeys(2) then -- SCC
        if Fkeys(7) = '1' then
          if "000" < SccVol then SccVol <= SccVol-'1'; end if;
        else
          if SccVol < "111" then SccVol <= SccVol+'1'; end if;
        end if;
      end if;

      if (reset = '1') then
        OpllVol <= "110";
      elsif Fkeys(1) /= vFKeys(1) then -- OPLL
        if Fkeys(7) = '1' then
          if "000" < OpllVol then OpllVol <= OpllVol-'1'; end if;
        else
          if OpllVol < "111" then OpllVol <= OpllVol+'1'; end if;
        end if;
      end if;      
      vFkeys := Fkeys;

      Amp := (Amp'high=>'1', others=>'0');
      -- PSG
      chAmp := "0000" & SHR(((PsgAmp + (KeyClick&"00000")) * PsgVol) & "0", MstrVol);
      Amp := Amp + chAmp;
      -- SCC
      chAmp := "000" & SHR((SccAmpL * SccVol)&"00", MstrVol);
      Amp := Amp - chAmp;
      -- OPLL 
      if OpllAmp < OPLL_ZERO then
        chAmp := "00" & SHR(((OPLL_ZERO - OpllAmp) * OpllVol)&"0", MstrVol);
        Amp := Amp - (chAmp - chAmp(chAmp'high downto 3));
      else
        chAmp := "00" & SHR(((OpllAmp - OPLL_ZERO) * OpllVol)&"0", MstrVol);
        Amp := Amp + (chAmp - chAmp(chAmp'high downto 3));
      end if;

      -- Limitter
      case Amp(Amp'high downto Amp'high-2) is
        when "111" => DACin <= (others=>'1');
        when "110" => DACin <= (others=>'1');
        when "101" => DACin <= (others=>'1');
        when "100" => DACin <= "1" & Amp(Amp'high-3 downto 2);
        when "011" => DACin <= "0" & Amp(Amp'high-3 downto 2);
        --when "010" => DACin <= (others=>'0');
        --when "001" => DACin <= (others=>'0');
        --when "000" => DACin <= (others=>'0');
	when others => DACin <= (others=>'0'); -- AL fixed for XST
      end case;

    end if;

  end process;

  pAudio <= DACout;


  -- TN9K: cassette interface removed (CMT input reads '0', as on turboR)
  CmtIn <= '0';


  ----------------------------------------------------------------
  -- External memory access
  ----------------------------------------------------------------
  -- Slot map / SD-RAM memory map in master mode
  --
  -- Slot 0-0 : MainROM         690000-697FFF(  32KB)
  -- Slot 0-2 : FM-BIOS         69C000-69FFFF(  16KB)
  -- Slot 1   : (EXTERNAL-SLOT)
  -- Slot 2   : (EXTERNAL-SLOT)
  --            / MegaRam       600000-67FFFF( 512KB)
  -- Slot 3-0 : Mapper          400000-4FFFFF(1024KB)
  -- Slot 3-1 : SubROM          698000-69BFFF(  16KB)
  --            Kanji BASIC     6A0000-6A7FFF(  32KB, pages 1-2, TN9K)
  -- Slot 3-2 : MegaSD          680000-68FFFF(  64KB) / 680000-6BFFFF(BIOS:256KB)
  -- Slot 3-3 : IPL-ROM         (blockRAM:512Bytes)
  -- VRAM     : VRAM            700000-71FFFF( 128KB)

  CpuAdr(22 downto 20) <= "010"                     when iSltMap    = '1' else
                          "110";
  CpuAdr(19 downto 0)  <=       MapAdr(19 downto 0) when iSltMap    = '1' else
                     '0'      & SccAdr(18 downto 0) when iSltScc    = '1' else
                     "10"     & ErmAdr(17 downto 0) when iSltErm    = '1' else
                     "101"    & KanAdr(16 downto 0) when rom_kanj   = '1' else
                     "10010"  & adr(14 downto 0)    when rom_main   = '1' else
                     "100110" & adr(13 downto 0)    when rom_extr   = '1' else
                     "10100" & adr(15) & adr(13 downto 0) when rom_kbas = '1' else
                     "100111" & adr(13 downto 0); --when rom_opll   = '1'


  ----------------------------------------------------------------
  -- Memory ports (TN9K: the SD-RAM sequencer is replaced by psram_msx)
  ----------------------------------------------------------------
  -- VRAM: the VDP drives one access per dot (address registered at the end
  -- of dotState "10", VideoDHClk = VideoDLClk = '1' during "00"); the read
  -- word comes back one dot later (see src/memory/psram_msx.vhd).
  pVramSlot <= VideoDHClk and VideoDLClk;
  pVramAdr  <= VdpAdr;
  pVramWe_n <= WeVdp_n;
  pVramDbo  <= VrmDbo;
  VrmDbi    <= pVramDbi;

  -- CPU memory: same request / acknowledge as the original RamReq / RamAck.
  -- Die address (4 MB, 22 bits) from CpuAdr (23 bits): bit 21 of CpuAdr is
  -- always 1 and bit 22 tells the mapper ("010", 0x200000-0x2FFFFF) from the
  -- rest ("110", 0x600000-0x6FFFFF), so the die gets CpuAdr(22) & (20:0):
  --   mapper RAM 1 MB   -> 0x000000-0x0FFFFF
  --   MegaRAM / SCC     -> 0x200000-0x27FFFF
  --   ESE-RAM (BIOS...) -> 0x280000-0x2BFFFF
  -- (taking CpuAdr(21 downto 0) made the three overlap: the BIOS RAM test of
  -- the mapper overwrote the BIOS image)
  -- The request is registered here: the slot / mapper decoding behind
  -- RamReq and CpuAdr is too deep for the memclk domain (1 memclk = 1/4 or
  -- 1/5 of clk21m). It costs one clk21m of latency (the Z80 samples the
  -- read data ~420 ns after MREQ; the PSRAM answers in ~250 ns).
  process(clk21m)
  begin
    if (clk21m'event and clk21m = '1') then
      pRamReq <= RamReq;
      if ((SccWrt = '1' and iSltScc = '1') or
          (ErmWrt = '1' and iSltErm = '1') or
          (MapWrt = '1' and iSltMap = '1')) then
        pRamWr <= '1';
      else
        pRamWr <= '0';
      end if;
      pRamAdr <= CpuAdr(22) & CpuAdr(20 downto 0);
      pRamDbo <= dbo;
    end if;
  end process;
  RamDbi  <= pRamDbi;
  RamAck  <= pRamAck and RamReq;

  -- TN9K debug port
  process(clk21m)
    variable vdpw_d : std_logic := '0';
    variable vdpw   : std_logic;
  begin
    if (clk21m'event and clk21m = '1') then
      if (CpuM1_n = '0' and BusMerq_n = '0') then
        DbgPc <= BusAdr;
      end if;
      if (req = '1' and mem = '0' and adr(7 downto 2) = "100110" and wrt = '1') then
        vdpw := '1';
      else
        vdpw := '0';
      end if;
      if (reset = '1') then
        DbgVdpW <= (others => '0');
      elsif (vdpw = '1' and vdpw_d = '0') then
        DbgVdpW <= DbgVdpW + 1;
      end if;
      vdpw_d := vdpw;
    end if;
  end process;
  pDbg <= DbgPc & PpiPortA & DbgVdpW;
  pDbgBus <= adr & dbo & mem & wrt & req & PriSltNum & ExpSltNum0 & ExpSltNum3;

  -- pause key (the original sampled it in the SD-RAM sequencer)
  process(clk21m)
  begin
    if (clk21m'event and clk21m = '1') then
      SdPaus <= Paus;
    end if;
  end process;


  ----------------------------------------------------------------
  -- Connect components
  ----------------------------------------------------------------
  U01 : t80a
    port map(
      RESET_n => reset_n,
      CLK_n   => cpuclk,
      WAIT_n  => BusWait_n,
      INT_n   => pVdpInt_n,
      NMI_n   => '1',
      BUSRQ_n => BusReq_n,
      M1_n    => CpuM1_n,
      MREQ_n  => BusMerq_n,
      IORQ_n  => BusIorq_n,
      RD_n    => BusRd_n,
      WR_n    => BusWr_n,
      RFSH_n  => CpuRfsh_n,
      HALT_n  => open,
      BUSAK_n => open,
      A       => BusAdr,
      DI      => BusDat,
      DO      => CpuDo,
      DOE     => CpuDoe
    );
    BusReq_n  <= '1';

  U02 : iplrom
    port map(clk21m, adr, RomDbi);

  U03 : megasd
    port map(clk21m, reset, clkena, ErmReq, ErmAck, wrt, adr, ErmDbi, dbo,
             ErmRam, ErmWrt, ErmAdr, RamDbi, ErmDbo,
             MmcDbi, MmcEna, MmcAct, pSd_Ck, pSd_Cs, pSd_Cm, pSd_Do,
             EPC_CK, EPC_CS, EPC_OE, EPC_DI, EPC_DO);

  -- BIOS flash: the former Altera EPCS port goes straight to a SPI flash
  pEpc_Ck <= EPC_CK;
  pEpc_Cs <= EPC_CS;
  pEpc_Di <= EPC_DI;
  EPC_DO  <= pEpc_Do;

  U05 : mapper
    port map(clk21m, reset, clkena, MapReq, MapAck, mem, wrt, adr, MapDbi, dbo,
             MapRam, MapWrt, MapAdr, RamDbi, MapDbo);

  U06 : eseps2
    port map (clk21m, reset, clkena, Kmap, Caps, Kana, Paus, open, Reso, Fkeys,
              pPs2Clk, pPs2Dat, PpiPortC, KbdKeyX);

  -- TN9K: the extra button acts as SPACE (row 8, bit 0, active low) and the
  -- UART keyboard presses one key (+ SHIFT / CTRL in row 6)
  process(KbdKeyX, PpiPortC, pKeySpace_n, pKeyInj, pKeyInjRow, pKeyInjCol, pKeyInjShift, pKeyInjCtrl)
    variable k : std_logic_vector(7 downto 0);
  begin
    k := KbdKeyX;
    if PpiPortC(3 downto 0) = "1000" and pKeySpace_n = '0' then
      k(0) := '0';
    end if;
    if pKeyInj = '1' then
      if PpiPortC(3 downto 0) = pKeyInjRow then
        k(conv_integer(pKeyInjCol)) := '0';
      end if;
      if PpiPortC(3 downto 0) = "0110" then
        if pKeyInjShift = '1' then k(0) := '0'; end if;
        if pKeyInjCtrl  = '1' then k(1) := '0'; end if;
      end if;
    end if;
    PpiPortB <= k;
  end process;

  G_RTC : if ENABLE_RTC generate
    U07 : rtc
      port map(clk21m, reset, clkena, RtcReq, RtcAck, wrt, adr, RtcDbi, dbo);
  end generate;
  G_NO_RTC : if not ENABLE_RTC generate
    RtcAck <= RtcReq;
    RtcDbi <= (others => '1');
  end generate;

  G_KANJI : if ENABLE_KANJI generate
    U08 : kanji
      port map(clk21m, reset, clkena, KanReq, KanAck, wrt, adr, KanDbi, dbo,
               KanRom, KanAdr, RamDbi, KanDbo);
  end generate;
  G_NO_KANJI : if not ENABLE_KANJI generate
    KanAck <= KanReq;
    KanDbi <= (others => '1');
    KanRom <= '0';
    KanAdr <= (others => '0');
    KanDbo <= (others => '0');
  end generate;

  U20 : vdp
    port map(
      clk21m, reset, VdpReq, VdpAck, wrt, adr, VdpDbi, dbo, pVdpInt_n,
      OeVdp_n, WeVdp_n, VdpAdr, VrmDbi, VrmDbo,
      VideoR, VideoG, VideoB, VideoHS_n, VideoVS_n,
      VideoDHClk, VideoDLClk
    );

  U30 : psg
    port map(clk21m, reset, clkena, PsgReq, PsgAck, wrt, adr, PsgDbi, dbo,
             pJoyA, pStrA, pJoyB, pStrB, Kana, CmtIn, KeyMode, PsgAmp);

  G_SCC : if ENABLE_SCC generate
    U31 : megaram
      port map(clk21m, reset, clkena, SccReq, SccAck, wrt, adr, SccDbi, dbo,
               SccRam, SccWrt, SccAdr, RamDbi, SccDbo, MegType, SccAmpL, SccAmpR);
  end generate;
  G_NO_SCC : if not ENABLE_SCC generate
    -- MegType is forced to "00", so slot 2 is never decoded as SCC
    SccAck  <= SccReq;
    SccDbi  <= (others => '1');
    SccRam  <= '0';
    SccWrt  <= '0';
    SccAdr  <= (others => '0');
    SccDbo  <= (others => '0');
    SccAmpL <= (others => '0');
    SccAmpR <= (others => '0');
  end generate;

  G_OPLL : if ENABLE_OPLL generate
    U32 : eseopll
      port map(clk21m, reset, clkena, OpllEnaWait, OpllReq, OpllAck, wrt, adr, dbo, OpllAmp);
  end generate;
  G_NO_OPLL : if not ENABLE_OPLL generate
    OpllAck <= OpllReq;
    OpllAmp <= (OpllAmp'high => '1', others => '0');   -- OPLL zero level
  end generate;
  OpllEnaWait <= '1' when clksel /= "00" else '0';

  U33: esepwm
    generic map ( DAC_MSBI ) port map (clk21m, reset, DACin, DACout);


end rtl;
