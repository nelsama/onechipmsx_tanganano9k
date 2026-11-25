-- From pengo_arcade (src/gowin/hdmi/tmds_encoder_2.vhd). Changes: smaller logic
-- (xnor word derived from the xor one) and an auxiliary symbol input.
-- author: Furkan Cayci, 2018
-- description: 8b/10b based tmds encoder

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tmds_encoder_2 is
    port (
        clk  : in  std_logic;
        disp_ena   : in  std_logic;
        control : in  std_logic_vector(1 downto 0);
        aux_ena : in  std_logic;                      -- send aux (disp_ena = 0)
        aux   : in  std_logic_vector(9 downto 0);
        d_in  : in  std_logic_vector(7 downto 0);
        q_out : out std_logic_vector(9 downto 0)
    );
end tmds_encoder_2;

architecture rtl of tmds_encoder_2 is
    signal n_ones_din : integer range 0 to 8;

    signal sel_xnor : std_logic;
    signal xored : std_logic_vector(7 downto 0);
    signal q_m : std_logic_vector(8 downto 0);

    -- a positive value represents the excess number of 1's that have been transmitted
    -- a negative value represents the excess number of 0's that have been transmitted
    signal disparity : signed(3 downto 0) := to_signed(0, 4);
    -- difference between 1's and 0's (/2 since the last bit is never used)
    signal diff : signed(3 downto 0) := to_signed(0, 4);

begin

    -- ones counter for input data
    process(d_in) is
        variable c : integer range 0 to 8;
    begin
        c := 0;
        for i in 0 to 7 loop
            if d_in(i) = '1' then
                c := c + 1;
            end if;
        end loop;
        n_ones_din <= c;
    end process;

    -- create xor encodings
    xored(0) <= d_in(0);
    encode_xor: for i in 1 to 7 generate
    begin
        xored(i) <= d_in(i) xor xored(i - 1);
    end generate;

    -- xnor encoding = xor encoding with the odd bits inverted
    sel_xnor <= '1' when n_ones_din > 4 or (n_ones_din = 4 and d_in(0) = '0') else '0';
    q_m_bits: for i in 0 to 7 generate
    begin
        q_m(i) <= xored(i) xor sel_xnor when i mod 2 = 1 else xored(i);
    end generate;
    q_m(8) <= not sel_xnor;

    -- ones counter for internal data
    process(q_m) is
        variable c : integer range 0 to 8;
    begin
        c := 0;
        for i in 0 to 7 loop
            if q_m(i) = '1' then
                c := c + 1;
            end if;
        end loop;
        diff <= to_signed(c-4, 4);
    end process;

    process(clk) is
    begin
        if rising_edge(clk) then
            if disp_ena = '0' then
                disparity <= (others => '0');
                if aux_ena = '1' then
                  q_out <= aux;
                else
                case control is
                    when "00"   => q_out <= "1101010100";
                    when "01"   => q_out <= "0010101011";
                    when "10"   => q_out <= "0101010100";
                    when others => q_out <= "1010101011";
                end case;
                end if;
             else
                if disparity = 0 or diff = 0 then
                    -- xnored data
                    if q_m(8) = '0' then
                        q_out <= "10" & not q_m(7 downto 0);
                        disparity <= disparity - diff;
                    -- xored data
                    else
                        q_out <= "01" & q_m(7 downto 0);
                        disparity <= disparity + diff;
                    end if;
                elsif (diff(diff'left) = '0' and disparity(disparity'left) = '0') or
                      (diff(diff'left) = '1' and disparity(disparity'left) = '1') then
                    q_out <= '1' & q_m(8) & not q_m(7 downto 0);
                    if q_m(8) = '1' then
                        disparity <= disparity + 1 - diff;
                    else
                        disparity <= disparity - diff;
                    end if;
                else
                    q_out <= '0' & q_m;
                    if q_m(8) = '1' then
                        disparity <= disparity + diff;
                    else
                        disparity <= disparity - 1 + diff;
                    end if;
                end if;
             end if;
        end if;
    end process;
end rtl;