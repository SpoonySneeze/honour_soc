# Repository Inventory & Module Hierarchy: Baseboard Management Controller (BMC) SoC

**Document ID:** `docs/arch/01_inventory.md`  
**Task:** Task 1 — Repository Inventory, Hierarchy Audit, File Classification, and Build Infrastructure  
**Target:** Honour SoC Verification Architecture & UVM Planning  

---

## 1. Directory Inventory and Content Classification

The table below catalogs every directory within the repository, its contents, primary role, and citations to source files validating the classification.

| Directory Path | Content Type | Detailed Description & Primary Artifacts | Source Citation |
|---|---|---|---|
| `rtl/` | SoC Integration RTL | Contains top-level synthesizable SoC integration module `soc_top` integrating the VeeR EL2 processor core, 3x8 AXI4 crossbar, 8KB boot ROM, and all peripheral IPs. | `rtl/soc_top.v:162-1891` |
| `rtl/custom_ips/` | Custom BMC IP RTL | Synthesizable RTL for custom BMC hardware engines and their AXI4 bus wrappers: Heartbeat Monitor, Power/Reset Sequencer, Recovery Policy & Event Log, VGA Controller, System Timer, GPIO Status, Boot ROM, and AXI-to-Wishbone bridge. | `rtl/custom_ips/axi_heartbeat_monitor.v:4`<br>`rtl/custom_ips/heartbeat_monitor.v:4`<br>`rtl/custom_ips/axi_reset_sequencer.v:4`<br>`rtl/custom_ips/reset_sequencer.v:4`<br>`rtl/custom_ips/axi_recovery_policy.v:4`<br>`rtl/custom_ips/recovery_policy.v:23`<br>`rtl/custom_ips/axi_vga_controller.v:4`<br>`rtl/custom_ips/vga_controller.v:18`<br>`rtl/custom_ips/axi_timer.v:10`<br>`rtl/custom_ips/axi_gpio.v:13`<br>`rtl/custom_ips/axi_rom.v:11`<br>`rtl/custom_ips/axi4_to_wb_bridge.v:17` |
| `rtl/interconnect/` | Bus Interconnect RTL | AXI4 crossbar matrices, wrappers, address decoders, arbiters, priority encoders, and pipeline registers based on the Alex Forencich AXI IP library. | `rtl/interconnect/axi_interconnect_wrap_3x8.v:34`<br>`rtl/interconnect/axi_interconnect.v:34`<br>`rtl/interconnect/arbiter.v:34`<br>`rtl/interconnect/priority_encoder.v:34` |
| `rtl/ips/axi-lite_uart-ipcore-develop/` | Ingested Third-Party IP | Third-party 16550-compatible AXI-Lite UART IP core (BSC / CIC-IPN) with 16-byte TX/RX FIFOs, baud-rate generator, and interrupt generator. Contains `src/rtl/` and `src/include/`. | `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v:28`<br>`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_internal_fifo.v:27` |
| `rtl/ips/aes_core/` | Ingested Third-Party IP (Unintegrated) | Third-party Secworks AES core with AXI-Lite wrapper (`aes_axi.v`). Present on disk, but [INFERRED] not integrated into `soc_top.v` or `Makefile`. | `rtl/ips/aes_core/rtl/verilog/aes_axi.v:14`<br>`rtl/soc_top.v:705-1891` |
| `rtl/core/Cores-VeeR-EL2/` | External Core Placeholder | Directory stub for Western Digital / CHIPS Alliance VeeR EL2 core repository. Resolved at build time via `RV_ROOT ?= $(CURDIR)/rtl/core/Cores-VeeR-EL2` or host environment path `/home/student/sriv_183/core/Cores-VeeR-EL2`. | `Makefile:31-32`<br>`snapshots/default/common_defines.vh:14` |
| `tb/` | Verilog Testbenches | Testbenches for full SoC end-to-end boot simulation, peripheral subsystem integration, standalone AXI4 crossbar arbitration, and standalone unit TBs for Heartbeat, Reset, and Policy IPs. | `tb/tb_soc_core.v:24`<br>`tb/tb_soc_top.v:18`<br>`tb/tb_axi_interconnect.v:20`<br>`tb/tb_heartbeat_monitor.v:14`<br>`tb/tb_reset_sequencer.v:14`<br>`tb/tb_recovery_policy.v:17` |
| `firmware/` | Bare-Metal Software & BSP | RISC-V bare-metal firmware sources, startup code (`start.S`), linker script (`link.ld`), test entry points (`main.c`), and local firmware Makefile. | `firmware/start.S:1-32`<br>`firmware/link.ld:1-36`<br>`firmware/Makefile:1-25` |
| `firmware/test/` | Per-IP Firmware Test Suites | C test suites for bare-metal execution on the VeeR core, plus register abstraction header (`test_common.h`). Includes individual test files for UART, Timer, GPIO, Heartbeat, Reset, Policy, VGA, and composite regression (`test_all.c`). | `firmware/test/test_common.h:1-35`<br>`firmware/test/test_uart.c:1-39`<br>`Makefile:113-122` |
| `scripts/` | Tooling & Generators | Python code-generation scripts based on Jinja2 templates used to generate multi-port AXI interconnect wrappers (`axi_interconnect_wrap.py`). | `scripts/axi_interconnect_wrap.py:1-25` |
| `waves/` | Verdi Waveform Configurations | Synopsys Verdi signal layout / restore files (`*.rc`) tailored for each simulation target (core, soc_top, AXI, Heartbeat, Reset, Policy). | `waves/soc_core_wave.rc:1-20`<br>`Makefile:77-83` |
| `docs/` | System Documentation | Architectural and micro-architectural specification, VCS/Verdi user manual, clean machine setup guide, test execution reports, and block diagrams. | `docs/BMC_Architecture_MicroArchitecture_Spec.md:1-599`<br>`docs/vcs_verdi_guide.md`<br>`docs/clean_machine_setup_guide.md`<br>`docs/SOC_VERIFICATION_AND_IP_REPORT.md` |
| `docs/arch/` | Verification & Architecture Docs | Dedicated location for UVM verification planning and architecture analysis documents. | Created for verification planning tasks |
| `docs/images/` | Architectural Diagrams | Top-level block diagrams and micro-architecture schematics (draw.io / PNG). | `docs/images/BMC_Architecture_Block_Diagrams-Top-Level SoC.drawio.png`<br>`README.md:49` |
| `snapshots/default/` | Core Snapshot Configs | Pre-generated configuration headers for VeeR EL2 core (`common_defines.vh`, `el2_pdef.vh`). | `snapshots/default/common_defines.vh:1-25`<br>`Makefile:49-52` |
| `build/` | Build Artifacts (Transient) | Directory created by Makefile for compiled simulation executables (`simv_*`), binary wrappers, and logs. | `Makefile:40, 161-163` |
| Constraints (`*.xdc`, `*.sdc`) | Synthesis / Timing Constraints | **NOT FOUND**. Neither Vivado physical constraints (`*.xdc`) nor Synopsys Design Constraints (`*.sdc`) exist in this repository. To confirm timing constraints, an FPGA board targeting definition or ASIC synthesis constraint bundle would be required. | `Makefile:1-391`<br>`run_xsim.bat:1-31` |

