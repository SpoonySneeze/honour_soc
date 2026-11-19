class vga_item extends uvm_sequence_item;

  bit vga_hsync;
  bit vga_vsync;
  bit [11:0] vga_rgb;

  `uvm_object_utils(vga_item)

  function new(string name="vga_item"); super.new(name); endfunction
endclass
