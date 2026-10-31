# Honour SoC — UVM & C Firmware Co-Verification Execution Plan

Please refer to the authoritative architecture document:
- [18_uvm_c_co_verification_execution_plan.md](arch/18_uvm_c_co_verification_execution_plan.md)

This comprehensive document contains:
1. Executive Summary & Verification Objectives
2. System Co-Verification Topology (Mermaid diagram)
3. Peripheral CSR Bitfield & Stimulus Specification
4. Cycle-Accurate Co-Verification Chronology & Protocol Sequence (Mermaid Sequence diagram)
5. C Firmware Implementation Specification (`firmware/test/test_uvm_co_verif.c`)
6. Detailed VIP Component Upgrades (`uart`, `gpio`, `heartbeat`, `reset_seq`, `vga`, `clk_rst`)
7. Top-Level Wrapper Testbench, Virtual Sequencer & Scoreboard Specifications
8. Build & Simulation Flow (Makefile targets and Mermaid flowchart)
9. Verification Checklist & Success Exit Criteria