---

## 2. SoC Top-Level Module & Complete Instantiation Hierarchy

### 2.1 Top-Level Identification
The hardware top-level module is **`soc_top`**, declared at `rtl/soc_top.v:162-1891`. It exposes clock (`clk`), active-low reset (`rst_n`), external heartbeat pulse input (`heartbeat_in`), external power reset pulse output (`reset_out`), UART serial pins (`uart_rx`, `uart_tx`), JTAG debug pins (`jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo`), and VGA video signals (`vga_hsync`, `vga_vsync`, `vga_rgb[11:0]`).

### 2.2 Hierarchical Instantiation Tree
The full instantiation hierarchy from `soc_top` down to leaf modules is detailed below. Each node lists:
`[Instance Name] : [Module Name] (Instance Location -> Definition Location) [Classification]`

```text
soc_top : soc_top (rtl/soc_top.v:162-1891) [Top-Level Module]
├── u_veer : el2_veer_wrapper (rtl/soc_top.v:1586 -> core/Cores-VeeR-EL2/design/el2_veer_wrapper.sv:24) [CPU Subsystem Wrapper]
│   ├── veer : el2_veer (el2_veer_wrapper.sv:891 -> core/Cores-VeeR-EL2/design/el2_veer.sv:23) [RISC-V 4-Stage Dual-Issue Core]
│   │   ├── dbg : el2_dbg (el2_veer.sv:956 -> core/Cores-VeeR-EL2/design/dbg/el2_dbg.sv:24) [Leaf - Debug Module]
│   │   ├── ifu : el2_ifu (el2_veer.sv:996 -> core/Cores-VeeR-EL2/design/ifu/el2_ifu.sv:24) [Instruction Fetch Unit]
│   │   │   ├── aln : el2_ifu_aln_ctl (el2_ifu.sv -> core/Cores-VeeR-EL2/design/ifu/el2_ifu_aln_ctl.sv) [Leaf - Align Control]
│   │   │   ├── compress : el2_ifu_compress_ctl (el2_ifu.sv -> core/Cores-VeeR-EL2/design/ifu/el2_ifu_compress_ctl.sv) [Leaf - RVC Decompressor]
│   │   │   ├── ifc : el2_ifu_ifc_ctl (el2_ifu.sv -> core/Cores-VeeR-EL2/design/ifu/el2_ifu_ifc_ctl.sv) [Leaf - Fetch Control]
│   │   │   └── bp : el2_ifu_bp_ctl (el2_ifu.sv -> core/Cores-VeeR-EL2/design/ifu/el2_ifu_bp_ctl.sv) [Leaf - Branch Predictor]
│   │   ├── dec : el2_dec (el2_veer.sv:1019 -> core/Cores-VeeR-EL2/design/dec/el2_dec.sv:24) [Instruction Decode Unit]
│   │   │   ├── decode : el2_dec_decode_ctl (el2_dec.sv -> core/Cores-VeeR-EL2/design/dec/el2_dec_decode_ctl.sv) [Leaf - Decode Control]
│   │   │   ├── gpr : el2_dec_gpr_ctl (el2_dec.sv -> core/Cores-VeeR-EL2/design/dec/el2_dec_gpr_ctl.sv) [Leaf - General Purpose Registers]
│   │   │   ├── ib : el2_dec_ib_ctl (el2_dec.sv -> core/Cores-VeeR-EL2/design/dec/el2_dec_ib_ctl.sv) [Leaf - Instruction Buffer Control]
│   │   │   ├── tlu : el2_dec_tlu_ctl (el2_dec.sv -> core/Cores-VeeR-EL2/design/dec/el2_dec_tlu_ctl.sv) [Leaf - Trap / CSR Control Unit]
│   │   │   ├── trigger : el2_dec_trigger (el2_dec.sv -> core/Cores-VeeR-EL2/design/dec/el2_dec_trigger.sv) [Leaf - Hardware Triggers]
│   │   │   └── pmp_ctl : el2_dec_pmp_ctl (el2_dec.sv -> core/Cores-VeeR-EL2/design/dec/el2_dec_pmp_ctl.sv) [Leaf - PMP Decode Control]
│   │   ├── exu : el2_exu (el2_veer.sv:1026 -> core/Cores-VeeR-EL2/design/exu/el2_exu.sv:24) [Execution Unit]
│   │   │   ├── alu : el2_exu_alu_ctl (el2_exu.sv -> core/Cores-VeeR-EL2/design/exu/el2_exu_alu_ctl.sv) [Leaf - Integer ALU]
│   │   │   ├── mul : el2_exu_mul_ctl (el2_exu.sv -> core/Cores-VeeR-EL2/design/exu/el2_exu_mul_ctl.sv) [Leaf - Multiplier]
│   │   │   └── div : el2_exu_div_ctl (el2_exu.sv -> core/Cores-VeeR-EL2/design/exu/el2_exu_div_ctl.sv) [Leaf - Radix-4 Divider]
│   │   ├── lsu : el2_lsu (el2_veer.sv:1032 -> core/Cores-VeeR-EL2/design/lsu/el2_lsu.sv:24) [Load / Store Unit]
│   │   │   ├── addrcheck : el2_lsu_addrcheck (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_addrcheck.sv) [Leaf - LSU Address Checker]
│   │   │   ├── lsc : el2_lsu_lsc_ctl (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_lsc_ctl.sv) [Leaf - Load/Store Control]
│   │   │   ├── stbuf : el2_lsu_stbuf (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_stbuf.sv) [Leaf - Store Buffer]
│   │   │   ├── bus_buffer : el2_lsu_bus_buffer (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_buffer.sv) [Leaf - Bus Buffer]
│   │   │   ├── bus_intf : el2_lsu_bus_intf (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_intf.sv) [Leaf - Bus Interface]
│   │   │   ├── ecc : el2_lsu_ecc (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_ecc.sv) [Leaf - DCCM SECDED ECC Unit]
│   │   │   ├── trigger : el2_lsu_trigger (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_trigger.sv) [Leaf - LSU Triggers]
│   │   │   └── clkdomain : el2_lsu_clkdomain (el2_lsu.sv -> core/Cores-VeeR-EL2/design/lsu/el2_lsu_clkdomain.sv) [Leaf - LSU Clock Domain]
│   │   ├── pic_ctrl_inst : el2_pic_ctrl (el2_veer.sv:1060 -> core/Cores-VeeR-EL2/design/el2_pic_ctrl.sv:24) [Leaf - Programmable Interrupt Controller]
│   │   ├── dma_ctrl : el2_dma_ctrl (el2_veer.sv:1073 -> core/Cores-VeeR-EL2/design/el2_dma_ctrl.sv:24) [Leaf - DMA Controller]
│   │   └── pmp : el2_pmp (el2_veer.sv:1107 -> core/Cores-VeeR-EL2/design/el2_pmp.sv:24) [Leaf - Physical Memory Protection Unit]
│   ├── mem : el2_mem (el2_veer_wrapper.sv:914 -> core/Cores-VeeR-EL2/design/el2_mem.sv:24) [Leaf - Memory Subsystem Router / Export Hook]
│   ├── dmi_wrapper : dmi_wrapper (el2_veer_wrapper.sv:925 -> core/Cores-VeeR-EL2/design/dmi/dmi_wrapper.v:28) [Debug Module Interface]
│   │   ├── rvjtag_tap : rvjtag_tap (dmi_wrapper.v:111 -> core/Cores-VeeR-EL2/design/dmi/rvjtag_tap.v:23) [Leaf - JTAG TAP Controller]
│   │   └── dmi_jtag_to_core_sync : dmi_jtag_to_core_sync (dmi_wrapper.v:164 -> core/Cores-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v:23) [Leaf - Clock Domain Synchronizer]
│   ├── dmi_mux : dmi_mux (el2_veer_wrapper.sv:946 -> core/Cores-VeeR-EL2/design/dmi/dmi_mux.v:23) [Leaf - Core / Uncore DMI Mux]
│   └── [Optional] lockstep : el2_veer_lockstep (el2_veer_wrapper.sv:904 -> core/Cores-VeeR-EL2/design/el2_veer_lockstep.sv:24) [Conditionally compiled under RV_LOCKSTEP_ENABLE]
├── gen_dccm_banks[0..3].u_dccm_bank : ram_4096x39 (rtl/soc_top.v:1821 -> core/Cores-VeeR-EL2/design/lib/mem_lib.sv:32) [Leaf - 4 Banks of 4096x39 SRAM (64KB DCCM with 7-bit ECC)]
├── u_axi_intercon : axi_interconnect_wrap_3x8 (rtl/soc_top.v:751 -> rtl/interconnect/axi_interconnect_wrap_3x8.v:34) [AXI4 3-Master x 8-Slave Interconnect Wrapper]
│   └── axi_interconnect_inst : axi_interconnect (axi_interconnect_wrap_3x8.v:613 -> rtl/interconnect/axi_interconnect.v:34) [AXI4 Crossbar Routing & Control Engine]
│       └── arb_inst : arbiter (axi_interconnect.v:494 -> rtl/interconnect/arbiter.v:34) [Round-Robin / Priority Arbiter]
│           ├── priority_encoder_inst : priority_encoder (arbiter.v:74 -> rtl/interconnect/priority_encoder.v:34) [Leaf - Base Priority Encoder]
│           └── priority_encoder_masked : priority_encoder (arbiter.v:91 -> rtl/interconnect/priority_encoder.v:34) [Leaf - Masked Priority Encoder]
├── u_uart : axi_uart_top (rtl/soc_top.v:705 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v:28) [Slave 0: 16550 AXI UART Controller]
│   ├── uart_controller_inst : uart_controller (axi_uart_top.v:561 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_controller.v:28) [UART Controller FSM]
│   │   ├── uart_receiver_inst : uart_receiver (uart_controller.v:134 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_receiver.v:27) [Leaf - RX FSM & Baud Sampler]
│   │   └── uart_transmitter_inst : uart_transmitter (uart_controller.v:152 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_transmitter.v:28) [TX FSM & Serializer]
│   │       └── uart_parity_bit_compute_tx_inst : uart_parity_bit_compute (uart_transmitter.v:219 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_parity_bit_compute.v:27) [Leaf - Parity Bit Generator]
│   ├── axi_internal_fifo_rx_inst : axi_internal_fifo (axi_uart_top.v:594 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_internal_fifo.v:27) [Leaf - 16-Character RX FIFO]
│   └── axi_internal_fifo_tx_inst : axi_internal_fifo (axi_uart_top.v:646 -> rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_internal_fifo.v:27) [Leaf - 16-Character TX FIFO]
├── u_timer : axi_timer (rtl/soc_top.v:1303 -> rtl/custom_ips/axi_timer.v:10) [Leaf - Slave 1: 32-bit System Monotonic Timer]
├── u_gpio : axi_gpio (rtl/soc_top.v:1346 -> rtl/custom_ips/axi_gpio.v:13) [Leaf - Slave 2: GPIO Input/Output Status Register]
├── u_heartbeat : axi_heartbeat_monitor (rtl/soc_top.v:1391 -> rtl/custom_ips/axi_heartbeat_monitor.v:4) [Slave 3: Heartbeat Monitor AXI Wrapper]
│   └── u_core : heartbeat_monitor (axi_heartbeat_monitor.v:74 -> rtl/custom_ips/heartbeat_monitor.v:4) [Leaf - Heartbeat Monitor FSM & Timer Core]
├── u_reset_seq : axi_reset_sequencer (rtl/soc_top.v:1437 -> rtl/custom_ips/axi_reset_sequencer.v:4) [Slave 4: Reset Sequencer AXI Wrapper]
│   └── u_core : reset_sequencer (axi_reset_sequencer.v:63 -> rtl/custom_ips/reset_sequencer.v:4) [Leaf - Atomic Power Reset Pulse FSM]
├── u_rec_policy : axi_recovery_policy (rtl/soc_top.v:1490 -> rtl/custom_ips/axi_recovery_policy.v:4) [Slave 5: Recovery Policy AXI Wrapper]
│   └── u_core : recovery_policy (axi_recovery_policy.v:61 -> rtl/custom_ips/recovery_policy.v:23) [Leaf - 16-Entry Circular Log & Lockout Threshold FSM]
├── u_vga : axi_vga_controller (rtl/soc_top.v:1535 -> rtl/custom_ips/axi_vga_controller.v:4) [Slave 6: VGA Controller AXI Wrapper]
│   └── u_core : vga_controller (axi_vga_controller.v:66 -> rtl/custom_ips/vga_controller.v:18) [Leaf - 640x480 @ 60Hz 3x40 Character Video Engine]
└── u_rom : axi_rom (rtl/soc_top.v:1856 -> rtl/custom_ips/axi_rom.v:11) [Leaf - Slave 7: 8KB AXI Boot ROM preloaded with firmware.hex]
```

