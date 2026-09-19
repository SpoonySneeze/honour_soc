# Custom IPs AXI Integration & Verification Log

This document details the architectural updates, testing methodologies, and top-level integration steps performed to encapsulate the custom Wishbone peripherals (Heartbeat Monitor, Reset Sequencer, and Recovery Policy) into self-contained AXI4 Intellectual Property (IP) blocks.

## 1. Motivation
The original SoC architecture instantiated Wishbone peripherals at the top level (`soc_top.v`) and relied on discrete `axi4_to_wb_bridge` modules to translate AXI4 traffic from the interconnect into Wishbone transactions. To align with modern AXI SoC design practices, the goal was to:
- Hide Wishbone signaling from the top level.
- Encapsulate the translation bridges inside the custom IPs.
- Provide a clean, direct AXI4 interface that plugs directly into the `axi_interconnect_wrap_2x7`.

## 2. AXI Wrapper Implementation
Three new wrapper files were created in `rtl/custom_ips/`:
1. `axi_heartbeat_monitor.v`
2. `axi_reset_sequencer.v`
3. `axi_recovery_policy.v`

### 2.1 Upgrading to Full AXI4 (64-bit)
Initially drafted as 32-bit AXI4-Lite wrappers, the wrappers were subsequently upgraded to expose the **Full AXI4 64-bit interface** to maintain compatibility with the 64-bit `m0X_axi_*` ports of the interconnect. 
Inside each wrapper, the generic `axi4_to_wb_bridge.v` module is instantiated alongside the core IP. This internal bridge handles:
- **Data Steering**: Automatically multiplexing 64-bit AXI write data down to 32-bit Wishbone data (and replicating read data up) based on the byte address (`addr[2]`).
- **ID Reflection**: Latching incoming `awid` and `arid` tags and faithfully reflecting them on the response channels (`bid` and `rid`), which is strictly required by the AXI Interconnect to route responses back to the correct VeeR master (LSU vs. System Bus).
- **Burst Termination**: Driving the `rlast` signal upon Wishbone read completion.

## 3. Testbench Refactoring & Icarus Verilog Pivot
The standalone unit tests (`tb_*.v`) for the custom IPs were refactored to drive AXI transactions (`axi_write()`, `axi_read()`) instead of Wishbone transactions. 

### 3.1 Resolving Verilator Limitations
During verification, Verilator encountered race conditions. Verilator is a cycle-based C++ compiler optimized for synthesis-like logic; it converts testbench `#delays` into C++ coroutines. This caused non-blocking assignments (`<=`) inside initialization tasks to execute aggressively, leading to missed AXI handshakes.

To resolve this, the verification toolchain was pivoted to **Icarus Verilog (`iverilog`)**. Icarus Verilog is a true event-driven interpreter that perfectly adheres to IEEE 1364 standard timing, seamlessly handling our delay-based testbenches and concurrent AXI handshake clearing blocks without race conditions.

### 3.2 Verification Results
All three AXI wrappers were compiled and run using Icarus Verilog (`make veri_all`). The results were 100% green across all edge cases:
- **Heartbeat Monitor**: 9 / 9 Tests Passed (Timeout detection, threshold accuracy, flag latching).
- **Reset Sequencer**: 12 / 12 Tests Passed (Basic reset pulse, configurable hold durations, ignored back-to-back triggers).
- **Recovery Policy**: 16 / 16 Tests Passed (Circular buffer wrapping, sticky lockouts, window resets).
- **Total**: 37 / 37 Tests Passed.

## 4. Top-Level SoC Integration (`soc_top.v`)
With the AXI wrappers verified, `rtl/soc_top.v` was cleaned up:
- The discrete `axi4_to_wb_bridge` instances (Bridges 3, 4, and 5) were **deleted**.
- The top-level Wishbone nets (`wbs3_*`, `wbs4_*`, `wbs5_*`) were **deleted**.
- The new `axi_heartbeat_monitor`, `axi_reset_sequencer`, and `axi_recovery_policy` wrappers were instantiated directly at the top level.
- The 64-bit interconnect output ports (`m03_axi_*`, `m04_axi_*`, `m05_axi_*`) were wired straight into the new AXI wrappers.

## 5. Build System Updates
The `Makefile` was updated to seamlessly support the new architecture:
- `IVERILOG` and `IVERILOG_FLAGS` were added to drive the `veri_hbm`, `veri_rst`, and `veri_pol` targets.
- The AXI wrapper files were appended to the global source lists (`SRC_HBM`, `SRC_RST`, `SRC_POL`) so that they are automatically included when compiling full SoC targets (e.g., `make compile_top`, `make sim_soc`) using VCS or other toolchains.
