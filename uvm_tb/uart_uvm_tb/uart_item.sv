class uart_item extends uvm_sequence_item;

  rand bit uart_rx;
  bit uart_tx;

  `uvm_object_utils(uart_item)

  function new(string name="uart_item"); super.new(name); endfunction
endclass
