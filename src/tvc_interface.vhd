library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tvc_interface is 
    generic (
        enable_host            : boolean := false;
        one_cycle_per_byte     : boolean := false 
    );
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        read        : in  std_logic;
        write       : in  std_logic;
        readdata    : out std_logic_vector(31 downto 0);
        writedata   : in  std_logic_vector(31 downto 0);
        address     : in  std_logic_vector(2  downto 0);
        interrupt   : out std_logic
    );
end entity tvc_interface;

architecture rtl of tvc_interface is 
    type control_status_bits is 
        (TVC_RESET, TVC_NEXT_VALUE, TVC_READY, TVC_INT_CLEAR, TVC_START, TVC_DONE);
        
    -- bit positions 
    constant TVC_RESET_BIT          : natural := control_status_bits'pos(TVC_RESET); --[0] --RW
    constant TVC_NEXT_VALUE_BIT     : natural := control_status_bits'pos(TVC_NEXT_VALUE); --[1] --WO
    constant TVC_READY_BIT          : natural := control_status_bits'pos(TVC_READY); --[2] --RO
    constant TVC_INT_CLEAR_BIT      : natural := control_status_bits'pos(TVC_INT_CLEAR); --[3] --WO
    constant TVC_START_BIT          : natural := control_status_bits'pos(TVC_START); --[4] --WO
    constant TVC_DONE_BIT           : natural := control_status_bits'pos(TVC_DONE); --[5] -- RO
    -- reserved bits 6-15
    constant TVC_ENABLE_HOST_BIT    : natural := 16; -- RO
    constant TVC_ONE_CYCLE_BIT      : natural := 17; -- RO
    -- reserved bits 18-23
    constant CORE_REVISION          : std_logic_vector(7 downto 0) := "00000001"; -- 1
    
    -- Register map
    signal control_status_reg       : std_logic_vector(31 downto 0);
    signal rng_reg                  : std_logic_vector(7 downto 0);
    signal start_address_reg        : std_logic_vector(31 downto 0);
    signal length_reg               : std_logic_vector(31 downto 0);
    signal seed_reg_0               : std_logic_vector(31 downto 0);
    signal seed_reg_1               : std_logic_vector(31 downto 0);
    signal seed_reg_2               : std_logic_vector(31 downto 0);
    
    -- Register map offsets
    constant control_status_offset  : std_logic_vector(2 downto 0) := "000"; --0x00
    constant rng_offset             : std_logic_vector(2 downto 0) := "001"; 
    constant start_address_offset   : std_logic_vector(2 downto 0) := "010";
    constant length_offset          : std_logic_vector(2 downto 0) := "011";
    constant seed_offset_0          : std_logic_vector(2 downto 0) := "100";
    constant seed_offset_1          : std_logic_vector(2 downto 0) := "101";
    constant seed_offset_2          : std_logic_vector(2 downto 0) := "110";
    
    -- Interface signals to Trivium wrapper
	alias tvc_reset_out             : std_logic is
					control_status_reg(TVC_RESET_BIT);
    signal tvc_next_value_out       : std_logic;
    signal tvc_start_out            : std_logic;
    signal tvc_ready_in             : std_logic;
    signal tvc_done_in              : std_logic;
    signal rng_data_in              : std_logic_vector(7 downto 0);
    signal seed_data_out            : std_logic_vector(95 downto 0);
    
    -- Raw data for encryption/decryption if host is enabled
    signal raw_data                 : std_logic_vector(7 downto 0);
    signal enc_data                 : std_logic_vector(7 downto 0);
    
    -- Interface signals to Host Controller
    signal start_address_out        : std_logic_vector(31 downto 0);
    signal length_out               : std_logic_vector(31 downto 0);
    
    -- Reads from write only registers
    constant bad_value              : std_logic_vector(31 downto 0) := x"0bad0bad";
    
    -- Interrupt control
    signal interrupt_pending        : std_logic;
    
    -- Signals for edge detection
    signal tvc_ready_signal         : std_logic_vector(1 downto 0) := "00";
    signal tvc_done_signal          : std_logic_vector(1 downto 0) := "00";
    
    component trivium_wrapper is
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
    end component;
    
