# RISC-V Baseboard Management Controller (BMC) SoC

[![Processor](https://img.shields.io/badge/CPU-VeeR--EL2%20(RV32IMC)-blue.svg)](docs/BMC_Architecture_MicroArchitecture_Spec.md#2-processor-core-veer-el2)
[![Interconnect](https://img.shields.io/badge/Interconnect-AXI4%2064--bit%203x8-orange.svg)](docs/BMC_Architecture_MicroArchitecture_Spec.md#3-interconnect-subsystem-axi4-3x8)
[![EDA Verification](https://img.shields.io/badge/Simulation-Synopsys%20VCS%20%26%20Verdi-red.svg)](docs/vcs_verdi_guide.md)
[![Toolchain](https://img.shields.io/badge/Toolchain-RISC--V%20GCC-green.svg)](docs/clean_machine_setup_guide.md)
[![Test Status](https://img.shields.io/badge/Tests-17%2F17%20Passed%20(100%25)-brightgreen.svg)](docs/SOC_VERIFICATION_AND_IP_REPORT.md)
[![License](https://img.shields.io/badge/License-Apache--2.0-lightgrey.svg)](#license--acknowledgements)

A complete, synthesizable server **Baseboard Management Controller (BMC) System-on-Chip (SoC)** built around the **Western Digital / CHIPS Alliance VeeR EL2** 32-bit RISC-V processor core and a high-performance **64-bit AXI4 crossbar interconnect**.

Designed for enterprise servers, cloud infrastructure, and hyperscale datacenters, this SoC provides hardware-enforced health monitoring, autonomous fault recovery, crash-loop lockout protection, and out-of-band management console telemetry.

---

## Key Features

- **Processor Core**: CHIPS Alliance VeeR EL2 (RV32IMC), 4-stage dual-issue superscalar pipeline, tightly coupled memories (64 KB DCCM with 7-bit ECC, ICCM bypass for direct AXI streaming), and integrated Programmable Interrupt Controller (PIC).
- **Interconnect**: 64-bit 3-Master $\times$ 8-Slave AXI4 crossbar (`axi_interconnect_wrap_3x8`) with round-robin arbitration, dynamic bus width conversion (64-bit to 32-bit), and address steering.
- **Hardware-Enforced BMC Subsystems**:
  - **Heartbeat Monitor IP**: Continuous pulse timing tracking with hardware timeout detection and sticky fault latching.
  - **Power/Reset Sequencer IP**: Programmable, atomic active-low reset pulse generation to safely cycle host CPU power.
  - **Recovery Policy & Event Log IP**: 16-entry circular RAM event log with rolling window recovery rate monitoring and automated crash-loop lockout.
  - **VGA Status Dashboard**: Real-time 640x480 @ 60Hz video engine driving a 3-row $\times$ 40-column hardware text console.
  - **16550 AXI UART**: Standard serial management console streaming boot logs and runtime telemetry at 115200 baud.
  - **System Timer & GPIO**: 32-bit monotonic uptime tick counter and external pin status monitoring.

---

## SoC Architecture

```
+----------------------------------------------------------------------------------------------------+
|                                    BMC SYSTEM-ON-CHIP (SoC)                                        |
|                                                                                                    |
|  +--------------------+      +--------------------+      +--------------------+      +----------+  |
|  |   VeeR EL2 Core    |      |  64-bit AXI4 3x8   |      | Custom BMC IPs     |      | External |  |
|  |  (RV32IMC, 100MHz) | <--> | Interconnect Cross | <--> | - Heartbeat Mon    | <--> | Host CPU |  |
|  |  - 64KB DCCM (ECC) |      | - LSU / IFU / SB   |      | - Reset Sequencer  |      | System   |  |
|  +--------------------+      +--------------------+      | - Recovery Policy  |      +----------+  |
|                                                          | - VGA Dashboard    |                    |
|  +--------------------+      +--------------------+      | - 16550 AXI UART   |      +----------+  |
|  | 8KB Boot AXI ROM   | <--> | Address Steering   |      | - Timer / GPIO     | <--> | Operator |  |
|  | (firmware.hex)     |      | 64-bit to 32-bit   |      +--------------------+      | Terminal |  |
|  +--------------------+      +--------------------+                                  +----------+  |
+----------------------------------------------------------------------------------------------------+
```

![Top-Level BMC SoC Architecture](docs/images/BMC_Architecture_Block_Diagrams-Top-Level%20SoC.drawio.png)

### Top-Level External Interfaces

| Signal | Direction | Width | Domain | Description |
| :--- | :---: | :---: | :---: | :--- |
| `clk`, `rst_n` | Input | 1, 1 | System | 100 MHz system clock and active-low master reset |
| `heartbeat_in` | Input | 1 | Monitored | Periodic heartbeat strobe from host CPU |
| `reset_out` | Output | 1 | Monitored | Active-low reset pulse driving host power/reset lines |
| `uart_rx`, `uart_tx` | In / Out | 1, 1 | Console | Management serial console (115200 baud) |
| `vga_hsync`, `vga_vsync`, `vga_rgb` | Output | 1, 1, 12 | Video | Standard 640x480 @ 60Hz VGA interface (12-bit RGB) |
| `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo` | In / Out | 1, 1, 1, 1 | Debug | VeeR EL2 JTAG debug interface |

> Detailed microarchitecture specifications, pipeline diagrams, and FSM descriptions are documented in [`docs/BMC_Architecture_MicroArchitecture_Spec.md`](docs/BMC_Architecture_MicroArchitecture_Spec.md).

---

## Memory Map Summary

The SoC implements a unified memory map spanning processor TCM, memory-mapped peripherals, and synchronous boot ROM:

| Slave Port | Base Address | Address Range | Size | Target Peripheral | Reference |
| :---: | :---: | :---: | :---: | :--- | :--- |
| — | `0x0000_0000` | `0x0000_0000` – `0x0000_FFFF` | 64 KB | ICCM (Instruction Memory) | Core TCM |
| — | `0xF004_0000` | `0xF004_0000` – `0xF004_FFFF` | 64 KB | DCCM (Data Memory with ECC) | Core TCM |
| **Slave 0** | `0x0002_0000` | `0x0002_0000` – `0x0002_00FF` | 256 B | **16550 UART Serial Controller** | [Register Map](docs/Register_Map.md#slave-0-axi_uart_top) |
| **Slave 1** | `0x0002_0100` | `0x0002_0100` – `0x0002_01FF` | 256 B | **32-bit System Uptime Timer** | [Register Map](docs/Register_Map.md#slave-1-axi_timer) |
| **Slave 2** | `0x0002_0200` | `0x0002_0200` – `0x0002_02FF` | 256 B | **GPIO Pin Status Register** | [Register Map](docs/Register_Map.md#slave-2-axi_gpio) |
| **Slave 3** | `0x0002_0300` | `0x0002_0300` – `0x0002_03FF` | 256 B | **Heartbeat Monitor IP** | [Register Map](docs/Register_Map.md#slave-3-axi_heartbeat_monitor) |
| **Slave 4** | `0x0002_0400` | `0x0002_0400` – `0x0002_04FF` | 256 B | **Power/Reset Sequencer IP** | [Register Map](docs/Register_Map.md#slave-4-axi_reset_sequencer) |
| **Slave 5** | `0x0002_0500` | `0x0002_0500` – `0x0002_05FF` | 256 B | **Recovery Policy & Event Log** | [Register Map](docs/Register_Map.md#slave-5-axi_recovery_policy) |
| **Slave 6** | `0x0002_0600` | `0x0002_0600` – `0x0002_06FF` | 256 B | **VGA Status Dashboard Controller** | [Register Map](docs/Register_Map.md#slave-6-axi_vga_controller) |
| **Slave 7** | `0x8000_0000` | `0x8000_0000` – `0x8000_1FFF` | 8 KB | **Synchronous AXI Boot ROM** | [Register Map](docs/Register_Map.md#slave-7-axi_rom) |

> For complete register offsets, bitfield definitions, and access rules, refer to [`docs/Register_Map.md`](docs/Register_Map.md).

---

## Quickstart Guide

### Prerequisites
- **Toolchain**: `riscv64-unknown-elf-gcc` (or `riscv32-unknown-elf-gcc`) with RV32IMC support.
- **Simulator**: Synopsys VCS (`vcs`, `simv`) and Verdi (`verdi`) for waveform analysis.
- *Detailed environment setup instructions are available in [`docs/clean_machine_setup_guide.md`](docs/clean_machine_setup_guide.md).*

### Build & Run in 3 Steps

```bash
# 1. Cross-compile bare-metal C firmware into bootable ROM hex
make build_firmware

# 2. Run full end-to-end SoC simulation (VeeR EL2 core + AXI bus + peripheral IPs)
make sim_core

# 3. (Optional) Inspect full-system execution waveforms in Synopsys Verdi
make waves_core
```

### Common Make Targets

| Command | Purpose |
| :--- | :--- |
| `make build_firmware` | Compiles `firmware/` C/assembly code into `program.hex` / `firmware.hex` |
| `make sim_core` | **Full SoC Simulation**: Boots VeeR EL2, runs bare-metal IP test suite, streams UART output |
| `make sim_soc` | Peripheral subsystem integration testbench |
| `make sim_axi` | Standalone 3x8 AXI Interconnect crossbar verification |
| `make sim_all` | Runs complete regression test suite across all units and subsystems |
| `make waves_core` | Opens Synopsys Verdi with preloaded SoC signal layouts (`waves/soc_top_wave.rc`) |
| `make clean` | Removes compiled binaries, simulation executables, and waveform databases |

---

## Verification & Regression Status

All hardware IP blocks and top-level integration suites are fully verified using Synopsys VCS:

| Test Suite | Makefile Target | Scope & Coverage | Tests | Status |
| :--- | :--- | :--- | :---: | :---: |
| **Full SoC Core** | `make sim_core` | VeeR EL2 core boot, AXI ROM fetch, C firmware IP validation suite | 17 / 17 | **PASS** |
| **SoC Subsystem** | `make sim_soc` | Peripheral integration, timeout fault injection, reset assertion | 17 / 17 | **PASS** |
| **AXI Crossbar** | `make sim_axi` | 3x8 Crossbar concurrent arbitration, bus width conversion, routing | 18 / 18 | **PASS** |
| **Heartbeat Monitor** | `make sim_hbm` | Pulse timing, timeout detection, sticky flag latching | 9 / 9 | **PASS** |
| **Reset Sequencer** | `make sim_rst` | Active-low pulse duration, atomic execution, busy-lock | 12 / 12 | **PASS** |
| **Recovery Policy** | `make sim_pol` | Rolling window tracking, circular event log wrap, crash lockout | 16 / 16 | **PASS** |
| **Top Elaboration** | `make compile_top` | RTL syntax check, structural elaboration, port connectivity | 0 errors | **PASS** |

<details>
<summary><b>View End-to-End Simulation Output Log (<code>make sim_core</code>)</b></summary>

```text
================================================================
 [TB] BMC SoC System Simulation Initialized
 [TB] Clock: 100 MHz | UART Baud: 115200 (Divisor: 16)
 [TB] AXI ROM initialized with firmware.hex
================================================================

 [TB] Reset deasserted (rst_n = 1). VeeR EL2 core booting from 0x80000000...

====================================================
  BMC System-on-Chip: Complete Hardware IP Test Suite
  Processor Core: VeeR EL2 (RV32IMC Bare-Metal)
====================================================

[TEST 1] Verifying System Timer (TMR_CTR)...
  Timer t1: 0x0000948A, t2: 0x0000A114
  [PASS] Timer monotonic counter incrementing

[TEST 2] Verifying GPIO Pin Status (GPIO_STAT)...
  GPIO Status: 0x00000002
  [PASS] GPIO indicates reset_out HIGH (active-low deasserted)

[TEST 3] Verifying Heartbeat Monitor IP...
  [PASS] HB_THRESHOLD register write/readback (50000)
  [PASS] HB_STATUS unresponsive flag is CLEAR
  [PASS] HB_CTRL petting command executed successfully

[TEST 4] Verifying Power/Reset Sequencer IP...
  Default RST_HOLD_CYCLES: 100
  [PASS] RST_HOLD_CYCLES reset value is 100
  [PASS] RST_HOLD_CYCLES write/readback (60)
  [PASS] RST_STATUS indicates idle (not in progress)

[TEST 5] Verifying Recovery Policy & Event Log IP...
  [PASS] POL_WINDOW write/readback (200000)
  [PASS] POL_THRESHOLD write/readback (3)
  [PASS] POL_STATUS lockout cleared
  [PASS] LOG_COUNT updated to 1 after Event 1
  Log[0] Data: 0x11223344
  [PASS] Circular Log Entry 0 matches staged timestamp 0x11223344
  [PASS] LOG_COUNT updated to 2 after Event 2
  Log[1] Data: 0xAABBCCDD
  [PASS] Circular Log Entry 1 matches staged timestamp 0xAABBCCDD

[TEST 6] Verifying VGA Status Dashboard IP...
  [PASS] VGA_CTRL enable display
  [PASS] VGA text buffer programmed with status dashboard

====================================================
  TEST SUMMARY REPORT
====================================================
  Total Passed: 17
  Total Failed: 0

>>> ALL IP INTEGRATION TESTS PASSED SUCCESSFULLY! <<<
```
</details>

---

## Repository Structure

```
honour_soc/
├── Makefile                # Master verification & build automation script
├── README.md               # Project overview, quickstart & architecture summary
├── docs/                   # Architectural specifications, register maps & guides
│   ├── images/             # System diagrams and block schematics
│   ├── BMC_Architecture_MicroArchitecture_Spec.md
│   ├── Register_Map.md
│   ├── clean_machine_setup_guide.md
│   ├── vcs_verdi_guide.md
│   └── SOC_VERIFICATION_AND_IP_REPORT.md
├── firmware/               # Bare-metal RISC-V C & assembly firmware
│   ├── start.S             # Core startup code (MRAC, stack pointer, BSS init)
│   ├── main.c              # BMC hardware driver test suite & heartbeat supervisor
│   └── link.ld             # Linker script (ROM @ 0x80000000, DCCM @ 0xF0040000)
├── rtl/                    # Synthesizable SystemVerilog / Verilog source files
│   ├── soc_top.v           # Top-level BMC SoC integration
│   ├── core/               # CHIPS Alliance VeeR EL2 RISC-V core
│   ├── custom_ips/         # BMC peripherals (Heartbeat, Reset Seq, Policy, VGA, Timer, ROM)
│   ├── interconnect/       # 64-bit 3x8 AXI4 crossbar and bus adapters
│   └── ips/                # Synthesizable 16550 AXI UART IP
├── tb/                     # VCS verification testbenches (unit, subsystem, and full SoC)
├── scripts/                # Automation and wrapper generation scripts
└── waves/                  # Synopsys Verdi waveform signal list configurations (.rc)
```

---

## Documentation Hub

Detailed documentation and guides are organized under the [`docs/`](docs/) directory:

| Document | Description |
| :--- | :--- |
| **[Architecture & Microarchitecture Spec](docs/BMC_Architecture_MicroArchitecture_Spec.md)** | Subsystem deep-dive, pipeline details, FSM state diagrams, and clock/reset schemes |
| **[Register Map Reference](docs/Register_Map.md)** | Authoritative register offsets, bitfield layouts, reset values, and access permissions |
| **[Clean Machine Setup Guide](docs/clean_machine_setup_guide.md)** | Toolchain installation, prerequisites, and environment variable configuration |
| **[VCS & Verdi Guide](docs/vcs_verdi_guide.md)** | Simulation setup, script options, and Verdi waveform debugging workflow |
| **[Verification & IP Report](docs/SOC_VERIFICATION_AND_IP_REPORT.md)** | Testbench architecture, test vectors, and regression results |
| **[Makefile Usage Guide](docs/Makefile_Usage.md)** | Detailed reference for all Makefile compilation and simulation targets |

---

## License & Acknowledgements

- **System Architecture & Hardware Design**: BMC SoC Project Team
- **RISC-V Processor Core**: [CHIPS Alliance / Western Digital Cores-VeeR-EL2](https://github.com/chipsalliance/Cores-VeeR-EL2) (Apache 2.0 License)
- **UART IP Core**: Synthesizable AXI-Lite 16550 UART (Apache 2.0 License)
- **EDA Tooling**: Synopsys VCS & Verdi Verification Platform
