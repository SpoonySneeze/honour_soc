class reset_seq_test extends uvm_test;
reset_seq_env env;
`uvm_component_utils(reset_seq_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=reset_seq_env::type_id::create("env",this); endfunction
endclass
