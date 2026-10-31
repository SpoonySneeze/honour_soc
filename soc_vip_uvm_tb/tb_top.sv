module tb_top;
import uvm_pkg::*; import soc_vip_pkg::*;
soc_vip_if vif();
initial run_test("soc_vip_test");
endmodule
