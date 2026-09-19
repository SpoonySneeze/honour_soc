# Plan: VeeR EL2 Core Integration — UART → Interconnect → Core

**Status:** Pre-implementation plan (to be executed after review)  
**Date:** September 19, 2026  
**Goal:** Fully instantiate `el2_veer_wrapper` in `soc_top.v` and wire it to the existing AXI 2×7 interconnect (which already has UART on Slave 0), completing the path:

```
VeeR Core (LSU + SB) → AXI Interconnect → UART (axi_uart_top)
                                         → Timer
                                         → GPIO
                                         → HB Monitor
                                         → Reset Sequencer
                                         → Recovery Policy
                                         → VGA Controller
```

---

## 1. Current State

| Component | Status |
|---|---|
| AXI Interconnect (2M × 7S) | ✅ Complete |
| UART IP (`axi_uart_top`, Slave 0) | ✅ Integrated directly on AXI |
| Timer (Slave 1) | ✅ Wishbone stub via bridge |
| GPIO (Slave 2) | ✅ Wishbone stub via bridge |
| HB Monitor (Slave 3) | ✅ Real IP via bridge |
| Reset Sequencer (Slave 4) | ✅ Real IP via bridge |
| Recovery Policy (Slave 5) | ✅ Real IP via bridge |
| VGA Controller (Slave 6) | ✅ Real IP via bridge |
| **VeeR EL2 Core** | ❌ Not instantiated (masters tied to 0) |
| `uart_irq` → VeeR PIC | ❌ Wire declared, not connected |

---

## 2. VeeR EL2 Core — Key Facts

**Location:** `/home/student/sriv_183/core/Cores-VeeR-EL2/design/el2_veer_wrapper.sv`  
**Module:** `el2_veer_wrapper`  
**ISA:** RV32IMC + Zba/Zbb/Zbc/Zbs  
**Snapshot params:** `snapshots/default/el2_param.vh` + `el2_pdef.vh`

### Bus Tag Widths (from `el2_param.vh`)

| Tag | Width |
|---|---|
| `LSU_BUS_TAG` | 3-bit |
| `SB_BUS_TAG` | 1-bit |
| `IFU_BUS_TAG` | 3-bit |
| `DMA_BUS_TAG` | 1-bit |
| `PIC_TOTAL_INT` | 31 (inputs [31:1]) |

### AXI Ports Used by SoC Integration

| Port Group | Direction | Bus Width | Connected To |
|---|---|---|---|
| `lsu_axi_*` | Output (master) | 64-bit data, 32-bit addr | Interconnect S00 (Master 0) |
| `sb_axi_*` | Output (master) | 64-bit data, 32-bit addr | Interconnect S01 (Master 1) |
| `ifu_axi_*` | Output (master) | 64-bit data, 32-bit addr | **ICCM** (stub for now) |
| `dma_axi_*` | Input (slave) | 64-bit data, 32-bit addr | **Tie off** (no DMA host) |

### Non-AXI Ports to Handle

| Port | Width | Plan |
|---|---|---|
| `clk` | 1 | → `clk` (SoC clock) |
| `rst_l` | 1 | → `rst_n` (active-low reset) |
| `dbg_rst_l` | 1 | → `rst_n` (same reset, no separate debug reset) |
| `rst_vec[31:1]` | 31 | → `31'h0000_0000` (boot from ICCM @ 0x0) |
| `nmi_int` | 1 | → `1'b0` (no NMI source) |
| `nmi_vec[31:1]` | 31 | → `31'h0000_0000` |
| `jtag_id[31:1]` | 31 | → `31'h0000_0000` (stub) |
| `jtag_tck/tms/tdi/tdo` | 1 each | → SoC JTAG ports (already in port list) |
| `timer_int` | 1 | → `1'b0` (no hardware timer interrupt yet) |
| `soft_int` | 1 | → `1'b0` |
| `extintsrc_req[31:1]` | 31 | → `{30'b0, uart_irq}` (UART on IRQ line 1) |
| `trace_rv_i_*` | various | → leave unconnected (debug only) |
| `haddr/hdata/hresp` (AHB) | various | → tie off (not using AHB) |

---

## 3. Integration Plan — Step by Step

### Step 1 — Copy VeeR Core Into Repo

```
rtl/core/                     ← new directory
├── el2_veer_wrapper.sv        ← from core/ (top-level wrapper only, or symlink)
```

