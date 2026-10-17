# SoC Architecture & Verification Consistency Audit

**Document ID:** `docs/arch/13_consistency_audit.md`  
**Stage:** Task 13 — Consistency Audit across Verification Architecture Documents and RTL Codebase  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Audited across [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) through [`docs/arch/12_test_plan_draft.md`](file:///home/student/sriv_183/honour_soc/docs/arch/12_test_plan_draft.md), [`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v), [`rtl/custom_ips/*`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/), and [`firmware/test/test_common.h`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h).

---

## 1. Executive Summary of Consistency Audit

A comprehensive, line-by-line audit was conducted comparing the verifiable feature catalog ([`10_features.md`](file:///home/student/sriv_183/honour_soc/docs/arch/10_features.md)), UVM agent interface definitions ([`11_agent_interfaces.md`](file:///home/student/sriv_183/honour_soc/docs/arch/11_agent_interfaces.md)), and draft verification test plan ([`12_test_plan_draft.md`](file:///home/student/sriv_183/honour_soc/docs/arch/12_test_plan_draft.md)) against the authoritative address map ([`04_address_map.md`](file:///home/student/sriv_183/honour_soc/docs/arch/04_address_map.md)), firmware header definitions ([`firmware/test/test_common.h`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h)), and synthesizable RTL source files.

The audit revealed multiple naming discrepancies, architectural deviations, and imaginary hardware features that had carried over from speculative design documents rather than reflecting the actual synthesizable RTL. 

---

## 2. Master Table of Discrepancies & Mismatches

| Discrepancy ID | Document & Location | Target Item / Field | Claimed Value in Document | Actual Value in RTL & Firmware | Authoritative RTL Source Citation | Impact & Resolution |
|---|---|---|---|---|---|---|
| **DISC-01** | `10_features.md`, `12_test_plan_draft.md` | Interconnect Slave Numbering for Peripherals | M00=Timer, M01=GPIO, M02=UART, M03=VGA, M04=HB, M05=RST, M06=POL | **M00=UART, M01=Timer, M02=GPIO, M03=HB, M04=RST, M05=POL, M06=VGA, M07=ROM** | [`rtl/soc_top.v:759-809`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L759-L809), [`firmware/test/test_common.h:9-15`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L9-L15) | **Critical**: Slave numbers were swapped/scrambled. Realign to match `soc_top.v` parameter mapping and `04_address_map.md`. |
| **DISC-02** | `10_features.md:SOC-RST-006`, `12_test_plan_draft.md:TP-RST-04` | Manual Override Register Fields in Reset Sequencer | `RST_CTRL.manual_en`, `RST_CTRL.manual_val` | **NOT FOUND / DOES NOT EXIST**. `RST_CTRL` contains only bit 0 (`trigger_req`). | [`rtl/custom_ips/reset_sequencer.v:45-56`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L45-L56), [`firmware/test/test_common.h:46`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L46) | **High**: Remove feature and test from test plan; marked as unsupported hardware feature. |
| **DISC-03** | `10_features.md:SOC-RST-004`, `12_test_plan_draft.md:TP-RST-03` | Reset Sequencer Duration Register Name | `RST_DURATION` | **`RST_HOLD_CYCLES`** (Address Offset `0x04`) | [`rtl/custom_ips/reset_sequencer.v:20, 52`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L20), [`firmware/test/test_common.h:47`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L47) | **Medium**: Correct register name across all docs. Note default reset value is `32'd100`, not 0. |
| **DISC-04** | `10_features.md:SOC-REG-003` | Reset Sequencer Real-Time Down-Counter Register | `RST_COUNTER` (Offset `0x0C`) | **NOT FOUND / DOES NOT EXIST**. Internal signal `rst_countdown` is not memory-mapped. | [`rtl/custom_ips/reset_sequencer.v:58-64`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L58-L64) | **Medium**: Remove `RST_COUNTER` from register lists; verify countdown strictly via internal hierarchical probe/bind. |
| **DISC-05** | `10_features.md:SOC-REG-004`, `SOC-CTRL-009` | Recovery Policy Threshold Register Name | `POL_MAX_RESETS` | **`POL_THRESHOLD`** (Address Offset `0x08`, 8-bit width, reset default `8'd3`) | [`rtl/custom_ips/recovery_policy.v:36, 85`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L36), [`firmware/test/test_common.h:53`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L53) | **Medium**: Correct register name and bit-width. |
| **DISC-06** | `10_features.md:SOC-REG-004`, `SOC-CTRL-008` | Recovery Policy Window Counter Register Name | `POL_WINDOW_COUNT` (as separate register) | **`POL_STATUS[15:8]`** (`window_recovery_count` field within status register) | [`rtl/custom_ips/recovery_policy.v:107`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L107), [`firmware/test/test_common.h:54`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L54) | **Medium**: Clarify that window recovery count is a bitfield of `POL_STATUS`, not a separate register. |
| **DISC-07** | `10_features.md:SOC-REG-010`, `12_test_plan_draft.md:TP-REG-04` | Event Log Index Selector Register Name | `POL_LOG_INDEX` | **`LOG_READ_IDX`** (Address Offset `0x14`, 4-bit width) | [`rtl/custom_ips/recovery_policy.v:39, 90`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L39), [`firmware/test/test_common.h:56`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L56) | **Medium**: Correct register name. |
| **DISC-08** | `10_features.md:SOC-REG-010`, `12_test_plan_draft.md:TP-REG-04` | Event Log Data Readout Register Name | `POL_LOG_TIMESTAMP` | **`LOG_READ_DATA`** (Offset `0x18`, RO) for read; **`POL_EVENT_TS`** (Offset `0x10`, WO) for write staging | [`rtl/custom_ips/recovery_policy.v:40-41, 108`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L40-L41), [`firmware/test/test_common.h:55-57`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L55-L57) | **High**: Clarify distinct staging register (`POL_EVENT_TS`) and log read register (`LOG_READ_DATA`). |
| **DISC-09** | `10_features.md:SOC-REG-001`, `SOC-DAT-001` | Heartbeat Monitor Counter Register Name | `HB_COUNTER` | **`HB_ELAPSED`** (Address Offset `0x0C`, RO) | [`rtl/custom_ips/heartbeat_monitor.v:23, 76`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L23), [`firmware/test/test_common.h:43`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L43) | **Low**: Correct register name from `HB_COUNTER` to `HB_ELAPSED`. |
| **DISC-10** | `10_features.md:SOC-IRQ-006`, `12_test_plan_draft.md:TP-IRQ-02` | Heartbeat Interrupt Masking Bit | `HB_CTRL.irq_en` | **NOT FOUND / DOES NOT EXIST**. `HB_CTRL` has only bit 0 (`enable`) and bit 1 (`clear_flag`). `hb_irq` is directly assigned `hb_unresponsive_flag`. | [`rtl/custom_ips/heartbeat_monitor.v:39, 58-61`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L39), [`firmware/test/test_common.h:40`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L40) | **High**: Remove `HB_CTRL.irq_en` masking test. Note that `hb_irq` can only be suppressed at the core PIC level, not inside `heartbeat_monitor`. |
| **DISC-11** | `10_features.md:SOC-DEC-001` | Core Instruction Memory Integration | ICCM at `0xEE00_0000`–`0xEE07_FFFF` (64 KB) | **NOT CONNECTED / TIED OFF**. VeeR ICCM export interface is tied to 0 in `soc_top.v:1841-1845`. Core boots strictly from Boot ROM (`0x8000_0000`). | [`rtl/soc_top.v:1841-1845`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1841-L1845), [`firmware/link.ld:4-10`](file:///home/student/sriv_183/honour_soc/firmware/link.ld#L4-L10) | **Critical**: ICCM at `0xEE00_0000` is from an outdated proposal document; actual hardware ties off ICCM and uses 8KB Boot ROM (`u_rom`) + 64KB DCCM (`u_dccm_bank`). |
| **DISC-12** | `10_features.md:SOC-REG-007`, `11_agent_interfaces.md` | External GPIO Pins and Direction Registers | 32-bit bidirectional `gpio_pins` with direction & output registers | **NOT FOUND / DOES NOT EXIST**. `soc_top` has NO external GPIO pins. `axi_gpio` is a 2-bit read-only status register sampling `heartbeat_in` and `reset_out_internal`. | [`rtl/soc_top.v:162-186, 1346-1354`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L162-L186), [`rtl/custom_ips/axi_gpio.v:4-8`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_gpio.v#L4-L8) | **Critical**: Remove external GPIO agent and direction/data registers. Document `axi_gpio` strictly as a pin-sensing status register. |
| **DISC-13** | `10_features.md`, `11_agent_interfaces.md` | UART Top-Level Port Names | `uart_rxd`, `uart_txd` | **`uart_rx`**, **`uart_tx`** | [`rtl/soc_top.v:173-174`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L173-L174) | **Low**: Update signal names to match top-level netlist ports. |
| **DISC-14** | `10_features.md`, `11_agent_interfaces.md` | VGA RGB Bus Width | 3-bit or 8-bit RGB (`vga_rgb`) | **12-bit width: `[11:0] vga_rgb`** (4-bit R, 4-bit G, 4-bit B) | [`rtl/soc_top.v:185`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L185), [`rtl/custom_ips/vga_controller.v:214-222`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L214-L222) | **Medium**: Correct signal width across all agent interfaces and test descriptions. |
| **DISC-15** | `10_features.md:SOC-CLK-003`, `11_agent_interfaces.md`, `12_test_plan_draft.md:TP-CLK-01` | Pixel Clock Domain Crossing & CDC FIFOs | Asynchronous dual-clock CDC domain (`pixel_clk` 25 MHz) with CDC FIFOs | **NOT FOUND / DOES NOT EXIST**. Entire VGA engine is single synchronous domain on `clk` (100 MHz) with a 1-in-4 clock enable `pixel_clk_en`. Zero CDC logic exists. | [`rtl/custom_ips/vga_controller.v:53-61`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L53-L61) | **Critical**: Delete CDC test and CDC failure modes. VGA controller is 100% synchronous. |
| **DISC-16** | `10_features.md:SOC-ERR-005`, `12_test_plan_draft.md:TP-ERR-03` | Hardware Lockout Suppression of Reset Trigger | Hardware interlock in `reset_sequencer` blocks `RST_CTRL.trigger` when locked | **NOT CONNECTED IN HARDWARE / FIRMWARE-ONLY**. `reset_sequencer` has NO hardware input from `recovery_policy`. Lockout is enforced strictly by firmware logic. | [`rtl/soc_top.v:1437-1472, 1490-1525`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1437-L1472), [`rtl/custom_ips/reset_sequencer.v:10-23`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L10-L23) | **Critical**: In hardware, `reset_sequencer` will happily trigger even when `lockout_flag == 1`. Lockout safety is a firmware responsibility. |

---

## 3. Explicit Focus Check Details

### 3.1 `manual_en` and `manual_val` in `reset_sequencer`
- **Claimed in `10_features.md` & `12_test_plan_draft.md`**: `RST_CTRL.manual_en = 1` forces `reset_out` to `RST_CTRL.manual_val`.
- **RTL Reality ([`rtl/custom_ips/reset_sequencer.v:45-56`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L45-L56))**:
  ```verilog
  case (reg_addr)
      ADDR_RST_CTRL:        trigger_req <= reg_wdata[0];
      ADDR_RST_HOLD_CYCLES: rst_hold_cycles_reg <= reg_wdata;
  endcase
  ```
  Only bit 0 (`trigger_req`) is parsed. Bits [31:1] are ignored. Manual override logic is **NOT FOUND**.

### 3.2 `RST_DURATION` vs `RST_HOLD_CYCLES` and `RST_COUNTER`
- **Register Name**: RTL defines `ADDR_RST_HOLD_CYCLES = 8'h04`. Default reset value is `32'd100` ([`reset_sequencer.v:47`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L47)).
- **Counter Accessibility**: `rst_countdown` is an internal FSM down-counter ([`reset_sequencer.v:28`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L28)). It has no memory-mapped register address.

### 3.3 `POL_MAX_RESETS`, `POL_LOG_INDEX`, `POL_LOG_TIMESTAMP`, and `POL_WINDOW_COUNT`
- **Threshold**: Register at `0x08` is `POL_THRESHOLD` (8-bit width, reset default `8'd3`), not `POL_MAX_RESETS`.
- **Log Index**: Register at `0x14` is `LOG_READ_IDX` (4-bit width), not `POL_LOG_INDEX`.
- **Log Data**: Register at `0x18` is `LOG_READ_DATA` (RO, 32-bit), not `POL_LOG_TIMESTAMP`. Write staging occurs via `POL_EVENT_TS` at `0x10`.
- **Window Count**: `window_recovery_count` is read from `POL_STATUS[15:8]`; there is no standalone `POL_WINDOW_COUNT` register.

### 3.4 `HB_CTRL.irq_en`
- **Claimed**: Disabling `HB_CTRL.irq_en` suppresses `hb_irq` assertion.
- **RTL Reality ([`rtl/custom_ips/heartbeat_monitor.v:39`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L39))**:
  ```verilog
  assign hb_irq = hb_unresponsive_flag;
  ```
  There is NO interrupt mask bit in `HB_CTRL`. Interrupt masking can only occur at the core PIC level (`el2_pic_ctrl.sv`).

### 3.5 Core Instruction Memory (`ICCM` at `0xEE00_0000`)
- **Claimed**: Instruction fetch routes to 64KB ICCM at `0xEE00_0000`–`0xEE07_FFFF`.
- **RTL Reality ([`rtl/soc_top.v:1841-1845`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1841-L1845), [`firmware/link.ld:4-10`](file:///home/student/sriv_183/honour_soc/firmware/link.ld#L4-L10))**:
  ```verilog
  // Tie off unused ICCM export interface
  for (genvar b = 0; b < 4; b = b + 1) begin : gen_iccm_tieoff
      assign el2_mem_export.iccm_bank_dout[b] = 32'd0;
      assign el2_mem_export.iccm_bank_ecc[b]  = 7'd0;
  end
  ```
  ICCM is uninstantiated and tied off. Instructions execute from Boot ROM (`0x8000_0000`) and DCCM (`0xF004_0000`).

### 3.6 GPIO Pins and Interfaces
- **Claimed**: 32-bit bidirectional GPIO port `gpio_pins` with direction registers.
- **RTL Reality ([`rtl/soc_top.v:162-186, 1346-1354`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L162-L186), [`rtl/custom_ips/axi_gpio.v:4-8`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_gpio.v#L4-L8))**:
  Top-level module `soc_top` has no GPIO pins. `axi_gpio` provides a single read-only register `GPIO_STAT` (`0x0002_0200`) sampling bit 0 (`heartbeat_in`) and bit 1 (`reset_out_internal`).

### 3.7 UART and VGA Boundary Ports
- **UART**: Top-level netlist ports are `uart_rx` (in) and `uart_tx` (out) ([`soc_top.v:173-174`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L173-L174)).
- **VGA RGB**: Output is `output wire [11:0] vga_rgb` (12 bits) ([`soc_top.v:185`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L185)).

### 3.8 Pixel Clock Domain & CDC Analysis
- **Claimed**: Dual-clock domain crossing with CDC FIFOs between 100 MHz bus clock and 25 MHz pixel clock.
- **RTL Reality ([`rtl/custom_ips/vga_controller.v:53-61`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L53-L61))**:
  ```verilog
  always @(posedge clk) begin
      if (!rst_n)
          pixel_clk_div <= 2'd0;
      else
          pixel_clk_div <= pixel_clk_div + 2'd1;
  end
  assign pixel_clk_en = (pixel_clk_div == 2'd0);
  ```
  The entire VGA controller runs synchronously on `clk` (100 MHz). Beam counters and video outputs update on `pixel_clk_en`. There are NO CDC FIFOs, no separate clock domain, and no metastability risks between bus and video logic.

---

## 4. Hardware vs. Firmware Lockout Determination

**Question**: Does `reset_sequencer` have any hardware input from `recovery_policy`'s `lockout_flag`, or is crash-loop lockout enforcement firmware-only?

**Determination**: **LOCKOUT ENFORCEMENT IS STRICTLY FIRMWARE-ONLY.**

**Evidence from RTL**:
1. In [`rtl/soc_top.v:1437-1472`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1437-L1472), `u_reset_seq` is instantiated with only AXI4 bus ports, `clk`, `rst_n`, and `reset_out`. It has NO input port for `lockout_flag` or `lockout_irq`.
2. In [`rtl/custom_ips/reset_sequencer.v:7-23`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L7-L23), module `reset_sequencer` has NO hardware lockout input port. The FSM transitions to `ST_ASSERT` unconditionally upon receiving `trigger_req` while in `ST_IDLE`.
3. In [`rtl/soc_top.v:1490-1525`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1490-L1525), `u_rec_policy` outputs `lockout_irq`, which routes directly to `u_veer.extintsrc_req[3]` ([`soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600)).
4. **Verification Implication**: If firmware writes `RST_CTRL.trigger = 1` while `POL_STATUS.lockout_flag == 1`, hardware **WILL** assert `reset_out`. Hardware does not block it. System safety relies entirely on firmware honoring `lockout_flag` / `lockout_irq` and refraining from triggering `reset_sequencer`.
