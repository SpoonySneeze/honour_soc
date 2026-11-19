class vga_driver extends uvm_driver #(vga_item);
virtual vga_if vif;
`uvm_component_utils(vga_driver)
function new(string n,uvm_component p);super.new(n,p);endfunction
task run_phase(uvm_phase phase); forever begin seq_item_port.get_next_item(req); @(posedge vif.clk); seq_item_port.item_done(); end endtask
endclass
