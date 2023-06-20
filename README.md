# FPGA_LCD_interface
LCD interface for an FPGA written in VHDL. Developed on Basys 3 FPGA development board. 

The interface component greatly streamlines the process of writing to an LCD. A successful write now consists of just setting the latch
high after preparing the data and destination register. On startup, the interface will automatically peform the 8-step initialization
sequence. The inteface also reads the LCD itself, acquiring the status of the busy flag which is used to ensure completion of internal
operation before sucessive writes. This requires only a minimal amount of additional logic in the top-level instantiation file. Lastly,
the timing requirements of each read/write operation are handled as well. 

As an example of implementation, "top.vhd" contains logic to write a message to both lines of a 16x2 LCD. Each line holds it own message
that is independent of one another. If the message on a single line is longer than 16 characters (the width of the LCD), the line will
automatically scroll, shifting each character left every 500 ms. Otherwise, it is static.      