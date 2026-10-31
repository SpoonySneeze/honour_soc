class reset_seq_env extends uvm_env;
reset_seq_agent agent; reset_seq_scoreboard sb;
`uvm_component_utils(reset_seq_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=reset_seq_agent::type_id::create("agent",this); sb=reset_seq_scoreboard::type_id::create("sb",this); endfunction
endclass
