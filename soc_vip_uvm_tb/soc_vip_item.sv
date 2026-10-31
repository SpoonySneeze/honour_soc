class soc_vip_item extends uvm_sequence_item;

  rand bit heartbeat_in;
  bit reset_out;
  rand bit uart_rx;
  bit uart_tx;
  bit vga_hsync;
  bit vga_vsync;
  bit [11:0] vga_rgb;
  rand bit [7:0] gpio_in;
  bit [7:0] gpio_out;
  bit [7:0] gpio_oe;

  `uvm_object_utils(soc_vip_item)

  function new(string name="soc_vip_item"); super.new(name); endfunction
endclass
