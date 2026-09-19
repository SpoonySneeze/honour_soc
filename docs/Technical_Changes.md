# Technical Changes: VeeR Integration & Interrupts

This document details the exact Verilog and architectural modifications made to integrate the VeeR EL2 core, convert IPs to use hardware interrupts, and add the external AXI ROM.

---

## 1. Interrupt Generation Logic
To eliminate the need for firmware polling, two IPs were modified to generate single-cycle hardware interrupts.

### A. VGA Controller (`vblank_irq`)
**File:** `rtl/custom_ips/vga_controller.v`
Added a new output port `vblank_irq`. The logic triggers exactly when the `v_count` enters the `V_ACTIVE` boundary (the start of the vertical front porch) and pulses high for one system clock cycle (`pixel_clk_en` acts as the trigger window):
```verilog
    // Pulse vblank_irq for exactly one system clock cycle at the start of VBLANK
    assign vblank_irq = (v_count == V_ACTIVE && h_count == 10'd0 && pixel_clk_en) ? 1'b1 : 1'b0;
```
*Rationale:* Firmware can use this interrupt to flip framebuffers or update the dashboard buffer safely without causing screen tearing.

### B. Recovery Policy (`lockout_irq`)
**File:** `rtl/custom_ips/recovery_policy.v`
Added a new output port `lockout_irq`. An edge-detector was implemented on the internal `lockout_flag` register so that the core is interrupted exactly once when the threshold is breached.
```verilog
    reg lockout_prev;
    always @(posedge clk) begin
        if (!rst_n) lockout_prev <= 1'b0;
        else lockout_prev <= lockout_flag;
    end
    
    // Pulse lockout_irq for one clock cycle on rising edge of lockout_flag
    assign lockout_irq = lockout_flag & ~lockout_prev;
```
*Rationale:* Firmware is immediately notified when the system enters a crash loop, allowing it to log the state and attempt a safe shutdown instead of endlessly polling `POL_STATUS`.

---

## 2. External Boot ROM (`axi_rom.v`)
**File:** `rtl/custom_ips/axi_rom.v`
Created a new AXI4-Lite slave to act as the instruction memory for the VeeR core.
- **Size:** 8KB (13-bit address width, parameterized as `ADDR_WIDTH = 13`).
- **Base Address Mapping:** Mapped to `0x8000_0000`.
- **Initialization:** Reads `firmware.hex` using `$readmemh` during elaboration.
- **AXI State Machine:** Handles standard AXI4-Lite read transactions (`ARVALID` -> `RVALID`), ignoring writes since it is read-only memory.

*Rationale:* The VeeR core defaults to booting from an internal ICCM, but mapping an AXI ROM to `0x8000_0000` allows us to cleanly load and execute compiled RISC-V C/Assembly programs.

---

## 3. SoC Core Integration (`soc_top.v`)
**File:** `rtl/soc_top.v`
The top-level was entirely re-wired to replace the old 2x7 interconnect with `axi_interconnect_wrap_3x8`, wiring the VeeR core directly into the system.

### A. Core Master Connections
VeeR's three AXI master ports were wired to the new interconnect masters:
- `s00_axi` (Master 0) <- `ifu_axi` (Instruction Fetch Unit)
- `s01_axi` (Master 1) <- `lsu_axi` (Load/Store Unit)
- `s02_axi` (Master 2) <- `sb_axi` (System Bus / Debugger)

### B. Memory Map (Slave Connections)
- `m00_axi`: UART (`0x0002_0000`)
- `m01_axi`: Timer (`0x0002_0100`)
- `m02_axi`: GPIO (`0x0002_0200`)
- `m03_axi`: Heartbeat Monitor (`0x0002_0300`)
- `m04_axi`: Reset Sequencer (`0x0002_0400`)
- `m05_axi`: Recovery Policy (`0x0002_0500`)
- `m06_axi`: VGA Controller (`0x0002_0600`)
- `m07_axi`: AXI ROM (`0x8000_0000`)

### C. VeeR Core Instantiation (`el2_veer_wrapper`)
The core was instantiated and the external interrupts were vectorized into `extintsrc_req`.
```verilog
    // Map hardware interrupts
    wire [31:1] extintsrc_req;
    assign extintsrc_req[1] = uart_irq;
    assign extintsrc_req[2] = hb_irq;
    assign extintsrc_req[3] = vblank_irq;
    assign extintsrc_req[4] = lockout_irq;
    assign extintsrc_req[31:5] = 27'd0;

    el2_veer_wrapper veer_core (
        .clk     (clk),
        .rst_l   (rst_n),
        .timer_int(1'b0),
        .soft_int (1'b0),
        .extintsrc_req (extintsrc_req),
        // ... AXI Master ports mapped ...
    );
```
Additionally, the `rst_vec` (Reset Vector) pin was tied to `31'h4000_0000` (which translates to address `0x8000_0000`), commanding the core to boot from the AXI ROM rather than internal memory.