### 2.3 Uninstantiated / Standalone RTL Modules Present in Repository
The following modules exist in the repository but are **not** instantiated in `soc_top.v`:
1. `axi4_to_wb_bridge` (`rtl/custom_ips/axi4_to_wb_bridge.v:17`): An AXI4-to-Wishbone B4 protocol converter. [INFERRED: Retained as legacy IP from a predecessor Wishbone-based SoC architecture; superseded in `soc_top.v` by direct AXI4 IP wrappers].
2. `axi_interconnect_2x7` (`rtl/interconnect/axi_interconnect_2x7.v:28`): A dedicated 2-Master x 7-Slave crossbar. [INFERRED: Predecessor interconnect superseded by the 3-Master x 8-Slave crossbar wrapper].
3. `axi_interconnect_wrap_2x7` (`rtl/interconnect/axi_interconnect_wrap_2x7.v:34`): A 2x7 wrapper module, uninstantiated.
4. `axi_crossbar_wrap_2x1` (`rtl/interconnect/axi_crossbar_wrap_2x1.v:34`): A 2x1 wrapper module, uninstantiated.
5. `aes_axi` (`rtl/ips/aes_core/rtl/verilog/aes_axi.v:14`): A 128-bit AES crypto accelerator with AXI-Lite interface. Uninstantiated in `soc_top.v` and unreferenced in `Makefile`.

