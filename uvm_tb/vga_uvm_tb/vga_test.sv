class vga_test extends uvm_test;
vga_env env;
`uvm_component_utils(vga_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=vga_env::type_id::create("env",this); endfunction
endclass
