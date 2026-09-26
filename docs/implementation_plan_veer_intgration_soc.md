# Integrate VeeR EL2 Processor

This plan details the integration of the Western Digital/Antmicro VeeR EL2 processor core into the BMC SoC (`soc_top.v`), replacing the placeholder tie-offs with a fully wired core.

## User Review Required

> [!WARNING]  
> **Interrupt Mapping**: I plan to map `uart_irq` to External IRQ 1, and `hb_irq` to External IRQ 2 on the VeeR's Programmable Interrupt Controller (PIC). Please confirm if you have a different preferred IRQ priority mapping.

> [!IMPORTANT]
> **Reset Topology**: The core's main reset (`rst_l`) will be driven by the custom **Reset Sequencer** (`reset_out_internal`), while the core's debug reset (`dbg_rst_l`) will be driven by the external, raw `rst_n`. This ensures that a warm system reset triggered by a software freeze doesn't wipe out a connected JTAG debugger's state. Please confirm this topology.

## Open Questions

> [!NOTE]  
> **Instruction Fetch**: The VeeR EL2 core is currently configured with 64KB of ICCM (Instruction Closely Coupled Memory) at `0xEE00_0000`. It will fetch instructions directly from ICCM, meaning the `ifu_axi_*` (Instruction Fetch Unit AXI) master port is unused in normal operation. Firmware will need to be side-loaded into the ICCM over JTAG (System Bus). Is this the expected boot strategy for your project, or do you have an external boot ROM in mind?

## Proposed Changes

### Top-Level Integration

#### [MODIFY] soc_top.v
- **Remove Tie-Offs**: Delete the placeholder assignments that currently force `lsu_axi_*` and `sb_axi_*` signals to `0`.
- **Instantiate Core**: Instantiate `el2_veer_wrapper u_veer`.
- **Clock & Resets**: 
  - `clk` -> SoC `clk`
  - `rst_l` -> `reset_out_internal` (from the Reset Sequencer)
  - `dbg_rst_l` -> `rst_n` (Raw SoC reset)
- **Interrupts**:
  - `timer_int`, `soft_int`, `nmi_int` -> `0`
  - `extintsrc_req[31:1]` -> `{29'd0, hb_irq, uart_irq}`
- **JTAG**: Connect the 5 JTAG ports to the existing SoC JTAG pins.
- **AXI Buses**:
  - `lsu_axi_*` (Load/Store Unit) -> Mapped directly to the interconnect Master 1.
  - `sb_axi_*` (System Bus Debugger) -> Mapped directly to the interconnect Master 2.
  - `ifu_axi_*` (Instruction Fetch Unit) -> Tied off safely.
  - `dma_axi_*` (DMA Slave) -> Tied off safely, as there is no DMA master writing into ICCM/DCCM.
- **Boot Vector**: `rst_vec` will be tied to `31'h77000000` (which corresponds to `0xEE000000 >> 1`), pointing execution directly to the ICCM on boot.

### Build System

#### [MODIFY] Makefile
- Define `RV_ROOT = rtl/core/Cores-VeeR-EL2`.
- Update `VCS` and `iverilog` compiler commands to include the `-f $(RV_ROOT)/design/flist` directive.
- Ensure the `RV_ROOT` environment variable is exported during the `make` recipes so that the `-f` parser accurately resolves file paths.
- Add necessary `+incdir+` directives for `el2_param.vh` and `el2_pkg.sv` so that both tools can elaborate the core's parameters.

## Verification Plan

### Automated Tests
- `make veri_soc` using Icarus Verilog: This will re-run the full SoC integration testbench to guarantee the newly instantiated VeeR EL2 core parses, elaborates without errors, and doesn't break the existing AXI interconnect wiring or custom IP mappings. 
- (Note: Because `tb_soc_top.v` uses dummy AXI masters to drive the Custom IPs, the testbench won't actually execute RISC-V firmware, but it will prove full structural/RTL integrity of the SoC).
