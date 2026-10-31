class soc_vip_env extends uvm_env;
soc_vip_agent agent; soc_vip_scoreboard sb;
`uvm_component_utils(soc_vip_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=soc_vip_agent::type_id::create("agent",this); sb=soc_vip_scoreboard::type_id::create("sb",this); endfunction
endclass
