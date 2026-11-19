class clk_rst_agent extends uvm_agent;
clk_rst_driver drv; clk_rst_monitor mon; clk_rst_sequencer seqr;
`uvm_component_utils(clk_rst_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=clk_rst_driver::type_id::create("drv",this); mon=clk_rst_monitor::type_id::create("mon",this); seqr=clk_rst_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
