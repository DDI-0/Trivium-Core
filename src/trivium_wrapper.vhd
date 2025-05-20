library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity trivium_wrapper is
    generic (
        one_cycle_per_byte : boolean := false
    );
    port (
        clk               : in  std_logic;
        tvc_reset_in      : in  std_logic;
        tvc_next_value_in : in  std_logic;
        tvc_start_in      : in  std_logic;
        tvc_ready_out     : out std_logic;
        tvc_done_out      : out std_logic;
        rng_data_out      : out std_logic_vector(7 downto 0);
        seed_data_in      : in  std_logic_vector(95 downto 0);
        raw_data_in       : in  std_logic_vector(7 downto 0);
        enc_data_out      : out std_logic_vector(7 downto 0)
    );
end entity trivium_wrapper;

architecture rtl of trivium_wrapper is
    component trivium_core is
        generic (
            one_cycle_per_byte : boolean := false
        );
        port (
            clock    : in  std_logic;
            load     : in  std_logic;
            enable   : in  std_logic;
            key      : in  std_logic_vector(1 to 80);
            iv       : in  std_logic_vector(1 to 80);
            bit_out  : out std_logic
        );
    end component;
    
    type state_type is (RESET_STATE, SEED_STATE, INIT_WAIT, GENERATE_NEXT, NEXT_BYTE);
    signal current_state , next_state : state_type := RESET_STATE;
    
    signal load_signal   : std_logic;
    signal enable_signal : std_logic;
    signal random_bit    : std_logic;
    
    signal init_counter  : unsigned(10 downto 0); -- For 1152 cycles
    signal bit_counter   : unsigned(2 downto 0);  -- For 8 bits
    
    signal key_data      : std_logic_vector(1 to 80);
    signal iv_data       : std_logic_vector(1 to 80);
    
    signal output_shift  : std_logic_vector(7 downto 0);
    
    signal core_output_ready : std_logic;
    
begin
    -- Extract key and IV from seed
    key_extraction: process(seed_data_in)
    begin
        for i in 0 to 79 loop
            key_data(i+1) <= seed_data_in(i);
        end loop;
    end process key_extraction;
    
    iv_extraction: process(seed_data_in)
    begin
        for i in 0 to 79 loop
            if i < 16 then
                iv_data(i+1) <= seed_data_in(i+80);
            else
                iv_data(i+1) <= '0'; -- Pad with zeros
            end if;
        end loop;
    end process iv_extraction;
    
    -- Trivium core instantiation
    trivium_inst: trivium_core
    generic map (
        one_cycle_per_byte => one_cycle_per_byte
    )
    port map (
        clock     => clk,
        load      => load_signal,
        enable    => enable_signal,
        key       => key_data,
        iv        => iv_data,
        bit_out   => random_bit
    );
    
    -- Connect output signals
    tvc_ready_out <= core_output_ready;
    rng_data_out <= output_shift;
    tvc_done_out <= '0'; -- Used only for host operations
    
    -- Next state logic (combinational)
    next_state_logic: process(current_state, init_counter, bit_counter, tvc_next_value_in)
    begin
        -- Default: stay in current state
        next_state <= current_state;
        
        case current_state is
            when RESET_STATE =>
                next_state <= SEED_STATE;
                
            when SEED_STATE =>
                next_state <= INIT_WAIT;
                
            when INIT_WAIT =>
                if init_counter = to_unsigned(1152, 11) then
                    next_state <= GENERATE_NEXT;
                end if;
                
            when GENERATE_NEXT =>
                if bit_counter = 7 then
                    next_state <= NEXT_BYTE;
                end if;
                
            when NEXT_BYTE =>
                if tvc_next_value_in = '1' then
                    next_state <= GENERATE_NEXT;
                end if;
                
            when others =>
                next_state <= RESET_STATE;
        end case;
    end process next_state_logic;
    
    -- State register (sequential)
    state_register: process(clk)
    begin
        if rising_edge(clk) then
            if tvc_reset_in = '0' then
                current_state <= RESET_STATE;
            else
                current_state <= next_state;
            end if;
        end if;
    end process state_register;
    
    -- Counter management (sequential)
    counter_management: process(clk)
    begin
        if rising_edge(clk) then
            if tvc_reset_in = '0' then
                init_counter <= (others => '0');
                bit_counter <= (others => '0');
            else
                case current_state is
                    when RESET_STATE =>
                        init_counter <= (others => '0');
                        bit_counter <= (others => '0');
                    
                    when INIT_WAIT =>
                        init_counter <= init_counter + 1;
                        
                    when GENERATE_NEXT =>
                        if bit_counter = 7 then
                            bit_counter <= (others => '0');
                        else
                            bit_counter <= bit_counter + 1;
                        end if;
                        
                    when others =>
                        -- Maintain counter values
                end case;
            end if;
        end if;
    end process counter_management;
    
    -- Output and ready management (sequential)
    output_and_ready_proc: process(clk)
    begin
        if rising_edge(clk) then
            if tvc_reset_in = '0' then
                output_shift <= (others => '0');
                core_output_ready <= '0';
            else
                case current_state is
                    when GENERATE_NEXT =>
                        -- Shift in the random bit
                        output_shift <= output_shift(6 downto 0) & random_bit;
                        
                        -- Set ready flag when byte is complete
                        if bit_counter = 7 then
                            core_output_ready <= '1';
                        end if;
                        
                    when NEXT_BYTE =>
                        if tvc_next_value_in = '1' then
                            core_output_ready <= '0';
                        end if;
                        
                    when others =>
                        core_output_ready <= '0';
                end case;
            end if;
        end if;
    end process output_and_ready_proc;
    
    -- Trivium control signals (combinational)
    trivium_control: process(current_state)
    begin
        -- Default values
        load_signal <= '0';
        enable_signal <= '0';
        
        case current_state is
            when RESET_STATE =>
                load_signal <= '0';
                enable_signal <= '0';
                
            when SEED_STATE =>
                load_signal <= '1';
                enable_signal <= '0';
                
            when INIT_WAIT | GENERATE_NEXT | NEXT_BYTE =>
                load_signal <= '0';
                enable_signal <= '1';
                
            when others =>
                load_signal <= '0';
                enable_signal <= '0';
        end case;
    end process trivium_control;
    
    encryption_process: process(raw_data_in, output_shift)
    begin
        enc_data_out <= raw_data_in xor output_shift;
    end process encryption_process;
    
end architecture rtl;