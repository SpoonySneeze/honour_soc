// ============================================================================
// Honour SoC — Top-Level UVM Base Test
// ============================================================================

class soc_test extends uvm_test;
  `uvm_component_utils(soc_test)

  soc_env env;

  function new(string name = "soc_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = soc_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("SOC_TOP_TEST", "SoC top-level verification environment successfully initialized", UVM_LOW)
    `uvm_info("SOC_TOP_TEST", "VeeR EL2 core executing bare-metal firmware...", UVM_LOW)
    #3000000; // Allow sufficient cycles for firmware execution and full UART print
    `uvm_info("SOC_TOP_TEST", "SoC top-level verification run phase completed", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
