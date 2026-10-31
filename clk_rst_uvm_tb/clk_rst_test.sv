class clk_rst_test extends uvm_test;
clk_rst_env env;
`uvm_component_utils(clk_rst_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=clk_rst_env::type_id::create("env",this); endfunction
endclass