Or reference the existing location via Makefile `+incdir` and source paths.  
**Decision:** Add VeeR core source path to Makefile `SRC_CORE` variable rather than copying the full codebase (it's large). Include the snapshot parameter files.

### Step 2 — Add VeeR Source Files to Makefile

```makefile
CORE_DIR    = /home/student/sriv_183/core/Cores-VeeR-EL2
CORE_DESIGN = $(CORE_DIR)/design
CORE_SNAP   = $(CORE_DIR)/snapshots/default

SRC_CORE    = $(CORE_DESIGN)/el2_veer_wrapper.sv \
              $(shell find $(CORE_DESIGN) -name "*.sv" -o -name "*.v")

VCS_CORE_INC = +incdir+$(CORE_SNAP) \
               +incdir+$(CORE_DESIGN)/include
```

Update `sim_soc` and `compile_top` targets to include `$(SRC_CORE)` and `$(VCS_CORE_INC)`.

### Step 3 — Declare New Wire Sets in `soc_top.v`

In the wire declarations section, add:

```verilog
// ---- VeeR EL2 Core AXI buses ----
// LSU → Interconnect Master 0 (already declared as lsu_axi_*)
// SB  → Interconnect Master 1 (already declared as sb_axi_*)
// IFU → ICCM (stub — tie off for now)
wire ifu_axi_awvalid, ifu_axi_arvalid;
// ... (all ifu_axi_* ports)

// DMA → tie off (no external DMA)
wire dma_axi_awready, dma_axi_wready, dma_axi_bvalid, dma_axi_arready, dma_axi_rvalid;
// ... (all dma_axi_* outputs from core)

// Trace (ignore outputs)
wire [31:0] trace_rv_i_insn_ip, trace_rv_i_address_ip, trace_rv_i_tval_ip;
wire        trace_rv_i_valid_ip, trace_rv_i_exception_ip;
wire        trace_rv_i_interrupt_ip;
wire [4:0]  trace_rv_i_ecause_ip;
```

### Step 4 — Remove Tie-Off Assigns for LSU/SB Masters

Remove all the existing `assign lsu_axi_* = ...` and `assign sb_axi_* = ...` tie-offs (lines ~658–710 in `soc_top.v`).

### Step 5 — Instantiate `el2_veer_wrapper`

```verilog
el2_veer_wrapper u_veer (
    // Clock & Reset
    .clk            (clk),
    .rst_l          (rst_n),
    .dbg_rst_l      (rst_n),

    // Boot / NMI
    .rst_vec        (31'h0000_0000),    // boot from 0x0000_0000
    .nmi_int        (1'b0),
    .nmi_vec        (31'h0000_0000),
    .jtag_id        (31'h0000_0000),

    // JTAG
    .jtag_tck       (jtag_tck),
    .jtag_tms       (jtag_tms),
    .jtag_tdi       (jtag_tdi),
    .jtag_tdo       (jtag_tdo),
    .jtag_tdoEn     (),                 // not used

    // Interrupts
    .timer_int      (1'b0),
    .soft_int       (1'b0),
    .extintsrc_req  ({30'b0, uart_irq}), // UART IRQ on line 1

    // LSU AXI Master → Interconnect S00
    .lsu_axi_awvalid (lsu_axi_awvalid),
    .lsu_axi_awready (lsu_axi_awready),
    .lsu_axi_awid    (lsu_axi_awid),
    .lsu_axi_awaddr  (lsu_axi_awaddr),
    // ... (all lsu_axi_* ports)

    // SB AXI Master → Interconnect S01
    .sb_axi_awvalid  (sb_axi_awvalid),
    .sb_axi_awready  (sb_axi_awready),
    // ... (all sb_axi_* ports)

    // IFU AXI Master → ICCM stub (tie off)
    .ifu_axi_awvalid (ifu_axi_awvalid),
    .ifu_axi_awready (1'b0),            // ICCM not yet connected
    // ...

    // DMA AXI Slave → tie off (no external DMA)
    .dma_axi_awvalid (1'b0),
    .dma_axi_awready (),
    // ...

    // Trace → ignored
    .trace_rv_i_insn_ip     (),
    .trace_rv_i_address_ip  (),
    .trace_rv_i_valid_ip    (),
    // ...

    // AHB → tie off (not using AHB)
    .haddr          (),
    .hrdata         (64'd0),
    .hready         (1'b0),
    .hresp          (1'b0),
    // ...
);
```

### Step 6 — Wire UART IRQ to Core PIC

The `uart_irq` wire (already declared) connects directly to `extintsrc_req[1]`:

```verilog
.extintsrc_req ({30'b0, uart_irq})
```

This puts the UART RX interrupt on **PIC external interrupt source #1**.  
UART firmware should write `IER = 0x1` to enable, then service IRQ via `extintsrc_req[1]`.

### Step 7 — Update `soc_top` Module Ports (if needed)

Check if any new top-level ports need to be added (e.g., `timer_int` from external, boot ROM address). For this phase, all new signals are tied internally — no port changes needed.

### Step 8 — Update Makefile

- Add `SRC_CORE` and `VCS_CORE_INC` to `sim_soc` and `compile_top` compile commands
- Add `$(SRC_CORE)` as prerequisite for `$(OUT_SOC)` and `$(OUT_TOP)`

---

## 4. Wire Compatibility Check

| soc_top wire | VeeR port | Width match? | Note |
|---|---|---|---|
| `lsu_axi_awid[7:0]` | `lsu_axi_awid[2:0]` | ⚠️ Mismatch | soc_top declares 8-bit; VeeR uses 3-bit (LSU_BUS_TAG=3). Interconnect ID width is 8. Need adapter: `{5'b0, lsu_axi_awid_veer}` |
| `sb_axi_awid[7:0]` | `sb_axi_awid[0:0]` | ⚠️ Mismatch | soc_top 8-bit; VeeR 1-bit (SB_BUS_TAG=1). Adapter needed: `{7'b0, sb_axi_awid_veer}` |
| `lsu_axi_awaddr[31:0]` | `lsu_axi_awaddr[31:0]` | ✅ | 32-bit match |
| `lsu_axi_wdata[63:0]` | `lsu_axi_wdata[63:0]` | ✅ | 64-bit match |
| `lsu_axi_wstrb[7:0]` | `lsu_axi_wstrb[7:0]` | ✅ | 8-bit match |
| `lsu_axi_bid[7:0]` → VeeR | VeeR `lsu_axi_bid[2:0]` | ⚠️ Mismatch | Take `[2:0]` from interconnect's 8-bit bid |
| `sb_axi_bid[7:0]` → VeeR | VeeR `sb_axi_bid[0:0]` | ⚠️ Mismatch | Take `[0]` from interconnect's 8-bit bid |
| `jtag_tdo` | `jtag_tdo` | ✅ | direct |
| `extintsrc_req` | `extintsrc_req[31:1]` | ✅ | 31 bits, UART on [1] |

**Action for ID mismatches:** Declare intermediate wires for VeeR-side IDs; zero-extend outgoing IDs and truncate incoming BIDs.

---

## 5. Files to Change

| File | Change |
|---|---|
| `rtl/soc_top.v` | Remove LSU/SB tie-offs; add VeeR ID adapter wires; instantiate `u_veer`; connect `uart_irq` to PIC |
| `Makefile` | Add `SRC_CORE`, `VCS_CORE_INC`; update `sim_soc`, `compile_top` targets |
| `doc/` | Add `VeeR_Core_Integration_Report.md` after integration |
| `doc/PROJECT_CHANGELOG.md` | Update with Phase 3 entry |

---

## 6. Verification Plan

After integration:

| Test | What it checks | Target |
|---|---|---|
| `make compile_top` | Elaboration: no errors with VeeR in hierarchy | 0 errors |
| `make sim_soc` | All 17 existing SoC assertions still pass | 17/17 PASS |
| `make sim_axi` | AXI interconnect unaffected | 18/18 PASS |
| `make sim_hbm/rst/pol` | Unit tests unaffected | PASS |
| Manual UART loopback test in tb | Write THR → LSR THRE/TEMT → RBR loopback via VeeR bus | TBD |

> [!IMPORTANT]
> The SoC testbench (`tb_soc_top.v`) drives the AXI masters directly (it drives lsu_axi_*/sb_axi_* from the TB). Once the VeeR core is connected, the TB can no longer drive these — the TB must be updated to drive the core's program inputs (ICCM/DCCM) instead.

---

## 7. Risks & Decisions Needed

| Risk | Mitigation |
|---|---|
| VeeR core source has many files (full SV codebase) | Include all `$(CORE_DESIGN)/**/*.sv` via wildcard in Makefile |
| Parameter file conflicts (`.vh` defines) | Use `+incdir+$(CORE_SNAP)` first to ensure snapshot params take priority |
| `soc_top.v` TB no longer drives masters | Update `tb_soc_top.v` to drive program memory or use VeeR simulation model |
| IFU AXI (instruction fetch) not connected | For Phase 1: tie `ifu_axi_*ready` low (core will stall on fetch). Phase 2: connect ICCM |
| `extintsrc_req` is 31 bits wide (`PIC_TOTAL_INT=31`) | Connect `uart_irq` on bit [1], rest tied 0 |

---

## 8. Out of Scope (This Phase)

- ICCM/DCCM program loading (needed to actually run code)
- DMA integration
- Full JTAG debug bring-up
- Timer peripheral interrupt to core (will be `extintsrc_req[2]` in future)
- VGA, GPIO interrupts

---

## 9. Summary Checklist

- [ ] Add VeeR core files to Makefile
- [ ] Declare VeeR ID adapter wires in soc_top.v
- [ ] Remove all `assign lsu_axi_* = 0` and `assign sb_axi_* = 0` tie-offs
- [ ] Instantiate `el2_veer_wrapper u_veer` with all ports connected
- [ ] Connect `uart_irq` to `extintsrc_req[1]`
- [ ] Tie off IFU, DMA, AHB, trace ports
- [ ] Remove JTAG stub (`assign jtag_tdo = 1'b0`)
- [ ] Run `make compile_top` → 0 errors
- [ ] Run `make sim_all` → all existing tests PASS
- [ ] Write `doc/VeeR_Core_Integration_Report.md`
- [ ] Commit with descriptive message