---

## 3. RTL File and Module Definition Inventory

The table below lists every synthesizable and simulation RTL file present in the repository, the module(s) it defines, its HDL dialect, and its integration status in the SoC top-level design.

| RTL File Path | Defined Module(s) | Language | Status in `soc_top.v` | Description / Role |
|---|---|---|---|---|
| `rtl/soc_top.v` | `soc_top` (lines 162-1891) | Verilog-2001 | **Active Top-Level** | Primary synthesizable SoC top-level integrating core, crossbar, and all peripherals. |
| `rtl/custom_ips/axi_timer.v` | `axi_timer` (line 10) | Verilog-2001 | Active (`u_timer`) | 32-bit free-running hardware monotonic uptime timer (Slave 1). |
| `rtl/custom_ips/axi_gpio.v` | `axi_gpio` (line 13) | Verilog-2001 | Active (`u_gpio`) | External input/output pin monitoring register (Slave 2). |
| `rtl/custom_ips/axi_heartbeat_monitor.v` | `axi_heartbeat_monitor` (line 4) | Verilog-2001 | Active (`u_heartbeat`) | AXI4 slave wrapper for heartbeat monitor core (Slave 3). |
| `rtl/custom_ips/heartbeat_monitor.v` | `heartbeat_monitor` (line 4) | Verilog-2001 | Active (`u_heartbeat.u_core`) | Core heartbeat pulse interval tracking and timeout FSM. |
| `rtl/custom_ips/axi_reset_sequencer.v` | `axi_reset_sequencer` (line 4) | Verilog-2001 | Active (`u_reset_seq`) | AXI4 slave wrapper for reset sequencer core (Slave 4). |
| `rtl/custom_ips/reset_sequencer.v` | `reset_sequencer` (line 4) | Verilog-2001 | Active (`u_reset_seq.u_core`) | Atomic, glitch-free active-low power reset pulse generator. |
| `rtl/custom_ips/axi_recovery_policy.v` | `axi_recovery_policy` (line 4) | Verilog-2001 | Active (`u_rec_policy`) | AXI4 slave wrapper for recovery policy core (Slave 5). |
| `rtl/custom_ips/recovery_policy.v` | `recovery_policy` (line 23) | Verilog-2001 | Active (`u_rec_policy.u_core`) | 16-entry circular event RAM and rolling window lockout FSM. |
| `rtl/custom_ips/axi_vga_controller.v` | `axi_vga_controller` (line 4) | Verilog-2001 | Active (`u_vga`) | AXI4 slave wrapper for VGA character buffer (Slave 6). |
| `rtl/custom_ips/vga_controller.v` | `vga_controller` (line 18) | Verilog-2001 | Active (`u_vga.u_core`) | 640x480 @ 60Hz VGA timing generator and 3x40 text console. |
| `rtl/custom_ips/axi_rom.v` | `axi_rom` (line 11) | Verilog-2001 | Active (`u_rom`) | 8KB AXI4 read-only boot memory preloaded with `firmware.hex` (Slave 7). |
| `rtl/custom_ips/axi4_to_wb_bridge.v` | `axi4_to_wb_bridge` (line 17) | Verilog-2001 | Uninstantiated | Standalone 64-bit AXI4 to 32-bit Wishbone B4 bus bridge. |
| `rtl/interconnect/axi_interconnect_wrap_3x8.v` | `axi_interconnect_wrap_3x8` (line 34) | Verilog-2001 | Active (`u_axi_intercon`) | 3-Master x 8-Slave AXI4 crossbar top wrapper with custom address maps. |
| `rtl/interconnect/axi_interconnect.v` | `axi_interconnect` (line 34) | Verilog-2001 | Active (`u_axi_intercon.axi_interconnect_inst`) | Multi-master, multi-slave parameterized AXI4 crossbar engine. |
| `rtl/interconnect/arbiter.v` | `arbiter` (line 34) | Verilog-2001 | Active (sub-block of interconnect) | Priority and round-robin arbiter for bus grant resolution. |
| `rtl/interconnect/priority_encoder.v` | `priority_encoder` (line 34) | Verilog-2001 | Active (sub-block of arbiter) | Parameterized bit priority encoder. |
| `rtl/interconnect/axi_crossbar.v` | `axi_crossbar` (line 34) | Verilog-2001 | Standalone / Reusable | Generic AXI4 crossbar switch matrix. |
| `rtl/interconnect/axi_crossbar_addr.v` | `axi_crossbar_addr` (line 34) | Verilog-2001 | Standalone / Reusable | Crossbar address decoding and admission controller. |
| `rtl/interconnect/axi_crossbar_rd.v` | `axi_crossbar_rd` (line 34) | Verilog-2001 | Standalone / Reusable | Crossbar read data routing channel. |
| `rtl/interconnect/axi_crossbar_wr.v` | `axi_crossbar_wr` (line 34) | Verilog-2001 | Standalone / Reusable | Crossbar write data routing channel. |
| `rtl/interconnect/axi_crossbar_wrap_2x1.v` | `axi_crossbar_wrap_2x1` (line 34) | Verilog-2001 | Uninstantiated | 2-Master x 1-Slave crossbar wrapper. |
| `rtl/interconnect/axi_interconnect_2x7.v` | `axi_interconnect_2x7` (line 28) | Verilog-2001 | Uninstantiated | Dedicated 2-Master x 7-Slave crossbar. |
| `rtl/interconnect/axi_interconnect_wrap_2x7.v` | `axi_interconnect_wrap_2x7` (line 34) | Verilog-2001 | Uninstantiated | 2-Master x 7-Slave interconnect wrapper. |
| `rtl/interconnect/axi_register_rd.v` | `axi_register_rd` (line 34) | Verilog-2001 | Standalone / Pipeline | AXI4 read channel pipeline skid buffer register. |
| `rtl/interconnect/axi_register_wr.v` | `axi_register_wr` (line 34) | Verilog-2001 | Standalone / Pipeline | AXI4 write channel pipeline skid buffer register. |
| `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v` | `axi_uart_top` (line 28) | Verilog-2001 | Active (`u_uart`) | Top-level 16550-compatible AXI-Lite UART IP core (Slave 0). |
| `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_controller.v` | `uart_controller` (line 28) | Verilog-2001 | Active (`u_uart.uart_controller_inst`) | UART FSM coordinating transmitter and receiver channels. |
| `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_receiver.v` | `uart_receiver` (line 27) | Verilog-2001 | Active (`u_uart...uart_receiver_inst`) | UART RX sampling and serial-to-parallel converter. |
| `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_transmitter.v` | `uart_transmitter` (line 28) | Verilog-2001 | Active (`u_uart...uart_transmitter_inst`) | UART TX parallel-to-serial serializer and framer. |
| `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/uart_parity_bit_compute.v` | `uart_parity_bit_compute` (line 27) | Verilog-2001 | Active (`u_uart...parity_compute`) | Odd / even parity bit calculator. |
| `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_internal_fifo.v` | `axi_internal_fifo` (line 27) | Verilog-2001 | Active (`u_uart.axi_internal_fifo_*`) | Dual-port 16-character asynchronous FIFO buffer. |
| `rtl/ips/aes_core/rtl/verilog/aes_axi.v` | `aes_axi` (line 14) | Verilog-2001 | Uninstantiated | 128-bit AES crypto accelerator top with AXI-Lite interface. |
| `tb/tb_soc_core.v` | `tb_soc_core` (line 24) | Verilog-2001 | Testbench (Full SoC) | End-to-end SoC testbench with real-time UART RX character snooper. |
| `tb/tb_soc_top.v` | `tb_soc_top` (line 18) | Verilog-2001 | Testbench (Peripheral) | Peripheral subsystem integration testbench driving AXI directly. |
| `tb/tb_axi_interconnect.v` | `tb_axi_interconnect` (line 20) | Verilog-2001 | Testbench (Interconnect) | Verification bench for multi-master AXI arbitration and steering. |
| `tb/tb_heartbeat_monitor.v` | `tb_heartbeat_monitor` (line 14) | Verilog-2001 | Testbench (Unit) | Standalone unit testbench for Heartbeat Monitor IP. |
| `tb/tb_reset_sequencer.v` | `tb_reset_sequencer` (line 14) | Verilog-2001 | Testbench (Unit) | Standalone unit testbench for Power/Reset Sequencer IP. |
| `tb/tb_recovery_policy.v` | `tb_recovery_policy` (line 17) | Verilog-2001 | Testbench (Unit) | Standalone unit testbench for Recovery Policy & Event Log IP. |

