# Honour SoC — Bidirectional C Firmware & UVM Testbench Synchronization Plan

Please refer to the authoritative architecture specification:
- [docs/arch/19_c_uvm_bidirectional_sync_architecture.md](arch/19_c_uvm_bidirectional_sync_architecture.md)

This comprehensive architecture document details:
1. **Executive Summary & System Topology**: High-level block diagram connecting VeeR EL2 core, MMIO registers, and UVM VIPs.
2. **Hardware Architecture**: Detailed register map (`SYNC_C2UVM`, `SYNC_UVM2C`, `SYNC_SCRATCH`) allocated in `axi_timer` (`0x0002_0100`).
3. **Hierarchical XMR Paths**: Exact SystemVerilog hierarchical cross-module references (`tb_top.u_dut.u_timer.sync_*`).
4. **Structured Token Protocol**: 32-bit token encoding schema for phase signaling and acknowledgment.
5. **Closed-Loop Co-Verification Scenarios**: Sequence diagrams for GPIO pin synchronization and dynamic Heartbeat dropout injection.
6. **Software & Testbench APIs**: C firmware macros in `firmware/test/test_common.h` and UVM synchronization tasks in `soc_top_uvm_tb/soc_test.sv`.
7. **5-Phase Implementation Roadmap**: Step-by-step rollout from RTL register additions to full regression verification.
