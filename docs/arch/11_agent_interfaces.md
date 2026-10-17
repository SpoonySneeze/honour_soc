# UVM Verification Agent Interfaces & Signal Tap Catalog

**Document ID:** `docs/arch/11_agent_interfaces.md`  
**Stage:** Stage 11 — Identification of UVM Verification Interfaces, Agent Topologies, and Assertion Bind Points  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) through [`docs/arch/10_features.md`](file:///home/student/sriv_183/honour_soc/docs/arch/10_features.md), audited in [`docs/arch/13_consistency_audit.md`](file:///home/student/sriv_183/honour_soc/docs/arch/13_consistency_audit.md).

---

## 1. Overview

To verify the Honour SoC systematically within a UVM (Universal Verification Methodology) environment, this document catalogs every physical chip boundary pin and internal interface where a UVM agent (active or passive) can be placed. It also specifies internal tap points required for SystemVerilog Assertions (SVA) and scoreboard checking, detailing their hierarchical accessibility and recommended instantiation method (`bind` vs hierarchical reference).

---

## 2. UVM Agent Interface Catalog

The table below lists all interfaces identified across the boundary and internal hierarchy of `soc_top.v`, detailing their signal names, widths, protocol classification, agent configuration, verification purpose, and mapping to features extracted in [`docs/arch/10_features.md`](file:///home/student/sriv_183/honour_soc/docs/arch/10_features.md).

| Interface Name | Signals (Name, Width, Direction) | Protocol Type | Suggested Agent Mode | What it Would Drive or Observe | Dependent Features ([`10_features.md`](file:///home/student/sriv_183/honour_soc/docs/arch/10_features.md)) | RTL Source Citation |
|---|---|---|---|---|---|---|
| **Clock & Reset Interface** | `clk` (1b, in)<br>`rst_n` (1b, in) | Digital Clock / Active-Low Reset | **Active Agent** | Drives primary 100 MHz clock and sequences power-on cold reset and warm reset pulses. Monitors reset release timing. | `SOC-CLK-001`<br>`SOC-CLK-002`<br>`SOC-RST-001`<br>`SOC-RST-002` | [`rtl/soc_top.v:163-164, 735-740`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L163-L164) |
| **External Heartbeat Interface** | `heartbeat_in` (1b, in) | Discrete Toggle / Pulse Stream | **Active Agent** | Injects periodic heartbeat pulses, generates pulse jitter, simulates host hang (prolonged high/low stop), and injects rapid glitch bursts. | `SOC-CTRL-001`<br>`SOC-CTRL-002`<br>`SOC-CTRL-003`<br>`SOC-CTRL-004`<br>`SOC-E2E-002`<br>`SOC-E2E-003` | [`rtl/soc_top.v:168`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L168), [`rtl/custom_ips/heartbeat_monitor.v:51-78`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L51-L78) |
| **Host Reset Control Interface** | `reset_out` (1b, out) | Discrete Active-Low Level Pulse | **Passive Agent** (Monitor only) | Samples host motherboard reset line. Verifies assertion, measures exact cycle duration against `RST_HOLD_CYCLES`, checks deassertion, and asserts glitch immunity. | `SOC-RST-002`<br>`SOC-RST-003`<br>`SOC-RST-004`<br>`SOC-RST-005`<br>`SOC-RST-006`<br>`SOC-E2E-003`<br>`SOC-E2E-004` | [`rtl/soc_top.v:170, 1475`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L170), [`rtl/custom_ips/reset_sequencer.v:65-98`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L65-L98) |
| **UART Serial Interface** | `uart_rx` (1b, in)<br>`uart_tx` (1b, out) | Asynchronous Serial (UART 8-N-1) | **Active Agent** | Drives serial character byte stream into `uart_rx` (host console input / admin commands). Monitors and decodes serial frame output from `uart_tx` (telemetry, boot messages). | `SOC-DAT-004`<br>`SOC-DAT-005`<br>`SOC-REG-008`<br>`SOC-IRQ-003`<br>`SOC-E2E-001`<br>`SOC-E2E-005` | [`rtl/soc_top.v:173-174`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L173-L174), [`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v:28-150`](file:///home/student/sriv_183/honour_soc/rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v#L28-L150) |
| **VGA Video Display Interface** | `vga_hsync` (1b, out)<br>`vga_vsync` (1b, out)<br>`vga_rgb` (12b, out) | Standard VGA Digital Raster (12b RGB444) | **Passive Agent** (Monitor only) | Observes horizontal and vertical sync timing parameters, samples 12-bit RGB pixel stream during active display regions, and reconstructs screen image for font/character comparison. | `SOC-DAT-006`<br>`SOC-IRQ-004`<br>`SOC-CLK-003`<br>`SOC-E2E-006` | [`rtl/soc_top.v:183-185`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L183-L185), [`rtl/custom_ips/vga_controller.v:18-225`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L18-L225) |
| **JTAG TAP Interface** | `jtag_tck` (1b, in)<br>`jtag_tms` (1b, in)<br>`jtag_tdi` (1b, in)<br>`jtag_tdo` (1b, out) | IEEE 1149.1 JTAG / RISC-V Debug | **Active Agent** | Navigates TAP controller states, injects debug instructions into VeeR DMI registers, executes core halt/resume, and verifies debug register readback. | `SOC-CLK-004`<br>`SOC-DEC-006`<br>`SOC-DEC-007` | [`rtl/soc_top.v:177-180, 1575-1582`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L177-L180) |
| **AXI S00 IFU Master Tap** | `ifu_axi_*` (AW, W, B, AR, R channels, 64-bit data, 32-bit addr) | AXI4 64-bit Read Channel | **Passive Monitor** (Active if CPU stubbed) | Tracks CPU instruction fetch address stream, verifies burst transfers from Boot ROM (`u_rom`). | `SOC-RST-001`<br>`SOC-DAT-001`<br>`SOC-ARB-001`<br>`SOC-ARB-004` | [`rtl/soc_top.v:754-758, 814-850`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L754-L758) |
| **AXI S01 LSU Master Tap** | `lsu_axi_*` (AW, W, B, AR, R channels, 64-bit data, 32-bit addr) | AXI4 64-bit Read/Write Channel | **Passive Monitor** (Active VIP in core-less bench) | Monitors all CPU data load/store memory operations, validates address decoding across M00–M07, captures `DECERR` on unmapped access. In core-less bench, acts as primary bus master driving directed MMIO tests. | `SOC-DEC-001`<br>`SOC-DEC-002`<br>`SOC-DEC-003`<br>`SOC-DEC-004`<br>`SOC-DEC-005`<br>`SOC-DAT-002`<br>`SOC-DAT-003`<br>`SOC-ERR-001`<br>`SOC-ERR-002`<br>`SOC-ARB-001` | [`rtl/soc_top.v:754-758, 853-895`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L754-L758) |
| **AXI S02 System Bus Tap** | `sb_axi_*` (AW, W, B, AR, R channels, 64-bit data, 32-bit addr) | AXI4 64-bit Read/Write Channel | **Passive Monitor** | Observes VeeR System Bus debug accesses. Specifically monitors for `DECERR` assertion when S02 attempts access to M00–M06 (validates interconnect masking constraint OQ-03). | `SOC-DEC-006`<br>`SOC-DEC-007` | [`rtl/soc_top.v:754-758, 897-939`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L754-L758) |
| **PIC Core Interrupt Boundary** | `extintsrc_req[31:0]` (32b, internal wire) | Multi-line Discrete Level IRQ | **Passive Monitor** | Samples raw peripheral interrupt assertions (`uart_irq=bit 0`, `hb_irq=bit 1`, `vblank_irq=bit 2`, `lockout_irq=bit 3`). Measures latency from hardware event to interrupt assertion and monitors deassertion upon firmware acknowledge. | `SOC-IRQ-001`<br>`SOC-IRQ-002`<br>`SOC-IRQ-003`<br>`SOC-IRQ-004`<br>`SOC-IRQ-005` | [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600) |
| **Peripheral AXI Slaves (M00–M07)** | `m00_axi_*` to `m07_axi_*` (64b/32b addr, 64b/32b data) | AXI4 / AXI-Lite | **Passive Monitors** (Per-slave) | Monitors per-peripheral transactions, measures slave backpressure stalls (`ready` deassertion), records register transactions into scoreboard memory models. | `SOC-REG-001` through `SOC-REG-010`<br>`SOC-DAT-007` | [`rtl/soc_top.v:759-809, 1018-1290`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L759-L809) |

*Note: There are NO general-purpose `gpio_pins` on `soc_top.v`. The `u_gpio` module senses `heartbeat_in` and `reset_out_internal` internally.*

---

## 3. Internal Signals for Assertions, Checkers, and Scoreboards

The table below lists internal signals that are inaccessible from external package pins but are strictly necessary for protocol assertions, cycle-accurate timing checkers, and functional coverage.

| Target Subsystem | Signal Name & Width | Hierarchical RTL Path | Reachability Method (`bind` vs Hierarchical Ref) | Checker / Assertion Function |
|---|---|---|---|---|
| **Heartbeat Monitor** | `hb_counter[31:0]` | `soc_top.u_heartbeat.u_core.hb_counter` | `bind heartbeat_monitor` (Preferred) or Hierarchical Ref | **SVA / Scoreboard**: Verify counter increments monotonically every cycle and resets to 0 on `heartbeat_in` rising pulse. |
| **Heartbeat Monitor** | `hb_prev_sample` | `soc_top.u_heartbeat.u_core.hb_prev_sample` | `bind heartbeat_monitor` | **SVA**: Temporal assertion verifying rising edge detection `!hb_prev_sample && heartbeat_in`. |
| **Heartbeat Monitor** | `hb_state[1:0]` | `soc_top.u_heartbeat.u_core.hb_state` | `bind heartbeat_monitor` | **SVA**: State transition checking (`DISABLED=00`, `IDLE=01`, `COUNTING=10`, `UNRESPONSIVE=11`). |
| **Reset Sequencer** | `rst_countdown[31:0]` | `soc_top.u_reset_seq.u_core.rst_countdown` | `bind reset_sequencer` (Preferred) or Hierarchical Ref | **SVA**: Verify countdown decrements exactly once per clock cycle without glitches or rollover. |
| **Reset Sequencer** | `rst_state[1:0]` | `soc_top.u_reset_seq.u_core.rst_state` | `bind reset_sequencer` | **SVA**: Formal state transition checking (`IDLE=00` -> `ASSERT=01` -> `DEASSERT=10` -> `IDLE=00`). |
| **Recovery Policy** | `log_wr_ptr[3:0]` | `soc_top.u_rec_policy.u_core.log_wr_ptr` | `bind recovery_policy` (Preferred) or Hierarchical Ref | **Scoreboard**: Verify pointer advances modulo-16 on each committed event record. |
| **Recovery Policy** | `window_counter[31:0]` | `soc_top.u_rec_policy.u_core.window_counter` | `bind recovery_policy` | **SVA**: Verify window counter expires exactly at `policy_window_reg` cycles. |
| **Recovery Policy** | `window_recovery_count[7:0]` | `soc_top.u_rec_policy.u_core.window_recovery_count` | `bind recovery_policy` | **Scoreboard**: Verify count matches injected failure events within active window. |
| **Recovery Policy** | `log_buffer[0:15][31:0]` | `soc_top.u_rec_policy.u_core.log_buffer` | Hierarchical Reference (RAM array) | **Scoreboard**: Inspect shadow RAM contents directly to verify timestamp logging integrity. |
| **AXI Interconnect** | `grant_reg[2:0]` | `soc_top.u_axi_intercon.axi_interconnect_inst.arb_inst.grant_reg` | `bind arbiter` or Hierarchical Ref | **SVA / Scoreboard**: Verify fair round-robin grant distribution between S00 and S01 under continuous requests. |
| **UART 16550** | `fifo_counter_o[4:0]` | `soc_top.u_uart.axi_internal_fifo_tx_inst.fifo_counter_o` | `bind axi_uart_top` or Hierarchical Ref | **Scoreboard**: Track TX FIFO occupancy, verify FIFO full backpressure, detect overrun/underrun. |
| **VeeR PIC** | `meip[30:0]` | `soc_top.u_veer.veer.pic_ctrl_inst.meip` | Hierarchical Reference | **SVA**: Verify external interrupt pending status inside core matches peripheral IRQ assertion. |

---

## 4. Testbench Architecture Recommendations

1. **System-Level Environment (Top-Level SoC TB)**:
   - Contains active agents for **Clock/Reset**, **External Heartbeat**, and **UART** (`uart_rx`/`uart_tx`).
   - Contains passive monitors for **Host Reset Control** (`reset_out`), **VGA** (`vga_hsync`, `vga_vsync`, `vga_rgb`), and **Internal PIC IRQ lines**.
   - VeeR core executes compiled RISC-V firmware from Boot ROM (`0x8000_0000`) and DCCM (`0xF004_0000`).
   - High-level virtual sequences coordinate host heartbeat failures, inject serial console commands, and observe host reset pulses.

2. **Core-Stubbed Subsystem Environment (High-Speed Bus TB)**:
   - Replaces `u_veer` with an active **AXI Master VIP** driving Master S01 (LSU).
   - Allows high-bandwidth, cycle-accurate directed stimulus of all peripheral registers, burst transfers, and unmapped error decodes without firmware compilation overhead.
