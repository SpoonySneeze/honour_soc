class reset_seq_agent extends uvm_agent;
reset_seq_driver drv; reset_seq_monitor mon; reset_seq_sequencer seqr;
`uvm_component_utils(reset_seq_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=reset_seq_driver::type_id::create("drv",this); mon=reset_seq_monitor::type_id::create("mon",this); seqr=reset_seq_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
