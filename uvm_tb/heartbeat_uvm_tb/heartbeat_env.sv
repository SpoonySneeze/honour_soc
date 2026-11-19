class heartbeat_env extends uvm_env;
heartbeat_agent agent; heartbeat_scoreboard sb;
`uvm_component_utils(heartbeat_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=heartbeat_agent::type_id::create("agent",this); sb=heartbeat_scoreboard::type_id::create("sb",this); endfunction
endclass
