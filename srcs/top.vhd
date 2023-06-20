library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
Port ( -- these signals are directly connected to the pins of the LCD
       register_select_out : out STD_LOGIC; -- HIGH/LOW : data/instruction
       read_write_out : out STD_LOGIC;      -- HIGH/LOW : read/write
       enable_out : out STD_LOGIC;          -- LCD reads data on rising edge
       data_bus : inout STD_LOGIC_VECTOR(7 DOWNTO 0);
       -- data bus is writable when read/write signal from interace is LOW, otherwise it is read only   
       clock : in STD_LOGIC;
       reset : in STD_LOGIC );
end top;

architecture Behavioral of top is
    component LCD_interface is
        -- creates output frames for LCD given data and destination register 
        -- automatically initializes LCD with reset sequence and control functions
        -- checks for busy flag before each write
        -- handles timing of read/write operations 
        generic ( clock_period : time );
        port ( register_select : in STD_LOGIC;
               data : in STD_LOGIC_VECTOR(7 DOWNTO 0);
               latch : in STD_LOGIC;
               LCD_frame : out STD_LOGIC_VECTOR(10 DOWNTO 0);
               -- 10:   register select
               -- 9:    read/write
               -- 8:    enable
               -- 7-0:  data
               ready_flag : out boolean;
               -- accepting new input
               clock : in STD_LOGIC;
               reset : in STD_LOGIC );
    end component;
    
    constant clock_period : time := 10 ns;
    
    -- message to be displayed
    -- line will automatically scroll if more than 16 characters
    constant msg_line_1 : string := "This line will scroll!     "; 
    constant msg_line_2 : string := "No movement here";
    
    -- input to LCD interface
    signal register_select : STD_LOGIC; 
    signal data : STD_LOGIC_VECTOR(7 DOWNTO 0);
    signal latch : STD_LOGIC := '0'; -- interface reads input on rising edge
    
    -- intermediaries from interface outputs 
    signal interface_read_write_out : STD_LOGIC; -- used as buffer to read from
    signal interface_data_out : STD_LOGIC_VECTOR(7 DOWNTO 0); -- outputs to data_bus on interface_read_write_out LOW
    
    signal ready_flag : boolean; -- interface accepting new input
    signal line_index : integer := 1; -- current position in line
    
    -- line offsets due to scrolling
    signal scrl_offst_ln1 : integer := 0; 
    signal scrl_offst_ln2 : integer := 0;
    
    signal first_line : boolean := true; -- is on first line of display
    signal counter : integer := 1; -- used for timing scroll shift delay
begin
    u1: LCD_interface
        generic map ( clock_period => clock_period )
        port map ( register_select => register_select,
                   data => data,
                   latch => latch,
                   LCD_frame(10) => register_select_out,
                   LCD_frame(9) => interface_read_write_out,
                   LCD_frame(8) => enable_out,
                   LCD_frame(7 DOWNTO 0) => interface_data_out, 
                   ready_flag => ready_flag,
                   clock => clock,
                   reset => reset ); 

    process(clock)
        impure function wait_done (delay : in time) return boolean is
        -- returns true when delay is met 
        begin
            if counter = delay/clock_period then
                counter <= 1;
                return true;
            else
                counter <= counter + 1;
                return false;
            end if;        
        end function;       
        
    begin
        if rising_edge(clock) then
            if reset = '1' then -- synchronous reset
                latch <= '0';
                line_index <= 1;
                scrl_offst_ln1 <= 0;
                scrl_offst_ln2 <= 0;
                first_line <= true;
                counter <= 1;
            else
                if interface_read_write_out = '1' then
                    data <= data_bus; -- read from LCD to interface
                    
                elsif ready_flag = true 
                    and latch = '0' then -- needed because ready_flag does not update until after cycle following latch HIGH
                    -- write to LCD
                    if line_index > 16 then 
                        -- jump lines
                        register_select <= '0';
                        if first_line = true then
                            data <= "11000000"; -- set DDRAM address to 0x40 or cursor to line 2 pos 1
                            latch <= '1'; 
                            first_line <= false; 
                            line_index <= 1; 
                        elsif wait_done(500 ms) then -- shift characters every 500 ms for scrolling
                            data <= "10000000"; -- set DDRAM address to 0x00 or cursor to line 1 pos 1
                            latch <= '1'; 
                            first_line <= true;
                            line_index <= 1;
                            scrl_offst_ln1 <= 0 when scrl_offst_ln1 = msg_line_1'length -- reset when scrolled all the way around
                                OR msg_line_1'length <= 16 -- do not scroll if line fits message
                                else scrl_offst_ln1 + 1;
                            scrl_offst_ln2 <= 0 when scrl_offst_ln2 = msg_line_2'length -- reset when scrolled all the way around
                                OR msg_line_2'length <= 16 -- do not scroll if line fits message
                                else scrl_offst_ln2 + 1;                                        
                        end if; 
                    else
                        -- write character
                        register_select <= '1';   
                        if first_line = true then
                            if line_index > msg_line_1'length then 
                                data <= X"20"; -- insert spaces if end of message reached before line done
                            else
                                -- wrap around if end of message reached
                                data <= STD_LOGIC_VECTOR(to_unsigned(character'pos(msg_line_1(line_index + scrl_offst_ln1 - msg_line_1'length)), 8)) 
                                    when line_index + scrl_offst_ln1 > msg_line_1'length
                                    else STD_LOGIC_VECTOR(to_unsigned(character'pos(msg_line_1(line_index + scrl_offst_ln1)), 8));      
                            end if;                      
                        else 
                            if line_index > msg_line_2'length then
                                data <= X"20"; -- insert spaces if end of message reached before line done
                            else
                                -- wrap around if end of message reached
                                data <= STD_LOGIC_VECTOR(to_unsigned(character'pos(msg_line_2(line_index + scrl_offst_ln2 - msg_line_2'length)), 8)) 
                                    when line_index + scrl_offst_ln2 > msg_line_2'length
                                    else STD_LOGIC_VECTOR(to_unsigned(character'pos(msg_line_2(line_index + scrl_offst_ln2)), 8));  
                            end if;   
                        end if;
                        latch <= '1'; 
                        line_index <= line_index + 1;
                    end if;
                    
                else
                    latch <= '0';      
                end if;   
            end if;
        end if; 
    end process;
    
    read_write_out <= interface_read_write_out; 
    data_bus <= interface_data_out when interface_read_write_out = '0' else (others => 'Z');

end Behavioral;
