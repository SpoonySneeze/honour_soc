class heartbeat_agent extends uvm_agent;
heartbeat_driver drv; heartbeat_monitor mon; heartbeat_sequencer seqr;
`uvm_component_utils(heartbeat_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=heartbeat_driver::type_id::create("drv",this); mon=heartbeat_monitor::type_id::create("mon",this); seqr=heartbeat_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
