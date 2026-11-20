----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    10:34:42 05/21/2007 
-- Design Name: 
-- Module Name:    xil_pll4x - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

---- Uncomment the following library declaration if instantiating
---- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity pll4x is
    Port ( inclk0 : in  STD_LOGIC;
           c0 : out  STD_LOGIC;
           c1 : out  STD_LOGIC;
           e0 : out  STD_LOGIC);
end pll4x;

architecture Behavioral of pll4x is

begin
	c0 <= inclk0;
	c1 <= inclk0;
	e0 <= inclk0;

end Behavioral;

