# Honour SoC Verification Plan Realignment Report: Whole-SoC Architecture & Boundary-Pin Classification

**Document ID:** `HRSOC-VERIF-SOC-REALIGN-001`  
**Date:** October 31, 2026  
**Target Repository:** `honour_soc` (Full-SoC Verification Architecture)  
**Target Artifacts:** `docs/honour_soc_verification_plan.xlsx`, `docs/arch/14_testplan.md`  

---

## 1. Executive Summary & Verification Paradigm

This report formally documents the comprehensive realignment of the **Honour SoC Verification Plan** ([honour_soc_verification_plan.xlsx](file:///home/STUDENT/Documents/sriv_183/honour_soc/docs/honour_soc_verification_plan.xlsx)) and related architectural test plan documentation ([14_testplan.md](file:///home/STUDENT/Documents/sriv_183/honour_soc/docs/arch/14_testplan.md)).

The realignment establishes two fundamental verification principles:

1. **Whole-SoC Verification Scope**:  
   The primary Device Under Test (DUT) is the **complete, unified Honour SoC** (`soc_top.v` with the embedded synthesizable VeeR EL2 RISC-V processor active). Individual internal IP blocks (3x8 AXI4 Interconnect, Heartbeat Watchdog Monitor, Power/Reset Sequencer, Recovery Policy, UART 16550, VGA Controller, System Timer, GPIO, and DCCM) are **not** verified in isolation through stubbed sub-block testbenches. Rather, **the SoC verifies its own internal IPs from within** by executing dedicated bare-metal C firmware suites (`firmware/test/*.c`).
2. **Strict Physical Boundary-Pin Classification Rule**:  
   - **Internal Tests**: Stimulus is initiated, routed, executed, and checked entirely within the physical boundary of the SoC by software running on the VeeR EL2 processor on internal on-chip buses (`s00_axi_*`, `s01_axi_*`, `s02_axi_*`, `m00..m07_axi_*`, DCCM). **Zero physical chip boundary signals are involved.**
   - **External Tests**: Tests that require direct stimulus injection across, or response observation at, the **outer physical chip boundary I/O pins** of `soc_top` (`rst_n`, `heartbeat_in`, `uart_rx`, `uart_tx`, `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo`, `vga_hsync`, `vga_vsync`, `vga_rgb[11:0]`).

---

## 2. Root Cause of Prior Misalignment

In legacy verification drafts (inherited from earlier UVM testbench templates):
* A dual-bench methodology (**Bench A** vs. **Bench B**) was originally proposed.
* In **Bench B** (`tb_soc_stub`), the VeeR EL2 CPU core was removed and replaced with an external AXI Master VIP attached to internal bus port `S01` (`lsu_axi_*`).
* **The Flaw**: By stubbing out the core and pulling internal bus `S01` out as a port of `soc_top_stub`, internal interconnect and peripheral tests (`XBR-001` through `XBR-007`, `XBR-010`, `XBR-012`, `SOC-004`, `SOC-005`) were designated as `c tests = n/a` and erroneously labeled `External`.
* **The Reality**: In silicon, `S01` has no physical pad or pin; it is an on-chip wire. In a true whole-SoC test plan, testing interconnect routing, CSR read/writes, and backpressure must be performed **internally by the processor itself** via software, making those tests strictly **Internal**.

---

## 3. Inventory of Changes Made

### 3.1 C Firmware Assignment & Scope Refinement
Every single test row across the entire verification plan has an assigned C test suite. Following the exclusion of JTAG TAP and System Bus S02 tests (as JTAG is not in the current project scope), the plan comprises **54 tests (100% firmware-driven)**:

* **`SOC-004` (Synchronous reset release)**: Assigned `test_all.c` (executes upon reset release to verify register reset stability across clock edges).
* **`SOC-005` (AXI access during reset assertion)**: Assigned `test_boot_sanity.c` (processor executes memory access while `rst_n` is toggled).
* **`XBR-008` (Decoupled AW/W channel acceptance)**: Assigned `test_interconnect.c` (firmware issues rapid writes exercising independent crossbar channel FIFOs).
* **`XBR-010` (Read channel backpressure)**: Assigned `test_interconnect.c` (firmware streams pipelined loads under slave wait-state stalls).
* **JTAG Scope Refinement**: Former tests `SOC-006` (JTAG CDC), `XBR-004` (S02 peripheral block), and `XBR-005` (S02 Boot ROM read) have been removed from the plan because JTAG is out of scope for the current project.

### 3.2 Boundary-Pin Reclassification (XBAR Sheet)
* **`XBR-008` (formerly XBR-010)**: Reclassified from `External` $\rightarrow$ **`Internal`** (Operates entirely on internal AXI crossbar FIFOs; zero boundary pins touched).
* **`XBR-010` (formerly XBR-012)**: Reclassified from `External` $\rightarrow$ **`Internal`** (Exercises internal AXI read channel ready/valid handshakes; zero boundary pins touched).
* In total, **all 10 `XBAR` tests are strictly `Internal`**. Zero boundary pins are touched by the interconnect crossbar.

### 3.3 Summary Sheet Realignment (`Sheet 1`)

| Sheet / Area | Tests | With a C Test (Firmware-in-the-Loop) | With an SV Test | Internal Tests (Purely On-Chip) | External Tests (Involves Chip I/O Pins) |
|---|:---:|:---:|:---:|:---:|:---:|
| **`SoC`** (Bring-up, DCCM, ECC) | 8 | **8** | 8 | **6** | **2** (`rst_n`) |
| **`XBAR`** (Interconnect Crossbar) | 10 | **10** | 10 | **10** | **0** |
| **`HBM`** (Heartbeat Watchdog) | 5 | **5** | 5 | **3** | **2** (`heartbeat_in`) |
| **`RSTSEQ`** (Reset Sequencer) | 6 | **6** | 6 | **6** | **0** |
| **`POL`** (Recovery Policy & Log) | 10 | **10** | 10 | **10** | **0** |
| **`PERIPH`** (UART, VGA & GPIO) | 7 | **7** | 7 | **4** | **3** (`uart_rx/tx`, `pixel_clk`, `gpio_*`) |
| **`IRQ`** (PIC Interrupt Controller) | 4 | **4** | 4 | **2** | **2** (`uart_rx`, `vblank`) |
| **`System`** (End-to-End Remediation)| 5 | **5** | 5 | **4** | **1** (`heartbeat_in`) |
| **Total** | **55** | **55 (100%)** | **55** | **45** | **10** |

### 3.4 Notes & Trace Sheets Synchronized
* **`Notes` (`Sheet 2`)**: Formally defines the whole-SoC paradigm, documents that all 55 tests feature firmware execution on the CPU, and codifies the physical boundary-pin rule.
* **`Trace` (`Sheet 11`)**: Synchronized all test mapping rows with the corresponding testbench environment and internal/external classification (55 active test rows).

---

## 4. Master 55-Test Taxonomy Under the Whole-SoC Boundary Rule

```
                                  [ HONOUR SOC BOUNDARY ]
                                  ┌─────────────────────┐
  External Stimulus / Pins       │                     │       Internal Tests (45 Tests)
  ────────────────────────       │   ┌──────────────┐  │       ─────────────────────────
  • rst_n                 ───────┼──>│  VeeR EL2    │  │       • XBR-001..010 (Interconnect Crossbar)
  • heartbeat_in          ───────┼──>│  CPU Core    │  │       • SOC-001..003, 006..008 (DCCM, ECC, CSRs)
  • uart_rx / uart_tx     <──────┼──>│ (Firmware-   │  │       • HBM-02..04 (Watchdog Timeout/Clear)
  • vga_rgb / sync        <──────┼───┤  Driven)     │  │       • RST-01..06 (Reset FSM & Sequence)
  • gpio_in / out / oe    <──────┼───┤              │  │       • POL-01..10 (Recovery Policy & Logs)
                                 │   └──────┬───────┘  │       • PER-01, 03, 04, 05 (Gaskets & Buffers)
  External Tests (10 Tests)      │          │ S00/S01  │       • IRQ-01, 02 (PIC Gateway & Priority)
  ─────────────────────────      │   ┌──────▼───────┐  │       • SYS-01..03, 05 (End-to-End Flows)
  • SOC-004, 005 (rst_n)         │   │ AXI4 3x8     │  │
  • HBM-01, 05, SYS-04 (hb_in)   │   │ Interconnect │  │
  • PER-02, IRQ-03 (uart pins)   │   └──────┬───────┘  │
  • PER-06, IRQ-04 (vga timing)  │          │ M00..M07 │
  • PER-07 (gpio_in/out/oe pins) │   ┌──────▼───────┐  │
                                 │   │ All On-Chip  │  │
                                 │   │ Peripheral   │  │
                                 │   │ IP Wrappers  │  │
                                 │   └──────────────┘  │
                                 └─────────────────────┘
```

The table below catalogs all 54 tests under this rigorous whole-SoC boundary framework:

| Test ID | Sheet | Test Title | Firmware Test Binary | Physical Boundary Pins Involved | Classification |
|---|---|---|---|:---:|:---:|
| **SOC-001** | SoC | Boot ROM first fetch after reset | `test_boot_sanity.c` | None (checks core AR) | **Internal** |
| **SOC-002** | SoC | Register reset values after chip reset | `test_all.c` | None (internal CSRs) | **Internal** |
| **SOC-003** | SoC | Read-only registers ignore writes | `test_all.c` | None (internal CSRs) | **Internal** |
| **SOC-004** | SoC | Synchronous reset release | `test_all.c` | `rst_n` (external pin release) | **External** |
| **SOC-005** | SoC | AXI access during reset assertion | `test_boot_sanity.c` | `rst_n` (external pin drop) | **External** |
| **SOC-006** | SoC | DCCM byte, halfword and word stores | `test_dccm_byte_enable.c` | None (internal DCCM) | **Internal** |
| **SOC-007** | SoC | Boot ROM 64-bit burst fetch | `test_boot_sanity.c` | None (internal S00 fetch) | **Internal** |
| **SOC-008** | SoC | DCCM ECC detection and correction | `test_dccm_ecc.c` | None (internal LSU ECC) | **Internal** |
| **XBR-001** | XBAR | Decode routing to every legal slave | `test_interconnect.c` | None (internal AXI crossbar) | **Internal** |
| **XBR-002** | XBAR | Unmapped address returns DECERR | `test_interconnect.c` | None (internal AXI crossbar) | **Internal** |
| **XBR-003** | XBAR | Undecoded offsets inside slave window | `test_interconnect.c` | None (internal IP aperture) | **Internal** |
| **XBR-004** | XBAR | Unmapped write has no side effects | `test_interconnect.c` | None (internal crossbar) | **Internal** |
| **XBR-005** | XBAR | Boot ROM write response | `test_interconnect.c` | None (internal ROM sink) | **Internal** |
| **XBR-006** | XBAR | Round-robin arbitration S00 vs S01 | `test_arb_contention.c` | None (internal arbiter) | **Internal** |
| **XBR-007** | XBAR | Burst atomicity | `test_boot_sanity.c` | None (internal burst lock) | **Internal** |
| **XBR-008** | XBAR | Decoupled AW/W channel acceptance | `test_interconnect.c` | None (internal crossbar FIFOs) | **Internal** |
| **XBR-009** | XBAR | Concurrent read and write to slaves | `test_arb_contention.c` | None (internal crossbar) | **Internal** |
| **XBR-010** | XBAR | Read channel backpressure handling | `test_interconnect.c` | None (internal ready/valid) | **Internal** |
| **HBM-01** | HBM | Heartbeat edge resets counter | `test_heartbeat.c` | `heartbeat_in` pin | **External** |
| **HBM-02** | HBM | Watchdog timeout sets flag and IRQ | `test_heartbeat.c` | None (internal timer timeout) | **Internal** |
| **HBM-03** | HBM | clear_flag clears status and IRQ | `test_heartbeat.c` | None (internal CSR write) | **Internal** |
| **HBM-04** | HBM | Disable stops watchdog timeout | `test_heartbeat.c` | None (internal CSR write) | **Internal** |
| **HBM-05** | HBM | Heartbeat edge on timeout cycle | `test_heartbeat.c` | `heartbeat_in` pin | **External** |
| **RST-01** | RSTSEQ | Idle state after reset release | `test_reset_sequencer.c` | None (internal FSM state) | **Internal** |
| **RST-02** | RSTSEQ | Trigger starts pulse of RST_HOLD_CYCLES | `test_reset_sequencer.c` | None (internal FSM timer) | **Internal** |
| **RST-03** | RSTSEQ | GPIO_STAT follows reset_out | `test_gpio.c` | None (internal register read) | **Internal** |
| **RST-04** | RSTSEQ | Re-trigger during pulse is ignored | `test_reset_sequencer.c` | None (internal FSM lockout) | **Internal** |
| **RST-05** | RSTSEQ | Reset FSM full traversal | `test_reset_sequencer.c` | None (internal FSM states) | **Internal** |
| **RST-06** | RSTSEQ | Trigger on ASSERT/DEASSERT boundary | `test_reset_sequencer.c` | None (internal FSM transition) | **Internal** |
| **POL-01** | POL | Event log read-back via index | `test_recovery_policy.c` | None (internal circular log) | **Internal** |
| **POL-02** | POL | Lockout after POL_THRESHOLD events | `test_recovery_policy.c` | None (internal policy FSM) | **Internal** |
| **POL-03** | POL | Window expiry clears event count | `test_recovery_policy.c` | None (internal window counter)| **Internal** |
| **POL-04** | POL | Events across window boundary | `test_recovery_policy.c` | None (internal counter logic) | **Internal** |
| **POL-05** | POL | clear_lockout clears lockout flag | `test_recovery_policy.c` | None (internal CSR write) | **Internal** |
| **POL-06** | POL | Lockout persistence across rollover | `test_recovery_policy.c` | None (internal sticky flag) | **Internal** |
| **POL-07** | POL | Event log circular wrap at 16 | `test_recovery_policy.c` | None (internal 4-bit pointer) | **Internal** |
| **POL-08** | POL | Detecting a full event log | `test_recovery_policy.c` | None (internal 32-bit count) | **Internal** |
| **POL-09** | POL | Event on window rollover cycle | `test_recovery_policy.c` | None (internal priority logic) | **Internal** |
| **POL-10** | POL | Hardware does not block reset trigger | `test_recovery_policy.c` | None (internal interconnect) | **Internal** |
| **PER-01** | PERIPH | UART gasket lane steering | `test_uart.c` | None (internal 64-to-32 mux) | **Internal** |
| **PER-02** | PERIPH | UART transmit and receive | `test_uart.c` | `uart_rx`, `uart_tx` pins | **External** |
| **PER-03** | PERIPH | UART gasket concurrent master access | `test_arb_contention.c` | None (internal crossbar arb) | **Internal** |
| **PER-04** | PERIPH | VGA character buffer read and write | `test_vga.c` | None (internal dual-port RAM) | **Internal** |
| **PER-05** | PERIPH | VGA character rendering | `test_vga.c` | None (internal font & frame gen) | **Internal** |
| **PER-06** | PERIPH | pixel_clk_en cadence | `test_vga.c` | `pixel_clk` / VGA timing | **External** |
| **PER-07** | PERIPH | GPIO 8-bit bidirectional data & direction | `test_gpio.c` | `gpio_in`, `gpio_out`, `gpio_oe` | **External** |
| **IRQ-01** | IRQ | lockout_irq pulse & edge PIC gateway | `test_pic_interrupt.c` | None (internal PIC & core) | **Internal** |
| **IRQ-02** | IRQ | PIC priority with concurrent IRQs | `test_pic_interrupt.c` | None (internal PIC priority) | **Internal** |
| **IRQ-03** | IRQ | UART interrupt assert and clear | `test_uart_irq.c` | `uart_rx` pin | **External** |
| **IRQ-04** | IRQ | vblank interrupt cadence per frame | `test_vblank_irq.c` | VGA vertical frame interval | **External** |
| **SYS-01** | System | Cold boot to firmware loop | `test_boot_sanity.c` | None (internal boot flow) | **Internal** |
| **SYS-02** | System | Watchdog timeout and reset recovery | `test_watchdog_remediation.c` | None (internal remediation) | **Internal** |
| **SYS-03** | System | Crash loop, lockout and resume | `test_crashloop_lockout.c` | None (internal supervisory) | **Internal** |
| **SYS-04** | System | Steady state with regular heartbeat | `test_steady_state.c` | `heartbeat_in` pin | **External** |
| **SYS-05** | System | All peripherals busy under stress | `test_stress_concurrent.c` | None (internal concurrent loop)| **Internal** |