---

## 4. HDL Languages, IP Lineage, and Build Infrastructure

### 4.1 HDL Languages & Dialects
- **Verilog-2001 (`IEEE 1364-2001`)**: Used for all custom SoC peripherals (`rtl/custom_ips/*.v`), top-level integration (`rtl/soc_top.v`), AXI interconnect modules (`rtl/interconnect/*.v`), ingested UART IP (`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/*.v`), and all testbenches (`tb/*.v`). Compiled in VCS with `+v2k` (`Makefile:36`).
- **SystemVerilog (`IEEE 1800-2012 / 2017`)**: Used for the VeeR EL2 processor core (`*.sv` files), package definitions (`el2_pkg`, `el2_lockstep_pkg`), interface definitions (`el2_mem_if`), and assertions. Compiled in VCS with `-sverilog` (`Makefile:36`).

### 4.2 Third-Party and Generated IP Inventory

| IP Component | Origin / Vendor | License | Generation Method / Status | Integration Notes |
|---|---|---|---|---|
| **VeeR EL2 RISC-V Core** | Western Digital / CHIPS Alliance | Apache-2.0 | Synthesizable SystemVerilog IP configured via `veer.config -target=default -set build_axi4` (`Makefile:169`) | Resolves to `/home/student/sriv_183/core/Cores-VeeR-EL2` via environment path (`snapshots/default/common_defines.vh:14`). Exposes 64-bit AXI4 IFU, LSU, and SB interfaces. |
| **AXI4 3x8 Crossbar Wrapper** | Alex Forencich AXI Library | MIT License | Generated via Python template script `scripts/axi_interconnect_wrap.py` (`rtl/soc_top.v:749`) | Parameters map 3 masters (LSU, IFU, SB) to 8 slave windows (`M00`–`M07`). |
| **AXI-Lite UART 16550** | BSC (Barcelona Supercomputing Center) / CIC-IPN | Apache-2.0 | Ingested third-party open-source IP | Includes dual 16-byte internal FIFOs and baud divider (`rtl/ips/axi-lite_uart-ipcore-develop`). |
| **DCCM SRAM Macro (`ram_4096x39`)** | VeeR Memory Library | Apache-2.0 | Vendor SRAM behavioral simulation model in `mem_lib.sv:32` | 4 instances form 64KB tightly coupled data memory with 7-bit SECDED ECC (`rtl/soc_top.v:1817-1839`). |
| **AES Core (`aes_axi`)** | Secworks / Joachim Strombergson | BSD-2-Clause | Ingested open-source IP (`rtl/ips/aes_core`) | Retained in repository tree; currently unintegrated into `soc_top.v` [INFERRED: candidate for future crypto expansion]. |

