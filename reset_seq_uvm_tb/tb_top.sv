module tb_top;
import uvm_pkg::*; import reset_seq_pkg::*;
reset_seq_if vif();
initial run_test("reset_seq_test");
endmodule
