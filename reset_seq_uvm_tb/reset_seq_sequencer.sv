class reset_seq_sequencer extends uvm_sequencer #(reset_seq_item);
`uvm_component_utils(reset_seq_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
