--import libraries
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_to_SPI is
 Port (
 CLK : in STD_LOGIC; --chip's clock
 RX : in STD_LOGIC; -- UART RX
 
 MOSI : out STD_LOGIC; --MASTER OUT
 LED1 : out STD_LOGIC; --LED - busy
 NSS : out STD_LOGIC; --NEGATE SLAVE SELECT
 SCLK : out STD_LOGIC -- SERIAL CLOCK
 );
end UART_to_SPI;

architecture Behavioral of UART_to_SPI is
 --states of state machine:
 --The state machine:
 type STATES is (
  none,  --None: state machine checks RX line for falling edge (start of reception)
  rd_nss, --ReaD NSS: first read a byte determining when NSS pin is in low/high state
		-- While transmitting data via SPI program:
		-- sets NSS to 0
		-- sets MOSI 
		-- sets NSS
		-- the only sensible values received in this state are 
		-- 0x01 (set NSS high after sending whole byte of data) 
		-- and 0x00 (leave NSS low)
  rd_nss_d, -- ReaD NSS Delay: add a delay, so that program doesn't read RX immidately after state change
		-- but "in middle of bit" (to avoid possible transient states of RX line)
  rd_wait, -- ReaD wait: after reading NSS state byte: wait for actual data byte
  rd_sda, -- ReaD Serial DAta: read data to be send via SPI (LSB first)
  rd_sda_d, -- ReaD Serial DAta Delay: see: rd_nss_d
  transfer, -- transmit data via SPI
  state_end -- end of program (reset counters and return to 'none' state)
  );
 signal state : STATES := none;
 
 ---signal read1 : STD_LOGIC := '1';
 ---signal read2 : STD_LOGIC := '1';
 
 signal rx1 : STD_LOGIC := '1'; -- two consequent states of RX line, for checking for falling edge
 signal rx2 : STD_LOGIC := '1'; 
 
 constant BITS_LIMIT : natural := 9; -- how many RX states to save in register
  --[there is bug, first data read is invalid, next 8 are valid data]
 signal rx_buf : STD_LOGIC_VECTOR(BITS_LIMIT-1 downto 0); --register for received data
 signal cnt : unsigned(13 downto 0) := b"00000000000000"; -- time counter 
 signal bits : unsigned(3 downto 0) :=b"0000"; --counter for received/transmitted bits
 
 signal nss_buf : STD_LOGIC_VECTOR(7 downto 0); -- NSS states (shift) register
 signal mosi_buf : STD_LOGIC_VECTOR(7 downto 0); -- MOSI states (shift) register
 signal mosi_buf_1 : STD_LOGIC :='1'; -- MOSI state
 signal nss_buf_1 : STD_LOGIC :='1'; -- NSS state
 signal sclk_buf : STD_LOGIC :='1'; -- SCLK state
 
 signal idle : STD_LOGIC :='0'; -- to check if program is in 'none' state
 
 -- chip's clock's freq = 50MHz
 -- divide it by desired baudrate to get number of 'ticks'
 -- UART @9600 bps
 constant CNT_UART_LIMIT : natural := 5208; -- = 50MHz / 9600bps
 constant CNT_SPI_LIMIT : natural := 5208;
 -- wait about half of UART bit duration
 constant CNT_DELAY_LIMIT : natural := 2000; -- = 1/2 * 5209
 

 begin
 process(CLK)
  begin
  if rising_edge(CLK) then --@50MHz
  
--########################################################################################
---------------------------------------------WAIT for NSS DATA
   case state is
    when none =>  
     --previous and updated state of RX, to check for falling edge
     rx1 <= rx1;
     rx2 <= RX;
     --if falling edge on RX
     if ((rx1 = '1') and (rx2 = '0')) then 
	  --reset counter
	  cnt <= (others => '0');
	  rx_buf <= (others => '0');
	  idle <='1'; --not idle
	  --start reading (with delay)
	  state <= rd_nss_d; --next state
	 end if;
---------------------------------------------DELAY: READ RX for NSS 
	when rd_nss_d =>
	 cnt <= cnt +1;
	 if cnt = CNT_DELAY_LIMIT then --increment cnt till LIMIT
      rx1 <= '1';
      rx2 <= '1';
      cnt <= (others => '0');
      state <= rd_nss; --next state
     end if;
     
