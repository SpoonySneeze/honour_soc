class gpio_item extends uvm_sequence_item;

  rand bit [7:0] gpio_in;
  bit [7:0] gpio_out;
  bit [7:0] gpio_oe;

  `uvm_object_utils(gpio_item)

  function new(string name="gpio_item"); super.new(name); endfunction
endclass
