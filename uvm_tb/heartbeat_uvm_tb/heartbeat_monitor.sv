class heartbeat_monitor extends uvm_monitor;
virtual heartbeat_if vif;
uvm_analysis_port #(heartbeat_item) ap;
`uvm_component_utils(heartbeat_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
