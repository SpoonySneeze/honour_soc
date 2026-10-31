// ============================================================================
// Honour SoC — Top-Level UVM Testbench Wrapper (tb_top)
// ============================================================================
// Wraps all individual subsystem interfaces, connects them to the soc_top DUT,
// registers virtual interfaces into uvm_config_db, and invokes UVM test phases.
// ============================================================================

`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Import individual VIP packages and top-level package
  import clk_rst_pkg::*;
  import uart_pkg::*;
  import gpio_pkg::*;
  import vga_pkg::*;
  import heartbeat_pkg::*;
  import reset_seq_pkg::*;
  import soc_pkg::*;

  // --------------------------------------------------------------------------
  // Primary Clock and Reset Generation
  // --------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk; // 100 MHz System Clock (10ns period)
  end

  initial begin
    rst_n = 1'b0;
    #100;
    @(posedge clk);
    rst_n = 1'b1;
  end

  // --------------------------------------------------------------------------
  // Subsystem VIP Interface Instantiations
  // --------------------------------------------------------------------------
  clk_rst_if   clk_rst_vif();
  uart_if      uart_vif();
  gpio_if      gpio_vif();
  vga_if       vga_vif();
  heartbeat_if hb_vif();
  reset_seq_if rst_seq_vif();

  // Clock & Reset distribution to all VIP interfaces
  assign clk_rst_vif.clk   = clk;
  assign clk_rst_vif.rst_n = rst_n;

  assign uart_vif.clk      = clk;
  assign uart_vif.rst_n    = rst_n;

  assign gpio_vif.clk      = clk;
  assign gpio_vif.rst_n    = rst_n;

  assign vga_vif.clk       = clk;
  assign vga_vif.rst_n     = rst_n;

  assign hb_vif.clk        = clk;
  assign hb_vif.rst_n      = rst_n;

  assign rst_seq_vif.clk   = clk;
  assign rst_seq_vif.rst_n = rst_n;

  // --------------------------------------------------------------------------
  // SoC Top DUT Instantiation & Boundary Pin Connections
  // --------------------------------------------------------------------------
  soc_top u_dut (
    .clk          (clk),
    .rst_n        (rst_n),

    // Heartbeat Monitor & Reset Sequencer
    .heartbeat_in (hb_vif.heartbeat_in),
    .reset_out    (rst_seq_vif.reset_out),

    // 16550 UART
    .uart_rx      (uart_vif.uart_rx),
    .uart_tx      (uart_vif.uart_tx),

    // JTAG TAP (excluded from scope; permanently tied quiescent)
    .jtag_tck     (1'b0),
    .jtag_tms     (1'b0),
    .jtag_tdi     (1'b0),
    .jtag_tdo     (),

    // VGA Output Display Controller
    .vga_hsync    (vga_vif.vga_hsync),
    .vga_vsync    (vga_vif.vga_vsync),
    .vga_rgb      (vga_vif.vga_rgb),

    // Standard 8-bit Bidirectional GPIO
    .gpio_in      (gpio_vif.gpio_in),
    .gpio_out     (gpio_vif.gpio_out),
    .gpio_oe      (gpio_vif.gpio_oe)
  );

  // --------------------------------------------------------------------------
  // Virtual Interface Registration and Test Execution
  // --------------------------------------------------------------------------
  initial begin
    // Register all virtual interfaces in UVM config DB for the top env
    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "clk_rst_vif", clk_rst_vif);
    uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", uart_vif);
    uvm_config_db#(virtual gpio_if)::set(null, "*", "gpio_vif", gpio_vif);
    uvm_config_db#(virtual vga_if)::set(null, "*", "vga_vif", vga_vif);
    uvm_config_db#(virtual heartbeat_if)::set(null, "*", "hb_vif", hb_vif);
    uvm_config_db#(virtual reset_seq_if)::set(null, "*", "rst_seq_vif", rst_seq_vif);

    // Run the integrated top-level test
    run_test("soc_test");
  end

endmodule
