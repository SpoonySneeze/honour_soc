class vga_agent extends uvm_agent;
vga_driver drv; vga_monitor mon; vga_sequencer seqr;
`uvm_component_utils(vga_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=vga_driver::type_id::create("drv",this); mon=vga_monitor::type_id::create("mon",this); seqr=vga_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