### 4.3 Build Systems, Filelists, and Tool Execution Scripts

The repository contains three primary build / simulation frameworks:

1. **Master VCS & Verdi Makefile (`Makefile:1-391`)**:
   - **Firmware Compilation Target (`build_firmware`, lines 175-190)**: Invokes `riscv64-unknown-elf-gcc` with flags `-march=rv32imc_zicsr -mabi=ilp32 -mcmodel=medany -Wall -O2 -ffreestanding -nostdlib` and linker script `firmware/link.ld` (`Makefile:26-27`). Converts `.elf` to Verilog hex via `objcopy --change-addresses -0x80000000 -O verilog` to produce `program.hex` and `firmware.hex` (`Makefile:185-186`).
   - **Full SoC End-to-End Simulation Target (`sim_core` / `vcs_core`, lines 195-212)**: Elaborates `tb/tb_soc_core.v`, `soc_top.v`, all custom IPs, UART, and VeeR core filelist (`-f $(RV_ROOT)/design/flist`) with VCS flags `-full64 -sverilog +v2k -debug_access+all -kdb -timescale=1ns/1ps +define+SIMULATION=1 +define+GTLSIM=1` (`Makefile:36, 199-204`).
   - **Per-IP Bare-Metal Firmware Test Targets (lines 222-245)**:
     - `make test_uart`: Runs `firmware/test/test_uart.c` on VeeR core (`Makefile:222-223`).
     - `make test_timer`: Runs `firmware/test/test_timer.c` on VeeR core (`Makefile:225-226`).
     - `make test_gpio`: Runs `firmware/test/test_gpio.c` on VeeR core (`Makefile:228-229`).
     - `make test_heartbeat`: Runs `firmware/test/test_heartbeat.c` on VeeR core (`Makefile:231-232`).
     - `make test_reset_sequencer`: Runs `firmware/test/test_reset_sequencer.c` on VeeR core (`Makefile:234-235`).
     - `make test_recovery_policy`: Runs `firmware/test/test_recovery_policy.c` on VeeR core (`Makefile:237-238`).
     - `make test_vga`: Runs `firmware/test/test_vga.c` on VeeR core (`Makefile:240-241`).
     - `make test_all_ips`: Compiles and executes comprehensive regression suite `firmware/test/test_all.c` (`Makefile:243-244`).
   - **Standalone Hardware Testbench Targets (lines 249-304)**:
     - `make sim_soc`: Peripheral subsystem integration testbench (`tb/tb_soc_top.v`).
     - `make sim_axi`: 3x8 AXI4 crossbar testbench (`tb/tb_axi_interconnect.v`).
     - `make sim_hbm`: Heartbeat Monitor unit testbench (`tb/tb_heartbeat_monitor.v`).
     - `make sim_rst`: Reset Sequencer unit testbench (`tb/tb_reset_sequencer.v`).
     - `make sim_pol`: Recovery Policy unit testbench (`tb/tb_recovery_policy.v`).
   - **Synopsys Verdi Waveform Viewing Targets (lines 326-369)**: Automatically invokes `verdi -ssf <target>.fsdb -sswr <target>.rc &` mapped to pre-configured layout files (`waves_core`, `waves_soc`, `waves_axi`, `waves_hbm`, `waves_rst`, `waves_pol`).
