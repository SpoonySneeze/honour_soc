# SoC Functional Feature List & Verification Catalog (Revised)

**Document ID:** `docs/arch/10_features.md`  
**Stage:** Stage 10 — Comprehensive Verifiable Feature Extraction and Classification  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Extracted from architecture analysis in [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) through [`docs/arch/09_open_questions.md`](file:///home/student/sriv_183/honour_soc/docs/arch/09_open_questions.md), corrected in accordance with [`docs/arch/13_consistency_audit.md`](file:///home/student/sriv_183/honour_soc/docs/arch/13_consistency_audit.md).

---

## 1. Overview & Verification Priority Scheme

This document defines every verifiable functional behavior of the Honour SoC as a numbered, uniquely identifiable verification feature. Following the consistency audit ([`docs/arch/13_consistency_audit.md`](file:///home/student/sriv_183/honour_soc/docs/arch/13_consistency_audit.md)), all register names, slave port numbers, bus widths, and clock domain interactions have been strictly aligned to the synthesizable RTL.

- **HIGH Priority**: Critical system-level functionality, security/isolation features, control loop behaviors, or high-risk architectural failure modes (e.g., reset isolation, crash-loop lockout, AXI decode error generation, watchdog timeout triggers).
- **MEDIUM Priority**: Standard bus protocol compliance, multi-master arbitration fairness, peripheral register read/write integrity, interrupt masking and delivery.
- **LOW Priority**: Informational status registers, display refresh mechanics, default values of non-critical configuration registers.

---

## 2. Reset and Boot Features (`SOC-RST`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-RST-001** | Core boots out of reset from Boot ROM reset vector address `0x8000_0000` | `u_veer`, `u_rom`, AXI S00 (IFU), M07 | [`rtl/soc_top.v:755, 1590`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L755), [`firmware/start.S:8`](file:///home/student/sriv_183/honour_soc/firmware/start.S#L8) | **HIGH**: Fundamental bring-up requirement. If boot vector fetch fails, the entire SoC is non-functional. |
| **SOC-RST-002** | Reset sequencer powers up in `IDLE` state (`rst_state=2'b00`) with `reset_out=1` (active-low deasserted) | `u_reset_seq`, `reset_out` pad | [`rtl/custom_ips/reset_sequencer.v:45-52`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L45-L52) | **HIGH**: Prevents accidental power-cycling or holding external host in reset during SoC power-on. |
| **SOC-RST-003** | Reset sequencer triggers active-low host reset pulse (`reset_out=0`) on `RST_CTRL.trigger=1` (offset `0x00`, bit 0) | `u_reset_seq`, `reset_out` pad, AXI M04 | [`rtl/custom_ips/reset_sequencer.v:65-71`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L65-L71) | **HIGH**: Primary mechanism by which BMC manages host server hardware lifecycle. |
| **SOC-RST-004** | Reset pulse duration exactly matches programmed value in `RST_HOLD_CYCLES` counter cycles (default `32'd100`) | `u_reset_seq`, `reset_out` pad, AXI M04 | [`rtl/custom_ips/reset_sequencer.v:47, 72-84`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L47) | **HIGH**: Host motherboards require exact pulse widths (e.g. ATX specification) to register valid reset. |
| **SOC-RST-005** | Reset sequencer transitions to `ST_DEASSERT`, sets `RST_STATUS.complete` (bit 1), and releases `reset_out=1` upon completion | `u_reset_seq`, AXI M04 | [`rtl/custom_ips/reset_sequencer.v:81-86`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L81-L86) | **MEDIUM**: Allows firmware to verify host reset completion via polling status register. |
| **SOC-RST-006** | `reset_out` assertion and deassertion does NOT reset VeeR core or internal SoC peripherals | `soc_top`, `u_veer`, `u_reset_seq` | [`rtl/soc_top.v:737, 1588-1589`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L737) | **HIGH**: Reset isolation safety. BMC must remain operational while host server is power-cycled. |
| **SOC-RST-007** | Host `reset_out` state is readable via GPIO input pin loopback (`GPIO_STAT[1]`) | `u_gpio`, `u_reset_seq`, AXI M02 | [`rtl/soc_top.v:1354`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1354), [`rtl/custom_ips/axi_gpio.v:7, 51`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_gpio.v#L7) | **LOW**: Diagnostic observability feature for firmware health check. |

---

## 3. Address Decode & Interconnect Connectivity Features (`SOC-DEC`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-DEC-001** | Address decode routing to DCCM (`0xF004_0000`–`0xF004_FFFF`) via VeeR core internal memory export | `u_veer`, `gen_dccm_banks` | [`rtl/soc_top.v:1817-1839`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1817-L1839), [`firmware/link.ld:9`](file:///home/student/sriv_183/honour_soc/firmware/link.ld#L9) | **HIGH**: Internal core SRAM execution and stack/heap memory integrity. (Note: ICCM is tied off and unmapped in hardware, [`soc_top.v:1841-1845`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1841-L1845)). |
| **SOC-DEC-002** | Address decode routing to Boot ROM (`0x8000_0000`–`0x8000_1FFF`) across crossbar port M07 | `u_axi_intercon`, `u_rom`, M07 | [`rtl/soc_top.v:808-809`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L808-L809), [`rtl/custom_ips/axi_rom.v:11`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_rom.v#L11) | **HIGH**: Required for initial boot code fetching and constants reading. |
| **SOC-DEC-003** | Address decode routing to peripheral slaves M00–M06 (`0x0002_0000`–`0x0002_06FF`): M00=UART, M01=Timer, M02=GPIO, M03=HB, M04=RST, M05=POL, M06=VGA | `u_axi_intercon`, M00–M06 | [`rtl/soc_top.v:759-806`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L759-L806), [`firmware/test/test_common.h:9-15`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L9-L15) | **HIGH**: Core LSU memory-mapped I/O communication path to peripherals and custom IPs. |
| **SOC-DEC-004** | Access to unmapped address space returns AXI `DECERR` (`2'b11`) response on read and write channels | `u_axi_intercon`, S00, S01, S02 | [`rtl/interconnect/axi_interconnect.v:642, 734`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L642) | **HIGH**: Security and bus robustness; prevents bus lockup on invalid pointer dereferences. |
| **SOC-DEC-005** | Master S00 (IFU) and S01 (LSU) have full read/write access to peripheral ports M00–M06 | `u_axi_intercon`, S00, S01 | [`rtl/soc_top.v:762-805`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L762-L805) | **HIGH**: Standard CPU execution and MMIO control path. |
| **SOC-DEC-006** | Master S02 (System Bus / JTAG Debug) access to M00–M06 is blocked and receives `DECERR` [BUG/RESTRICTION] | `u_axi_intercon`, S02, M00–M06 | [`rtl/soc_top.v:762-805`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L762-L805) | **HIGH**: Documents and verifies the architectural isolation / interconnect masking constraint (OQ-03). |
| **SOC-DEC-007** | Master S02 retains connectivity to M07 (Boot ROM) via default connectivity parameter `3'b111` | `u_axi_intercon`, S02, M07 | [`rtl/soc_top.v:808-809`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L808-L809) | **MEDIUM**: Allows external debug tools to verify boot ROM image integrity. |

---

## 4. Register Access & Storage Integrity Features (`SOC-REG`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-REG-001** | Heartbeat Monitor register read/write access (`HB_CTRL`, `HB_THRESHOLD`, `HB_STATUS`, `HB_ELAPSED`) at `0x0002_0300` | `u_heartbeat`, AXI M03 | [`rtl/custom_ips/heartbeat_monitor.v:20-23`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L20-L23), [`firmware/test/test_common.h:40-43`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L40-L43) | **HIGH**: Essential configuration registers for watchdog operation. |
| **SOC-REG-002** | `HB_CTRL.clear_flag` (bit 1, WO self-clearing) clears `HB_STATUS.unresponsive_flag` and deasserts `hb_irq` | `u_heartbeat`, AXI M03, `hb_irq` | [`rtl/custom_ips/heartbeat_monitor.v:58-61, 107-111`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L58-L61) | **HIGH**: Interrupt servicing handshake requirement. Failure prevents clearing watchdog state. |
| **SOC-REG-003** | Reset Sequencer register read/write access (`RST_CTRL`, `RST_HOLD_CYCLES`, `RST_STATUS`) at `0x0002_0400` | `u_reset_seq`, AXI M04 | [`rtl/custom_ips/reset_sequencer.v:19-21`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L19-L21), [`firmware/test/test_common.h:46-48`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L46-L48) | **HIGH**: Hardware reset controller programming interface. |
| **SOC-REG-004** | Recovery Policy register read/write access (`POL_CTRL`, `POL_WINDOW`, `POL_THRESHOLD`, `POL_STATUS`, `POL_EVENT_TS`, `LOG_READ_IDX`, `LOG_READ_DATA`, `LOG_COUNT`) at `0x0002_0500` | `u_rec_policy`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:34-41`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L34-L41), [`firmware/test/test_common.h:51-58`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L51-L58) | **HIGH**: Crash-loop policy threshold and window programming interface. |
| **SOC-REG-005** | `POL_CTRL.clear_lockout` (bit 1, WO self-clearing) clears `POL_STATUS.lockout_flag` and resets `window_recovery_count` | `u_rec_policy`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:77, 148-152`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L77) | **HIGH**: System unfreeze mechanism following crash-loop containment. |
| **SOC-REG-006** | System Timer register read access (`TMR_CTR`) at `0x0002_0100` (Slave M01) returns 32-bit free-running ticks | `u_timer`, AXI M01 | [`rtl/soc_top.v:1303-1341`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1303-L1341), [`firmware/test/test_common.h:34`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L34) | **MEDIUM**: General SoC timebase for firmware scheduling. |
| **SOC-REG-007** | GPIO pin status register read access (`GPIO_STAT`) at `0x0002_0200` (Slave M02) returns `heartbeat_in` on bit 0 and `reset_out` on bit 1 | `u_gpio`, AXI M02 | [`rtl/custom_ips/axi_gpio.v:4-8, 45-75`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_gpio.v#L4-L8), [`firmware/test/test_common.h:37`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L37) | **MEDIUM**: Internal pin observability status register. |
| **SOC-REG-008** | UART 16550 standard register set access at `0x0002_0000` (Slave M00) (RBR/THR, IER, IIR/FCR, LCR, MCR, LSR, MSR, SCR) | `u_uart`, AXI M00 | [`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v:28-150`](file:///home/student/sriv_183/honour_soc/rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v#L28-L150), [`firmware/test/test_common.h:20-30`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L20-L30) | **HIGH**: Primary debug telemetry and console communication interface. |
| **SOC-REG-009** | Read-only register enforcement: writes to read-only status and counter registers are silently discarded | All Custom IPs, AXI M00–M06 | [`rtl/custom_ips/heartbeat_monitor.v:55-68`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L55-L68), [`rtl/custom_ips/reset_sequencer.v:45-56`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L45-L56), [`rtl/custom_ips/recovery_policy.v:79-98`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L79-L98) | **MEDIUM**: Robustness check to prevent register corruption by rogue firmware writes. |
| **SOC-REG-010** | Event log indexed readback: writing `LOG_READ_IDX` (0..15) selects slot, reading `LOG_READ_DATA` returns timestamp | `u_rec_policy`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:90, 108`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L90), [`firmware/test/test_common.h:56-57`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L56-L57) | **MEDIUM**: Diagnostic telemetry path for reading crash timestamps. |
| **SOC-REG-011** | VGA character buffer access: words at `0x08`–`0x7C` in Slave M06 are writable and readable by CPU | `u_vga`, AXI M06 | [`rtl/custom_ips/vga_controller.v:86-105`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L86-L105) | **LOW**: Allows software to update and verify display text. |

---

## 5. Data Path Features (`SOC-DAT`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-DAT-001** | 64-bit instruction burst fetching from Boot ROM to VeeR IFU across Slave M07 without data truncation | `u_veer`, `u_rom`, S00, M07 | [`rtl/soc_top.v:755, 808-809`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L755) | **HIGH**: Fetch efficiency and pipeline execution throughput. |
| **SOC-DAT-002** | 64-bit load/store access to DCCM with byte enable mask precision (`wstrb[7:0]`) | `u_veer`, S01, DCCM | [`rtl/soc_top.v:1817-1839`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1817-L1839) | **HIGH**: Data integrity for sub-word (byte, half-word) memory writes. |
| **SOC-DAT-003** | 64-to-32 bit bus gasket down-conversion steers lower/upper 32-bit lane based on address bit `[2]` for Slave M00 (UART) | `soc_top`, `u_uart`, AXI M00 | [`rtl/soc_top.v:685-700`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L685-L700) | **HIGH**: Interconnect compatibility gasket; byte-lane mismatch corrupts UART characters. |
| **SOC-DAT-004** | UART TX FIFO buffering accepts write data and transmits serialized bitstream on `uart_tx` pad | `u_uart`, `uart_tx` pad | [`rtl/soc_top.v:174`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L174), [`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_transmitter.v:28-150`](file:///home/student/sriv_183/honour_soc/rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_transmitter.v#L28-L150) | **MEDIUM**: Console character output reliability. |
| **SOC-DAT-005** | UART RX FIFO deserializes bitstream from `uart_rx` pad and presents character data in `RBR` | `u_uart`, `uart_rx` pad | [`rtl/soc_top.v:173`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L173), [`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_receiver.v:27-140`](file:///home/student/sriv_183/honour_soc/rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_receiver.v#L27-L140) | **MEDIUM**: Console character input reliability. |
| **SOC-DAT-006** | VGA character buffer stores ASCII characters and drives 12-bit display stream (`vga_rgb[11:0]`) to video DAC | `u_vga`, AXI M06, VGA pads | [`rtl/soc_top.v:185`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L185), [`rtl/custom_ips/vga_controller.v:85-150, 214-222`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L85-L150) | **LOW**: Diagnostic visual output path. |
| **SOC-DAT-007** | AXI backpressure handling: custom IP slaves correctly stall masters via `awready/wready/arready` | All Custom IPs, M00–M06 | [`rtl/custom_ips/axi_heartbeat_monitor.v:65-75`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_heartbeat_monitor.v#L65-L75), [`rtl/custom_ips/axi_vga_controller.v:70-95`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_vga_controller.v#L70-L95) | **HIGH**: Prevents transaction drops when slaves are temporarily busy. |

---

## 6. Control Path Features (`SOC-CTRL`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-CTRL-001** | Heartbeat monitor samples `heartbeat_in` and detects rising edge pulse via `hb_prev_sample` | `u_heartbeat`, `heartbeat_in` pad | [`rtl/custom_ips/heartbeat_monitor.v:51-53`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L51-L53) | **HIGH**: Pulse detection logic is the basis of all watchdog monitoring. |
| **SOC-CTRL-002** | Heartbeat edge detection resets `hb_counter` to 0 in `COUNTING` state | `u_heartbeat`, `heartbeat_in` pad | [`rtl/custom_ips/heartbeat_monitor.v:93-96`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L93-L96) | **HIGH**: Ensures active host prevents watchdog timeouts. |
| **SOC-CTRL-003** | When `hb_counter` reaches `HB_THRESHOLD`, `hb_unresponsive_flag` sets to 1 and `hb_irq` asserts | `u_heartbeat`, `hb_irq`, AXI M03 | [`rtl/custom_ips/heartbeat_monitor.v:97-100`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L97-L100) | **HIGH**: Primary failure detection mechanism for hung host server. |
| **SOC-CTRL-004** | Heartbeat monitor state machine enters `DISABLED` when `HB_CTRL.enable=0`, resetting counter and flags | `u_heartbeat`, AXI M03 | [`rtl/custom_ips/heartbeat_monitor.v:80-87`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L80-L87) | **MEDIUM**: Allows firmware to gracefully pause watchdog during scheduled host maintenance. |
| **SOC-CTRL-005** | Reset Sequencer FSM transitions `IDLE` (`00`) -> `ASSERT` (`01`) -> `DEASSERT` (`10`) -> `IDLE` (`00`) upon `RST_CTRL.trigger=1` | `u_reset_seq`, `reset_out` pad | [`rtl/custom_ips/reset_sequencer.v:65-98`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L65-L98) | **HIGH**: Core state machine governing physical hardware power reset sequence. |
| **SOC-CTRL-006** | Reset sequencer discards secondary triggers while FSM is active (`rst_state != IDLE`) | `u_reset_seq`, AXI M04 | [`rtl/custom_ips/reset_sequencer.v:64-70`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L64-L70) | **HIGH**: Prevents FSM re-trigger collision and reset signal glitches. |
| **SOC-CTRL-007** | Recovery Policy commits staged timestamp `POL_EVENT_TS` into circular RAM upon `POL_CTRL.record_event=1` pulse | `u_rec_policy`, `u_timer`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:119-125`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L119-L125) | **HIGH**: Audit trail creation for post-mortem crash analysis. |
| **SOC-CTRL-008** | Recovery Policy increments `window_recovery_count` (`POL_STATUS[15:8]`) upon each recorded failure event | `u_rec_policy`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:133-134`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L133-L134) | **HIGH**: Crash-loop detection frequency tracking. |
| **SOC-CTRL-009** | Recovery Policy asserts sticky `POL_STATUS.lockout_flag` and generates single-cycle `lockout_irq` pulse when count >= `POL_THRESHOLD` | `u_rec_policy`, `lockout_irq`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:136-141, 161-166`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L136-L141) | **HIGH**: Crash-loop containment; alerts CPU to halt automatic rebooting. |
| **SOC-CTRL-010** | Rolling window counter resets `window_recovery_count` to 0 when `window_counter >= POL_WINDOW` | `u_rec_policy`, AXI M05 | [`rtl/custom_ips/recovery_policy.v:112-117`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L112-L117) | **HIGH**: Prevents isolated, transient resets over long periods from triggering lockout. |

---

## 7. Arbitration & Concurrency Features (`SOC-ARB`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-ARB-001** | Crossbar arbiter grants access fairly between S00 (IFU) and S01 (LSU) under simultaneous requests | `u_axi_intercon`, `arbiter.v` | [`rtl/interconnect/arbiter.v:40-75`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/arbiter.v#L40-L75), [`rtl/soc_top.v:751`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L751) | **HIGH**: Starvation prevention; instruction fetches must not indefinitely stall data accesses or vice-versa. |
| **SOC-ARB-002** | Independent read and write channels operate concurrently across non-conflicting peripheral slaves | `u_axi_intercon`, M00–M07 | [`rtl/interconnect/axi_interconnect.v:550-620`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L550-L620) | **MEDIUM**: Verifies full-duplex AXI crossbar throughput. |
| **SOC-ARB-003** | Interleaved write address (`AW`) and write data (`W`) handshakes accepted without deadlock | `u_axi_intercon`, All Slaves | [`rtl/interconnect/axi_interconnect.v:610-635`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L610-L635) | **HIGH**: AXI protocol compliance; addresses arriving before data or data before address must succeed. |
| **SOC-ARB-004** | Crossbar holds grant active across multi-beat bursts until `WLAST` or `RLAST` asserts | `u_axi_intercon`, S00, S01 | [`rtl/interconnect/axi_interconnect.v:450-480`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L450-L480) | **HIGH**: Burst atomicity; bursts must not be interleaved with beats from other masters. |

---

## 8. Interrupt Architecture & Event Dispatch Features (`SOC-IRQ`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-IRQ-001** | `uart_irq` line directly drives VeeR PIC external interrupt line 0 (`extintsrc_req[0]`) | `u_uart`, `u_veer`, PIC | [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600) | **MEDIUM**: Console character reception and transmission interrupt servicing. |
| **SOC-IRQ-002** | `hb_irq` line directly drives VeeR PIC external interrupt line 1 (`extintsrc_req[1]`) | `u_heartbeat`, `u_veer`, PIC | [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600) | **HIGH**: Watchdog timeout alert dispatch to CPU. |
| **SOC-IRQ-003** | `vblank_irq` line directly drives VeeR PIC external interrupt line 2 (`extintsrc_req[2]`) | `u_vga`, `u_veer`, PIC | [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600) | **LOW**: Display frame synchronization. |
| **SOC-IRQ-004** | `lockout_irq` single-cycle pulse directly drives VeeR PIC external interrupt line 3 (`extintsrc_req[3]`) | `u_rec_policy`, `u_veer`, PIC | [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600), [`rtl/custom_ips/recovery_policy.v:161-166`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L161-L166) | **HIGH**: Critical crash-loop emergency notification to CPU. |
| **SOC-IRQ-005** | PIC registers interrupt pending, supports priority arbitration, and signals `meip` to CPU | `u_veer`, PIC | [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600), [`core/Cores-VeeR-EL2/design/pic_ctrl/el2_pic_ctrl.sv:120`](file:///home/student/sriv_183/honour_soc/core/Cores-VeeR-EL2/design/pic_ctrl/el2_pic_ctrl.sv#L120) | **HIGH**: RISC-V privileged architecture interrupt handling compliance. |

---

## 9. Error Handling & Recovery Features (`SOC-ERR`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-ERR-001** | Out-of-bounds MMIO read returns `DECERR` (`2'b11`) with zeroed or undefined read data | `u_axi_intercon`, S01 | [`rtl/interconnect/axi_interconnect.v:734`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L734) | **HIGH**: Verifies processor receives precise bus fault on illegal read. |
| **SOC-ERR-002** | Out-of-bounds MMIO write returns `DECERR` (`2'b11`) on `bresp` channel and drops write | `u_axi_intercon`, S01 | [`rtl/interconnect/axi_interconnect.v:642`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L642) | **HIGH**: Verifies processor receives precise bus fault on illegal write. |
| **SOC-ERR-003** | Boot ROM write access handling: write response is generated without bus hang (OQ-06) | `u_rom`, S01, M07 | [`rtl/custom_ips/axi_rom.v:11-30`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_rom.v#L11-L30) | **MEDIUM**: Ensures write to read-only memory terminates cleanly without hung bus. |
| **SOC-ERR-004** | Circular event log buffer wraps cleanly from index 15 to 0 after 16 events without corruption | `u_rec_policy`, RAM | [`rtl/custom_ips/recovery_policy.v:123-125`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L123-L125) | **HIGH**: Circular buffer overflow robustness under prolonged fault conditions. |
| **SOC-ERR-005** | Firmware-enforced lockout suppression: firmware detects `lockout_flag==1` and suppresses writes to `RST_CTRL` | `u_rec_policy`, `u_reset_seq` | [`rtl/soc_top.v:1437-1472, 1490-1525`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1437-L1472), [`docs/arch/13_consistency_audit.md`](file:///home/student/sriv_183/honour_soc/docs/arch/13_consistency_audit.md) | **HIGH**: Verifies crash-loop containment policy; notes hardware does not interlock `u_reset_seq`. |

---

## 10. Clock & Reset Interaction Features (`SOC-CLK`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-CLK-001** | Synchronous reset release: all custom IP registers achieve legal reset defaults on `rst_n=0->1` | All Custom IPs, `soc_top` | [`rtl/soc_top.v:735-740`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L735-L740) | **HIGH**: Ensures deterministic state initialization across entire chip. |
| **SOC-CLK-002** | VeeR core reset sequence: `rst_l` and `dbg_rst_l` deassert synchronously with core clock | `u_veer`, `soc_top` | [`rtl/soc_top.v:1588-1589`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1588-L1589) | **HIGH**: Clean processor boot without meta-stability or pipeline corruption. |
| **SOC-CLK-003** | Synchronous video clock enable: `pixel_clk_en` pulses every 4 cycles of 100 MHz `clk`; zero CDC logic exists | `u_vga`, `clk` | [`rtl/custom_ips/vga_controller.v:53-61`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L53-L61) | **MEDIUM**: Purely synchronous single-clock domain design. |
| **SOC-CLK-004** | JTAG clock domain crossing: `jtag_tck` (25 MHz) synchronizers prevent meta-stability in debug unit | `u_veer`, `jtag_tck`, `clk` | [`rtl/soc_top.v:1575-1582`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1575-L1582) | **MEDIUM**: Debug interface reliability during active core execution. |

---

## 11. End-to-End System Scenarios (`SOC-E2E`)

| Feature ID | Feature Description | Blocks & Interfaces Involved | Source Citation | Priority & Justification |
|---|---|---|---|---|
| **SOC-E2E-001** | **Cold Boot to Firmware Loop**: Power-on reset -> Boot ROM bootloader -> Peripheral init -> Main poll loop | `u_veer`, `u_rom`, `u_uart`, Peripherals | [`firmware/start.S:8`](file:///home/student/sriv_183/honour_soc/firmware/start.S#L8), [`firmware/test/test_all.c:12`](file:///home/student/sriv_183/honour_soc/firmware/test/test_all.c#L12) | **HIGH**: Complete SoC system integration and firmware execution baseline. |
| **SOC-E2E-002** | **Normal Heartbeat Service**: Continuous external pulses arrive within window -> No timeout -> Zero resets | `u_heartbeat`, `heartbeat_in`, `hb_irq` | [`rtl/custom_ips/heartbeat_monitor.v:51-78`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L51-L78) | **HIGH**: Steady-state healthy server operation. |
| **SOC-E2E-003** | **Watchdog Timeout & Reset Recovery**: Host hangs -> `hb_irq` fires -> Firmware reads status -> Records event -> Triggers `reset_out` -> Host recovers | `u_heartbeat`, `u_rec_policy`, `u_reset_seq`, `reset_out` | [`docs/arch/05_control_path.md`](file:///home/student/sriv_183/honour_soc/docs/arch/05_control_path.md) | **HIGH**: Primary BMC autonomous remediation capability. |
| **SOC-E2E-004** | **Crash-Loop Containment (Lockout)**: Repeated failure events exceed `POL_THRESHOLD` within `POL_WINDOW` -> `lockout_irq` fires -> Firmware locks out host resets | `u_rec_policy`, `u_reset_seq`, `lockout_irq` | [`rtl/custom_ips/recovery_policy.v:136-141`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L136-L141), [`docs/arch/13_consistency_audit.md`](file:///home/student/sriv_183/honour_soc/docs/arch/13_consistency_audit.md) | **HIGH**: Protection against server reboot storms; enforced via firmware policy. |
| **SOC-E2E-005** | **Lockout Override & Resumption**: Administrator issues clear command via UART -> `POL_CTRL.clear_lockout=1` -> Lockout clears -> Watchdog monitoring resumes | `u_rec_policy`, `u_uart`, `u_heartbeat` | [`rtl/custom_ips/recovery_policy.v:148-152`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L148-L152) | **HIGH**: Operational recovery flow following administrator triage. |
| **SOC-E2E-006** | **Simultaneous Multi-Peripheral Activity**: Concurrent UART telemetry output + VGA display refresh + Heartbeat edge detection + Timer tick | All Custom IPs, AXI crossbar | Full SoC top | **MEDIUM**: Verifies system stability under concurrent stress and heavy interconnect traffic. |
