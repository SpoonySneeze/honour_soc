class heartbeat_item extends uvm_sequence_item;

  rand bit heartbeat_in;

  `uvm_object_utils(heartbeat_item)

  function new(string name="heartbeat_item"); super.new(name); endfunction
endclass
