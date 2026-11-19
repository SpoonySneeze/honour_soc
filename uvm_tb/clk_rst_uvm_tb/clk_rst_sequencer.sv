class clk_rst_sequencer extends uvm_sequencer #(clk_rst_item);
`uvm_component_utils(clk_rst_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
