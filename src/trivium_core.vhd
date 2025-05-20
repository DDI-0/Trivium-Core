library ieee;
use ieee.std_logic_1164.all;

entity trivium_core is
	generic (
		one_cycle_per_byte:	boolean	:= false
	);
	port (
		clock:	in	std_logic	:= '0';
		load:	in	std_logic	:= '0';
		enable:	in	std_logic	:= '0';

		key:	in	std_logic_vector(1 to 80) := (others => '0');
		iv:	in	std_logic_vector(1 to 80) := (others => '0');

		bit_out:	out	std_logic
	);
end entity trivium_core;

architecture rtl of trivium_core is
	signal internal_state: std_logic_vector(1 to 288);
begin
	assert (not one_cycle_per_byte)
		report "feature not implemented"
			severity failure;

	generator: process(clock) is
		variable t1, t2, t3: std_logic := '0';
		variable p1, p2, p3: std_logic := '0';
	begin
		if rising_edge(clock) then
			if load = '1' then
				internal_state(1 to 93) <= key & (81 to 93 => '0');
				internal_state(94 to 177) <= iv & "0000";
				internal_state(178 to 288) <= (178 to 285 => '0') & "111";
			elsif enable = '1' then
				t1 := internal_state(66) xor internal_state(93);
				t2 := internal_state(162) xor internal_state(177);
				t3 := internal_state(243) xor internal_state(288);

				p1 := t1 xor (internal_state(91) and internal_state(92))
					xor internal_state(171);
				p2 := t2 xor (internal_state(175) and internal_state(176))
					xor internal_state(264);
				p3 := t3 xor (internal_state(286) and internal_state(287))
					xor internal_state(69);

				internal_state(1 to 93)		<= t1 & internal_state(1 to 92);
				internal_state(94 to 177)	<= t2 & internal_state(94 to 176);
				internal_state(178 to 288)	<= t3 & internal_state(178 to 287);

				bit_out <= t1 xor t2 xor t3;
			end if;
		end if;
	end process generator;

	
end architecture rtl;
