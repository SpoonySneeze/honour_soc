class clk_rst_monitor extends uvm_monitor;
virtual clk_rst_if vif;
uvm_analysis_port #(clk_rst_item) ap;
`uvm_component_utils(clk_rst_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
