module tb_top;
import uvm_pkg::*; import heartbeat_pkg::*;
heartbeat_if vif();
initial run_test("heartbeat_test");
endmodule
