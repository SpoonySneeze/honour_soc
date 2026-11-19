class heartbeat_sequencer extends uvm_sequencer #(heartbeat_item);
`uvm_component_utils(heartbeat_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
