module tb_top;
import uvm_pkg::*; import vga_pkg::*;
vga_if vif();
initial run_test("vga_test");
endmodule
