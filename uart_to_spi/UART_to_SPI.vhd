library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_to_SPI is
 Port (
 CLK : in STD_LOGIC; --chip's clock
 RX : in STD_LOGIC; -- UART RX
 --NSS_in : in STD_LOGIC; --NSS button
 
 MOSI : out STD_LOGIC; --MASTER OUT
 LED1 : out STD_LOGIC;
 --LED : out STD_LOGIC_VECTOR(2 downto 0); --debug only
 NSS : out STD_LOGIC; --NEGATE SLAVE SELECT
 SCLK : out STD_LOGIC -- SERIAL CLOCK
 --SCLK_2 : out STD_LOGIC;
 --INDICATOR : out STD_LOGIC
 );
end UART_to_SPI;

architecture Behavioral of UART_to_SPI is
 type STATES is (none, rd_nss, rd_nss_d, rd_wait, rd_sda, rd_sda_d, transfer, state_end);
 signal state : STATES := none;
 
 ---signal read1 : STD_LOGIC := '1';
 ---signal read2 : STD_LOGIC := '1';
 
 signal rx1 : STD_LOGIC := '1';
 signal rx2 : STD_LOGIC := '1';
 
 constant BITS_LIMIT : natural := 9;
 signal rx_buf : STD_LOGIC_VECTOR(BITS_LIMIT-1 downto 0);
 signal cnt : unsigned(13 downto 0) := b"00000000000000";
 signal bits : unsigned(3 downto 0) :=b"0000";
 
 signal nss_buf : STD_LOGIC_VECTOR(7 downto 0);
 signal mosi_buf : STD_LOGIC_VECTOR(7 downto 0);
 signal mosi_buf_1 : STD_LOGIC :='1';
 signal nss_buf_1 : STD_LOGIC :='1';
 signal sclk_buf : STD_LOGIC :='1';
 
 signal idle : STD_LOGIC :='0';
 
 constant CNT_UART_LIMIT : natural := 5208; -- = 50MHz / 9600bps
 constant CNT_SPI_LIMIT : natural := 5208;
 constant CNT_DELAY_LIMIT : natural := 2000; -- = 3/2 * 5209
 

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
	  idle <='1';
	  --start reading (with delay)
	  state <= rd_nss_d;
	 end if;
---------------------------------------------DELAY: READ RX for NSS 
	when rd_nss_d =>
	 cnt <= cnt +1;
	 if cnt = CNT_DELAY_LIMIT then
      rx1 <= '1';
      rx2 <= '1';
      cnt <= (others => '0');
      state <= rd_nss;
     end if;
     
---------------------------------------------READ RX for NSS
    when rd_nss =>
     cnt <= cnt +1;
     
     if cnt = CNT_UART_LIMIT then
      cnt <= (others => '0');
      rx_buf(BITS_LIMIT-1 downto 1) <= rx_buf(BITS_LIMIT-2 downto 0);
      rx_buf(0) <= RX;
      bits <= bits +1;
     end if;
     
     if bits = BITS_LIMIT then --received data
      bits <= (others => '0');
      cnt <= (others => '0');
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
      --mosi_buf(7 downto 0) <= mosi_buf(0 to 7); --TO LSB first
      ---read1 <= '1';
      state <= transfer;
      --state <= none;
     end if;
---------------------------------------------WRITE
	when transfer =>
	 cnt <= cnt +1;
	 
	 if cnt = 100 then
      nss_buf_1 <='0';
     end if;
	 
	 if cnt = 200 then
      mosi_buf_1 <= mosi_buf(7); --LSB first
      
     end if;
     
     if cnt = 300 then
      sclk_buf <='0';
     end if;
     
     if cnt = 400 then
      sclk_buf <='1';
     end if;
     
     if cnt = 500 then
      nss_buf_1 <= nss_buf(0);
     end if;
     
     if cnt = 600 then
	  cnt <= (others => '0');
      bits <= bits +1;
      mosi_buf(7 downto 1) <= mosi_buf(6 downto 0);
      nss_buf(6 downto 0) <= nss_buf(7 downto 1);
     end if;
      
     if bits = 8 then
      bits <= (others => '0');
      state <= state_end;
     end if;
---------------------------------------------(end)
    when state_end =>
     idle <='0';
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
 --LED(2 downto 0) <= rx_buf(BITS_LIMIT-1 downto BITS_LIMIT-3);
  LED1 <= idle;
 --LED(2) <= mosi_buf(7);
end Behavioral;  
  