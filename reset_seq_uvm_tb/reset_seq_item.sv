class reset_seq_item extends uvm_sequence_item;

  bit reset_out;

  `uvm_object_utils(reset_seq_item)

  function new(string name="reset_seq_item"); super.new(name); endfunction
endclass
