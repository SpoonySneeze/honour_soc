class reset_seq_monitor extends uvm_monitor;
virtual reset_seq_if vif;
uvm_analysis_port #(reset_seq_item) ap;
`uvm_component_utils(reset_seq_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
