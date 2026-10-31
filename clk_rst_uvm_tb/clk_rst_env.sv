class clk_rst_env extends uvm_env;
clk_rst_agent agent; clk_rst_scoreboard sb;
`uvm_component_utils(clk_rst_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=clk_rst_agent::type_id::create("agent",this); sb=clk_rst_scoreboard::type_id::create("sb",this); endfunction
endclass
