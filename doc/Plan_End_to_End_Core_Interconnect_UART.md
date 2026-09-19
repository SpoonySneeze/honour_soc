# Master Plan: End-to-End Integration of VeeR Core, AXI Interconnect, and UART

**Document Version:** 1.0  
**Date:** September 19, 2026  
**Repository:** `honour_soc`  
**Status:** Architecture & Implementation Plan  

---

## 1. Executive Summary & Current State Audit

This plan provides the comprehensive blueprint for completing the integration of the **VeeR EL2 RISC-V Core**, the **2-Master × 7-Slave AXI4 Interconnect**, and the **AXI-Lite UART IP Core**.

### Component Integration Status Matrix

| Sub-system Path | Status | Details |
| :--- | :---: | :--- |
| **AXI Interconnect $\longleftrightarrow$ UART IP** | ✅ **COMPLETE** | `axi_uart_top` is instantiated on Slave 0 (`0x0002_0000`) of the AXI interconnect with 64-to-32 bit data width adaptation. Real `uart_tx` and `uart_rx` lines are connected to SoC pads. |
| **AXI Interconnect $\longleftrightarrow$ Peripheral Slaves 1–6** | ✅ **COMPLETE** | Slaves 1–6 (Timer, GPIO, Heartbeat Monitor, Reset Sequencer, Recovery Policy, VGA) are wired through dedicated 64-to-32 bit AXI-to-Wishbone bridges. |
| **VeeR Core $\longleftrightarrow$ AXI Interconnect** | ❌ **NOT INTEGRATED** | The core (`el2_veer_wrapper`) is not yet instantiated in `rtl/soc_top.v`. Interconnect Master 0 (`lsu_axi_*`) and Master 1 (`sb_axi_*`) are currently tied off to idle (`1'b0`). |
| **UART $\longleftrightarrow$ VeeR Core Interrupt (PIC)** | ❌ **NOT INTEGRATED** | `uart_irq` wire is declared in `soc_top.v` but is floating and not routed to the core's Programmable Interrupt Controller (`extintsrc_req`). |
| **End-to-End CPU Software Execution** | ❌ **NOT INTEGRATED** | The current SoC testbench (`tb/tb_soc_top.v`) drives interconnect bus masters directly as a verification test fixture; the CPU does not yet execute code from memory to control the UART. |

---

## 2. End-to-End Architecture & Topology

```
                  +-------------------------------------------------------+
                  |                      soc_top                          |
                  |                                                       |
+--------------+  |  +--------------------+                               |
| JTAG Debug   |==|==|  el2_veer_wrapper  |                               |
+--------------+  |  |    (VeeR EL2)      |                               |
                  |  |                    |                               |
                  |  |  +--------------+  |                               |
                  |  |  | ICCM (64 KB) |  |                               |
                  |  |  | DCCM (64 KB) |  |                               |
                  |  |  +--------------+  |                               |
                  |  |                    |                               |
                  |  | LSU Master (64b)   | SB Master (64b)               |
                  |  +---------||---------+--------||---------------------+
                  |            ||                  ||                     
                  |  +---------vv------------------vv------------------+  |
                  |  |         AXI4 Interconnect 2x7 (64-bit)          |  |
                  |  |           (axi_interconnect_wrap_2x7)           |  |
                  |  +---||-------||-------||-------||-----------------+  |
                  |      || S0    || S1    || S2    || S3..S6             |
                  |      || (64b) || (64b) || (64b) || (64b)              |
                  |      ||       ||       ||       ||                    |
                  |  +---vv----+  ||       ||       ||                    |
                  |  | 64b/32b |  ||       ||       ||                    |
                  |  | Steering|  ||       ||       ||                    |
                  |  +---||----+  ||       ||       ||                    |
                  |      || (32b) ||       ||       ||                    |
                  |  +---vv----+  ||       ||       ||                    |
                  |  | axi_    |  +---vv---++---vv--++---vv---------------+
                  |  | uart_   |  | Dedicated AXI4-to-Wishbone Bridges    |
                  |  | top     |  | (u_bridge_s1 .. u_bridge_s6)          |
                  |  +---||----+  +---||-------||-------||----------------+
                  |      ||           ||       ||       ||                
                  |      ||       +---vv-+ +---vv-+ +---vv----------------+
                  |      ||       |Timer | |GPIO  | |Custom BMC Hardware  |
                  |      ||       | IP   | | IP   | |(HBM, RST, POL, VGA) |
                  |      ||       +------+ +------+ +---------------------+
                  |      ||                                               
                  |      |+-----------------+                             
                  |      |                  | (uart_irq)                  
                  |      |                  v                             
                  |      |       +---------------------+                  
                  |      |       | VeeR PIC Line 1     |                  
                  |      |       | (extintsrc_req[1])  |                  
                  |      |       +---------------------+                  
                  |      |                                                
                  |      +====> [uart_tx, uart_rx pads]                   
                  +-------------------------------------------------------+
```