---------------------------------------------READ RX for NSS
    when rd_nss =>
     cnt <= cnt +1;
     -- increment counter till LIMIT
     -- when limit reached get RX state
     if cnt = CNT_UART_LIMIT then
      cnt <= (others => '0'); --reset counter
      --shift RX data register left
      rx_buf(BITS_LIMIT-1 downto 1) <= rx_buf(BITS_LIMIT-2 downto 0);
      -- write bit to 0th (rigthmost) bit
      rx_buf(0) <= RX;
      bits <= bits +1;
     end if;
     
     if bits = BITS_LIMIT then --data reception completed
      bits <= (others => '0');-- reset counters
      cnt <= (others => '0');
      --write received data to NSS states register
      nss_buf(7 downto 0) <= rx_buf(BITS_LIMIT-1 downto BITS_LIMIT-8);
      ---read1 <= '0';
      state <= rd_wait;
      --state <= state_end;
      --state <= none;
     end if;
     
---------------------------------------------WAIT for MOSI DATA
    when rd_wait =>
     --previous and updated state of RX, to check for falling edge
     rx1 <= rx1;
     rx2 <= RX;
     --if falling edge on RX
     if ((rx1 = '1') and (rx2 = '0')) then 
	  --reset counter
	  cnt <= (others => '0');
	  --start reading (with delay)
	  state <= rd_sda_d;
	 end if;
     
---------------------------------------------DELAY: READ RX for MOSI
    when rd_sda_d =>
	 cnt <= cnt +1;
	 if cnt = CNT_DELAY_LIMIT then
      rx1 <= '1';
      rx2 <= '1';
      cnt <= (others => '0');
      state <= rd_sda;
     end if;
---------------------------------------------READ RX for MOSI
    when rd_sda =>
     cnt <= cnt +1;
     
     if cnt = CNT_UART_LIMIT then
      cnt <= (others => '0');
      rx_buf(BITS_LIMIT-1 downto 1) <= rx_buf(BITS_LIMIT-2 downto 0);
      rx_buf(0) <= RX;
      bits <= bits +1;
     end if;
     
     if bits = BITS_LIMIT then --received 8 bits of data
      cnt <= (others => '0');
      bits <= (others => '0');
      mosi_buf(7 downto 0) <= rx_buf(BITS_LIMIT-1 downto BITS_LIMIT-8);
      ---read1 <= '1';
      state <= transfer;
      --state <= none;
     end if;
---------------------------------------------WRITE
	when transfer =>
	 cnt <= cnt +1;
	 -- SPI mode 3 (CPHA=1, CPOL=1)
	 -- SCLK idle state is high
	 -- data is read on falling edge
	 
	 if cnt = 100 then
      nss_buf_1 <='0'; --always set NSS low
     end if;
	 
	 if cnt = 200 then
      -- get MOSI state
      -- at data reception data register was shifted left
      -- that means LSB is in the leftmost (7th) bit 
      mosi_buf_1 <= mosi_buf(7); --LSB first
      
     end if;
     
     if cnt = 300 then
      --data is read by slave at falling edge of SCLK
      sclk_buf <='0';
     end if;
     
     if cnt = 400 then
      -- return to idle
      sclk_buf <='1';
     end if;
     
     if cnt = 500 then
      --NSS state is in rightmost bit
      -- for convience:
      -- in order to set NSS low/high after 8 bits 
      -- UART must send 0x00 or 0x01 byte
      nss_buf_1 <= nss_buf(0);
     end if;
     
     if cnt = 600 then
	  cnt <= (others => '0');
      bits <= bits +1; --bits count
      --shift registers:
      --left, if data sent LSB first
      --right, if data sent MSB first
      mosi_buf(7 downto 1) <= mosi_buf(6 downto 0);
      nss_buf(6 downto 0) <= nss_buf(7 downto 1);
     end if;
      
     if bits = 8 then --data transmission completed
      bits <= (others => '0');
      state <= state_end;
     end if;
---------------------------------------------(end)
    when state_end =>
     idle <='0'; -- idle
     state <= none;
---------------------------------------------(other)
    when others =>
     state <= none;
   end case;
--########################################################################################
   
  end if;
 end process;
 MOSI <= mosi_buf_1;
 SCLK <= sclk_buf;
 NSS <= nss_buf_1;
  LED1 <= idle;
end Behavioral;  
  