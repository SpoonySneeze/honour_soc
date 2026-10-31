# Honour SoC — Verification Realignment, JTAG Removal & Standard GPIO Implementation Report

**Document ID:** `HRSOC-CHANGE-2026-10-31`  
**Date:** October 31, 2026  
**Status:** Complete & Fully Synchronized  
**Repository:** `honour_soc`

---

## 1. Executive Summary

This document details the comprehensive engineering changes executed across the **Honour Baseboard Management Controller (BMC) SoC** repository. The updates accomplish three primary architectural objectives:
1. **Decoupling and Complete Removal of JTAG from the Verification Scope**: Eliminated obsolete JTAG tests, tied off JTAG TAP input pins in the testbench, and synchronized all verification plans.
2. **Upgrade to a Full Standard 8-bit Bidirectional GPIO Peripheral**: Replaced the legacy 2-bit read-only sensor with an industrial-standard 8-bit bidirectional GPIO IP featuring dedicated split boundary pins (`gpio_in[7:0]`, `gpio_out[7:0]`, `gpio_oe[7:0]`), complete data and direction registers, and preserved hardware status monitoring.
3. **Rigorous Test Suite and Test Plan Synchronization**: Updated all bare-metal C firmware tests, the master test plan Excel workbook ([honour_soc_verification_plan.xlsx](file:///home/student/sriv_183/honour_soc/docs/honour_soc_verification_plan.xlsx)), architectural specifications, and UVM VIP generator CSVs to achieve 100% data and mathematical consistency.

---

## 2. Inventory of Modified & Created Files

| File Path | Type | Nature of Changes |
|---|:---:|---|
| [`rtl/custom_ips/axi_gpio.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_gpio.v) | Hardware RTL | Upgraded to standard 8-bit bidirectional GPIO with `GPIO_DATA` (`0x00`), `GPIO_DIR` (`0x04`), and `GPIO_STAT` (`0x08`). |
| [`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v) | Hardware RTL | Added top-level package boundary pins `gpio_in[7:0]`, `gpio_out[7:0]`, `gpio_oe[7:0]` and connected them to `u_gpio`. |
| [`tb/tb_soc_core.v`](file:///home/student/sriv_183/honour_soc/tb/tb_soc_core.v) | Testbench | Wired GPIO boundary pins to DUT, added stimulus driver `gpio_in = 8'hA5`, and verified JTAG inputs tied low (`1'b0`). |
| [`tb/tb_soc_top.v`](file:///home/student/sriv_183/honour_soc/tb/tb_soc_top.v) | Testbench | Connected `gpio_in`, `gpio_out`, and `gpio_oe` signals in peripheral subsystem integration testbench. |
| [`firmware/test/test_common.h`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h) | C Header | Defined `GPIO_DATA` (`0x00`), `GPIO_DIR` (`0x04`), and preserved `GPIO_STAT` (`0x08`). |
| [`firmware/test/test_gpio.c`](file:///home/student/sriv_183/honour_soc/firmware/test/test_gpio.c) | C Test Suite | Upgraded to 4 rigorous subtests verifying reset defaults, output drive, input sampling, and BMC status sensing. |
| [`firmware/test/test_all.c`](file:///home/student/sriv_183/honour_soc/firmware/test/test_all.c) | C Test Suite | Expanded integrated GPIO test to exercise direction configuration, data writing, input readback, and status checking. |
| [`firmware/main.c`](file:///home/student/sriv_183/honour_soc/firmware/main.c) | C Application | Updated `TEST 2` to exercise `GPIO_DIR`, `GPIO_DATA`, and `GPIO_STAT`. |
| [`docs/Register_Map.md`](file:///home/student/sriv_183/honour_soc/docs/Register_Map.md) | Documentation | Documented `GPIO_DATA` (`0x00`), `GPIO_DIR` (`0x04`), `GPIO_STAT` (`0x08`) bitfields and operation. |
| [`docs/honour_soc_verification_plan.xlsx`](file:///home/student/sriv_183/honour_soc/docs/honour_soc_verification_plan.xlsx) | Master Excel Plan | Removed 3 JTAG tests, added `PER-07` GPIO external test, added `interface signals` column, updated Summary to 55 tests. |
| [`docs/arch/14_testplan.md`](file:///home/student/sriv_183/honour_soc/docs/arch/14_testplan.md) | Test Plan | Added GPIO boundary pins to top-level interface table, updated test counts to 55, documented JTAG exclusion. |
| [`docs/arch/17_whole_soc_testplan_realignment_report.md`](file:///home/student/sriv_183/honour_soc/docs/arch/17_whole_soc_testplan_realignment_report.md) | Architecture Report | Realignment report updated to 55 tests (45 Internal, 10 External), added `PER-07` to master taxonomy. |
| [`docs/vip_inf_sigs.csv`](file:///home/student/sriv_183/honour_soc/docs/vip_inf_sigs.csv) | UVM Configuration | Cleaned up duplicate `reset_out`, added `gpio_in`, `gpio_out`, `gpio_oe` for automated testbench generation. |
| [`docs/vip_interface_signals.csv`](file:///home/student/sriv_183/honour_soc/docs/vip_interface_signals.csv) | UVM VIP Catalog | Documented all 12 external boundary signals from the VIP point of view (Input vs. Output). |

---

## 3. Detailed Architectural & Implementation Changes

### 3.1 JTAG Removal from Verification Scope
* **Context**: JTAG is not utilized in the active scope of the server BMC SoC project.
* **Verification Plan Changes**:
  * Removed **`SOC-006`** (`TP-CLK-03`): JTAG clock domain crossing.
  * Removed **`XBR-004`** (`TP-DEC-03`): System Bus `S02` debug access blocked from peripherals `M00`–`M06`.
  * Removed **`XBR-005`** (`TP-DEC-04`): System Bus `S02` read Boot ROM `M07`.
* **Hardware & Testbench Quiescence**:
  * In [tb/tb_soc_core.v](file:///home/student/sriv_183/honour_soc/tb/tb_soc_core.v#L123-L125), `jtag_tck`, `jtag_tms`, and `jtag_tdi` are permanently tied to `1'b0`.
  * The VeeR core TAP controller remains permanently in Test-Logic-Reset, preventing spurious transactions.

---

### 3.2 Upgrade to Standard 8-bit Bidirectional GPIO

#### A. Pin Configuration
The GPIO IP was upgraded from a 2-bit read-only hardware sensor to an industrial standard 8-bit general-purpose I/O controller with split boundary pins:
* `input wire [7:0] gpio_in`: Samples external physical input logic levels.
* `output wire [7:0] gpio_out`: Drives external physical output logic levels.
* `output wire [7:0] gpio_oe`: Output enable control (`1` = active drive, `0` = input / high-Z mode).

#### B. Register Architecture (`Base: 0x0002_0200`)
* **`0x0002_0200` (`GPIO_DATA`) [R/W]**:
  * **Write**: Updates `gpio_out[7:0]`.
  * **Read**: Returns `(gpio_in & ~gpio_oe) | (gpio_out & gpio_oe)`.
* **`0x0002_0204` (`GPIO_DIR`) [R/W]**:
  * **Direction / Tri-state Control**: Sets `gpio_oe[7:0]`. Reset value is `0x0000_0000` (all pins default to input mode).
* **`0x0002_0208` (`GPIO_STAT`) [RO]**:
  * Preserves backward compatibility: Bit 0 = `heartbeat_in`, Bit 1 = `reset_out` (deasserted high = 1). All existing watchdog recovery tests continue to pass without regression.

---

### 3.3 Testbench Integration
* [tb_soc_core.v](file:///home/student/sriv_183/honour_soc/tb/tb_soc_core.v): Instantiates `soc_top` with `.gpio_in(gpio_in)`, `.gpio_out(gpio_out)`, `.gpio_oe(gpio_oe)`. Testbench stimulates `gpio_in` with `8'hA5`.
* [tb_soc_top.v](file:///home/student/sriv_183/honour_soc/tb/tb_soc_top.v): Wires `u_gpio` with `gpio_in`, `gpio_out_w`, and `gpio_oe_w`.

---

### 3.4 Bare-Metal C Firmware Suite Updates
* [test_common.h](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h): Added `#define GPIO_DATA` (`0x00`), `#define GPIO_DIR` (`0x04`), and shifted `#define GPIO_STAT` to `0x08`.
* [test_gpio.c](file:///home/student/sriv_183/honour_soc/firmware/test/test_gpio.c):
  * **Subtest 1**: `GPIO_DIR` reset value verification (`0x00`) and output mode configuration (`0xFF`).
  * **Subtest 2**: `GPIO_DATA` output writing and loopback verification (`0x5A`, `0x3C`).
  * **Subtest 3**: `GPIO_DATA` input mode external pin sampling (`0xA5`).
  * **Subtest 4**: `GPIO_STAT` hardware status sensing validation.
* [test_all.c](file:///home/student/sriv_183/honour_soc/firmware/test/test_all.c): Updated integrated peripheral run `run_test_gpio()` to test direction, data writing, pin sampling, and BMC status.
* [main.c](file:///home/student/sriv_183/honour_soc/firmware/main.c): Updated `TEST 2` in the standalone boot application.

---

### 3.5 Master Verification Plan Updates (`honour_soc_verification_plan.xlsx`)
1. **New Test Case `PER-07` Added**:
   * **Test ID**: `PER-07` (`TP-DAT-07` in Trace sheet).
   * **Title**: `GPIO 8-bit bidirectional data and direction control`.
   * **C Test**: `test_gpio.c`.
   * **SV Test**: `soc_gpio_bidir_test`.
   * **Classification**: `External` (involves physical boundary pins `gpio_in`, `gpio_out`, `gpio_oe`).
2. **Dedicated Column Added**:
   * Added Column **`H`** (`interface signals`) to all 8 subsystem sheets.
   * Added Column **`K`** (`interface signals`) to the `Trace` sheet.
3. **Audit Verification**:
   * Verified with automated audit script: **0 mismatches** between subsystem sheets, Summary formulas, and the Trace sheet.

---

## 4. Final Verification Metrics Matrix

| Subsystem Sheet | Total Tests | C Firmware Tests | SV / UVM Tests | Internal Tests | External Tests | Physical Boundary Signals |
|---|:---:|:---:|:---:|:---:|:---:|---|
| **`SoC`** (Bring-up, DCCM, ECC) | **8** | 8 | 8 | 6 | **2** | `rst_n, clk` |
| **`XBAR`** (Interconnect Crossbar) | **10** | 10 | 10 | 10 | **0** | *None (100% on-chip internal)* |
| **`HBM`** (Heartbeat Watchdog) | **5** | 5 | 5 | 3 | **2** | `heartbeat_in` |
| **`RSTSEQ`** (Reset Sequencer) | **6** | 6 | 6 | 6 | **0** | *None (internal CSRs & FSM)* |
| **`POL`** (Recovery Policy & Log) | **10** | 10 | 10 | 10 | **0** | *None (internal circular RAM)* |
| **`PERIPH`** (UART, VGA & GPIO) | **7** | 7 | 7 | 4 | **3** | `uart_rx/tx`, `pixel_clk`, `gpio_*` |
| **`IRQ`** (PIC Interrupt Controller) | **4** | 4 | 4 | 2 | **2** | `uart_rx`, `vblank` |
| **`System`** (End-to-End Remediation)| **5** | 5 | 5 | 4 | **1** | `heartbeat_in, reset_out, uart_tx` |
| **Total** | **55** | **55 (100%)** | **55 (100%)** | **45** | **10** | **4 Physical Interfaces** |

---

## 5. External Interface Signals Catalog (10 External Tests)

```
                       ┌────────────────────────────────────────────────────────┐
                       │          Honour SoC Top-Level Boundary Pins            │
                       ├──────────────────────┬─────────────┬───────────────────┤
                       │ Signal Name          │ Direction   │ Bit Width         │
                       ├──────────────────────┼─────────────┼───────────────────┤
                       │ clk                  │ Input       │ 1-bit             │
                       │ rst_n                │ Input       │ 1-bit             │
                       │ heartbeat_in         │ Input       │ 1-bit             │
                       │ reset_out            │ Output      │ 1-bit             │
                       │ uart_rx              │ Input       │ 1-bit             │
                       │ uart_tx              │ Output      │ 1-bit             │
                       │ vga_hsync            │ Output      │ 1-bit             │
                       │ vga_vsync            │ Output      │ 1-bit             │
                       │ vga_rgb              │ Output      │ 12-bit (RGB444)   │
                       │ gpio_in              │ Input       │ 8-bit             │
                       │ gpio_out             │ Output      │ 8-bit             │
                       │ gpio_oe              │ Output      │ 8-bit             │
                       └──────────────────────┴─────────────┴───────────────────┘
```
