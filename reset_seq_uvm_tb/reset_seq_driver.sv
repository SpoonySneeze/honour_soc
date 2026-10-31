class reset_seq_driver extends uvm_driver #(reset_seq_item);
virtual reset_seq_if vif;
`uvm_component_utils(reset_seq_driver)
function new(string n,uvm_component p);super.new(n,p);endfunction
task run_phase(uvm_phase phase); forever begin seq_item_port.get_next_item(req); @(posedge vif.clk); seq_item_port.item_done(); end endtask
endclass