---

## 3. Detailed Technical Analysis

### 3.1. VeeR EL2 Core Wrapper Ports & Adaptation Requirements

The core wrapper is located at `/home/student/sriv_183/core/Cores-VeeR-EL2/design/el2_veer_wrapper.sv`.

#### Bus Tag / ID Width Mismatches
| Bus Channel | Core Port Width (`el2_param.vh`) | Interconnect Width (`soc_top.v`) | Adapter Method |
| :--- | :--- | :--- | :--- |
| **LSU Write Address ID** | `lsu_axi_awid[2:0]` (3 bits) | `s00_axi_awid[7:0]` (8 bits) | Zero-extend: `s00_axi_awid = {5'b0, lsu_axi_awid}` |
| **LSU Write Resp ID** | `lsu_axi_bid[2:0]` (3 bits) | `s00_axi_bid[7:0]` (8 bits) | Truncate: `lsu_axi_bid = s00_axi_bid[2:0]` |
| **LSU Read Address ID** | `lsu_axi_arid[2:0]` (3 bits) | `s00_axi_arid[7:0]` (8 bits) | Zero-extend: `s00_axi_arid = {5'b0, lsu_axi_arid}` |
| **LSU Read Data ID** | `lsu_axi_rid[2:0]` (3 bits) | `s00_axi_rid[7:0]` (8 bits) | Truncate: `lsu_axi_rid = s00_axi_rid[2:0]` |
| **SB Write Address ID** | `sb_axi_awid[0:0]` (1 bit) | `s01_axi_awid[7:0]` (8 bits) | Zero-extend: `s01_axi_awid = {7'b0, sb_axi_awid}` |
| **SB Write Resp ID** | `sb_axi_bid[0:0]` (1 bit) | `s01_axi_bid[7:0]` (8 bits) | Truncate: `sb_axi_bid = s01_axi_bid[0]` |
| **SB Read Address ID** | `sb_axi_arid[0:0]` (1 bit) | `s01_axi_arid[7:0]` (8 bits) | Zero-extend: `s01_axi_arid = {7'b0, sb_axi_arid}` |
| **SB Read Data ID** | `sb_axi_rid[0:0]` (1 bit) | `s01_axi_rid[7:0]` (8 bits) | Truncate: `sb_axi_rid = s01_axi_rid[0]` |

#### Memory Export Interfaces
`el2_veer_wrapper` includes internal memory control (`el2_mem`) which instantiates ICCM, DCCM, and ICache. The wrapper exposes SystemVerilog interfaces:
```systemverilog
el2_mem_if.veer_icache_src  el2_icache_export,
el2_mem_if.veer_sram_src    el2_mem_export,
```
In `soc_top.v`, instances of `el2_mem_if` must be declared and hooked to these ports to satisfy port bindings.

#### Unused Core Channels Tie-Off
1. **Instruction Fetch Unit AXI (`ifu_axi_*`)**: Tie `ifu_axi_awready = 1'b0`, `ifu_axi_wready = 1'b0`, `ifu_axi_arready = 1'b0`, `ifu_axi_bvalid = 1'b0`, `ifu_axi_rvalid = 1'b0`. Core fetches instructions directly from internal ICCM.
2. **DMA Slave Port (`dma_axi_*`)**: Tie `dma_axi_awvalid = 1'b0`, `dma_axi_wvalid = 1'b0`, `dma_axi_arvalid = 1'b0`, `dma_axi_bready = 1'b1`, `dma_axi_rready = 1'b1`.
3. **AHB Bus Interface**: Core AHB ports tied to inactive levels (`hrdata = 64'd0`, `hready = 1'b1`, `hresp = 1'b0`).
4. **Trace Ports (`trace_rv_i_*`)**: Leave unconnected (monitored only in debug simulation).

### 3.2. Address Mapping & Routing to UART

