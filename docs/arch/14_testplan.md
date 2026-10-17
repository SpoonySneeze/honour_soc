# Honour SoC — UVM Verification Test Plan
**Document ID:** HRSOC-TP-001  
**Revision:** 1.0  
**Status:** Draft  
**DUT:** `soc_top` (Honour SoC — BMC Watchdog / Power Management Controller)  
**RTL Baseline:** commit `3ce74f5` (branch `main`)  
**Sources:** `docs/arch/01_inventory.md` through `docs/arch/13_consistency_audit.md`

---

## Table of Contents

1. [Scope and Objectives](#1-scope-and-objectives)
2. [DUT Definition](#2-dut-definition)
3. [Testbench Topology](#3-testbench-topology)
4. [Register Abstraction Layer (RAL)](#4-register-abstraction-layer-ral)
5. [Functional Coverage Model](#5-functional-coverage-model)
6. [SVA / Protocol Checker Catalog](#6-sva--protocol-checker-catalog)
7. [Test Cases — Reset Group](#7-test-cases--reset-group)
8. [Test Cases — Address Decode Group](#8-test-cases--address-decode-group)
9. [Test Cases — Register Access Group](#9-test-cases--register-access-group)
10. [Test Cases — Data Path Group](#10-test-cases--data-path-group)
11. [Test Cases — Control Path Group](#11-test-cases--control-path-group)
12. [Test Cases — Interrupt Group](#12-test-cases--interrupt-group)
13. [Test Cases — Arbitration Group](#13-test-cases--arbitration-group)
14. [Test Cases — Error Handling Group](#14-test-cases--error-handling-group)
15. [Test Cases — Clock Group](#15-test-cases--clock-group)
16. [Test Cases — End-to-End / System Group](#16-test-cases--end-to-end--system-group)
17. [Test Cases — Spec Gap Group](#17-test-cases--spec-gap-group)
18. [Regression Strategy](#18-regression-strategy)
19. [RAL Exclusion List](#19-ral-exclusion-list)
20. [Sign-off Criteria](#20-sign-off-criteria)
21. [Feature-to-Test Traceability Matrix](#21-feature-to-test-traceability-matrix)

---

## 1. Scope and Objectives

### 1.1 Purpose
This document defines the complete verification test plan for the Honour SoC. It specifies, for every test case: the feature being verified, the stimulus applied, the expected DUT response, the pass/fail criterion, the verification method, and the UVM class hierarchy used to execute it. It is intended to be used directly by the verification engineer to implement the UVM testbench and regression suite.

### 1.2 Verification Objectives

| ID | Objective |
|---|---|
| OBJ-01 | Verify all 44 features defined in `10_features.md` have at least one associated test case. |
| OBJ-02 | Achieve ≥ 95% functional coverage closure on all defined covergroups. |
| OBJ-03 | Achieve ≥ 90% line, 85% branch, 80% FSM-state coverage across all custom IPs. |
| OBJ-04 | Demonstrate zero AXI protocol violations under any stimulus. |
| OBJ-05 | Demonstrate end-to-end BMC watchdog-to-reset flow with correct cycle timing. |
| OBJ-06 | Confirm that all 16 discrepancies found in `13_consistency_audit.md` are reflected in the RTL baseline. |
| OBJ-07 | Confirm lockout_irq (1-cycle pulse) is only received by VeeR PIC when PIC gateway is edge-triggered. |

### 1.3 Out of Scope
- VeeR EL2 core microarchitecture internals (pipeline stages, branch predictor, L1 cache).
- JTAG debug chain above the TAP boundary (Debugger software/OpenOCD).
- Post-silicon characterization (timing margins, SI).
- Power-management flows (no power-gating in this design).
- Synthesis and physical implementation sign-off.

---

## 2. DUT Definition

### 2.1 Top-Level Interface

**Module:** `soc_top`  
**Source:** `rtl/soc_top.v:162–186`

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Primary 100 MHz system clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `heartbeat_in` | in | 1 | External watchdog heartbeat pulse |
| `reset_out` | out | 1 | Host power-reset output (active-low) |
| `uart_rx` | in | 1 | UART serial receive |
| `uart_tx` | out | 1 | UART serial transmit |
| `jtag_tck` | in | 1 | JTAG clock (separate domain, ~25 MHz) |
| `jtag_tms` | in | 1 | JTAG mode select |
| `jtag_tdi` | in | 1 | JTAG data in |
| `jtag_tdo` | out | 1 | JTAG data out |
| `vga_hsync` | out | 1 | VGA horizontal sync |
| `vga_vsync` | out | 1 | VGA vertical sync |
| `vga_rgb` | out | 12 | VGA 12-bit RGB444 pixel data |

> [!IMPORTANT]
> `jtag_trst_n` does **NOT** exist as a chip pin. It is internally tied to `rst_n` at `soc_top.v:1766`. Do not drive it externally.  
> There is NO external `gpio_pins` bus. `u_gpio` is a 2-bit read-only internal status register only.

### 2.2 Address Map Summary

| Base | Size | End | Slave | ID |
|---|---|---|---|---|
| `0x0002_0000` | 256 B | `0x0002_00FF` | UART 16550 (`u_uart`) | M00 |
| `0x0002_0100` | 256 B | `0x0002_01FF` | System Timer (`u_timer`) | M01 |
| `0x0002_0200` | 256 B | `0x0002_02FF` | GPIO Status (`u_gpio`) | M02 |
| `0x0002_0300` | 256 B | `0x0002_03FF` | Heartbeat Monitor (`u_heartbeat`) | M03 |
| `0x0002_0400` | 256 B | `0x0002_04FF` | Reset Sequencer (`u_reset_seq`) | M04 |
| `0x0002_0500` | 256 B | `0x0002_05FF` | Recovery Policy (`u_rec_policy`) | M05 |
| `0x0002_0600` | 256 B | `0x0002_06FF` | VGA Controller (`u_vga`) | M06 |
| `0x8000_0000` | 8 KB | `0x8000_1FFF` | Boot ROM (`u_rom`) | M07 |
| `0xF004_0000` | 64 KB | `0xF004_FFFF` | DCCM (VeeR internal) | — |
| `0xF00C_0000` | 32 KB | `0xF00C_7FFF` | PIC (VeeR internal) | — |

---

## 3. Testbench Topology

### 3.1 Two-Bench Strategy

The plan uses two distinct UVM environments to balance coverage depth and simulation speed.

#### Bench A: Full-SoC Environment (`tb_soc_top`)
- Instantiates the complete `soc_top` RTL with VeeR EL2 core running compiled RISC-V firmware.
- Used for: end-to-end flows, firmware-in-the-loop, UART console tests, interrupt ISR tests.
- VeeR is active; firmware polls registers and drives heartbeat responses.

#### Bench B: Core-Stubbed Environment (`tb_soc_stub`)
- Replaces `u_veer` with an **AXI Master VIP** on the S01 (LSU) port.
- The S00 (IFU) port is terminated with a passive AXI4 monitor only.
- Used for: all register-level tests, address decode, arbitration, error injection, RAL sequences, 500-seed random regression.
- Enables deterministic, high-speed stimulus without firmware compilation dependency.

### 3.2 UVM Component Hierarchy

```
uvm_root
└── soc_tb_top (Bench A or B)
    └── soc_env
        ├── clk_rst_agent          (active)   clk + rst_n generation
        ├── heartbeat_agent        (active)   drives heartbeat_in
        ├── uart_agent             (active)   drives uart_rx, monitors uart_tx
        ├── axi_master_agent       (active, Bench B only)  S01 AXI VIP
        ├── reset_out_monitor      (passive)  observes reset_out
        ├── vga_monitor            (passive)  hsync, vsync, vga_rgb
        ├── pic_irq_monitor        (passive)  extintsrc_req[3:0]
        ├── axi_s00_monitor        (passive)  IFU AXI channel
        ├── axi_s01_monitor        (passive)  LSU AXI channel (passive in Bench A)
        ├── axi_s02_monitor        (passive)  SB AXI channel
        ├── peripheral_monitors[]  (passive)  M00–M07 slave taps
        ├── soc_scoreboard         scores all transactions
        ├── soc_coverage           all covergroups
        ├── soc_predictor          RAL mirror predictor
        └── soc_ral_model          Register Abstraction Layer
```

### 3.3 Agent Configuration: Active vs. Passive Operating Modes

The testbench dynamically configures agents as `UVM_ACTIVE` (instantiating driver, sequencer, and monitor) or `UVM_PASSIVE` (instantiating monitor only) depending on whether the test runs in **Bench A (Full SoC)** or **Bench B (Core-Stubbed Subsystem)**:

| Agent Name | Boundary / Pin Interface | Bench A (Full SoC) Mode | Bench B (Core-Stubbed) Mode | Functional Role & Responsibilities |
|---|---|---|---|---|
| `clk_rst_agent` | `clk`, `rst_n` | **UVM_ACTIVE** | **UVM_ACTIVE** | Drives 100 MHz primary clock, manages synchronous assertion and deassertion of active-low system reset `rst_n`. |
| `heartbeat_agent` | `heartbeat_in` | **UVM_ACTIVE** | **UVM_ACTIVE** | Drives external watchdog heartbeat pulse stream; injects programmable pulse widths, periods, jitter, and intentional dropouts (timeouts). |
| `uart_agent` | `uart_rx`, `uart_tx` | **UVM_ACTIVE** | **UVM_ACTIVE** | Driver transmits characters/commands onto `uart_rx`; passive monitor samples `uart_tx`, verifies baud timing, frame parity, and decodes test output strings. |
| `jtag_agent` | `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo` | **UVM_ACTIVE** | **UVM_PASSIVE** (Tied off) | Drives IEEE 1149.1 JTAG TAP controller to execute debug register reads/writes and core debug halt/resume in Bench A. |
| `axi_master_agent` (VIP) | `lsu_axi_*` (Master S01) | **UVM_PASSIVE** (Monitor only) | **UVM_ACTIVE** (Master VIP) | In **Bench B**, drives high-bandwidth directed and randomized AXI4 read/write transactions into S01. In **Bench A**, passively tracks CPU LSU bus accesses. |
| `axi_s00_monitor` | `ifu_axi_*` (Master S00) | **UVM_PASSIVE** | **UVM_PASSIVE** | Passively monitors instruction fetch transactions from the VeeR IFU to Boot ROM (`0x8000_0000`) and DCCM (`0xF004_0000`). |
| `axi_s02_monitor` | `sb_axi_*` (Master S02) | **UVM_PASSIVE** | **UVM_PASSIVE** | Passively observes System Bus accesses from VeeR debug unit; validates decode masking to M00–M06. |
| `reset_out_monitor` | `reset_out` | **UVM_PASSIVE** | **UVM_PASSIVE** | Monitors host power reset output pin; measures pulse width duration, verifies active-low polarity, and timestamps edge events. |
| `vga_monitor` | `vga_hsync`, `vga_vsync`, `vga_rgb[11:0]` | **UVM_PASSIVE** | **UVM_PASSIVE** | Samples digital RGB444 pixel bus during active display intervals, tracks sync periods, and reconstructs character frames for font comparison. |
| `pic_irq_monitor` | `extintsrc_req[3:0]` | **UVM_PASSIVE** | **UVM_PASSIVE** | Monitors internal interrupt lines to the VeeR PIC (`uart_irq=bit 0`, `hb_irq=bit 1`, `vblank_irq=bit 2`, `lockout_irq=bit 3`); captures latency and pulse widths. |
| `peripheral_monitors[0..7]` | `m00_axi_*` to `m07_axi_*` | **UVM_PASSIVE** | **UVM_PASSIVE** | Per-slave passive monitors recording individual transactions, wait-state stalls, and handshake timing for scoreboard checking. |

---

### 3.4 Required Bare-Metal C Test Suite (Firmware-in-the-Loop)

For **Bench A (Full SoC)**, firmware executes bare-metal on the VeeR EL2 core (`RV32IMC`). The required C firmware test programs and their specific roles are:

| Firmware Test Binary | Source Location | Associated UVM Test(s) | Key Firmware Operations & Interactions |
|---|---|---|---|
| `test_boot_sanity.elf` | `firmware/test/test_boot_sanity.c` | `TP-E2E-01`, `TP-RST-01` | • MRAC CSR (`0x7c0 = 0x2`) configuration<br>• Stack pointer init (`sp = 0xF005_0000`) in DCCM<br>• UART baud divisor configuration (DLL=1, DLM=0)<br>• Transmits boot banner `"HONOUR_SOC_READY\n"` via `uart_tx` |
| `test_pic_interrupt.elf` | `firmware/test/test_pic_interrupt.c` | `TP-IRQ-01`, `TP-IRQ-02` | • Configures `mtvec` trap vector address<br>• **Configures PIC gateway `meigwctrl[3]` at `0xF00C_4030` to EDGE-TRIGGERED mode** (bit 0=1) so single-cycle `lockout_irq` pulse is latched<br>• Enables `mie.meie` and `mstatus.mie`<br>• Implements ISR to claim interrupt, log ID, and clear gateway |
| `test_watchdog_remediation.elf` | `firmware/test/test_watchdog_remediation.c` | `TP-E2E-02`, `TP-CTRL-02` | • Programs `HB_THRESHOLD` and arms watchdog (`HB_CTRL.enable = 1`)<br>• Polls or receives `hb_irq` upon host timeout<br>• Reads `HB_STATUS`, stages event into `POL_EVENT_TS`, writes `POL_CTRL.record_event = 1`<br>• Programs `RST_HOLD_CYCLES = 100`, writes `RST_CTRL.trigger = 1`<br>• Polls `RST_STATUS.complete` |
| `test_crashloop_lockout.elf` | `firmware/test/test_crashloop_lockout.c` | `TP-E2E-03`, `TP-ERR-05` | • Configures `POL_THRESHOLD = 3` and `POL_WINDOW`<br>• Enters remediation loop; checks `POL_STATUS.lockout_flag` before triggering reset<br>• **Enforces firmware lockout suppression**: halts `RST_CTRL` triggers once lockout asserts<br>• Waits for UART unlock character from testbench, clears lockout via `POL_CTRL.clear_lockout = 1`, and resumes |
| `test_stress_concurrent.elf` | `firmware/test/test_stress_concurrent.c` | `TP-E2E-06` | • Tight supervisory loop: continuous UART telemetry, VGA dashboard buffer updates, system timer polling, and watchdog servicing under concurrent bus traffic |

#### Firmware Build & Load Flow
1. **Compilation**: `riscv64-unknown-elf-gcc -march=rv32imc_zicsr -mabi=ilp32 -mcmodel=medany -Wall -O2 -ffreestanding -nostdlib -T firmware/link.ld firmware/start.S firmware/test/<target>.c -o program.elf`
2. **Hex Generation**: `riscv64-unknown-elf-objcopy --change-addresses -0x80000000 -O verilog program.elf firmware.hex`
3. **Memory Preload**: Testbench preloads Boot ROM via SystemVerilog task `$readmemh("firmware.hex", soc_top.u_rom.rom_mem);` prior to reset release.

#### Test-by-Test Firmware Dependency Matrix (C Test vs. Pure VIP)

| Test Group | Test Case IDs | Requires C Test? | Testbench Environment | Firmware Binary / Driver Source |
|---|---|:---:|---|---|
| **Reset & Boot** | `TP-RST-01` | **YES** | Bench A (Full SoC) | `test_boot_sanity.c` (executes boot vector, stack init, prints banner) |
| **Reset & Boot** | `TP-RST-02` | Optional | Bench A or B | `test_boot_sanity.c` or passive monitor |
| **Reset & Boot** | `TP-RST-03`, `TP-RST-04` | **NO** | Bench B (Subsystem) | Driven directly by AXI Master VIP (`axi_master_agent`) |
| **Address Decode** | `TP-DEC-01`, `TP-DEC-02`, `TP-DEC-05` | **NO** | Bench B (Subsystem) | Driven directly by AXI Master VIP (`axi_master_agent`) |
| **Address Decode** | `TP-DEC-03`, `TP-DEC-04` | **YES** | Bench A (Full SoC) | JTAG TAP agent stimulates VeeR Debug Unit (`u_veer.sb`) |
| **Register Access** | `TP-REG-01` through `TP-REG-06` | **NO** | Bench B (Subsystem) | Driven directly by UVM RAL Model & AXI Master VIP |
| **Data Path** | `TP-DAT-01` | **YES** | Bench A (Full SoC) | `test_boot_sanity.c` (issues byte/halfword/word store instructions) |
| **Data Path** | `TP-DAT-02`, `TP-DAT-03`, `TP-DAT-06` | **NO** | Bench B (Subsystem) | Driven directly by AXI Master VIP & UART agent |
| **Data Path** | `TP-DAT-04` | **YES** | Bench A (Full SoC) | `test_vga.c` (writes ASCII text lines into `VGA_BUFFER`) |
| **Data Path** | `TP-DAT-05` | **YES** | Bench A (Full SoC) | Passive monitor observing VeeR IFU burst fetch during boot |
| **Control Path** | `TP-CTRL-01` through `TP-CTRL-08` | **NO** | Bench B (Subsystem) | Driven directly by AXI Master VIP & Heartbeat agent |
| **Interrupts** | `TP-IRQ-01`, `TP-IRQ-02` | **YES** | Bench A (Full SoC) | `test_pic_interrupt.c` (configures `meigwctrl`, ISR vector, claims IRQ) |
| **Interrupts** | `TP-IRQ-03`, `TP-IRQ-04` | **YES** / Opt | Bench A (Full SoC) | `test_all.c` or passive monitor on `extintsrc_req` lines |
| **Arbitration** | `TP-ARB-01` | **YES** | Bench A (Full SoC) | Multi-master traffic generated by VeeR IFU/LSU concurrently |
| **Arbitration** | `TP-ARB-02` through `TP-ARB-04` | **NO** | Bench B (Subsystem) | Driven directly by AXI Master VIP |
| **Error Handling** | `TP-ERR-01`, `TP-ERR-02`, `TP-ERR-03`, `TP-ERR-05` | **NO** | Bench B (Subsystem) | Driven directly by AXI Master VIP |
| **Error Handling** | `TP-ERR-04` (`TP-MEM-01`) | **YES** | Bench A (Full SoC) | `test_all.c` (firmware reads injected DCCM ECC fault location) |
| **Clock & CDC** | `TP-CLK-01`, `TP-CLK-02` | **NO** | Bench B (Subsystem) | Driven directly by Clock/Reset agent & AXI Master VIP |
| **Clock & CDC** | `TP-CLK-03` | **YES** | Bench A (Full SoC) | `test_all.c` running while JTAG TAP scans asynchronous vectors |
| **End-to-End** | `TP-E2E-01` | **YES** | Bench A (Full SoC) | `test_boot_sanity.c` (cold boot to firmware loop) |
| **End-to-End** | `TP-E2E-02` | **YES** | Bench A (Full SoC) | `test_watchdog_remediation.c` (catches timeout, logs, fires reset) |
| **End-to-End** | `TP-E2E-03` | **YES** | Bench A (Full SoC) | `test_crashloop_lockout.c` (lockout suppression & UART unlock) |
| **End-to-End** | `TP-E2E-04` | **YES** | Bench A (Full SoC) | `test_all.c` (healthy steady-state execution) |
| **End-to-End** | `TP-E2E-05` | **YES** | Bench A (Full SoC) | `test_stress_concurrent.c` (tight multi-peripheral concurrent loop) |
| **Spec Gaps** | `TP-GAP-01` through `TP-GAP-07` | **NO** | Bench B (Subsystem) | Cycle-accurate VIP race stimulus & boundary hazard injection |

---

### 3.5 Complete SoC Hardware & Software Bringup Sequence

The table and sequence below detail the cycle-accurate bringup flow of the Honour SoC from initial power-on to steady-state execution:

```mermaid
sequenceDiagram
    autonumber
    participant TB as Testbench / clk_rst_agent
    participant ROM as Boot ROM (u_rom)
    participant Core as VeeR EL2 Core (u_veer)
    participant DCCM as DCCM SRAM (u_dccm)
    participant Peri as Custom IPs & UART
    participant PIC as VeeR PIC (pic_ctrl)

    Note over TB,Peri: Phase 1: Hardware Power-On & Reset
    TB->>TB: Start 100 MHz clk & 25 MHz jtag_tck
    TB->>TB: Drive rst_n = 0 (held for ≥ 20 cycles)
    TB->>ROM: Preload firmware.hex via $readmemh
    TB->>Peri: Synchronous reset asserts: registers attain reset values
    TB->>TB: Synchronous reset release: rst_n = 1

    Note over Core,ROM: Phase 2: Core Reset & Fetch
    Core->>Core: rst_l & dbg_rst_l release synchronously
    Core->>ROM: Master S00 issues AXI AR burst to 0x8000_0000
    ROM-->>Core: Boot code instructions returned over R channel

    Note over Core,DCCM: Phase 3: Assembly CRT0 Startup (start.S)
    Core->>Core: csrw mstatus, zero & csrw mie, zero (disable interrupts)
    Core->>Core: csrw 0x7c0, 0x2 (MRAC: mark 0x0002_xxxx as side-effect device space)
    Core->>Core: li sp, 0xF005_0000 (stack pointer set to top of DCCM)
    Core->>DCCM: Loop clears .bss section to 0x00000000
    Core->>Core: call main (jump to C runtime)

    Note over Core,PIC: Phase 4: Driver & Interrupt Setup
    Core->>Peri: Program UART divisor (DLL=1, DLM=0) & line format
    Core->>PIC: Write meigwctrl[3] = 0x1 (configure line 3 to EDGE-TRIGGERED)
    Core->>Core: Write mtvec to ISR base; set mstatus.mie = 1
    Core->>Peri: Write "HONOUR_SOC_READY" to UART_THR

    Note over Core,TB: Phase 5: Testbench Ready Handshake
    Peri-->>TB: uart_tx serializes banner string
    TB->>TB: uart_agent confirms banner; launches test sequences
```

#### Step-by-Step Bringup Chronology:
1. **Clock & Reset Initialization ($t = 0$ to $t = 200\,\text{ns}$)**:
   - Primary `clk` (100 MHz, 10 ns period) and `jtag_tck` (25 MHz, 40 ns period) begin toggling.
   - Active-low system reset `rst_n` is driven low (`0`) and held for at least 20 clock cycles.
   - Preload `$readmemh("firmware.hex", soc_top.u_rom.rom_mem)` completes before reset release.
2. **Synchronous Reset Deassertion ($t = 200\,\text{ns}$)**:
   - `rst_n` transitions $0 \to 1$ synchronously with the rising edge of `clk`.
   - All custom IP registers achieve legal reset defaults: `reset_out` pad drives `1` (inactive), `RST_HOLD_CYCLES = 100`, `POL_THRESHOLD = 3`, `GPIO_STAT = 0x0000_0002`, `UART_LSR = 0x60`, `VGA_BUFFER[*] = 0x2020_2020`.
3. **Core Reset Vector Fetch**:
   - VeeR EL2 core reset lines `rst_l` and `dbg_rst_l` deassert. Hardware initializes the Program Counter to `boot_vector = 0x8000_0000`.
   - IFU (Master S00) issues its first AXI AR burst transaction targeting `0x8000_0000` to Boot ROM (M07).
4. **Assembly CRT0 Initialization (`firmware/start.S`)**:
   - `csrw mstatus, zero` and `csrw mie, zero`: Globally disables interrupts during initialization.
   - `csrw 0x7c0, 0x2`: Configures VeeR Machine Region Access Control (MRAC) register to designate memory region `0x0002_xxxx` as side-effect device space (prevents speculative or out-of-order peripheral accesses).
   - `li sp, 0xF005_0000`: Sets stack pointer to top of 64KB DCCM SRAM (`0xF004_0000`–`0xF004_FFFF`).
   - Clears uninitialized data segment (`.bss`) in DCCM from `_sbss` to `_ebss`.
   - Branches to `main()` in compiled C test firmware.
5. **Driver Initialization & PIC Gateway Configuration**:
   - Initializes UART 16550 IP: sets baud divisor in `UART_DLL`/`UART_DLM` and line format in `UART_LCR`.
   - **Crucial PIC Gateway Step**: Firmware writes `0x0000_0001` to `meigwctrl[3]` at `0xF00C_4030` to configure PIC external interrupt line 3 as **edge-triggered**, ensuring the 1-cycle `lockout_irq` pulse is latched into `meip[3]`.
   - Sets `mtvec` register to point to the external interrupt dispatch vector table; enables global interrupts via `mstatus.mie = 1`.
6. **Testbench Synchronization (Ready Handshake)**:
   - Firmware streams the ASCII synchronization string `"HONOUR_SOC_READY\n"` to `UART_THR`.
   - The UVM `uart_agent` monitor receives and validates the banner, signalling to the virtual sequencer that the SoC DUT has completed bringup and is ready for stimulus injection.

---

### 3.6 Internal Signal Access Strategy

Bind modules are used for all internal signals to avoid hierarchical reference proliferation.

| Bind Target | Signals Exposed | Purpose |
|---|---|---|
| `bind heartbeat_monitor` | `hb_counter`, `hb_prev_sample`, `hb_state` | Counter/FSM assertions |
| `bind reset_sequencer` | `rst_countdown`, `rst_state` | FSM assertions, duration check |
| `bind recovery_policy` | `log_wr_ptr`, `window_counter`, `window_recovery_count`, `log_buffer` | Log integrity, window timing |
| `bind axi_interconnect` | `grant_reg`, `state_reg` | Arbitration fairness, FSM checks |

---

## 4. Register Abstraction Layer (RAL)

### 4.1 RAL Coverage

The RAL model (`soc_ral_model`) shall include all registers listed in `04_address_map.md` Section 4.

| Slave | Registers in RAL |
|---|---|
| M00 UART | `UART_RBR/THR/DLL`, `UART_IER/DLM`, `UART_IIR/FCR`, `UART_LCR`, `UART_MCR`, `UART_LSR`, `UART_MSR`, `UART_SCR` |
| M01 Timer | `TMR_CTR` |
| M02 GPIO | `GPIO_STAT` |
| M03 Heartbeat | `HB_CTRL`, `HB_THRESHOLD`, `HB_STATUS`, `HB_ELAPSED` |
| M04 Reset Seq | `RST_CTRL`, `RST_HOLD_CYCLES`, `RST_STATUS` |
| M05 Rec Policy | `POL_CTRL`, `POL_THRESHOLD`, `POL_WINDOW`, `POL_STATUS`, `LOG_READ_IDX`, `LOG_READ_DATA`, `LOG_COUNT`, `LOG_TIMESTAMP` |
| M06 VGA | `VGA_CTRL`, `VGA_STATUS`, `VGA_BUFFER[0..29]` |

### 4.2 Predictor Strategy
- Front-door (AXI read/write) access via the `axi_master_agent`.
- Back-door (hierarchical force) for reset value checks and direct state inspection.
- The `soc_predictor` updates the RAL mirror on every write transaction seen on the S01 AXI monitor.

### 4.3 Excluded Registers (see §19)
`RST_CTRL` (write-1 self-clear), `HB_CTRL` (enable bit changes FSM), `UART_FCR` (WO), `UART_THR` (WO), `UART_LCR` (DLAB bit changes register map), `VGA_BUFFER` (initialized to `0x2020_2020`; bit-bash may disturb display state). See §19 for full list and rationale.

---

## 5. Functional Coverage Model

### 5.1 Covergroup: `cg_heartbeat_fsm`

```
Bins:
  DISABLED_state     (hb_state == 2'b00)
  IDLE_state         (hb_state == 2'b01)
  COUNTING_state     (hb_state == 2'b10)
  UNRESPONSIVE_state (hb_state == 2'b11)
Transitions:
  IDLE->COUNTING     (enable asserted, heartbeat seen)
  COUNTING->IDLE     (heartbeat received before timeout)
  COUNTING->UNRESPONSIVE (timeout expires, no heartbeat)
  UNRESPONSIVE->IDLE (clear_flag written)
Cross:
  hb_state X irq_en  (irq enabled vs disabled in each state)
```

### 5.2 Covergroup: `cg_heartbeat_threshold`

```
Bins:
  threshold_min      (HB_THRESHOLD == 1)
  threshold_small    (HB_THRESHOLD inside [2:99])
  threshold_medium   (HB_THRESHOLD inside [100:9999])
  threshold_large    (HB_THRESHOLD inside [10000:$])
  threshold_zero     (HB_THRESHOLD == 0)  // edge case
```

### 5.3 Covergroup: `cg_rst_seq_fsm`

```
Bins:
  ST_IDLE     (rst_state == 2'b00)
  ST_ASSERT   (rst_state == 2'b01)
  ST_DEASSERT (rst_state == 2'b10)
Transitions:
  IDLE->ASSERT        (trigger written)
  ASSERT->DEASSERT    (countdown reaches 0)
  DEASSERT->IDLE      (reset deasserted)
  ASSERT->ASSERT_retrigger (write trigger during ASSERT state -- must be ignored)
```

### 5.4 Covergroup: `cg_rst_hold_cycles`

```
Bins:
  hold_min    (RST_HOLD_CYCLES inside [1:10])
  hold_default (RST_HOLD_CYCLES == 100)
  hold_large  (RST_HOLD_CYCLES inside [101:9999])
  hold_max    (RST_HOLD_CYCLES == 32'hFFFF_FFFF)
```

### 5.5 Covergroup: `cg_rec_policy_lockout`

```
Bins:
  below_threshold  (window_recovery_count < POL_THRESHOLD)
  at_threshold     (window_recovery_count == POL_THRESHOLD)
  above_threshold  (window_recovery_count > POL_THRESHOLD -- can only reach via increment; lockout fires at ==)
  lockout_asserted (lockout_flag == 1)
  lockout_cleared  (clear_lockout written while lockout_flag==1)
Cross:
  lockout_flag X window_expired
```

### 5.6 Covergroup: `cg_rec_policy_log`

```
Bins:
  log_entries_0    (LOG_COUNT == 0)
  log_entries_1_8  (LOG_COUNT inside [1:8])
  log_entries_9_15 (LOG_COUNT inside [9:15])
  log_entries_16   (LOG_COUNT == 16)  // pointer wrap
  log_entries_overflow (>16 events written -- wraps)
  all_16_slots_read (all LOG_READ_IDX 0..15 read after wrap)
```

### 5.7 Covergroup: `cg_axi_decode`

```
Bins:
  slave_M00 through slave_M07 (AR/AW addr hits each decoded window)
  unmapped_low  (0x0002_0700 to 0x7FFF_FFFF)
  unmapped_high (0x8000_2000 to 0xF003_FFFF)
  dccm_range    (0xF004_0000 to 0xF004_FFFF)
  s02_to_M00_M06_blocked (S02 master + M00..M06 target)
  s02_to_M07_allowed     (S02 master + M07 target)
```

### 5.8 Covergroup: `cg_axi_resp`

```
Bins:
  OKAY     (rresp/bresp == 2'b00)
  EXOKAY   (2'b01) -- not supported; must never appear
  SLVERR   (2'b10) -- not supported; must never appear
  DECERR   (2'b11)
Cross:
  axi_resp X master_id (S00, S01, S02)
```

### 5.9 Covergroup: `cg_irq_lines`

```
Bins:
  uart_irq_assert      (extintsrc_req[0] rises)
  hb_irq_assert        (extintsrc_req[1] rises)
  vblank_irq_assert    (extintsrc_req[2] rises)
  lockout_irq_assert   (extintsrc_req[3] rises)  // single-cycle pulse
  no_irq_active        (extintsrc_req[3:0] == 4'b0000)
  multi_irq_concurrent (extintsrc_req has >1 bit set simultaneously)
```

### 5.10 Covergroup: `cg_uart_path`

```
Bins:
  tx_byte_all_zeros  (uart_tx byte == 8'h00)
  tx_byte_all_ones   (uart_tx byte == 8'hFF)
  tx_byte_random     (uart_tx byte inside [1:254])
  rx_byte_all_zeros  through rx_byte_random (mirror of TX)
  lsr_thre_set       (UART_LSR[5] == 1)
  lsr_dr_set         (UART_LSR[0] == 1)
  fifo_empty         (TX FIFO empty)
  fifo_full          (TX FIFO full -- 16-deep)
```

### 5.11 Covergroup: `cg_vga_buffer`

```
Bins:
  buffer_word_space      (VGA_BUFFER word == 32'h2020_2020)
  buffer_word_pattern    (non-space ASCII pattern written and read)
  buffer_all_slots       (VGA_BUFFER[0..29] all written at least once)
  vga_ctrl_enable_set    (VGA_CTRL[0] == 1)
  vga_ctrl_enable_clear  (VGA_CTRL[0] == 0)
```

### 5.12 Coverage Closure Target

| Covergroup | Target |
|---|---|
| All FSM state covergroups | 100% bins, 100% transitions |
| `cg_axi_decode` | 100% bins |
| `cg_axi_resp` | 100% bins |
| `cg_irq_lines` | 100% bins |
| All parameter/threshold covergroups | ≥ 90% bins |
| `cg_uart_path`, `cg_vga_buffer` | ≥ 90% bins |

---

## 6. SVA / Protocol Checker Catalog

All SVAs are bound via `bind` modules (not inline in RTL). Each SVA lists the property, the bind target, and the failure description.

| SVA ID | Bind Target | Property | Failure |
|---|---|---|---|
| SVA-HB-01 | `heartbeat_monitor` | `@(posedge clk) (hb_state==COUNTING && !heartbeat_in) |-> ##1 hb_counter == $past(hb_counter)+1` | Counter skips a cycle |
| SVA-HB-02 | `heartbeat_monitor` | `@(posedge clk) (hb_prev_sample==0 && heartbeat_in) |-> ##1 hb_counter == 0` | Counter not reset on rising edge |
| SVA-HB-03 | `heartbeat_monitor` | `@(posedge clk) (hb_counter == HB_THRESHOLD && hb_state==COUNTING) |-> ##1 unresponsive_flag` | Timeout not flagged at threshold |
| SVA-HB-04 | `heartbeat_monitor` | `@(posedge clk) $rose(clear_flag_w) |-> ##1 !unresponsive_flag && !hb_irq` | Clear flag does not clear status |
| SVA-RST-01 | `reset_sequencer` | `@(posedge clk) (rst_state==ST_IDLE && trigger_req) |-> ##1 rst_state==ST_ASSERT && !reset_out` | FSM does not enter ASSERT |
| SVA-RST-02 | `reset_sequencer` | `@(posedge clk) (rst_state==ST_ASSERT) |-> rst_countdown==$past(rst_countdown)-1` | Countdown not decrementing |
| SVA-RST-03 | `reset_sequencer` | `@(posedge clk) (rst_state==ST_ASSERT && rst_countdown==0) |-> ##1 rst_state==ST_DEASSERT && reset_out` | FSM does not deassert reset |
| SVA-RST-04 | `reset_sequencer` | `@(posedge clk) (rst_state==ST_DEASSERT) |-> ##1 rst_state==ST_IDLE` | FSM stuck in DEASSERT |
| SVA-RST-05 | `reset_sequencer` | `@(posedge clk) (rst_state==ST_ASSERT && trigger_req) |-> ##1 rst_state==ST_ASSERT` | Re-trigger accepted mid-pulse |
| SVA-POL-01 | `recovery_policy` | `@(posedge clk) $rose(record_event_w) |-> ##1 log_wr_ptr==$past(log_wr_ptr)+1 [% 16]` | Log pointer not advancing |
| SVA-POL-02 | `recovery_policy` | `@(posedge clk) (window_counter==policy_window_reg) |-> ##1 window_counter==0 && window_recovery_count==0` | Window not resetting |
| SVA-POL-03 | `recovery_policy` | `@(posedge clk) (window_recovery_count==policy_threshold_reg) |-> ##1 lockout_flag` | Lockout not asserted at threshold |
| SVA-POL-04 | `recovery_policy` | `@(posedge clk) $rose(lockout_flag) |-> lockout_irq && ##1 !lockout_irq` | lockout_irq not exactly 1 cycle |
| SVA-AXI-01 | `axi_interconnect` | AXI4 handshake: `VALID` must not deassert without `READY` | Protocol violation |
| SVA-AXI-02 | `axi_interconnect` | `AWVALID` + `WVALID` must both be asserted before `BVALID` | Write response before data |
| SVA-AXI-03 | `axi_interconnect` | `(rresp==2'b01 or rresp==2'b10) |-> $error` | EXOKAY or SLVERR must never appear |
| SVA-AXI-04 | `axi_interconnect` | Burst atomicity: `grant_reg` does not change during ARLEN > 0 | Burst broken by arbitration |
| SVA-CLK-01 | `vga_controller` | `@(posedge clk) ($rose(pixel_clk_en)) |-> ##4 $rose(pixel_clk_en)` | pixel_clk_en not every 4 cycles |
| SVA-CLK-02 | `soc_top` | `@(posedge clk) (rst_n==0) |-> !reset_out` | reset_out not driven during chip reset |

---

## 7. Test Cases — Reset Group

### TP-RST-01: Boot ROM First Fetch on Reset Release

| Field | Value |
|---|---|
| **Test ID** | TP-RST-01 |
| **Title** | Boot ROM first fetch address at reset release |
| **Feature(s)** | SOC-RST-001, SOC-CLK-001, SOC-CLK-002 |
| **Bench** | Bench A (Full SoC) |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_boot_rst_test` |
| **Sequence** | `clk_rst_seq` (assert rst_n for 10 cycles, release) |
| **Stimulus** | Assert `rst_n=0` for 20 clock cycles, then deassert `rst_n=1`. No heartbeat. |
| **Internal Signals Checked** | `soc_top.u_veer.ifu_axi_araddr` (first AR beat after reset release) |
| **Expected Result** | First AXI AR address on S00 IFU channel is `0x8000_0000`. Observed within 5 cycles of `rst_n` rising. |
| **Pass Criterion** | `pic_irq_monitor` sees no spurious IRQs during reset. AXI S00 monitor records first `araddr == 32'h8000_0000`. |
| **Fail Criterion** | Any other first AR address; or no AR transaction within 1000 cycles; or any AXI handshake violation. |
| **SVA Coverage** | SVA-RST-01 active; SVA-CLK-02 active |
| **Functional Coverage** | `cg_rst_seq_fsm`: ST_IDLE bin |
| **Notes** | Run in simulation after full SoC power-on reset. Boot ROM must be preloaded with `firmware.hex`. |

---

### TP-RST-02: Reset Sequencer Power-Up State

| Field | Value |
|---|---|
| **Test ID** | TP-RST-02 |
| **Title** | Reset sequencer `IDLE` state and `reset_out=1` at power-up |
| **Feature(s)** | SOC-RST-002, SOC-RST-006 |
| **Bench** | Bench A or B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_rst_seq_idle_test` |
| **Sequence** | `clk_rst_seq` (apply reset), then `axi_rd_seq` on `RST_STATUS` |
| **Stimulus** | Assert and release `rst_n`. Read `RST_STATUS` and `RST_CTRL`. |
| **Internal Signals Checked** | `rst_state` via bind (`ST_IDLE == 2'b00`) |
| **Expected Result** | `reset_out = 1` (active-low = deasserted) at all times during reset and immediately after release. `RST_STATUS.complete = 0`. `rst_state = ST_IDLE`. |
| **Pass Criterion** | `reset_out_monitor` sees `reset_out=1` throughout. RAL readback of `RST_STATUS` returns `0x00000000`. |
| **Fail Criterion** | `reset_out` pulses low during chip reset; or `RST_STATUS.complete` is set without trigger. |
| **SVA Coverage** | SVA-CLK-02 |
| **Functional Coverage** | `cg_rst_seq_fsm`: ST_IDLE bin |

---

### TP-RST-03: Reset Sequencer Trigger and Duration

| Field | Value |
|---|---|
| **Test ID** | TP-RST-03 |
| **Title** | `RST_CTRL.trigger` fires reset pulse; duration matches `RST_HOLD_CYCLES` |
| **Feature(s)** | SOC-RST-003, SOC-RST-004, SOC-RST-005, SOC-CTRL-005 |
| **Bench** | Bench B (AXI VIP) |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_rst_trigger_test` |
| **Sequence** | `rst_trigger_seq` — write `RST_HOLD_CYCLES`, write `RST_CTRL.trigger=1`, monitor `reset_out` |
| **Stimulus** | 1. Write `RST_HOLD_CYCLES = N` (parameterized: try N=10, 100, 1000). 2. Write `RST_CTRL[0]=1`. |
| **Internal Signals Checked** | `rst_state`, `rst_countdown` |
| **Expected Result** | `reset_out` falls to 0 within 1 cycle of trigger write. `reset_out` remains low for exactly N cycles. `reset_out` returns to 1. `RST_STATUS.complete` becomes 1. |
| **Pass Criterion** | `reset_out_monitor` measures `duration_cycles == N` (±1 cycle for synchronous pipeline). RAL readback of `RST_STATUS[0] == 1`. SVA-RST-01 through SVA-RST-04 pass. |
| **Fail Criterion** | Duration off by more than 1 cycle; `reset_out` doesn't return to 1; `RST_STATUS.complete` not set. |
| **SVA Coverage** | SVA-RST-01, SVA-RST-02, SVA-RST-03, SVA-RST-04 |
| **Functional Coverage** | `cg_rst_seq_fsm`: all 3 state bins + all 3 transitions; `cg_rst_hold_cycles`: multiple bins |
| **Parameters** | Run with N = 10, 100, 1000, 4294967295 (max 32-bit) |

---

### TP-RST-04: GPIO_STAT Reflects reset_out

| Field | Value |
|---|---|
| **Test ID** | TP-RST-04 |
| **Title** | `GPIO_STAT[1]` tracks live `reset_out` state |
| **Feature(s)** | SOC-RST-007 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_gpio_stat_test` |
| **Sequence** | `rst_trigger_seq`, then `axi_rd_seq` on `GPIO_STAT` while `reset_out` is low |
| **Stimulus** | Trigger reset pulse. While `reset_out=0`, read `GPIO_STAT`. After pulse completes, read again. |
| **Expected Result** | `GPIO_STAT[1] == 0` during active `reset_out` pulse. `GPIO_STAT[1] == 1` when `reset_out` is deasserted. `GPIO_STAT[0]` reflects live `heartbeat_in`. |
| **Pass Criterion** | Both GPIO_STAT reads return correct values correlated with `reset_out_monitor` timestamps. Reset value of `GPIO_STAT` is `0x0000_0002` (confirmed by `axi_gpio.v:114`). |
| **Fail Criterion** | `GPIO_STAT[1]` stuck at 0 or 1 regardless of `reset_out`. |
| **Notes** | Reset value `0x0000_0002` = bit 1 set because `reset_out` idle = high = 1. |

---

## 8. Test Cases — Address Decode Group

### TP-DEC-01: Decode Routing — All Legal Slaves

| Field | Value |
|---|---|
| **Test ID** | TP-DEC-01 |
| **Title** | AXI address decode routes correctly to M00–M07 |
| **Feature(s)** | SOC-DEC-001, SOC-DEC-002, SOC-DEC-003, SOC-DEC-005 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_decode_all_slaves_test` |
| **Sequence** | `decode_sweep_seq` — iterates base address of each slave, performs 1-word read and write |
| **Stimulus** | Issue single-word AXI reads from S01 to: `0x0002_0000`, `0x0002_0100`, `0x0002_0200`, `0x0002_0300`, `0x0002_0400`, `0x0002_0500`, `0x0002_0600`, `0x8000_0000`. |
| **Expected Result** | Each transaction is forwarded to the correct slave (M00–M07). `rresp/bresp == OKAY (2'b00)`. Each slave's AXI monitor records exactly one transaction. No other slave monitor records any transaction. |
| **Pass Criterion** | Scoreboard cross-checks: address in → slave tap recording match. `cg_axi_decode` bins M00–M07 all hit. |
| **Fail Criterion** | Wrong slave receives a transaction; DECERR on a valid address; multiple slaves triggered by one address. |
| **SVA Coverage** | SVA-AXI-01, SVA-AXI-02 |
| **Functional Coverage** | `cg_axi_decode`: slave_M00..slave_M07 bins; `cg_axi_resp`: OKAY bin |

---

### TP-DEC-02: Unmapped Address — DECERR Response

| Field | Value |
|---|---|
| **Test ID** | TP-DEC-02 |
| **Title** | Access to unmapped space returns AXI DECERR |
| **Feature(s)** | SOC-DEC-004, SOC-ERR-001, SOC-ERR-002 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_decode_error_test` |
| **Sequence** | `decode_error_seq` — randomizes address in unmapped ranges |
| **Stimulus** | Issue reads and writes to unmapped addresses: `0x0002_0700`, `0x1000_0000`, `0x7FFF_FFFF`, `0x8000_2000`, `0xDEAD_BEEF`. |
| **Expected Result** | All transactions return `rresp/bresp == DECERR (2'b11)`. Write data is discarded (no slave memory modified). No AXI bus hang (transaction completes within 100 cycles). |
| **Pass Criterion** | `pic_irq_monitor` sees no IRQ. Protocol monitor records DECERR on every transaction. Scoreboard confirms no slave state changed. |
| **Fail Criterion** | OKAY returned on unmapped address; AXI bus hangs (no response); SLVERR instead of DECERR. |
| **SVA Coverage** | SVA-AXI-01, SVA-AXI-03 |
| **Functional Coverage** | `cg_axi_decode`: unmapped_low, unmapped_high bins; `cg_axi_resp`: DECERR bin |
| **Notes** | RTL (`axi_interconnect.v:642, 734`) returns `2'b11` — NOT `2'b10`. Any `2'b10` response is a test failure. |

---

### TP-DEC-03: S02 Master Blocked from M00–M06

| Field | Value |
|---|---|
| **Test ID** | TP-DEC-03 |
| **Title** | VeeR System Bus (S02) cannot access peripheral slaves M00–M06 |
| **Feature(s)** | SOC-DEC-006 |
| **Bench** | Bench A (S02 is driven by VeeR debug unit) |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_s02_block_test` |
| **Sequence** | JTAG agent issues debug memory access targeting `0x0002_0300` (HBM base) via S02 |
| **Stimulus** | Use JTAG TAP to issue a system bus access (abstract command or progbuf) targeting `0x0002_0300`. |
| **Expected Result** | S02 monitor records the attempted transaction. Response is DECERR (`2'b11`) **[KNOB: configurable — OQ-03 open]**. No M03 slave tap records the transaction. |
| **Pass Criterion** | S02 AXI monitor records transaction with `rresp == 2'b11`. M03 monitor sees zero transactions. |
| **Fail Criterion** | Peripheral slave responds to S02 access; OKAY returned to S02; no response within timeout. |
| **Functional Coverage** | `cg_axi_decode`: s02_to_M00_M06_blocked bin |
| **Notes** | This test has a configurable `expect_decerr` knob because OQ-03 is not fully resolved. Default: expect DECERR. |

---

### TP-DEC-04: S02 Can Access M07 (Boot ROM)

| Field | Value |
|---|---|
| **Test ID** | TP-DEC-04 |
| **Title** | VeeR System Bus (S02) can read Boot ROM |
| **Feature(s)** | SOC-DEC-007 |
| **Bench** | Bench A |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_s02_rom_test` |
| **Sequence** | JTAG debug read targeting `0x8000_0000` |
| **Stimulus** | JTAG system bus read at `0x8000_0000`. |
| **Expected Result** | Response is OKAY. Data matches ROM content (first word of firmware). M07 monitor records one read transaction. |
| **Pass Criterion** | S02 monitor sees OKAY + data. Scoreboard compares against `firmware.hex` word 0. |
| **Fail Criterion** | DECERR on Boot ROM read; data mismatch; bus hang. |
| **Functional Coverage** | `cg_axi_decode`: s02_to_M07_allowed bin |

---

### TP-DEC-05: In-Window Undecoded Offsets Return OKAY

| Field | Value |
|---|---|
| **Test ID** | TP-DEC-05 |
| **Title** | Accesses within a peripheral window to undecoded offsets return OKAY (not DECERR) |
| **Feature(s)** | SOC-DEC-003 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_inwindow_undecoded_test` |
| **Sequence** | `axi_rd_seq` targeting offsets beyond register map within slave windows |
| **Stimulus** | Read `0x0002_0320` (HBM base + 0x20, beyond HBM registers at 0x0C). |
| **Expected Result** | OKAY response, undefined/zero read data. No DECERR. AXI bus does not hang. |
| **Pass Criterion** | `rresp == OKAY (2'b00)`. No protocol violation. |
| **Fail Criterion** | DECERR on in-window access; bus hang. |
| **Notes** | This is a spec gap (Spec Gap 1 in `09_open_questions.md`). Test documents actual hardware behavior. |

---

## 9. Test Cases — Register Access Group

### TP-REG-01: Hardware Reset Values

| Field | Value |
|---|---|
| **Test ID** | TP-REG-01 |
| **Title** | All registers read back correct reset values after chip reset |
| **Feature(s)** | SOC-REG-001 through SOC-REG-011, SOC-CLK-001 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_reg_reset_test` |
| **Sequence** | `uvm_reg_hw_reset_seq` (with exclusions in §19 applied) |
| **Stimulus** | Apply chip reset. Read every non-excluded register via RAL front-door. |
| **Expected Result** | Every register returns its RTL-verified reset value (from `04_address_map.md` Section 4). Key values: `RST_HOLD_CYCLES = 32'd100`, `POL_THRESHOLD = 8'd3`, `GPIO_STAT = 32'h0000_0002`, `UART_LSR = 32'h60`, `UART_IIR = 32'h01`, `VGA_BUFFER[*] = 32'h2020_2020`. |
| **Pass Criterion** | RAL mirror matches RTL back-door read for all non-excluded registers. |
| **Fail Criterion** | Any register differs from expected reset value by even 1 bit. |
| **Functional Coverage** | `cg_heartbeat_fsm`: DISABLED_state bin; `cg_rst_seq_fsm`: ST_IDLE bin |
| **Notes** | `RST_CTRL`, `HB_CTRL`, `UART_FCR`, `UART_THR`, `UART_LCR`, `VGA_BUFFER` are excluded — see §19. |

---

### TP-REG-02: HB_CTRL clear_flag Clears Status

| Field | Value |
|---|---|
| **Test ID** | TP-REG-02 |
| **Title** | Writing `HB_CTRL.clear_flag=1` clears `unresponsive_flag` and `hb_irq` |
| **Feature(s)** | SOC-REG-002 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_hbm_clear_test` |
| **Sequence** | `hbm_timeout_seq` then `hbm_clear_seq` |
| **Stimulus** | 1. Enable HBM, set small threshold, let timeout fire. 2. Confirm `HB_STATUS[0]==1` and `hb_irq` asserted. 3. Write `HB_CTRL[1]=1` (clear_flag). |
| **Expected Result** | `HB_STATUS[0]` returns to 0 in the next cycle. `hb_irq` deasserts in next cycle. `HB_ELAPSED` reflects last elapsed count. |
| **Pass Criterion** | PIC IRQ monitor sees `extintsrc_req[1]` fall within 2 cycles of clear_flag write. RAL mirror of `HB_STATUS` is 0. |
| **Fail Criterion** | `unresponsive_flag` remains set; `hb_irq` remains asserted; register reads still show timeout. |
| **SVA Coverage** | SVA-HB-04 |

---

### TP-REG-03: Read-Only Register Write Protection

| Field | Value |
|---|---|
| **Test ID** | TP-REG-03 |
| **Title** | Writing to RO registers has no effect |
| **Feature(s)** | SOC-REG-009 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_reg_ro_test` |
| **Sequence** | `uvm_reg_bit_bash_seq` restricted to RO registers |
| **Stimulus** | Write all-1s to: `HB_STATUS`, `HB_ELAPSED`, `GPIO_STAT`, `TMR_CTR`, `RST_STATUS`, `UART_LSR`, `UART_IIR`, `UART_MSR`, `POL_STATUS`, `LOG_READ_DATA`, `LOG_COUNT`, `LOG_TIMESTAMP`, `VGA_STATUS`. |
| **Expected Result** | Register values unchanged after write. No AXI error response for the write attempt (write is absorbed silently or returns OKAY). |
| **Pass Criterion** | Read-back of each register equals pre-write value. |
| **Fail Criterion** | Any RO register value changes after write. |

---

### TP-REG-04: Event Log Read via LOG_READ_IDX

| Field | Value |
|---|---|
| **Test ID** | TP-REG-04 |
| **Title** | Event log can be read back via `LOG_READ_IDX` / `LOG_READ_DATA` |
| **Feature(s)** | SOC-REG-010 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_log_readback_test` |
| **Sequence** | Record N events; iterate `LOG_READ_IDX` = 0..N-1; compare `LOG_READ_DATA` |
| **Stimulus** | 1. Write `POL_CTRL.record_event=1` N times (N=1, 8, 16). 2. Write `LOG_READ_IDX = 0`. Read `LOG_READ_DATA`. Increment index and repeat. |
| **Expected Result** | Each `LOG_READ_DATA` returns the timestamp that was sampled when the corresponding event was recorded. `LOG_COUNT` equals N (saturates at 16). |
| **Pass Criterion** | Scoreboard compares timestamps from `LOG_READ_DATA` against timestamps captured by the `axi_master_agent` at the time of each `record_event` write (cycle-accurate). |
| **Fail Criterion** | Data mismatch at any index; LOG_COUNT incorrect; accessing index ≥ N returns garbage timestamp. |
| **Functional Coverage** | `cg_rec_policy_log`: log_entries_1_8, log_entries_9_15 bins |

---

### TP-REG-05: VGA Buffer Read/Write

| Field | Value |
|---|---|
| **Test ID** | TP-REG-05 |
| **Title** | VGA character buffer (`0x0002_0608–0x0002_067C`) read/write access |
| **Feature(s)** | SOC-REG-011 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_vga_buf_rw_test` |
| **Sequence** | Write test pattern to all 30 VGA_BUFFER words, read back |
| **Stimulus** | Write `0x41424344` ("ABCD") to `VGA_BUFFER[0]` through `VGA_BUFFER[29]` (30 words at offsets 0x08 to 0x7C). Read each back. |
| **Expected Result** | Each word read back exactly matches what was written. |
| **Pass Criterion** | All 30 words match. No DECERR. |
| **Fail Criterion** | Any word mismatch; write address misrouted; DECERR. |
| **Notes** | Confirmed readable over AXI per `vga_controller.v:136–147` (read mux returns `dashboard_buffer[(reg_addr-0x08)>>2]`). Reset value is `32'h2020_2020` per `vga_controller.v:114`. |
| **Functional Coverage** | `cg_vga_buffer`: buffer_all_slots bin |

---

### TP-REG-06: POL_CTRL.clear_lockout Clears Lockout

| Field | Value |
|---|---|
| **Test ID** | TP-REG-06 |
| **Title** | Writing `POL_CTRL.clear_lockout=1` deasserts `lockout_flag` |
| **Feature(s)** | SOC-REG-005 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_lockout_clear_test` |
| **Sequence** | Drive lockout (see TP-CTRL-04), then write `POL_CTRL.clear_lockout=1` |
| **Stimulus** | After lockout is asserted, write `POL_CTRL[1]=1`. Read `POL_STATUS`. |
| **Expected Result** | `POL_STATUS.lockout_flag` clears to 0 within 1 cycle. `lockout_irq` does NOT re-fire on clear (it is not re-asserted). |
| **Pass Criterion** | RAL read of `POL_STATUS[0] == 0`. PIC IRQ monitor does not record another `extintsrc_req[3]` pulse. |
| **Fail Criterion** | Lockout remains asserted after write; spurious second lockout_irq pulse. |
| **SVA Coverage** | SVA-POL-04 (verifies lockout_irq is 1 cycle only on assertion, not on clear) |

---

## 10. Test Cases — Data Path Group

### TP-DAT-01: DCCM Read/Write with Byte Enables

| Field | Value |
|---|---|
| **Test ID** | TP-DAT-01 |
| **Title** | 64-bit DCCM read and write with all byte enable combinations |
| **Feature(s)** | SOC-DAT-002 |
| **Bench** | Bench A (firmware-driven) or Bench B (AXI VIP via internal DCCM tie-off — verify accessibility) |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_dccm_be_test` |
| **Sequence** | Firmware writes to DCCM with sub-word stores (byte, halfword, word) |
| **Stimulus** | Firmware: byte write to `0xF004_0000`, halfword write to `0xF004_0002`, word write to `0xF004_0004`. Read back each. |
| **Expected Result** | Read-back matches written data with byte enables correctly applied. Other bytes in the same word are unmodified. |
| **Pass Criterion** | DCCM memory model (scoreboard shadow) matches each written byte exactly. |
| **Fail Criterion** | Byte-enable corruption; read returns stale or zero data. |

---

### TP-DAT-02: UART 64-to-32 Bit Gasket Steering

| Field | Value |
|---|---|
| **Test ID** | TP-DAT-02 |
| **Title** | UART bus gasket routes data to correct 32-bit lane based on `AWADDR[2]` |
| **Feature(s)** | SOC-DAT-003 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_uart_gasket_test` |
| **Sequence** | `uart_gasket_seq` — writes to both address-even and address-odd UART registers |
| **Stimulus** | 1. Write `0x0002_0000` (addr[2]=0 → lower 32b lane). 2. Write `0x0002_0004` (addr[2]=1 → upper 32b lane). |
| **Internal Signals Checked** | `soc_top.uart_awaddr2_r` (via bind or hierarchical ref) |
| **Expected Result** | `uart_awaddr2_r` latches `addr[2]` on each AWVALID+AWREADY handshake. Correct byte lane reaches UART 32-bit data bus. |
| **Pass Criterion** | SVA on `uart_awaddr2_r` confirms correct latch value. Scoreboard confirms UART register was written with correct byte. |
| **Fail Criterion** | Wrong lane selected; gasket does not update on new address. |
| **SVA Coverage** | SVA-AXI-01 |

---

### TP-DAT-03: UART TX and RX Path

| Field | Value |
|---|---|
| **Test ID** | TP-DAT-03 |
| **Title** | UART transmit byte from THR serialized on `uart_tx`; incoming `uart_rx` deserialized to `RBR` |
| **Feature(s)** | SOC-DAT-004, SOC-DAT-005 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_uart_loopback_test` |
| **Sequence** | `uart_tx_seq` + `uart_rx_seq` |
| **Stimulus** | TX: Set baud rate (DLL=1, DLM=0 → 115200 baud equivalent in sim), write `0x55` to `UART_THR`. RX: UART agent drives `uart_rx` with serial encoding of `0xAA`. |
| **Expected Result** | TX: `uart_agent` monitor decodes `uart_tx` and reconstructs `0x55`. RX: Reading `UART_RBR` returns `0xAA`. `UART_LSR[0]` (DR) is set. |
| **Pass Criterion** | TX scoreboard: decoded byte == `0x55`. RX scoreboard: `UART_RBR == 0xAA` and `UART_LSR[0]==1`. |
| **Fail Criterion** | Framing error; wrong byte value; `UART_LSR.DR` not set after receive. |
| **Functional Coverage** | `cg_uart_path`: tx_byte_random, rx_byte_random, lsr_thre_set, lsr_dr_set bins |

---

### TP-DAT-04: VGA Character Rendering

| Field | Value |
|---|---|
| **Test ID** | TP-DAT-04 |
| **Title** | VGA character buffer renders correct pixel stream on `vga_rgb` |
| **Feature(s)** | SOC-DAT-006 |
| **Bench** | Bench A (with VGA monitor active) |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_vga_render_test` |
| **Sequence** | Write known character pattern to VGA_BUFFER, wait one VGA frame, capture pixel output |
| **Stimulus** | Write `0x41414141` ("AAAA") to `VGA_BUFFER[0]`. Wait for `vblank_irq` or `VGA_STATUS.vblank`. Capture one full frame from VGA monitor. |
| **Expected Result** | `vga_monitor` reconstructs pixel stream. The character 'A' appears at column 0, row 0 of the text area. `vga_rgb != 0` during character render; `vga_rgb == 0` during blanking. |
| **Pass Criterion** | VGA frame scoreboard confirms character 'A' pixel pattern in correct screen location (font ROM lookup). |
| **Fail Criterion** | Wrong character; all-zero pixels during active display; `vga_hsync`/`vga_vsync` timing outside VGA 640x480@60Hz spec. |
| **Notes** | `pixel_clk_en` = every 4 cycles, confirmed by `vga_controller.v:53–61`. No CDC. |

---

### TP-DAT-05: Boot ROM 64-bit Instruction Burst

| Field | Value |
|---|---|
| **Test ID** | TP-DAT-05 |
| **Title** | IFU fetches 64-bit instruction bursts from Boot ROM |
| **Feature(s)** | SOC-DAT-001, SOC-DEC-002 |
| **Bench** | Bench A |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_rom_fetch_test` |
| **Sequence** | Passive monitoring of S00 AXI channel after reset release |
| **Stimulus** | Normal boot (no special stimulus). Monitor S00 AXI AR channel. |
| **Expected Result** | S00 AR channel shows 64-bit (`arsize==3'b011`) burst transactions to addresses in range `0x8000_0000–0x8000_1FFF`. `arlen > 0` for burst fetches. |
| **Pass Criterion** | AXI S00 monitor records at least one burst (ARLEN > 0) with correct address range and 64-bit size. |
| **Fail Criterion** | Only single-beat fetches; wrong address range; `arsize != 3'b011`. |

---

### TP-DAT-06: AXI Backpressure / Wait State Handling

| Field | Value |
|---|---|
| **Test ID** | TP-DAT-06 |
| **Title** | Interconnect handles slave backpressure (RREADY/BREADY deassertion) without deadlock |
| **Feature(s)** | SOC-DAT-007 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_backpressure_test` |
| **Sequence** | `backpressure_seq` — AXI VIP drives RREADY=0 for 10–100 cycles after RVALID |
| **Stimulus** | Issue AXI read. VIP deasserts `RREADY` for 50 cycles after slave presents `RVALID`. |
| **Expected Result** | RDATA remains stable during RREADY=0. No `rresp` violation. Handshake completes when RREADY reasserts. |
| **Pass Criterion** | Protocol checker SVA-AXI-01 passes. Data is correct after back-pressure completes. Total transaction time = 50 stall cycles + normal latency. |
| **Fail Criterion** | RVALID drops while RREADY=0; data corrupted; bus deadlock. |

---

## 11. Test Cases — Control Path Group

### TP-CTRL-01: Heartbeat Edge Detection and Counter Reset

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-01 |
| **Title** | Rising edge on `heartbeat_in` detected and `hb_counter` reset to 0 |
| **Feature(s)** | SOC-CTRL-001, SOC-CTRL-002 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_hbm_edge_test` |
| **Sequence** | `heartbeat_seq` (single pulse) after enabling HBM |
| **Stimulus** | 1. Write `HB_CTRL[0]=1` (enable). Set `HB_THRESHOLD = 1000`. 2. Drive `heartbeat_in` low→high for 2 cycles. |
| **Internal Signals Checked** | `hb_prev_sample`, `hb_counter` (bind) |
| **Expected Result** | On the rising edge cycle: `hb_prev_sample==0` and `heartbeat_in==1`. Next cycle: `hb_counter == 0`. FSM moves to COUNTING state. |
| **Pass Criterion** | SVA-HB-02 passes. RAL read of `HB_ELAPSED` returns ~0. |
| **Fail Criterion** | Counter not reset; edge not detected; FSM stays in IDLE. |
| **SVA Coverage** | SVA-HB-01, SVA-HB-02 |
| **Functional Coverage** | `cg_heartbeat_fsm`: COUNTING_state, IDLE->COUNTING transition |

---

### TP-CTRL-02: Heartbeat Watchdog Timeout

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-02 |
| **Title** | Watchdog timeout sets `unresponsive_flag` and `hb_irq` |
| **Feature(s)** | SOC-CTRL-003, SOC-IRQ-002 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_hbm_timeout_test` |
| **Sequence** | `hbm_enable_seq` + wait for timeout |
| **Stimulus** | Enable HBM with `HB_THRESHOLD = T` (try T=50, T=200, T=1000). Drive no heartbeat pulses. Wait T+5 cycles. |
| **Expected Result** | At cycle T: `hb_counter == HB_THRESHOLD`. Next cycle: `unresponsive_flag = 1`, `hb_irq = 1`. FSM → UNRESPONSIVE. `HB_STATUS[0]` reads 1. |
| **Pass Criterion** | PIC IRQ monitor sees `extintsrc_req[1]` assert at expected cycle (±1). RAL reads `HB_STATUS[0]==1`. SVA-HB-03 passes. |
| **Fail Criterion** | Flag set too early or too late; `hb_irq` not asserted; wrong cycle count. |
| **SVA Coverage** | SVA-HB-03 |
| **Functional Coverage** | `cg_heartbeat_fsm`: UNRESPONSIVE_state, COUNTING->UNRESPONSIVE transition; `cg_heartbeat_threshold`: multiple bins |

---

### TP-CTRL-03: Reset Sequencer Re-trigger Rejection

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-03 |
| **Title** | Trigger write during active `ST_ASSERT` state is rejected |
| **Feature(s)** | SOC-CTRL-006 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_rst_retrigger_test` |
| **Sequence** | `rst_trigger_seq`, then write trigger again while `rst_state==ST_ASSERT` |
| **Stimulus** | Set `RST_HOLD_CYCLES = 500`. Trigger reset. After 10 cycles (still in ST_ASSERT), write `RST_CTRL[0]=1` again. |
| **Expected Result** | `reset_out` duration is still exactly 500 cycles (not restarted or extended). `rst_countdown` continues decrementing from where it was. FSM does not re-enter ST_ASSERT from the second trigger. |
| **Pass Criterion** | `reset_out_monitor` records exactly 500-cycle duration. SVA-RST-05 passes (re-trigger ignored). |
| **Fail Criterion** | Duration extends beyond 500 cycles; countdown resets to 500 on second write; any protocol violation. |
| **SVA Coverage** | SVA-RST-05 |
| **Functional Coverage** | `cg_rst_seq_fsm`: ASSERT_retrigger transition bin |

---

### TP-CTRL-04: Recovery Policy Lockout

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-04 |
| **Title** | Recovery policy asserts `lockout_flag` after `POL_THRESHOLD` events in window; fires 1-cycle `lockout_irq` |
| **Feature(s)** | SOC-CTRL-007, SOC-CTRL-008, SOC-CTRL-009, SOC-IRQ-004, SOC-REG-004 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_lockout_test` |
| **Sequence** | `pol_lockout_seq` — configure threshold, record events, verify lockout |
| **Stimulus** | 1. Write `POL_THRESHOLD = K` (try K=2, 3, 5). 2. Write `POL_WINDOW = W` (large value, e.g. 100000). 3. Write `POL_CTRL.record_event = 1` K times within the window. |
| **Internal Signals Checked** | `window_recovery_count`, `lockout_flag`, `lockout_irq` (bind) |
| **Expected Result** | After K-th `record_event` write: `lockout_flag` asserts to 1. `lockout_irq` pulses high for **exactly 1 clock cycle**. `POL_STATUS[0]` reads 1. `LOG_COUNT` increments K times. |
| **Pass Criterion** | SVA-POL-03 passes. SVA-POL-04 passes (lockout_irq exactly 1 cycle). PIC IRQ monitor records `extintsrc_req[3]` for exactly 1 cycle. RAL reads `POL_STATUS[0]==1`. |
| **Fail Criterion** | lockout_flag not set after K events; lockout_irq lasts more than 1 cycle (PIC level gateway will never latch it); lockout_irq not asserted; wrong `LOG_COUNT`. |
| **Notes** | **CRITICAL:** PIC gateway for line 3 resets to LEVEL mode. A 1-cycle pulse WILL be missed unless firmware first writes `meigwctrl[3]` to configure edge-triggered. This test verifies the hardware behavior of the pulse, not firmware ISR delivery. |
| **Functional Coverage** | `cg_rec_policy_lockout`: at_threshold, lockout_asserted bins |

---

### TP-CTRL-05: Rolling Window Reset Clears Count

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-05 |
| **Title** | After `POL_WINDOW` cycles, `window_recovery_count` resets and no lockout is declared |
| **Feature(s)** | SOC-CTRL-010 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_window_reset_test` |
| **Sequence** | Record K-1 events, let window expire, record 1 more event, confirm no lockout |
| **Stimulus** | Set `POL_THRESHOLD=3`, `POL_WINDOW=100`. Record 2 events at cycle 10 and 20. Wait until cycle 101 (window expires). Record 1 more event at cycle 110. |
| **Internal Signals Checked** | `window_counter`, `window_recovery_count` (bind) |
| **Expected Result** | At cycle 101: `window_counter` wraps to 0, `window_recovery_count` resets to 0. Event at cycle 110 increments count to 1. No `lockout_flag` asserted (count=1 < threshold=3). |
| **Pass Criterion** | SVA-POL-02 passes at window expiry. `POL_STATUS.lockout_flag` remains 0. |
| **Fail Criterion** | Lockout asserted despite window reset (count from previous window carried over); `window_recovery_count` not reset. |
| **SVA Coverage** | SVA-POL-02 |
| **Functional Coverage** | `cg_rec_policy_lockout`: below_threshold bin post-window-reset |

---

### TP-CTRL-06: Events Spanning Window Boundary

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-06 |
| **Title** | Events near window boundary do not falsely cause lockout |
| **Feature(s)** | SOC-CTRL-010 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_window_boundary_test` |
| **Sequence** | Record events timed to straddle the window boundary |
| **Stimulus** | `POL_THRESHOLD=3`, `POL_WINDOW=100`. Record 2 events at cycles 1 and 2. At cycle 100 (window boundary), record 1 event simultaneously with window expiry. |
| **Expected Result** | Whichever happens first (counter reset or increment) determines count. No lockout should fire (2 events in old window + 1 at boundary). This test documents actual RTL behavior. |
| **Pass Criterion** | `lockout_flag` remains 0. `window_recovery_count` is either 0 or 1 after boundary (both acceptable; must be consistent). |
| **Fail Criterion** | Lockout asserted; undefined/X state on `window_recovery_count`. |
| **Notes** | This is Spec Gap 5 from `09_open_questions.md`. The test captures actual behavior, not defined behavior. |

---

### TP-CTRL-07: Heartbeat Monitor Disable

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-07 |
| **Title** | Disabling HBM (`HB_CTRL[0]=0`) suppresses timeout and clears state |
| **Feature(s)** | SOC-CTRL-004 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_hbm_disable_test` |
| **Sequence** | Enable HBM, wait half threshold, disable, let remaining cycles expire |
| **Stimulus** | Enable HBM (threshold=100). After 50 cycles (no heartbeat), write `HB_CTRL[0]=0`. Wait additional 100 cycles. |
| **Expected Result** | FSM transitions to DISABLED. `hb_irq` not asserted. `unresponsive_flag` not set. Counter frozen or reset to 0 per FSM spec. |
| **Pass Criterion** | PIC IRQ monitor sees no `extintsrc_req[1]`. `HB_STATUS[0]` remains 0. |
| **Fail Criterion** | Timeout fires while disabled; IRQ asserted after disable. |
| **Functional Coverage** | `cg_heartbeat_fsm`: DISABLED_state bin; COUNTING->DISABLED transition |

---

### TP-CTRL-08: Reset Sequencer FSM Full Traversal

| Field | Value |
|---|---|
| **Test ID** | TP-CTRL-08 |
| **Title** | RST Sequencer FSM visits all 3 states in correct order |
| **Feature(s)** | SOC-CTRL-005 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_rst_fsm_traversal_test` |
| **Sequence** | Trigger reset; observe all FSM state transitions via bind |
| **Stimulus** | Trigger `RST_CTRL[0]=1` with `RST_HOLD_CYCLES=10`. |
| **Internal Signals Checked** | `rst_state` (bind: `ST_IDLE`, `ST_ASSERT`, `ST_DEASSERT`) |
| **Expected Result** | `rst_state` sequence: `00` → `01` → `10` → `00`. Transition latency: IDLE→ASSERT within 1 cycle of trigger; ASSERT→DEASSERT after exactly 10 cycles; DEASSERT→IDLE within 1 cycle. |
| **Pass Criterion** | All SVA-RST-01..04 pass. All 3 FSM state bins in `cg_rst_seq_fsm` hit. All 3 transition bins hit. |
| **Fail Criterion** | Any state skipped; wrong transition order; stuck state. |
| **SVA Coverage** | SVA-RST-01, SVA-RST-02, SVA-RST-03, SVA-RST-04 |
| **Functional Coverage** | `cg_rst_seq_fsm`: all bins and all transition bins |

---

## 12. Test Cases — Interrupt Group

### TP-IRQ-01: PIC Gateway Edge-Triggered Configuration for lockout_irq

| Field | Value |
|---|---|
| **Test ID** | TP-IRQ-01 |
| **Title** | `lockout_irq` 1-cycle pulse captured by VeeR PIC only when gateway is edge-triggered |
| **Feature(s)** | SOC-IRQ-004, SOC-IRQ-005 |
| **Bench** | Bench A |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_pic_gateway_test` |
| **Sequence** | Configure PIC via firmware write, then trigger lockout |
| **Stimulus** | **Part A (Level mode — negative test):** Trigger lockout without configuring `meigwctrl[3]`. Confirm IRQ is NOT taken by core. **Part B (Edge mode — positive test):** Firmware writes `meigwctrl` at `0xF00C_4030` to configure `gw3` as edge-triggered (bit 0 = 1). Then trigger lockout. |
| **Internal Signals Checked** | `soc_top.u_veer.veer.pic_ctrl_inst.meip[30:0]` |
| **Expected Result** | Part A: `meip` for line 3 remains 0 (pulse missed by level gateway). Part B: `meip` for line 3 asserts and drives core to take trap. |
| **Pass Criterion** | Part A: No trap taken. Part B: Core takes external interrupt trap. `extintsrc_req[3]` pulse observed for exactly 1 cycle in both parts. |
| **Fail Criterion** | Level gateway captures 1-cycle pulse (would indicate RTL different from analysis); edge gateway misses pulse. |
| **Notes** | **CRITICAL open item from Task 14.** `recovery_policy.v:215-224`: `lockout_irq = lockout_flag & ~lockout_prev`. `meigwctrl` at `0xF00C_4030` (PIC base + gateway control offset). No firmware currently configures this. |

---

### TP-IRQ-02: PIC Priority and Multi-IRQ Arbitration

| Field | Value |
|---|---|
| **Test ID** | TP-IRQ-02 |
| **Title** | VeeR PIC prioritizes correctly when multiple interrupt lines are active |
| **Feature(s)** | SOC-IRQ-005 |
| **Bench** | Bench A |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_pic_priority_test` |
| **Sequence** | Simultaneously assert `uart_irq` and `hb_irq`, monitor PIC claim |
| **Stimulus** | Configure PIC with different priorities for line 0 (UART) and line 1 (HBM). Assert both simultaneously (within same cycle). |
| **Expected Result** | PIC presents the higher-priority interrupt to the core first. After core claims and clears the higher, PIC presents the lower. |
| **Pass Criterion** | Internal PIC signals show correct priority ordering. Both IRQs are eventually claimed. |
| **Fail Criterion** | Lower-priority IRQ served first; one IRQ permanently masked. |
| **Functional Coverage** | `cg_irq_lines`: multi_irq_concurrent bin |

---

### TP-IRQ-03: uart_irq Assertion and Deassertion

| Field | Value |
|---|---|
| **Test ID** | TP-IRQ-03 |
| **Title** | `uart_irq` asserts when enabled UART interrupt conditions are met |
| **Feature(s)** | SOC-IRQ-001 |
| **Bench** | Bench A or B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_uart_irq_test` |
| **Sequence** | Configure UART IER, receive byte, check IRQ |
| **Stimulus** | Write `UART_IER[0]=1` (enable data-ready IRQ). Drive `uart_rx` with one character. |
| **Expected Result** | `extintsrc_req[0]` asserts. `UART_IIR[0]` clears (interrupt pending). Reading `UART_RBR` clears the IRQ. |
| **Pass Criterion** | PIC IRQ monitor records `extintsrc_req[0]` assertion. After `UART_RBR` read, `extintsrc_req[0]` deasserts. |
| **Fail Criterion** | No IRQ; IRQ stays asserted after read; `UART_IIR` not updated. |

---

### TP-IRQ-04: vblank_irq Timing

| Field | Value |
|---|---|
| **Test ID** | TP-IRQ-04 |
| **Title** | `vblank_irq` asserts once per VGA frame at vertical blanking |
| **Feature(s)** | SOC-IRQ-003 |
| **Bench** | Bench A |
| **Priority** | LOW |
| **UVM Test Class** | `soc_vblank_irq_test` |
| **Sequence** | Enable VGA, monitor `extintsrc_req[2]` for two consecutive frames |
| **Stimulus** | Enable VGA (`VGA_CTRL[0]=1`). Wait 2 frames. |
| **Expected Result** | `extintsrc_req[2]` asserts exactly twice (once per frame) at the start of vertical blank. Period between assertions equals VGA frame period. |
| **Pass Criterion** | PIC IRQ monitor records 2 pulses of `extintsrc_req[2]` separated by 1 VGA frame period (≈ 800×525 pixel_clk_en cycles = 800×525×4 `clk` cycles at 1-in-4 enable). |
| **Fail Criterion** | vblank_irq fires more than once per frame; zero pulses observed. |

---

## 13. Test Cases — Arbitration Group

### TP-ARB-01: Round-Robin Fairness Between S00 and S01

| Field | Value |
|---|---|
| **Test ID** | TP-ARB-01 |
| **Title** | AXI crossbar applies fair round-robin arbitration between masters S00 and S01 |
| **Feature(s)** | SOC-ARB-001, SOC-DEC-005 |
| **Bench** | Bench A (both S00 IFU and S01 LSU active) |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_arb_rr_test` |
| **Sequence** | `arb_stress_seq` — both masters continuously request access to the same slave |
| **Stimulus** | Core executing tight memory loop (S00 fetching) while LSU simultaneously performs burst reads to a peripheral. Drive continuous contention to a single slave. |
| **Internal Signals Checked** | `grant_reg[2:0]` (bind to arbiter) |
| **Expected Result** | Grants alternate between S00 and S01 without starvation. Neither master waits more than 2 consecutive grants for the other. |
| **Pass Criterion** | Arbiter scoreboard records grant sequence; deviation from round-robin > 2 consecutive grants is a failure. |
| **Fail Criterion** | One master monopolizes bus for > 3 consecutive grants; starvation observed (one master waits > 100 cycles). |
| **SVA Coverage** | SVA-AXI-04 |
| **Functional Coverage** | `cg_axi_decode`: slave_M07 bin from S00, slave_M00..M06 bins from S01 |

---

### TP-ARB-02: Interleaved Write Address and Data Acceptance

| Field | Value |
|---|---|
| **Test ID** | TP-ARB-02 |
| **Title** | AXI interconnect accepts write address and write data channels independently |
| **Feature(s)** | SOC-ARB-003 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_arb_interleaved_test` |
| **Sequence** | AXI VIP drives AWVALID before WVALID with variable delay |
| **Stimulus** | Issue AWVALID at cycle 0, then WVALID at cycle 5, 10, 20, and 50 (parameterized delay). |
| **Expected Result** | Interconnect accepts AWVALID and issues AWREADY. Interconnect accepts WVALID and issues WREADY independently. BVALID is presented after both are accepted. |
| **Pass Criterion** | SVA-AXI-02 passes. No deadlock. Write completes correctly in all delay configurations. |
| **Fail Criterion** | Interconnect requires simultaneous AWVALID+WVALID; BVALID before WREADY. |
| **SVA Coverage** | SVA-AXI-01, SVA-AXI-02 |

---

### TP-ARB-03: Concurrent Read and Write Channels

| Field | Value |
|---|---|
| **Test ID** | TP-ARB-03 |
| **Title** | Simultaneous AXI read and write transactions to different slaves do not interfere |
| **Feature(s)** | SOC-ARB-002 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_arb_concurrent_test` |
| **Sequence** | Issue read to M03 and write to M05 simultaneously |
| **Stimulus** | Drive ARVALID (read to M03) and AWVALID+WVALID (write to M05) in the same cycle. |
| **Expected Result** | Both transactions complete independently without deadlock. Read response from M03 and write response from M05 are both received with OKAY. |
| **Pass Criterion** | Both transactions complete. No deadlock within 100 cycles. Scoreboard confirms correct slave received each transaction. |
| **Fail Criterion** | One transaction blocked indefinitely by the other; wrong slave receives data. |

---

### TP-ARB-04: Burst Atomicity

| Field | Value |
|---|---|
| **Test ID** | TP-ARB-04 |
| **Title** | Crossbar holds grant active across all beats of an AXI burst |
| **Feature(s)** | SOC-ARB-004 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_arb_burst_test` |
| **Sequence** | Issue INCR burst (ARLEN=7, 8 beats) to Boot ROM from S01 |
| **Stimulus** | AXI VIP drives a read burst with `arlen=7`, `arsize=3'b011`, `arburst=INCR` to `0x8000_0000`. |
| **Internal Signals Checked** | `grant_reg` (must not change during burst) |
| **Expected Result** | All 8 beats of the burst are returned without the grant changing to another master mid-burst. |
| **Pass Criterion** | SVA-AXI-04 passes. All 8 beats received. `grant_reg` held constant across all 8 beats. |
| **Fail Criterion** | Grant changes mid-burst; fewer than 8 beats returned; data corruption. |
| **SVA Coverage** | SVA-AXI-04 |
| **Functional Coverage** | `cg_axi_decode`: slave_M07 bin |

---

## 14. Test Cases — Error Handling Group

### TP-ERR-01: Boot ROM Write Response

| Field | Value |
|---|---|
| **Test ID** | TP-ERR-01 |
| **Title** | Write transaction to Boot ROM does not hang the bus |
| **Feature(s)** | SOC-ERR-003 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_rom_write_test` |
| **Sequence** | AXI write to `0x8000_0000` |
| **Stimulus** | Issue AXI write with `awaddr=0x8000_0000`, `wdata=0xDEADBEEF`. |
| **Expected Result** | Write response (`bresp`) received within 100 cycles. AXI bus does not hang. ROM contents unchanged (verified by subsequent read). `bresp` is either OKAY (write silently dropped) or DECERR — document whichever is actual behavior. |
| **Pass Criterion** | No bus deadlock. ROM read-back matches original `firmware.hex` content. `bresp` captured. |
| **Fail Criterion** | AXI bus hangs (no `bvalid` within 1000 cycles). ROM contents corrupted. |
| **Notes** | This is OQ-06. Actual `bresp` value is UNCLEAR from RTL analysis; this test determines it. |

---

### TP-ERR-02: Event Log Circular Wrap-Around

| Field | Value |
|---|---|
| **Test ID** | TP-ERR-02 |
| **Title** | Circular event log wraps cleanly from index 15 to 0 after 16 events |
| **Feature(s)** | SOC-ERR-004 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_log_wrap_test` |
| **Sequence** | Record 20 events; read back all 16 slots; confirm oldest entries overwritten |
| **Stimulus** | Set large `POL_WINDOW`. Record 20 events (more than 16). Read all 16 log slots via `LOG_READ_IDX`. |
| **Internal Signals Checked** | `log_wr_ptr` (bind) |
| **Expected Result** | After 16 events: `log_wr_ptr == 0` (wrapped). Events 17–20 overwrite slots 0–3. `LOG_COUNT` reflects wrapped state. `log_wr_ptr` advances modulo-16 per SVA-POL-01. |
| **Pass Criterion** | SVA-POL-01 passes for all 20 writes. Log scoreboard confirms slots 0–3 contain events 17–20 timestamps; slots 4–15 contain events 5–16. |
| **Fail Criterion** | Pointer does not wrap (sticks at 15); older slots not overwritten; data corruption at wrap boundary. |
| **SVA Coverage** | SVA-POL-01 |
| **Functional Coverage** | `cg_rec_policy_log`: log_entries_16, log_entries_overflow, all_16_slots_read bins |

---

### TP-ERR-03: Firmware Lockout Suppression (Core Test)

| Field | Value |
|---|---|
| **Test ID** | TP-ERR-03 |
| **Title** | Verify `RST_CTRL.trigger` still fires `reset_out` even when `lockout_flag=1` (hardware does NOT interlock) |
| **Feature(s)** | SOC-ERR-005 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_lockout_hw_test` |
| **Sequence** | Assert lockout, then still write RST_CTRL.trigger=1 |
| **Stimulus** | 1. Assert lockout_flag (via K events). 2. Write `RST_CTRL[0]=1` (trigger). |
| **Expected Result** | `reset_out` fires despite `lockout_flag=1`. Hardware does NOT block the trigger. **Lockout suppression is firmware-only** (firmware must check `POL_STATUS.lockout_flag` before writing `RST_CTRL`). |
| **Pass Criterion** | `reset_out_monitor` records a pulse after trigger write, even with lockout active. Document this as confirmed firmware-only behavior. |
| **Fail Criterion** | `reset_out` blocked by hardware when `lockout_flag=1` (would indicate RTL changed from `13_consistency_audit.md` finding). |
| **Notes** | Citation: `soc_top.v:1437–1472`. Hardware routes `trigger_req` directly to FSM with no lockout check. This test is **a safety validation**. |

---

### TP-ERR-04 / TP-MEM-01: DCCM ECC Error Injection (UNCLEAR)

| Field | Value |
|---|---|
| **Test ID** | TP-ERR-04 (also referenced as TP-MEM-01 in 12_test_plan_draft.md) |
| **Title** | DCCM ECC detection on single and double bit errors |
| **Feature(s)** | SOC-DAT-002 (ECC sub-feature), SOC-DEC-001 |
| **Bench** | Bench A |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_dccm_ecc_test` |
| **Sequence** | Force single-bit and double-bit errors in DCCM bank; observe core response |
| **Stimulus** | After writing known data to DCCM, force a 1-bit error in `ram_4096x39` (use `force` on ECC bit). Read back data. |
| **Expected Result** | Single-bit: ECC correction, data reads correctly, correctable error flag set. Double-bit: ECC detection, uncorrectable error trap taken. |
| **Pass Criterion** | Core behavior matches VeeR EL2 DCCM ECC spec. UNCLEAR — actual behavior depends on VeeR core internal configuration. Mark this test as UNCLEAR until VeeR DCCM ECC registers are confirmed. |
| **Fail Criterion** | No ECC correction/detection; core crashes on single-bit error. |
| **Notes** | **UNCLEAR** — This test depends on VeeR EL2 DCCM ECC configuration, which is not confirmed in RTL analysis. Mark as blocked until resolved. |

---

### TP-ERR-05: Unmapped Write Drops Data (No Side Effects)

| Field | Value |
|---|---|
| **Test ID** | TP-ERR-05 |
| **Title** | Unmapped address write returns DECERR and causes no side effects on any slave |
| **Feature(s)** | SOC-ERR-001, SOC-ERR-002 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_unmapped_write_test` |
| **Sequence** | Write to unmapped address; read all slaves; verify unchanged |
| **Stimulus** | Write `0xDEADBEEF` to `0x0002_0700` (unmapped). Then read base addresses of all slaves M00–M07. |
| **Expected Result** | All slave reads return their reset values (no slave received the write). `bresp == DECERR`. |
| **Pass Criterion** | All 8 slave monitors record zero write transactions. Scoreboard confirms all register states unchanged. |
| **Fail Criterion** | Any slave register modified by the unmapped write. |

---

## 15. Test Cases — Clock Group

### TP-CLK-01: pixel_clk_en Cadence

| Field | Value |
|---|---|
| **Test ID** | TP-CLK-01 |
| **Title** | `pixel_clk_en` pulses once every 4 `clk` cycles |
| **Feature(s)** | SOC-CLK-003 |
| **Bench** | Bench A or B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_pclk_cadence_test` |
| **Sequence** | Enable VGA; monitor `pixel_clk_en` for 100 cycles |
| **Stimulus** | Enable VGA (`VGA_CTRL[0]=1`). Observe `pixel_clk_en` via bind on `vga_controller`. |
| **Expected Result** | `pixel_clk_en` asserts for exactly 1 cycle every 4 cycles. No two consecutive cycles where `pixel_clk_en==1`. |
| **Pass Criterion** | SVA-CLK-01 passes for 100 consecutive cycles. |
| **Fail Criterion** | `pixel_clk_en` asserts on 2 consecutive cycles; period ≠ 4 cycles; any gap. |
| **SVA Coverage** | SVA-CLK-01 |
| **Notes** | `vga_controller.v:53–61`. Single clock domain — no CDC logic. |

---

### TP-CLK-02: Synchronous Reset Release

| Field | Value |
|---|---|
| **Test ID** | TP-CLK-02 |
| **Title** | All custom IP registers reach correct reset values synchronously on `rst_n` release |
| **Feature(s)** | SOC-CLK-001, SOC-CLK-002 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_sync_reset_test` |
| **Sequence** | `clk_rst_seq` (apply reset, release), immediate register readback on cycle 1 |
| **Stimulus** | Assert `rst_n=0` for 10 cycles. Release `rst_n=1`. Read all registers on cycle 1 after release. |
| **Expected Result** | All registers read back reset values on the very first cycle after `rst_n=1`. No `rst_n` asynchronous behavior (design is synchronous reset). |
| **Pass Criterion** | Consistent with TP-REG-01. All values stable from cycle 1. |
| **Fail Criterion** | Any register requires more than 1 cycle to reach reset value after `rst_n` release. |

---

### TP-CLK-03: JTAG CDC Integrity

| Field | Value |
|---|---|
| **Test ID** | TP-CLK-03 |
| **Title** | JTAG clock domain crossing does not cause metastability or data corruption |
| **Feature(s)** | SOC-CLK-004 |
| **Bench** | Bench A |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_jtag_cdc_test` |
| **Sequence** | JTAG agent reads/writes while core is executing; randomize JTAG clock phase |
| **Stimulus** | Drive `jtag_tck` at a random phase offset relative to `clk`. Issue JTAG register reads while the core is actively executing firmware. Repeat 100 times. |
| **Expected Result** | All JTAG responses are correct. No X propagation or timing violations visible in functional simulation. |
| **Pass Criterion** | All 100 JTAG register reads return correct values with no X-valued bits. |
| **Fail Criterion** | Any X value in `jtag_tdo`; incorrect register value returned. |

---

## 16. Test Cases — End-to-End / System Group

### TP-E2E-01: Cold Boot Firmware Execution

| Field | Value |
|---|---|
| **Test ID** | TP-E2E-01 |
| **Title** | Cold boot: power-on reset → Boot ROM → firmware init → peripheral test loop |
| **Feature(s)** | SOC-E2E-001, SOC-RST-001 |
| **Bench** | Bench A |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_coldboot_test` |
| **Sequence** | `clk_rst_seq` (cold reset), monitor UART output |
| **Stimulus** | Apply cold reset. Release. Preload ROM with `test_all.c` firmware. |
| **Expected Result** | Firmware completes peripheral initialization. UART `uart_tx` emits expected test output (e.g., `"TEST PASS"` string or register read-back values). All peripherals respond to firmware writes. |
| **Pass Criterion** | `uart_agent` monitor decodes expected string from `uart_tx`. No watchdog timeout fires during normal init. |
| **Fail Criterion** | Core never reaches firmware; `uart_tx` silent; unexpected IRQ fires. |

---

### TP-E2E-02: Watchdog Timeout and Reset Recovery

| Field | Value |
|---|---|
| **Test ID** | TP-E2E-02 |
| **Title** | Host stops sending heartbeats → watchdog fires → firmware triggers `reset_out` → host recovers |
| **Feature(s)** | SOC-E2E-003, SOC-CTRL-003, SOC-RST-003 |
| **Bench** | Bench A |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_watchdog_recovery_test` |
| **Sequence** | Normal heartbeat for 10 cycles, then gap (no pulses for HB_THRESHOLD cycles), then firmware response |
| **Stimulus** | 1. Firmware enables HBM. 2. Heartbeat agent sends 10 pulses. 3. Heartbeat agent stops (simulates host hang). 4. Let watchdog fire. 5. Firmware firmware reads `HB_STATUS`, records event to policy, triggers `reset_out`. |
| **Expected Result** | Sequence: `hb_irq` asserts → firmware ISR (or poll) detects → `POL_CTRL.record_event=1` → `RST_CTRL.trigger=1` → `reset_out` pulses low for `RST_HOLD_CYCLES` cycles → returns to 1. |
| **Pass Criterion** | `reset_out_monitor` records one complete pulse. No lockout (count < threshold). UART telemetry shows expected log output. |
| **Fail Criterion** | `reset_out` never fires; `hb_irq` not cleared; firmware deadlocks. |

---

### TP-E2E-03: Crash-Loop Lockout and Resumption

| Field | Value |
|---|---|
| **Test ID** | TP-E2E-03 |
| **Title** | Repeated watchdog timeouts exceed threshold → lockout asserted → firmware suppresses further resets → administrator clears |
| **Feature(s)** | SOC-E2E-004, SOC-E2E-005, SOC-ERR-005, SOC-CTRL-009 |
| **Bench** | Bench A |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_crashloop_lockout_test` |
| **Sequence** | Repeat watchdog→reset cycle K times, then verify lockout; then send UART clear command |
| **Stimulus** | Repeat watchdog timeout+reset cycle `POL_THRESHOLD` times within `POL_WINDOW`. After K-th event: observe `lockout_irq` and `lockout_flag`. Then: UART agent sends clear command; firmware writes `POL_CTRL.clear_lockout=1`. |
| **Expected Result** | After K events: `lockout_flag=1`, `lockout_irq` fires once. Firmware stops triggering `reset_out`. After clear: `lockout_flag=0`, watchdog monitoring resumes. |
| **Pass Criterion** | `reset_out_monitor` records exactly K reset pulses then zero. PIC IRQ monitor records exactly one `extintsrc_req[3]` pulse. After clear: another watchdog timeout generates another reset. |
| **Fail Criterion** | More than K resets before lockout; lockout persists after clear; second lockout_irq pulse on clear. |
| **Notes** | Lockout suppression in step "firmware stops triggering" is **firmware-enforced only** — hardware does NOT prevent the trigger. |

---

### TP-E2E-04: Normal Steady-State Operation

| Field | Value |
|---|---|
| **Test ID** | TP-E2E-04 |
| **Title** | Continuous heartbeat pulses maintain healthy state — no timeouts, no resets |
| **Feature(s)** | SOC-E2E-002 |
| **Bench** | Bench A |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_steady_state_test` |
| **Sequence** | Run for 10,000 cycles with periodic heartbeats at < threshold period |
| **Stimulus** | Enable HBM (threshold = 500). Send heartbeat every 100 cycles for 10,000 cycles. |
| **Expected Result** | `unresponsive_flag` remains 0. `reset_out` remains 1 (never fires). `lockout_flag` remains 0. `LOG_COUNT` remains 0. |
| **Pass Criterion** | All monitors show no unexpected events for 10,000 cycles. All SVAs pass continuously. |
| **Fail Criterion** | Any spurious `hb_irq`, `reset_out` pulse, or `lockout_flag` assertion. |

---

### TP-E2E-05: Simultaneous Multi-Peripheral Stress

| Field | Value |
|---|---|
| **Test ID** | TP-E2E-05 |
| **Title** | All peripherals active simultaneously under maximum bus traffic |
| **Feature(s)** | SOC-E2E-006 |
| **Bench** | Bench A |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_stress_test` |
| **Sequence** | Firmware runs tight loop accessing all peripherals; heartbeat agent fires every 200 cycles; UART agent sends/receives continuously |
| **Stimulus** | Firmware repeatedly reads all peripheral registers. Heartbeat agent sends pulses. UART agent sends a stream of 100 bytes. VGA buffer is updated every 1000 cycles. |
| **Expected Result** | No AXI deadlock. No protocol violations. No register corruption (all reads return expected values). All peripheral interactions complete correctly. |
| **Pass Criterion** | All SVAs pass for the entire stress duration. No scoreboard mismatches. |
| **Fail Criterion** | Any AXI hang; wrong register value; spurious IRQ or reset during normal operation. |

---

## 17. Test Cases — Spec Gap Group

### TP-GAP-01: Heartbeat Pulse/Timeout Collision

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-01 |
| **Title** | Rising edge on `heartbeat_in` on the exact cycle `hb_counter == HB_THRESHOLD` |
| **Feature(s)** | SOC-CTRL-001, SOC-CTRL-003 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_hbm_collision_test` |
| **Sequence** | Count cycles to threshold, drive rising edge on exact timeout cycle |
| **Stimulus** | Enable HBM (threshold=50). At cycle 50 exactly (when `hb_counter` would hit `HB_THRESHOLD`), drive `heartbeat_in` rising edge. |
| **Internal Signals Checked** | `hb_counter`, `unresponsive_flag`, `hb_irq` (bind) |
| **Expected Result** | **UNDEFINED** — document actual RTL behavior. Either: (a) counter reset wins → no timeout; or (b) comparator wins → 1-cycle `unresponsive_flag`, then cleared by edge. |
| **Pass Criterion** | Behavior is one of the two options above. **No X-state**. `hb_counter` and `unresponsive_flag` have deterministic values. |
| **Fail Criterion** | X on any output; oscillation; deadlock. |
| **Notes** | Spec Gap 1 from `09_open_questions.md`. Result must be documented as the defined hardware behavior. |

---

### TP-GAP-02: AXI Access During Reset Assertion

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-02 |
| **Title** | AXI transaction attempted while `rst_n=0` terminates cleanly |
| **Feature(s)** | SOC-CLK-001 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_axi_during_reset_test` |
| **Sequence** | Assert `rst_n=0` mid-transaction; verify clean termination |
| **Stimulus** | Issue AXI read. While ARVALID is asserted, drop `rst_n=0` for 10 cycles, then release. |
| **Expected Result** | Transaction either completes before reset, or is cleanly discarded. No AXI bus hang after reset release. DUT recovers to reset state. |
| **Pass Criterion** | After `rst_n` release, all registers read back reset values. No hung AXI channel. |
| **Fail Criterion** | AXI bus stuck after reset release; X on any output. |
| **Notes** | Spec Gap 2 from `09_open_questions.md`. |

---

### TP-GAP-03: Log Wrap Detection by Firmware

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-03 |
| **Title** | No `log_full` flag: verify firmware can detect overflow only via `LOG_COUNT == 16` |
| **Feature(s)** | SOC-ERR-004, SOC-REG-010 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_log_full_detect_test` |
| **Sequence** | Write 17 events; read LOG_COUNT; confirm no flag exists |
| **Stimulus** | Write 17 events. Read `LOG_COUNT`. Read `POL_STATUS`. |
| **Expected Result** | `LOG_COUNT == 16` (or wraps — document actual behavior). No `log_full` bit in `POL_STATUS` (there is no such bit in RTL). Firmware must infer overflow from count. |
| **Pass Criterion** | `LOG_COUNT` behavior documented. `POL_STATUS` has no `log_full` bit set. |
| **Fail Criterion** | `POL_STATUS` has an undocumented `log_full` bit (would be RTL vs doc mismatch). |

---

### TP-GAP-04: Reset Sequencer Retrigger at ASSERT→DEASSERT Boundary

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-04 |
| **Title** | Trigger write on exact cycle `rst_countdown == 0` (ASSERT→DEASSERT boundary) |
| **Feature(s)** | SOC-CTRL-006 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_rst_boundary_retrigger_test` |
| **Sequence** | Trigger reset; write trigger again on the exact cycle rst_countdown reaches 0 |
| **Stimulus** | `RST_HOLD_CYCLES=10`. Trigger reset. At cycle 10 (when `rst_countdown==0`), write `RST_CTRL[0]=1` again. |
| **Expected Result** | **UNDEFINED** — document behavior: either new trigger ignored (FSM in DEASSERT, not IDLE), or new trigger accepted (FSM transitions back to ASSERT). |
| **Pass Criterion** | Deterministic behavior (no X). `reset_out` duration documented. |
| **Fail Criterion** | X state; illegal FSM transition. |
| **Notes** | Spec Gap 4 from `09_open_questions.md`. |

---

### TP-GAP-05: Record Event on Window Rollover Cycle

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-05 |
| **Title** | `POL_CTRL.record_event` written on exact cycle `window_counter == POL_WINDOW` |
| **Feature(s)** | SOC-CTRL-007, SOC-CTRL-010 |
| **Bench** | Bench B |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_pol_event_boundary_test` |
| **Sequence** | Wait for window_counter to be 1 cycle before rollover; write record_event on boundary cycle |
| **Stimulus** | `POL_WINDOW=100`. At cycle 100 (boundary), write `POL_CTRL.record_event=1`. |
| **Expected Result** | **UNDEFINED** — document whether event is counted in old window (count increments before reset) or new window (count=1 after reset). |
| **Pass Criterion** | Deterministic output. `window_recovery_count` has a defined value (0 or 1). No X. |
| **Fail Criterion** | X state on `window_recovery_count`; inconsistent behavior across runs. |
| **Notes** | Spec Gap 5 from `09_open_questions.md`. |

---

### TP-GAP-06: UART Gasket with Interleaved Multi-Master Access

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-06 |
| **Title** | Concurrent S00 and S01 writes to UART gasket: verify `uart_awaddr2_r` not corrupted |
| **Feature(s)** | SOC-DAT-003 |
| **Bench** | Bench B (two AXI VIP masters) |
| **Priority** | HIGH |
| **UVM Test Class** | `soc_uart_gasket_concurrent_test` |
| **Sequence** | Two VIP masters simultaneously issue writes to different UART registers |
| **Stimulus** | S00 writes to `0x0002_0000` (addr[2]=0). S01 writes to `0x0002_0004` (addr[2]=1) in the same cycle. |
| **Internal Signals Checked** | `uart_awaddr2_r` (bind or hierarchical ref) |
| **Expected Result** | `uart_awaddr2_r` is not corrupted. Each write reaches its correct 32-bit lane. Arbitration correctly serializes the two accesses. |
| **Pass Criterion** | Both writes complete. UART register values match expected. `uart_awaddr2_r` holds the correct value for the winning master's address. |
| **Fail Criterion** | Wrong byte lane selected; register value mixed from both masters' data; bus corruption. |
| **Notes** | Spec Gap 6 from `09_open_questions.md`. This is Risk Rank 3 from `09_open_questions.md`. |

---

### TP-GAP-07: Lockout Persistence Across Window Rollover

| Field | Value |
|---|---|
| **Test ID** | TP-GAP-07 |
| **Title** | `lockout_flag` remains set across window rollover; new events after clear are counted fresh |
| **Feature(s)** | SOC-CTRL-009, SOC-REG-005 |
| **Bench** | Bench B |
| **Priority** | MEDIUM |
| **UVM Test Class** | `soc_lockout_persist_test` |
| **Sequence** | Assert lockout; wait for window rollover; verify lockout still set |
| **Stimulus** | Assert lockout (K events). Wait 2× `POL_WINDOW` cycles. Read `POL_STATUS`. |
| **Expected Result** | `lockout_flag` remains 1 despite window rollover. `window_recovery_count` has reset to 0 (new window). `lockout_flag` is sticky until `clear_lockout` written. |
| **Pass Criterion** | `POL_STATUS[0] == 1` after window rollover. `window_recovery_count == 0`. |
| **Fail Criterion** | `lockout_flag` cleared by window rollover (would be incorrect hardware behavior). |

---

## 18. Regression Strategy

### 18.1 Test Groups

| Group | Bench | Tests | Run Mode | Seeds |
|---|---|---|---|---|
| Directed Sanity | Bench B | TP-RST-01..04, TP-DEC-01..05, TP-REG-01..06 | Directed (1 seed) | 1 |
| Register Batch | Bench B | All TP-REG, TP-DAT-01..06 | Directed | 1 |
| Control Batch | Bench B | All TP-CTRL, TP-ARB, TP-ERR, TP-CLK | Directed | 1 |
| Interrupt Batch | Bench A | All TP-IRQ | Directed | 1 |
| Spec Gap Batch | Bench B | All TP-GAP | Directed | 1 |
| E2E Batch | Bench A | All TP-E2E | Directed | 1 |
| **Random Regression** | **Bench B** | All Bench B tests | **Randomized** | **500** |
| Nightly Full | Bench A + B | All tests | Both | 50 |

### 18.2 Random Regression (500-Seed)
- **Bench:** Bench B only (core-stubbed). The 500-seed regression must NOT run on Bench A due to firmware compilation time.
- **Randomized parameters:** AXI burst length (1–8), AXI address within each slave window, heartbeat period (1–10,000 cycles), `POL_THRESHOLD` (1–15), `POL_WINDOW` (50–100,000), `RST_HOLD_CYCLES` (1–10,000), UART baud divisor, backpressure injection enable/disable.
- **Fixed constraints:** Address must not alias across slaves. `RST_HOLD_CYCLES ≥ 1`. `POL_THRESHOLD ≥ 1`. UART DLL+DLM must produce a valid baud rate.
- **Seed management:** Seeds 0–499. Failed seeds are reported with the full random seed value for reproduction. Failed seeds are not excluded from coverage merging.
- **Coverage merge:** All 500 seeds merge into one coverage database per regression run. Failing runs below 95% functional coverage trigger a coverage gap analysis.

### 18.3 Simulator Configuration

```makefile
# Simulation tool: VCS (Synopsys)
VCS_FLAGS  = -full64 -sverilog -debug_access+all
VCS_FLAGS += -cm line+cond+fsm+branch+tgl
VCS_FLAGS += +define+SIMULATION
VCS_FLAGS += -timescale=1ns/1ps

# UVM
UVM_FLAGS  = +UVM_TESTNAME=$(TEST)
UVM_FLAGS += +UVM_VERBOSITY=UVM_MEDIUM
UVM_FLAGS += +UVM_MAX_QUIT_COUNT=5

# Coverage
COV_FLAGS  = -cm_name $(TEST)_$(SEED)
COV_FLAGS += -cm_dir coverage/$(TEST)

# FSDB / waveform
FSDB_FLAGS = +fsdb+functions+all -o waves/$(TEST)_$(SEED).fsdb

# Regression
regression:
    for seed in $(seq 0 499); do \
        vcs $(VCS_FLAGS) $(COV_FLAGS) $(UVM_FLAGS) \
            +ntb_random_seed=$$seed \
            -l logs/regr_$$seed.log ; \
    done
    urg -dir coverage/ -format both -dbname merged_coverage
```

---

## 19. RAL Exclusion List

The following registers and fields are excluded from `uvm_reg_hw_reset_seq` and/or `uvm_reg_bit_bash_seq`. Each exclusion has an RTL-verified justification.

| Register | Exclusion Type | Reason | RTL Citation |
|---|---|---|---|
| `RST_CTRL[0]` (trigger) | `uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq` | Self-clearing write-1 field. Writing 1 starts a hardware state machine (RST FSM). Cannot be tested with standard reset/bit-bash sequences without disturbing DUT state. | `reset_sequencer.v:48` |
| `HB_CTRL[0]` (enable) | `uvm_reg_bit_bash_seq` | Toggling enable bit transitions the HBM FSM between DISABLED and active states, invalidating other concurrent register tests. Must be controlled explicitly. | `heartbeat_monitor.v:58` |
| `HB_CTRL[1]` (clear_flag) | `uvm_reg_bit_bash_seq` | W1C field. Writing 1 clears `unresponsive_flag`. Bit-bash sequence will clear flags set by other concurrent stimulus, breaking scoreboard state. | `heartbeat_monitor.v:59` |
| `UART_FCR` (full register) | `uvm_reg_bit_bash_seq` | Write-only register. Writing random values clears/resets TX and RX FIFOs, corrupting any in-progress UART transfer. | `axi_uart_top.v:48` |
| `UART_THR` (full register) | `uvm_reg_bit_bash_seq` | Write-only. Writing pushes data into TX FIFO. Bit-bash would fill TX FIFO with garbage bytes and corrupt UART output. | `axi_uart_top.v:530` |
| `UART_LCR[7]` (DLAB) | `uvm_reg_bit_bash_seq` | DLAB bit remaps register offsets 0x00 and 0x04. Toggling DLAB during bit-bash changes which registers are accessible and breaks offset-to-register mapping. | `axi_uart_top.v:533` |
| `POL_CTRL[0]` (record_event) | `uvm_reg_bit_bash_seq` | W1P (write-1-pulse). Writing 1 commits an event to the circular log and increments `window_recovery_count`. Bit-bash will generate spurious events and potentially trigger lockout. | `recovery_policy.v:100` |
| `POL_CTRL[1]` (clear_lockout) | `uvm_reg_bit_bash_seq` | W1C. Clears `lockout_flag`. Writing during lockout test would invalidate concurrent control path tests. | `recovery_policy.v:148` |
| `VGA_BUFFER[0..29]` | `uvm_reg_bit_bash_seq` | Bit-bash on character buffer may corrupt display state being verified by VGA monitor scoreboard in parallel. Test via TP-REG-05 instead. | `vga_controller.v:114` |

---

## 20. Sign-off Criteria

### 20.1 Code Coverage Targets

| Metric | Target | Mandatory |
|---|---|---|
| Line coverage (custom IPs + soc_top) | ≥ 90% | Yes |
| Branch coverage | ≥ 85% | Yes |
| FSM state coverage (all FSMs) | 100% | Yes |
| FSM transition coverage | ≥ 95% | Yes |
| Toggle coverage | ≥ 80% | No |
| Condition coverage | ≥ 80% | No |

### 20.2 Functional Coverage Targets

| Covergroup | Target |
|---|---|
| `cg_heartbeat_fsm` | 100% bins + transitions |
| `cg_rst_seq_fsm` | 100% bins + transitions |
| `cg_rec_policy_lockout` | 100% bins |
| `cg_rec_policy_log` | ≥ 95% bins |
| `cg_axi_decode` | 100% bins |
| `cg_axi_resp` | 100% bins (EXOKAY/SLVERR bins must be **zero hits**) |
| `cg_irq_lines` | 100% bins |
| `cg_uart_path` | ≥ 90% bins |
| `cg_vga_buffer` | ≥ 90% bins |
| `cg_heartbeat_threshold` | ≥ 90% bins |
| `cg_rst_hold_cycles` | ≥ 90% bins |

### 20.3 Test Execution Criteria

| Criterion | Requirement |
|---|---|
| All directed tests pass | 100% pass rate (no waivers without written RTL justification) |
| 500-seed random regression | ≥ 495/500 pass (≤ 1% failure rate); all failures root-caused |
| Zero UVM\_FATAL | Mandatory |
| Zero AXI protocol violations (SVA-AXI-*) | Mandatory |
| Zero X on DUT outputs | Mandatory |
| All spec gap tests executed | Mandatory (pass/fail based on documented behavior, not expected behavior) |

### 20.4 Open Question Resolution

The following open questions from `09_open_questions.md` must be resolved before final sign-off:

| OQ | Question | Blocking Test(s) |
|---|---|---|
| OQ-03 | S02 masking: is the response DECERR or no-response? | TP-DEC-03 (knob) |
| OQ-06 | Boot ROM write: what `bresp` is returned? | TP-ERR-01 |
| OQ-07 | DCCM ECC: correctable/uncorrectable trap behavior? | TP-ERR-04 |

### 20.5 Waiver Policy
- Any test marked **UNCLEAR** requires written RTL analysis to confirm behavior before waiver is approved.
- Waivers for OQ items require the actual RTL behavior to be documented in `09_open_questions.md` as a resolution.
- No waiver is permitted for mandatory FSM coverage or AXI protocol SVA items.

---

## 21. Feature-to-Test Traceability Matrix

| Feature ID | Feature Summary | Test Case(s) | Coverage |
|---|---|---|---|
| SOC-RST-001 | Boot from ROM at `0x8000_0000` | TP-RST-01 | SVA-RST-01, `cg_rst_seq_fsm` |
| SOC-RST-002 | RST Seq idle with reset_out=1 | TP-RST-02 | `cg_rst_seq_fsm` ST_IDLE |
| SOC-RST-003 | RST Seq fires on trigger | TP-RST-03 | SVA-RST-01..04 |
| SOC-RST-004 | Duration matches RST_HOLD_CYCLES | TP-RST-03 | `cg_rst_hold_cycles` |
| SOC-RST-005 | RST_STATUS.complete set | TP-RST-03 | RAL readback |
| SOC-RST-006 | reset_out does NOT reset VeeR | TP-RST-02 | `reset_out_monitor` |
| SOC-RST-007 | GPIO_STAT[1] tracks reset_out | TP-RST-04 | RAL comparison |
| SOC-DEC-001 | DCCM routing | TP-DEC-01, TP-DAT-01, TP-MEM-01 | `cg_axi_decode` |
| SOC-DEC-002 | Boot ROM routing | TP-DEC-01, TP-DAT-05 | `cg_axi_decode` |
| SOC-DEC-003 | Peripheral routing M00–M06 | TP-DEC-01, TP-DEC-05 | `cg_axi_decode` |
| SOC-DEC-004 | Unmapped → DECERR | TP-DEC-02, TP-ERR-05 | `cg_axi_resp` |
| SOC-DEC-005 | S00+S01 full access | TP-DEC-01, TP-ARB-01 | `cg_axi_decode` |
| SOC-DEC-006 | S02 blocked from M00–M06 | TP-DEC-03 | `cg_axi_decode` |
| SOC-DEC-007 | S02 can access M07 | TP-DEC-04 | `cg_axi_decode` |
| SOC-REG-001 | HBM register R/W | TP-REG-01 | RAL |
| SOC-REG-002 | clear_flag clears status | TP-REG-02 | SVA-HB-04 |
| SOC-REG-003 | RST Seq register R/W | TP-REG-01, TP-RST-03 | RAL |
| SOC-REG-004 | POL register R/W | TP-REG-01, TP-CTRL-04 | RAL |
| SOC-REG-005 | clear_lockout clears flag | TP-REG-06 | RAL, SVA-POL-04 |
| SOC-REG-006 | TMR_CTR read | TP-REG-01 | RAL |
| SOC-REG-007 | GPIO_STAT read | TP-REG-01, TP-RST-04 | RAL |
| SOC-REG-008 | UART register set | TP-REG-01, TP-DAT-03 | RAL |
| SOC-REG-009 | RO write protection | TP-REG-03 | RAL bit-bash |
| SOC-REG-010 | Log indexed readback | TP-REG-04, TP-GAP-03 | `cg_rec_policy_log` |
| SOC-REG-011 | VGA buffer R/W | TP-REG-05 | `cg_vga_buffer` |
| SOC-DAT-001 | 64-bit ROM burst fetch | TP-DAT-05 | AXI S00 monitor |
| SOC-DAT-002 | DCCM 64-bit byte enable & ECC | TP-DAT-01, TP-ERR-04 (TP-MEM-01) | Memory model |
| SOC-DAT-003 | UART gasket addr[2] steering | TP-DAT-02, TP-GAP-06 | SVA on gasket |
| SOC-DAT-004 | UART TX FIFO serialize | TP-DAT-03 | UART scoreboard |
| SOC-DAT-005 | UART RX FIFO deserialize | TP-DAT-03 | UART scoreboard |
| SOC-DAT-006 | VGA render to RGB raster | TP-DAT-04 | VGA frame scoreboard |
| SOC-DAT-007 | AXI backpressure | TP-DAT-06 | SVA-AXI-01 |
| SOC-CTRL-001 | HBM edge detection | TP-CTRL-01, TP-GAP-01 | SVA-HB-02 |
| SOC-CTRL-002 | HBM counter reset on edge | TP-CTRL-01 | SVA-HB-02 |
| SOC-CTRL-003 | Watchdog timeout flag | TP-CTRL-02, TP-GAP-01 | SVA-HB-03 |
| SOC-CTRL-004 | HBM disable behavior | TP-CTRL-07 | `cg_heartbeat_fsm` |
| SOC-CTRL-005 | RST Seq FSM transitions | TP-CTRL-08, TP-RST-03 | SVA-RST-01..04 |
| SOC-CTRL-006 | RST re-trigger rejection | TP-CTRL-03, TP-GAP-04 | SVA-RST-05 |
| SOC-CTRL-007 | POL timestamp log commit | TP-CTRL-04, TP-GAP-05 | Scoreboard shadow |
| SOC-CTRL-008 | POL increments window count | TP-CTRL-04 | RAL readback |
| SOC-CTRL-009 | POL lockout + lockout_irq pulse | TP-CTRL-04, TP-IRQ-01 | SVA-POL-03, SVA-POL-04 |
| SOC-CTRL-010 | Rolling window reset | TP-CTRL-05, TP-CTRL-06, TP-GAP-05 | SVA-POL-02 |
| SOC-ARB-001 | Round-robin arbitration | TP-ARB-01 | Arbiter scoreboard |
| SOC-ARB-002 | Concurrent R+W channels | TP-ARB-03 | Protocol scoreboard |
| SOC-ARB-003 | Interleaved AW+W acceptance | TP-ARB-02, TP-GAP-06 | SVA-AXI-02 |
| SOC-ARB-004 | Burst atomicity | TP-ARB-04 | SVA-AXI-04 |
| SOC-IRQ-001 | uart_irq → PIC line 0 | TP-IRQ-03 | PIC IRQ monitor |
| SOC-IRQ-002 | hb_irq → PIC line 1 | TP-CTRL-02, TP-IRQ-03 | PIC IRQ monitor |
| SOC-IRQ-003 | vblank_irq → PIC line 2 | TP-IRQ-04 | PIC IRQ monitor |
| SOC-IRQ-004 | lockout_irq 1-cycle → PIC line 3 | TP-CTRL-04, TP-IRQ-01 | SVA-POL-04, PIC monitor |
| SOC-IRQ-005 | PIC arbitration + priority | TP-IRQ-01, TP-IRQ-02 | PIC internal signals |
| SOC-ERR-001 | Unmapped read → DECERR | TP-DEC-02, TP-ERR-05 | `cg_axi_resp` |
| SOC-ERR-002 | Unmapped write → DECERR, no effect | TP-DEC-02, TP-ERR-05 | Scoreboard |
| SOC-ERR-003 | Boot ROM write terminates cleanly | TP-ERR-01 | Protocol monitor |
| SOC-ERR-004 | Log circular wrap at 16 | TP-ERR-02, TP-GAP-03 | SVA-POL-01 |
| SOC-ERR-005 | Firmware lockout suppression (HW fires anyway) | TP-ERR-03 | reset_out_monitor |
| SOC-CLK-001 | Sync reset to legal defaults | TP-REG-01, TP-CLK-02, TP-GAP-02 | RAL |
| SOC-CLK-002 | VeeR core sync reset release | TP-CLK-02 | SVA-CLK-02 |
| SOC-CLK-003 | pixel_clk_en every 4 cycles | TP-CLK-01 | SVA-CLK-01 |
| SOC-CLK-004 | JTAG CDC integrity | TP-CLK-03 | Protocol monitor |
| SOC-E2E-001 | Cold boot firmware execution | TP-E2E-01 | UART monitor |
| SOC-E2E-002 | Normal steady-state | TP-E2E-04 | System scoreboard |
| SOC-E2E-003 | Watchdog + reset recovery | TP-E2E-02 | E2E scoreboard |
| SOC-E2E-004 | Crash-loop lockout | TP-E2E-03 | E2E scoreboard |
| SOC-E2E-005 | Lockout override | TP-E2E-03 | E2E scoreboard |
| SOC-E2E-006 | Multi-peripheral stress | TP-E2E-05 | Stress scoreboard |

---

*End of Document — HRSOC-TP-001 Rev 1.0*
