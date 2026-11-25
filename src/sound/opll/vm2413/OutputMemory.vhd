-- 
-- OutputMemory.vhd 
--
-- Copyright (c) 2006 Mitsutaka Okazaki (brezza@pokipoki.org)
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
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use WORK.VM2413.ALL;

entity OutputMemory is port ( 
  clk    : in std_logic;
  reset  : in std_logic;
  wr     : in std_logic;
  addr  : in SLOT_TYPE;
  wdata  : in SIGNED_LI_TYPE;
  rdata  : out SIGNED_LI_TYPE;
  addr2  : in SLOT_TYPE;
  rdata2 : out SIGNED_LI_TYPE
);
end OutputMemory;

architecture RTL of OutputMemory is

  type SIGNED_LI_ARRAY_TYPE is array (0 to MAXSLOT) of SIGNED_LI_VECTOR_TYPE;
  signal data_array : SIGNED_LI_ARRAY_TYPE := (others => (others => '0'));
  -- TN9K: synchronous read -> block RAM (saves LUT-RAM on the GW1NR-9)
  attribute syn_ramstyle : string;
  attribute syn_ramstyle of data_array : signal is "block_ram";
  
begin

  process (clk)
    
  begin
  
    -- TN9K: not cleared on reset (power-on content is 0 and every slot is
    -- rewritten on each pass); saves logic
    if clk'event and clk = '1' then

      -- write-through (the GW1NR-9 true dual port RAM has no read-before-
      -- write); OutputGenerator does not use rdata while writing
      if wr = '1' then
        data_array(addr) <= CONV_SIGNED_LI_VECTOR(wdata);
        rdata <= wdata;
      else
        rdata <= CONV_SIGNED_LI(data_array(addr));
      end if;
      rdata2 <= CONV_SIGNED_LI(data_array(addr2));
      
    end if;
    
  end process;
  
end RTL;