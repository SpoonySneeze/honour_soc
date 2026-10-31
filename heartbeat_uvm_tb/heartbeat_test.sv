class heartbeat_test extends uvm_test;
heartbeat_env env;
`uvm_component_utils(heartbeat_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=heartbeat_env::type_id::create("env",this); endfunction
endclass
