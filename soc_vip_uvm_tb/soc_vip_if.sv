interface soc_vip_if;
logic clk;
logic rst_n;
logic heartbeat_in;
logic reset_out;
logic uart_rx;
logic uart_tx;
logic vga_hsync;
logic vga_vsync;
logic [11:0] vga_rgb;
logic [7:0] gpio_in;
logic [7:0] gpio_out;
logic [7:0] gpio_oe;
endinterface