2. **Standalone Firmware Makefile (`firmware/Makefile:1-25`)**:
   - Independent build script for cross-compiling `firmware/start.S` and `firmware/main.c` into `firmware.hex` without requiring top-level VCS targets.
3. **Vivado XSIM Windows / WSL Batch Script (`run_xsim.bat:1-31`)**:
   - Standalone batch execution script compiling VeeR SystemVerilog files (`xvlog -sv`, line 5) and SoC Verilog files (`xvlog`, line 9) into Vivado xsim snapshot `tb_soc_top_snap`, supporting VCD waveform generation via `xsim -tclbatch dump.tcl` (`run_xsim.bat:19-25`).
4. **Core Filelists & Configuration Snapshot**:
   - `$(RV_ROOT)/design/flist`: Complete source filelist for VeeR EL2 core (`Makefile:201`).
   - `$(RV_ROOT)/snapshots/default/common_defines.vh`: Macro definition header (`Makefile:49`).
   - `$(RV_ROOT)/design/include/el2_def.sv`: SystemVerilog parameter and struct definitions (`Makefile:50`).
   - `$(RV_ROOT)/snapshots/default/el2_pdef.vh`: Package definitions (`Makefile:51`).
   - `$(RV_ROOT)/design/el2_lockstep_pkg.sv`: Lockstep package (`Makefile:52`).
