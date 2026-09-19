# VeeR Instruction Fetch Architecture: ICCM vs. External Boot ROM

This document explains the default instruction fetch behavior of the VeeR EL2 core and details the architectural modifications made to allow the core to boot autonomously from an external AXI ROM.

---

## 1. The Default VeeR Architecture: ICCM

By default, the VeeR EL2 core is designed to execute code from its **Instruction Closely Coupled Memory (ICCM)**. 
- The ICCM is an internal SRAM tightly coupled to the pipeline, providing 0-wait-state instruction fetches.
- **The Problem:** ICCM is volatile. When the SoC is powered on, the ICCM is empty (contains garbage data). 
- **The Standard Boot Flow:** To boot a VeeR core using ICCM, the system typically requires an external agent (like a JTAG debugger, a DMA controller, or a separate boot processor) to pause the core via the `rst_l` (reset) pin, write the firmware binaries over the AXI System Bus into the ICCM address space, and *then* release the core from reset.

For a standalone SoC (and for streamlined simulations), relying on a JTAG debugger to pre-load memory before every boot is highly impractical.

---

## 2. Our Solution: Autonomous External Boot ROM

To allow the SoC to boot instantly and autonomously without an external debugger pre-loading memory, I bypassed the ICCM and forced the core to fetch instructions from a synthesized ROM attached to the system interconnect.

### Step 1: Modifying the Reset Vector (`rst_vec`)
When the VeeR core comes out of reset, it fetches its very first instruction from the memory address specified by its `rst_vec` input pin. 
- In `rtl/soc_top.v`, I tied the `rst_vec` pin to address `0x8000_0000`:
```verilog
    el2_veer_wrapper veer_core (
        .clk     (clk),
        .rst_l   (rst_n),
        // ...
        .rst_vec (31'h4000_0000), // Maps to 0x8000_0000 (shifted by 1 as [31:1])
        // ...
    );
```
*Because of this, the core's Instruction Fetch Unit (IFU) immediately issues an AXI Master Read request to `0x8000_0000` the moment `rst_n` goes high.*

### Step 2: Implementing the AXI ROM (`axi_rom.v`)
To answer the IFU's AXI read requests, I created a custom hardware ROM peripheral.
- **Memory Array:** The ROM is implemented as a Verilog array (`reg [31:0] memory [0:2047];`), giving us 8KB of instruction space.
- **Initialization:** During synthesis and simulation elaboration, the ROM uses `$readmemh("firmware.hex", memory)` to permanently burn the compiled RISC-V machine code into the FPGA's block RAM.

### Step 3: Integrating with the AXI Interconnect
The VeeR IFU port (`ifu_axi`) is wired to Master 0 of our `axi_interconnect_wrap_3x8`. 
The `axi_rom` is wired to Slave 7. 
In the interconnect parameterization, Slave 7 is strictly mapped to `0x8000_0000`.

### The New Boot Flow (Step-by-Step)
1. Power is applied; `rst_n` is asserted low, then goes high.
2. The VeeR core looks at `rst_vec` and decides to fetch the instruction at `0x8000_0000`.
3. The VeeR IFU asserts `ifu_axi_arvalid` with `araddr = 0x8000_0000`.
4. The AXI Interconnect decodes the address, realizes it belongs to Slave 7, and routes the request to `axi_rom.v`.
5. `axi_rom.v` asserts `arready`, reads the first instruction from its internal array, and places it on `rdata`, asserting `rvalid`.
6. The VeeR core receives the instruction, decodes it, and begins executing the SoC firmware immediately.
