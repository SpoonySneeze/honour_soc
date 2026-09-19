# UART IP Core Ingestion and Verdi RC Waveform Report

**Date:** September 19, 2026  
**Repository:** `honour_soc`  
**Location of Ingested IP:** `rtl/ips/axi-lite_uart-ipcore-develop`  
**Status:** Ingested (Stand-alone Verified, NOT integrated into `soc_top.v`), All Tests Passing (8/8)  

---

## 1. Overview & Objectives

In accordance with user directives:
1. **IP Ingestion:** Import the AXI-Lite UART IP core from `/home/student/sriv_183/IPs/axi-lite_uart-ipcore-develop` into `rtl/ips/axi-lite_uart-ipcore-develop`.
2. **No Top-Level Integration:** The core is maintained in a stand-alone verification state and is **not** integrated into `rtl/soc_top.v`.
3. **Stand-Alone Verification:** Compile and execute the full testbench (`tb_axi_uart.v`) using Synopsys VCS to verify functionality.
4. **Verdi `.rc` Configuration:** Generate comprehensive Verdi signal restore files (`.rc`) for all simulation wave dumps (`.fsdb`), enabling categorized, hierarchical waveform viewing.
5. **Regression Verification:** Ensure SoC regression and top-level compilation remain 100% clean with zero regressions.
6. **Strict Exclusions:** Ensure `rtl/ips/aes_core/` remains entirely unmodified and untouched.

---

## 2. Ingested IP Architecture & Features

The ingested IP is a configurable **AXI4-Lite UART IP Core** with decoupled clock domains and internal FIFO buffers:
- **Module Name:** `axi_uart_top`
- **Bus Interface:** 32-bit AXI4-Lite Slave (`axi_aclk_i`, `axi_aresetn_i`)
- **UART Core Clock:** Independent `fixed_clk_i` domain with synchronizers
- **TX Path:** 16-deep internal FIFO (`axi_internal_fifo`) $\to$ Serial Transmitter (`uart_transmitter`)
- **RX Path:** Serial Receiver (`uart_receiver`) $\to$ 16-deep internal FIFO $\to$ AXI Read
- **Interrupt:** `read_interrupt_o` asserted when data is available in RX FIFO and enabled in IER

### Register Map (Word-Aligned, 5-bit Address Bus)

| Offset | Index (`addr[4:2]`) | Name | Mode | Description |
|---|---|---|---|---|
| `0x00` | 0 | **THR** | WO (`DLAB=0`) | Transmit Holding Register (data to send) |
| `0x00` | 0 | **RBR** | RO (`DLAB=0`) | Receiver Buffer Register (received data) |
| `0x04` | 1 | **IER** | WO (`DLAB=0`) | Interrupt Enable Register (`bit[0]` = RX IRQ enable) |
| `0x08` | 2 | **BAUD_DIV** | WO (`DLAB=1`) | Baud Rate Clock Divisor Register |
| `0x0C` | 3 | **LCR** | WO | Line Control Register (Stop bits, Parity, DLAB) |
| `0x14` | 5 | **LSR** | RO | Line Status Register (`bit[0]` = DR, `bit[5]` = THRE, `bit[6]` = TEMT) |

---

## 3. Testbench Verification Results

The IP was verified using its native VCS testbench (`bench/verilog/tb_axi_uart.v`) via `./run.csh all`.

