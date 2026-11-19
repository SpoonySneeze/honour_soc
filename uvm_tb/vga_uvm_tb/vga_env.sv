class vga_env extends uvm_env;
vga_agent agent; vga_scoreboard sb;
`uvm_component_utils(vga_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=vga_agent::type_id::create("agent",this); sb=vga_scoreboard::type_id::create("sb",this); endfunction
endclass
