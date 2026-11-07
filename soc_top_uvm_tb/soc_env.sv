// ============================================================================
// Honour SoC — Top-Level UVM Environment
// ============================================================================
// Wraps and coordinates all individual interface VIP agents:
//   - clk_rst_agent   (Clock & Reset)
//   - uart_agent      (16550 UART RX/TX)
//   - gpio_agent      (8-bit Bidirectional GPIO)
//   - vga_agent       (VGA Timing & RGB Pixels)
//   - heartbeat_agent (Host Watchdog Heartbeat Stream)
//   - reset_seq_agent (Host Power-Reset Pulse Monitor)
// ============================================================================

class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  // Subsystem VIP Agents
  clk_rst_agent   clk_rst_agnt;
  uart_agent      uart_agnt;
  gpio_agent      gpio_agnt;
  vga_agent       vga_agnt;
  heartbeat_agent hb_agnt;
  reset_seq_agent rst_seq_agnt;

  // Virtual Interface Handles
  virtual clk_rst_if   clk_rst_vif;
  virtual uart_if      uart_vif;
  virtual gpio_if      gpio_vif;
  virtual vga_if       vga_vif;
  virtual heartbeat_if hb_vif;
  virtual reset_seq_if rst_seq_vif;

  function new(string name = "soc_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    clk_rst_agnt = clk_rst_agent::type_id::create("clk_rst_agnt", this);
    uart_agnt    = uart_agent::type_id::create("uart_agnt", this);
    gpio_agnt    = gpio_agent::type_id::create("gpio_agnt", this);
    vga_agnt     = vga_agent::type_id::create("vga_agnt", this);
    hb_agnt      = heartbeat_agent::type_id::create("hb_agnt", this);
    rst_seq_agnt = reset_seq_agent::type_id::create("rst_seq_agnt", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Retrieve and bind virtual interfaces directly to drivers & monitors
    void'(uvm_config_db#(virtual clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst_vif));
    clk_rst_agnt.drv.vif = clk_rst_vif;
    clk_rst_agnt.mon.vif = clk_rst_vif;

    void'(uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", uart_vif));
    uart_agnt.drv.vif = uart_vif;
    uart_agnt.mon.vif = uart_vif;

    void'(uvm_config_db#(virtual gpio_if)::get(this, "", "gpio_vif", gpio_vif));
    gpio_agnt.drv.vif = gpio_vif;
    gpio_agnt.mon.vif = gpio_vif;

    void'(uvm_config_db#(virtual vga_if)::get(this, "", "vga_vif", vga_vif));
    vga_agnt.drv.vif = vga_vif;
    vga_agnt.mon.vif = vga_vif;

    void'(uvm_config_db#(virtual heartbeat_if)::get(this, "", "hb_vif", hb_vif));
    hb_agnt.drv.vif = hb_vif;
    hb_agnt.mon.vif = hb_vif;

    void'(uvm_config_db#(virtual reset_seq_if)::get(this, "", "rst_seq_vif", rst_seq_vif));
    rst_seq_agnt.drv.vif = rst_seq_vif;
    rst_seq_agnt.mon.vif = rst_seq_vif;
  endfunction

endclass