begin
    trivium_wrapper_inst: trivium_wrapper
    generic map (
        one_cycle_per_byte => one_cycle_per_byte
    )
    port map (
        clk               => clk,
        tvc_reset_in      => tvc_reset_out,
        tvc_next_value_in => tvc_next_value_out,
        tvc_start_in      => tvc_start_out,
        tvc_ready_out     => tvc_ready_in,
        tvc_done_out      => tvc_done_in,
        rng_data_out      => rng_data_in,
        seed_data_in      => seed_data_out,
        raw_data_in       => raw_data,
        enc_data_out      => enc_data
    );
    
	 tvc_next_value_out <= '1' when control_status_reg(TVC_NEXT_VALUE_BIT) = '1' else '0';
	 tvc_start_out <= '1' when (enable_host and control_status_reg(TVC_START_BIT) = '1') else '0';
    
    seed_data_out <= seed_reg_2 & seed_reg_1 & seed_reg_0;
    
    -- Pass address and length to host controller
    start_address_out <= start_address_reg; 
    length_out <= length_reg;
    
    raw_data <= (others => '0');
    
    -- Register the incoming RNG data
    process(clk)
    begin
        if rising_edge(clk) then
            if tvc_ready_in = '1' then
                rng_reg <= rng_data_in;
            end if;
        end if;
    end process;
    
    -- Drive interrupt logic
    interrupt_logic: process(clk) is
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                interrupt_pending <= '0';
            elsif write = '1' and address = control_status_offset and writedata(TVC_INT_CLEAR_BIT) = '1' then
                interrupt_pending <= '0';
            elsif tvc_ready_signal = "10" or (enable_host and tvc_done_signal = "10") then
                interrupt_pending <= '1';
            end if;
            
            interrupt <= interrupt_pending;
        end if;
    end process interrupt_logic;

    -- Ready signal rising edge detection
    ready_rising_edge: process(clk) is
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                tvc_ready_signal <= "00";
            else
                tvc_ready_signal(0) <= tvc_ready_in;
                tvc_ready_signal(1) <= tvc_ready_signal(0);
            end if;
        end if;
    end process ready_rising_edge;

    -- Done signal rising edge detection (only used if enable_host is true)
    done_rising_edge: process(clk) is
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                tvc_done_signal <= "00";
            else
                tvc_done_signal(0) <= tvc_done_in;
                tvc_done_signal(1) <= tvc_done_signal(0);
            end if;
        end if;
    end process done_rising_edge;
    
    -- Reading logic interface
    reading_logic_interface: process(clk)
    begin
        if rising_edge(clk) then 
            if reset_n = '0' then 
                readdata <= (others => '0');
            else
                if read = '1' then 
                    -- control and status register
                    case address is
                        when control_status_offset =>
                            readdata(31 downto 24)           <= CORE_REVISION;   -- revision
                            readdata(23 downto 18)           <= (others => '0'); -- reserved bits 
                            
                            if one_cycle_per_byte then
                                readdata(TVC_ONE_CYCLE_BIT) <= '1';
                            else
                                readdata(TVC_ONE_CYCLE_BIT) <= '0';
                            end if;
                            
                            if enable_host then
                                readdata(TVC_ENABLE_HOST_BIT) <= '1';
                            else
                                readdata(TVC_ENABLE_HOST_BIT) <= '0';
                            end if;
                            
                            readdata(15 downto 6)            <= (others => '0'); -- reserved bits
                            
                            if enable_host then
                                readdata(TVC_DONE_BIT) <= tvc_done_in;
                            else
                                readdata(TVC_DONE_BIT) <= '0';
                            end if;
                            
                            readdata(TVC_START_BIT)          <= '0'; -- bit 4 - WO
                            readdata(TVC_INT_CLEAR_BIT)      <= '0'; -- bit 3 - WO
                            readdata(TVC_READY_BIT)          <= tvc_ready_in; -- bit 2 - RO
                            readdata(TVC_NEXT_VALUE_BIT)     <= '0'; -- bit 1 - WO
                            readdata(TVC_RESET_BIT)          <= tvc_reset_out; -- bit 0 - RW
                                
                        when rng_offset => 
                            readdata(31 downto 8) <= (others => '0');
                            readdata(7 downto 0) <= rng_reg;
                        when start_address_offset =>
                            if enable_host then
                                readdata <= start_address_reg;
                            else
                                readdata <= (others => '0');
                            end if;
                        when length_offset =>
                            if enable_host then
                                readdata <= length_reg;
                            else
                                readdata <= (others => '0');
                            end if;
                        when seed_offset_0 | seed_offset_1 | seed_offset_2 =>
                            readdata <= bad_value;
                        when others => 
                            readdata <= (others => '0');
                    end case;
                end if;
            end if;
        end if;
    end process;

    writing_logic_interface: process(clk)
    begin    
        if rising_edge(clk) then
            if reset_n = '0' then
                control_status_reg <= (others => '0');
                start_address_reg  <= (others => '0');
                length_reg         <= (others => '0');
                seed_reg_0         <= (others => '0');
                seed_reg_1         <= (others => '0');
                seed_reg_2         <= (others => '0');
            else
                -- Clear one-shot signals
                control_status_reg(TVC_NEXT_VALUE_BIT) <= '0';
                control_status_reg(TVC_START_BIT) <= '0';
                control_status_reg(TVC_INT_CLEAR_BIT) <= '0';
                
                -- Update status bits from external signals
                control_status_reg(TVC_READY_BIT) <= tvc_ready_in;
                if enable_host then
                    control_status_reg(TVC_DONE_BIT) <= tvc_done_in;
                end if;
                    
                if write = '1' then 
                    case address is 
                        when control_status_offset => 
                            control_status_reg(TVC_RESET_BIT) <= writedata(TVC_RESET_BIT);
                                
                            if writedata(TVC_NEXT_VALUE_BIT) = '1' then
                                control_status_reg(TVC_NEXT_VALUE_BIT) <= '1';
                            end if;
                                
                            if writedata(TVC_INT_CLEAR_BIT) = '1' then
                                control_status_reg(TVC_INT_CLEAR_BIT) <= '1';
                            end if;
                                
                            if enable_host and writedata(TVC_START_BIT) = '1' then
                                control_status_reg(TVC_START_BIT) <= '1';
                            end if;
                        when rng_offset => 
                            null; -- Read-only register
                        when start_address_offset =>
                            if enable_host then
                                start_address_reg <= writedata;
                            end if;
                        when length_offset =>
                            if enable_host then
                                length_reg <= writedata;
                            end if;
                        when seed_offset_0 =>
                            seed_reg_0 <= writedata;
                        when seed_offset_1 =>
                            seed_reg_1 <= writedata;
                        when seed_offset_2 =>
                            seed_reg_2 <= writedata;
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;
    
end architecture rtl;
