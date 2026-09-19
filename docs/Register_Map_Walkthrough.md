# Walkthrough: SoC Register Mapping & Top-Level Integration

This walkthrough details the review of the RTL codebase and documentation in `honour_soc`, the formalization and writing of the register mapping directly into [rtl/soc_top.v](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v), and the compilation verification using Synopsys VCS.

---

## 1. What Was Completed

### A. Repository & Architectural Analysis
1. **Reviewed RTL Sources**:
   - Analyzed top-level integration: [`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v)
   - Analyzed custom IPs in [`rtl/custom_ips/`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/):
     - [`heartbeat_monitor.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v) (Custom IP #1)
     - [`reset_sequencer.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v) (Custom IP #2)
     - [`recovery_policy.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v) (Custom IP #3)
     - [`vga_controller.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v) (Custom IP #4)
     - [`axi4_to_wb_bridge.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi4_to_wb_bridge.v)
     - [`wb_interconnect.v`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/wb_interconnect.v) (7-slave address decoder)
2. **Reviewed Architecture Specifications**:
   - [`docs/Register_Map.md`](file:///home/student/sriv_183/honour_soc/docs/Register_Map.md)
   - [`docs/BMC_Architecture_MicroArchitecture_Spec.md`](file:///home/student/sriv_183/honour_soc/docs/BMC_Architecture_MicroArchitecture_Spec.md)
   - [`tb/tb_soc_top.v`](file:///home/student/sriv_183/honour_soc/tb/tb_soc_top.v)
3. **Confirmed Scope Exclusion**:
   - Excluded AES core (`rtl/ips/aes_core`) per your requirement.

---

### B. Register Mapping in [rtl/soc_top.v](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v)

We updated [`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v) with three major additions:

#### 1. Authoritative Top-Level Header Documentation
A complete register reference table specifying:
- Base addresses for all 7 Wishbone slaves.
- Full 32-bit CPU memory addresses (`0x0002_0000` to `0x0002_067C`).
- Word-aligned offsets (`0x00`, `0x04`, `0x08`, `0x0C`, `0x10`, `0x14`, `0x18`, `0x1C`, `0x08–0x7C`).
- Access types: `R/W`, `RO` (Read-Only), `WO` (Write-Only / reads return 0).
- Reset values and bitfield descriptions (including self-clearing trigger bits, sticky flags, and saturating counters).

```
============================================================================
SYSTEM MEMORY MAP (32-bit Address Space)
============================================================================
  Address Range              Size     Target / Peripheral         Bus Interface
  --------------------------------------------------------------------------
  0x0000_0000 – 0x0000_FFFF  64 KB    ICCM (Instruction Memory)   VeeR TCM (Core)
  0x0001_0000 – 0x0001_FFFF  64 KB    DCCM (Data Memory)          VeeR TCM (Core)
  0x0002_0000 – 0x0002_00FF  256 B    Slave 0: UART               Wishbone B4
  0x0002_0100 – 0x0002_01FF  256 B    Slave 1: Timer              Wishbone B4
  0x0002_0200 – 0x0002_02FF  256 B    Slave 2: GPIO               Wishbone B4
  0x0002_0300 – 0x0002_03FF  256 B    Slave 3: Heartbeat Monitor  Wishbone B4
  0x0002_0400 – 0x0002_04FF  256 B    Slave 4: Reset Sequencer    Wishbone B4
  0x0002_0500 – 0x0002_05FF  256 B    Slave 5: Recovery Policy    Wishbone B4
  0x0002_0600 – 0x0002_06FF  256 B    Slave 6: VGA Controller     Wishbone B4
```

#### 2. Synthesizable Hardware `localparam` Constants
Added Verilog `localparam` blocks inside `soc_top` declaring:
- Base addresses (`BASE_UART`, `BASE_TIMER`, `BASE_GPIO`, `BASE_HB_MON`, `BASE_RESET_SEQ`, `BASE_REC_POL`, `BASE_VGA`)
- Register offsets (`OFF_*`)
- Full 32-bit CPU memory-mapped addresses (`ADDR_*`)

These parameters can be directly referenced by testbenches, assertions, hardware checkers, and verification suites without hardcoding magic numbers.

#### 3. In-line Peripheral Instance Annotations
Annotated every slave instance and stub in `soc_top.v` (Slaves 0 to 6) with its address range, register layout, bit assignments, and operational notes.

---

### C. Compilation & Elaboration Verification

Validated syntax and elaboration of [`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v) with Synopsys VCS:

```bash
vcs -sverilog -full64 +v2k rtl/soc_top.v rtl/custom_ips/*.v -kdb
```

**Result**:
- **0 errors, 0 warnings**
- Verdi KDB database successfully generated.