| Master | Target Peripheral | Base Address | Offset Range | Access Type |
| :--- | :--- | :--- | :--- | :--- |
| **VeeR LSU** (Data Read/Write) | **UART Core** | `0x0002_0000` | `0x00` – `0x1F` | 32-bit word read/write |
| **VeeR LSU** | Timer | `0x0002_0100` | `0x00` – `0x0F` | 32-bit counter read |
| **VeeR LSU** | GPIO | `0x0002_0200` | `0x00` – `0x0F` | 32-bit status read |
| **VeeR LSU** | Heartbeat Monitor | `0x0002_0300` | `0x00` – `0x0F` | Config & status registers |
| **VeeR LSU** | Reset Sequencer | `0x0002_0400` | `0x00` – `0x0F` | Trigger & cycle hold |
| **VeeR LSU** | Recovery Policy | `0x0002_0500` | `0x00` – `0x1F` | Window, threshold, log |
| **VeeR LSU** | VGA Controller | `0x0002_0600` | `0x00` – `0x7F` | Text buffer & control |

---

## 4. Step-by-Step Implementation Roadmap

### Phase 1: Toolchain & Build System Integration
1. **Define File Lists in `Makefile`**:
   - Reference VeeR EL2 include directories:
     - `/home/student/sriv_183/core/Cores-VeeR-EL2/snapshots/default` (contains `el2_param.vh`, `el2_pdef.vh`, `common_defines.vh`)
     - `/home/student/sriv_183/core/Cores-VeeR-EL2/design/include`
   - Include the VeeR design file list from `/home/student/sriv_183/core/Cores-VeeR-EL2/design/flist`.
2. **Update VCS Compilation Flags**:
   - Ensure `-sverilog +v2k` and `+incdir` paths are included for `compile_top` and `sim_soc`.

### Phase 2: Top-Level Integration (`rtl/soc_top.v`)
1. **Remove Master Stubs**:
   - Delete `assign lsu_axi_awvalid = 1'b0;` through `assign sb_axi_rready = 1'b0;` (lines ~658–710).
2. **Add ID Adapters & Interface Hooks**:
   - Declare `el2_mem_if el2_mem_export();` and `el2_mem_if el2_icache_export();`.
   - Wire bus tag adapters between VeeR LSU/SB ports and interconnect wires.
3. **Instantiate `el2_veer_wrapper u_veer`**:
   - Connect clocks (`clk`) and active-low resets (`rst_l`, `dbg_rst_l` $\leftarrow$ `rst_n`).
   - Wire boot vector: `rst_vec = 31'h0000_0000` (boots from ICCM).
   - Wire JTAG external pins: `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo`, `jtag_trst_n = rst_n`.
   - Connect `lsu_axi_*` to interconnect Master 0 (`s00_axi_*`).
   - Connect `sb_axi_*` to interconnect Master 1 (`s01_axi_*`).
   - Connect `extintsrc_req = {30'b0, uart_irq}` (UART interrupt routed to PIC interrupt 1).
   - Tie off IFU, DMA, and AHB unused ports.

### Phase 3: Elaboration & Syntax Verification
1. Run `make clean && make compile_top`.
2. Confirm zero errors, zero unresolved references, and successful KDB generation.

### Phase 4: Testbench & Simulation Strategy
1. **Dual-Mode SoC Testbench**:
   - Mode A (Regression Harness): Keep existing external stimuli for automated assertion checking of peripherals.
   - Mode B (CPU Program Execution): Allow VeeR core to boot a firmware sequence in ICCM that writes `'H'`, `'E'`, `'L'`, `'L'`, `'O'` to UART THR (`0x0002_0000`), verifies transmission on `uart_tx`, and receives loopback bytes on `uart_rx`.
2. **Run Full Regression**:
   - `sim_hbm`, `sim_rst`, `sim_pol`, `sim_axi`, and `sim_soc`.

### Phase 5: Documentation & Git Commit
1. Generate detailed completion report: `doc/VeeR_Core_AXI_UART_Integration_Report.md`.
2. Update `doc/PROJECT_CHANGELOG.md`.
3. Stage and commit with descriptive git commit message.

---

## 5. Verification Checklist

- [ ] All VeeR RTL files compile without syntax errors under VCS.
- [ ] `el2_veer_wrapper` elaborates inside `soc_top` without unresolved modules.
- [ ] LSU AXI writes from core reach `axi_uart_top` THR (`0x0002_0000`).
- [ ] LSU AXI reads from core read `axi_uart_top` LSR (`0x0002_0014`).
- [ ] UART RX interrupt triggers `extintsrc_req[1]` on the core.
- [ ] 72/72 existing assertion tests pass without regression.
- [ ] `aes_core/` remains 100% untouched.
- [ ] Report documented in `doc/` and committed to git.