### Execution Summary
```
=====================================================
 AXI-lite UART Testbench Starting
=====================================================

--- Test 1: LSR Reset State ---
PASS [LSR[THRE] reset=1]: 1
PASS [LSR[TEMT] reset=1]: 1
PASS [LSR[DR]   reset=0]: 0
PASS [RBR reset=0]: 0x00000000

--- Test 2: LCR Write (write-only) ---
PASS [LCR write parity_en=1]: accepted (write-only reg)
PASS [LCR write restored=0]: accepted

--- Test 3: IER Write / Interrupt ---
PASS [IRQ deasserted (IER=0, empty FIFO)]: 0

--- Test 4: DLAB Baud Divisor Write ---
PASS [BAUD divisor set to 100]: accepted
PASS [LSR[THRE]=1 after baud config]: 1

--- Test 5: TX Path ---
PASS [LSR[THRE]=1 after TX]: 1
PASS [LSR[TEMT]=1 after TX]: 1

--- Test 6: Single Byte Loopback ---
PASS [Loopback 0x55]: 0x55

--- Test 7: DATA_READY & Interrupt ---
PASS [LSR DATA_READY set]: 1
PASS [read_interrupt asserted]: 1
PASS [RBR byte 0xC3]: 0xc3
PASS [LSR DATA_READY cleared]: 0

--- Test 8: Multi-Byte Loopback ---
PASS [Multi-byte loopback]: 0xde
PASS [Multi-byte loopback]: 0xad
PASS [Multi-byte loopback]: 0xbe
PASS [Multi-byte loopback]: 0xef

=====================================================
 ALL TESTS PASSED
=====================================================
```
- **Total Tests:** 8
- **Passed:** 8
- **Failed:** 0
- **Waveform Dump:** `sim/vcs/wave.fsdb` (71,135,000 ps)

---

## 4. Verdi `.rc` Signal Configuration Files

To fulfill the user request (*"write a .rc file for every fsdb we do when re run verdi for them"*), standard Verdi session restore files (`.rc`) were established:

1. **UART IP Wave Configuration:**
   - **Path:** `rtl/ips/axi-lite_uart-ipcore-develop/waves/uart_wave.rc`
   - **Integrated with:** `./run.csh verdi`
   - **Groups:**
     - Group 1: Clock & Reset (`fixed_clk`, `axi_clk`, `aresetn`)
     - Group 2: AXI Write Address Channel (AW)
     - Group 3: AXI Write Data Channel (W)
     - Group 4: AXI Write Response Channel (B)
     - Group 5: AXI Read Address Channel (AR)
     - Group 6: AXI Read Data Channel (R)
     - Group 7: UART FSM & Clock Domain Sync (`write_state`, `read_state`, `axi_sync_wren`, `axi_sync_rden`)
     - Group 8: UART Control & Status Registers (`LCR`, `LSR`, `BAUD`, `IER`)
     - Group 9: UART Serial Interface (`uart_tx`, `uart_rx`, `read_interrupt`)
     - Group 10: TX Path & FIFO
     - Group 11: RX Path & FIFO
     - Group 12: UART Transmitter Core FSM & State
     - Group 13: UART Receiver Core FSM & State

2. **AXI Interconnect 2x7 Wave Configuration:**
   - **Path:** `waves/axi_interconnect_wave.rc`
   - **Integrated with:** `make waves_axi`
   - **Groups:** Clock & Reset, Master 0 (LSU), Master 1 (SB), Slaves 0..6 (UART, Timer, GPIO, HB Mon, Reset Seq, Rec Policy, VGA)

3. **SoC Top-Level System Wave Configuration:**
   - **Path:** `waves/soc_top_wave.rc`
   - **Integrated with:** `make waves_soc`
   - **Groups:** Clock & Reset, Host AXI Master Interface, SoC External Pins, Heartbeat Monitor, Reset Sequencer, Recovery Policy, UART & VGA Displays

---

## 5. System Regression & Integration Verification

To ensure seamless compatibility across all verification flows, `tb/tb_axi_interconnect.v` and `tb/tb_soc_top.v` were upgraded with conditional `$test$plusargs("fsdb")` support, and `Makefile` was updated to generate FSDB waveforms and automatically launch Verdi with the corresponding `.rc` file.

Full regression test results:
- **`sim_hbm`:** PASSED
- **`sim_rst`:** PASSED
- **`sim_pol`:** PASSED
- **`sim_axi`:** 18/18 assertions PASSED (`tb_axi_interconnect.fsdb` generated)
- **`sim_soc`:** 17/17 assertions PASSED (`tb_soc_top.fsdb` generated)
- **`compile_top`:** PASSED (0 errors, 0 warnings)
- **`rtl/ips/aes_core/`:** UNMODIFIED (Verified via git status)
