library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity LCD_interface is
    Generic ( clock_period : time := 10 ns );
    Port ( register_select : in STD_LOGIC;
           -- HIGH/LOW: data/instruction
           data : in STD_LOGIC_VECTOR(7 DOWNTO 0);
           latch : in STD_LOGIC;
           LCD_frame : out STD_LOGIC_VECTOR(10 DOWNTO 0);
           -- 10:   register select
           -- 9:    read/write
           -- 8:    enable
           -- 7-0:  data
           ready_flag : out boolean := false;
           -- accepting new input
           clock : in STD_LOGIC;
           reset : in STD_LOGIC );
end LCD_interface;

architecture Behavioral of LCD_interface is
    type controller_state is (in_work, write, read_BF);
    type init_seq is (reset_msg_1, reset_msg_2, reset_msg_3,
                      func_set, disp_off, clr_disp, entry_mode, disp_on);
    type readwrite_seq is (en_pulse_high, en_pulse_low, hold_wait); 
    signal current_state : controller_state := in_work; 
    signal init_step : init_seq := reset_msg_1; -- sequence for initializing LCD
    signal write_step : readwrite_seq := en_pulse_high; -- sequence for writing to LCD
    signal read_step : readwrite_seq := en_pulse_high; -- sequence for reading from LCD

    signal counter : integer := 1; -- used for timing delays
    signal init_flag : boolean := false; -- LCD is initialized
    signal register_select_temp : STD_LOGIC; -- stores destination register of data while busy flag is checked
    signal busy_flag : STD_LOGIC; -- stores busy flag status read from LCD
    signal prev_latch : STD_LOGIC := '0'; -- used to detect rising edge
begin
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
        
        procedure write_to_LCD ( register_select_out : in STD_LOGIC;
                                 data_out : in STD_LOGIC_VECTOR(7 DOWNTO 0);
                                 check_BF : in boolean ) is
        -- set check_BF true if busy flag avaiable, otherwise execution timing requirements must be met manually  
        begin
            register_select_temp <= register_select_out; -- store while busy flag is checked 
            LCD_frame(7 DOWNTO 0) <= data_out; -- data can be output right away as it not required to check busy flag
            if check_BF then
                current_state <= read_BF;
            else
                current_state <= write;
            end if;
        end procedure;
   
    begin
        if rising_edge(clock) then
            if reset = '1' then -- synchronous reset 
                current_state <= in_work;
                init_step <= reset_msg_1;
                write_step <= en_pulse_high;
                read_step <= en_pulse_high;
                counter <= 1; 
                init_flag <= false;
                prev_latch <= '0';
            else 
                case current_state is
                    when in_work => -- initializing or preparing data for read/write
                        if init_flag = true then 
                            if latch = '1' and prev_latch = '0' then       
                                write_to_LCD(register_select, data, true);
                            end if;
                            prev_latch <= latch;
                        else
                            case init_step is
                                when reset_msg_1 =>
                                    if wait_done(100 ms) then -- power on timing requirement
                                        write_to_LCD('0', "00110000", false);
                                        -- function set ; 8-bit
                                        -- skip read_BF because BF not avaiable
                                        init_step <= reset_msg_2; 
                                    end if;
                                      
                                when reset_msg_2 =>
                                    if wait_done(10 ms) then -- execution timing requirement 
                                        write_to_LCD('0', "00110000", false);
                                        -- function set ; 8-bit
                                        -- skip read_BF because BF not avaiable 
                                        init_step <= reset_msg_3;
                                    end if;                          

                                when reset_msg_3 =>
                                    if wait_done(200 us) then -- execution timing requirement    
                                        write_to_LCD('0', "00110000", false); 
                                        -- function set ; 8-bit
                                        -- skip read_BF because BF not avaiable
                                        init_step <= func_set;
                                    end if;
                                                            
                                when func_set =>
                                    write_to_LCD('0', "00111000", true);
                                    -- function set ; 8-bit ; 2-line ; 5x8 
                                    init_step <= disp_off;                              
                                        
                                when disp_off => 
                                    write_to_LCD('0', "00001000", true);
                                    -- display off 
                                    init_step <= clr_disp;                   
                                                                                                 
                                when clr_disp =>
                                    write_to_LCD('0', "00000001", true);
                                    -- clear display 
                                    init_step <= entry_mode;
                                    
                                when entry_mode =>
                                    write_to_LCD('0', "00000110", true);
                                    -- entry mode set ; increment ; do not shift display
                                    init_step <= disp_on;       
                     
                                when disp_on =>
                                    write_to_LCD('0', "00001100", true);
                                    -- display on ; cursor on ; blinking on
                                    init_flag <= true;                                                                                                    
                            end case;            
                        end if;
                         
                    when write =>
                        case write_step is
                            when en_pulse_high =>
                                LCD_frame(10 DOWNTO 8) <= register_select_temp & "01"; 
                                -- read/write: WRITE
                                -- enable: HIGH
                                write_step <= en_pulse_low;
 
                            when en_pulse_low =>
                                if wait_done(1 us) then -- enable pulse width timing requirement
                                    LCD_frame(8) <= '0';
                                    -- enable: LOW
                                    write_step <= hold_wait; 
                                end if;
                                                                                 
                            when hold_wait =>
                                if wait_done(1 us) then -- enable pulse width timing requirement
                                    current_state <= in_work;
                                    write_step <= en_pulse_high; 
                                end if;               
                        end case;
                        
                    when read_BF =>
                        case read_step is
                            when en_pulse_high =>
                                LCD_frame(10 DOWNTO 8) <= "011";
                                -- register select: instruction
                                -- read/write: read
                                -- enable: HIGH
                                read_step <= en_pulse_low;
 
                            when en_pulse_low =>
                                if wait_done(1 us) then -- enable pulse width timing requirement
                                    LCD_frame(8) <= '0';
                                    -- enable: LOW
                                    busy_flag <= data(7);
                                    read_step <= hold_wait; 
                                end if;
                                                                                 
                            when hold_wait =>
                                if wait_done(1 us) then -- enable pulse width timing requirement
                                   if busy_flag = '0' then
                                       current_state <= write; 
                                   end if; 
                                   read_step <= en_pulse_high; 
                                end if;                  
                        end case;
                    
                end case;
            end if;
        end if;
    end process;
    
    ready_flag <= init_flag and current_state = in_work; -- interface accepting new input
    
end Behavioral;
