// ============================================================================
// Honour SoC — Top-Level UVM Package
// ============================================================================

package soc_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Import all individual subsystem VIP packages
  import clk_rst_pkg::*;
  import uart_pkg::*;
  import gpio_pkg::*;
  import vga_pkg::*;
  import heartbeat_pkg::*;
  import reset_seq_pkg::*;

  `include "soc_env.sv"
  `include "soc_test.sv"
endpackage
