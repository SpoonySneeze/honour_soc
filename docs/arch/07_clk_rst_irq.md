# Clock, Reset, Interrupt, and Power/Debug Architecture

**Document ID:** `docs/arch/07_clk_rst_irq.md`  
**Stage:** Stage 7 — Clock Tree, Reset Tree, Reset Fan-Out, Interrupt Architecture, and Power/Debug  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md), [`docs/arch/02_blocks.md`](file:///home/student/sriv_183/honour_soc/docs/arch/02_blocks.md), [`docs/arch/03_bus_matrix.md`](file:///home/student/sriv_183/honour_soc/docs/arch/03_bus_matrix.md), [`docs/arch/04_address_map.md`](file:///home/student/sriv_183/honour_soc/docs/arch/04_address_map.md), [`docs/arch/05_control_path.md`](file:///home/student/sriv_183/honour_soc/docs/arch/05_control_path.md), and [`docs/arch/06_data_path.md`](file:///home/student/sriv_183/honour_soc/docs/arch/06_data_path.md)  

---

## 1. Clock Distribution Tree

The BMC SoC is designed predominantly as a single-synchronous clock design operating from a primary external 100 MHz clock input, supplemented by an asynchronous JTAG clock and an internally divided video pixel strobe.

| Clock Domain | Frequency | Source / Generator | Destination Blocks & Modules | CDC Handling Mechanism | Source Citation |
|---|---|---|---|---|---|
| **`clk`** (Main SoC Clock) | 100 MHz (Period: 10 ns) | External oscillator pad `clk` | • `u_veer.clk` (CPU core)<br>• `u_axi_intercon.clk` (Crossbar)<br>• `u_uart` (`fixed_clk_i`, `axi_aclk_i`)<br>• `u_timer.clk`<br>• `u_gpio.clk`<br>• `u_heartbeat.clk`<br>• `u_reset_seq.clk`<br>• `u_rec_policy.clk`<br>• `u_vga.clk`<br>• `u_rom.clk`<br>• `gen_dccm_banks[*].u_dccm_bank.CLK` | Primary synchronous domain. No CDC required between these blocks. | `rtl/soc_top.v:163, 706-707, 811, 1308, 1351, 1392, 1438, 1491, 1536, 1587, 1822, 1857`<br>`tb/tb_soc_core.v:29` |
| **`jtag_tck`** (Debug Clock) | Up to 25 MHz (Asynchronous) | External JTAG header pin `jtag_tck` | • `u_veer.jtag_tck`<br>• `u_veer.dmi_wrapper` (TAP controller) | Multi-stage double-flop synchronizers in `dmi_jtag_to_core_sync` transfer debug requests between `jtag_tck` and core `clk`. | `rtl/soc_top.v:170, 1761`<br>`core/Cores-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v:23-55` |
| **`pixel_clk`** (Video Strobe) | 25 MHz (Derived) | Internal clock divider in `vga_controller` (divided by 4 from 100 MHz) | Internal VGA beam counters (`h_count`, `v_count`) and pixel serializer | Synchronous divide-by-4 flip-flop counter. Text buffer written by CPU is held static during frame refresh. | `docs/BMC_Architecture_MicroArchitecture_Spec.md:205, 328`<br>`rtl/custom_ips/vga_controller.v:18` |
| **`active_l2clk` / `free_l2clk`** | 100 MHz (Gated) | Internal clock gating logic in `el2_veer` | Core pipeline execution units and arithmetic logic | Dynamic clock gating cells (`el2_clkhdr`) enabling execution blocks only during active instruction execution. | `core/Cores-VeeR-EL2/design/el2_veer.sv:43-44` |

---

## 2. Reset Distribution Tree & Reset Sequencer Fan-Out Analysis

### 2.1 SoC Reset Architecture

The table below catalogs every reset network present on the SoC, its polarity, synchronicity, and destinations.

| Reset Signal | Polarity | Sync / Async | Source | Destination Blocks | Purpose / Behavior | Source Citation |
|---|---|---|---|---|---|---|
| **`rst_n`** (Main Reset) | Active-Low | Asynchronous assertion, Synchronous deassertion | External pin `rst_n` | • `u_veer.rst_l` & `dbg_rst_l`<br>• `u_uart.axi_aresetn_i`<br>• `u_timer.rst_n`<br>• `u_gpio.rst_n`<br>• `u_heartbeat.rst_n`<br>• `u_reset_seq.rst_n`<br>• `u_rec_policy.rst_n`<br>• `u_vga.rst_n`<br>• `u_rom.rst_n`<br>• `jtag_trst_n` | Master cold power-on reset. Forces all pipeline registers, FSMs, and configuration registers to default quiescent states. | `rtl/soc_top.v:164, 708, 1309, 1352, 1393, 1439, 1492, 1537, 1588-1589, 1766, 1858` |
| **`rst`** (Interconnect Reset) | Active-High | Synchronous | Inverter: `assign rst = ~rst_n` | `u_axi_intercon.rst` | Flushes AXI crossbar routing channels and resets arbiters to `STATE_IDLE`. | `rtl/soc_top.v:812` |
| **`reset_out`** (`reset_out_internal`) | Active-Low | Synchronous | `u_reset_seq.reset_out` | • External pad `reset_out`<br>• `u_gpio.reset_out` (sense only) | Atomic power reset pulse driven to external host CPU. | `rtl/soc_top.v:1471, 1475, 1354` |

### 2.2 Deep-Dive: Exactly How `reset_sequencer`'s `reset_out` Fans Out

A critical architectural distinction verified directly against the RTL in [`rtl/soc_top.v:1471-1475`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1471-L1475) is the fan-out scope of `reset_out`:

1. **Physical Routing in RTL**:
   ```verilog
   axi_reset_sequencer u_reset_seq (
       ...
       .reset_out (reset_out_internal)
   );

   assign reset_out = reset_out_internal; // Driven to chip boundary pad
   ```
   And connected to `u_gpio`:
   ```verilog
   axi_gpio u_gpio (
       ...
       .reset_out (reset_out_internal), // Sensed input for software readback
       ...
   );
   ```
2. **Blocks Reset by `reset_out`**:
   - **External Host System ONLY**: The pulse is routed directly to chip pad `reset_out` (`soc_top.v:1475`) to cycle the external server motherboard / host CPU power rails.
   - **Internal BMC Logic**: **ZERO internal BMC blocks are reset by `reset_out`**.
3. **Is the VeeR Core Reset by `reset_out`?**:
   - **NO**. The VeeR core reset pins (`u_veer.rst_l` and `u_veer.dbg_rst_l`) are connected **strictly** to external system reset `rst_n` (`soc_top.v:1588-1589`).
   - The VeeR core continues executing firmware uninterrupted before, during, and after the host reset pulse is asserted.
4. **Architectural Rationale**:
   - This implements the fundamental BMC design rule: *the watchdog and supervisory controller must remain fully operational while resetting the target machine*. If the BMC core reset itself when power-cycling the host, it would lose the recovery history in `u_rec_policy`, abort ongoing UART console sessions, and create recursive reset loops.

---

## 3. Interrupt Architecture & Event Routing

### 3.1 Interrupt Routing Matrix

All external interrupt sources are aggregated in [`rtl/soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600) and presented to the VeeR EL2 core's Programmable Interrupt Controller (PIC):
```verilog
.extintsrc_req ({27'd0, lockout_irq, vblank_irq, hb_irq, uart_irq})
```

| IRQ Bit ID | Signal Name | Source Module / Logic | Trigger Condition | Clear / Acknowledge Mechanism | Destination & Priority | Source Citation |
|---|---|---|---|---|---|---|
| **IRQ 0** (`extintsrc_req[0]`) | `uart_irq` | `u_uart.read_interrupt_o` | RX FIFO has characters available, or TX FIFO empty with `UART_IER` bits enabled | Reading `UART_RBR` (clears RX) or writing `UART_THR` (clears TX) | VeeR Core PIC (Source ID 1). Priority configurable via PIC register `0xF00C_0000 + 4*1`. | `rtl/soc_top.v:738, 1600`<br>`axi_uart_top.v:110` |
| **IRQ 1** (`extintsrc_req[1]`) | `hb_irq` | `u_heartbeat.hb_irq` | `hb_counter >= HB_THRESHOLD` (Watchdog Timeout) | Writing `HB_CTRL.clear_flag = 1` (`0x0002_0300`, bit 1) | VeeR Core PIC (Source ID 2). Priority configurable via PIC register `0xF00C_0000 + 4*2`. | `rtl/soc_top.v:1430, 1600`<br>`tb/tb_heartbeat_monitor.v:268, 303` |
| **IRQ 2** (`extintsrc_req[2]`) | `vblank_irq` | `u_vga.vblank_irq` | Video beam enters vertical blanking line 480 | Cleared automatically at beginning of next active frame | VeeR Core PIC (Source ID 3). Priority configurable via PIC register `0xF00C_0000 + 4*3`. | `rtl/soc_top.v:1572, 1600` |
| **IRQ 3** (`extintsrc_req[3]`) | `lockout_irq` | `u_rec_policy.lockout_irq` | `window_recovery_count >= POL_THRESHOLD` (Crash-Loop) | Writing `POL_CTRL.clear_lockout = 1` (`0x0002_0500`, bit 1) | VeeR Core PIC (Source ID 4). Priority configurable via PIC register `0xF00C_0000 + 4*4`. | `rtl/soc_top.v:1524, 1600`<br>`tb/tb_recovery_policy.v:10` |
| **IRQs 30:4** | Tied to 0 | Unused (`27'd0`) | Never asserted | N/A | Reserved PIC interrupt inputs | `rtl/soc_top.v:1600` |

### 3.2 Core PIC Control & Servicing
- **Programmable Interrupt Controller (PIC)**: Instantiated inside VeeR core (`core/Cores-VeeR-EL2/design/el2_pic_ctrl.sv:24`).
- **Memory Mapping**: Internal core bus window `0xF00C_0000`–`0xF00C_7FFF` (`snapshots/default/common_defines.vh:112`).
- **Registers per Source**:
  - `meipl[i]`: Priority level (0 = disabled, 1 = lowest, 15 = highest).
  - `meip[i]`: Pending status bit.
  - `meie[i]`: Interrupt enable mask bit.
- **CPU Trap Vector**: Traps to `mtvec` (Machine Trap-Vector Base-Address Register) when `mstatus.MIE = 1` and `mie.MEIE = 1`.

---

## 4. Power, Mode, and Debug Control Architecture

| Subsystem Control | Physical Port / Register | Controlling Entity | Default Setting | Operational Role & Constraints | Source Citation |
|---|---|---|---|---|---|
| **Autonomous Boot** | `mpc_reset_run_req` | Hardwired constant in `soc_top.v:1788` | `1'b1` (Always Run) | Instructs VeeR EL2 core to immediately begin program execution upon reset release without waiting for debugger run command. | `rtl/soc_top.v:1788` |
| **External Halt Request** | `i_cpu_halt_req`, `mpc_debug_halt_req` | Hardwired constant in `soc_top.v:1784, 1790` | `1'b0` (Disabled) | Prevents unprompted external CPU halting; CPU can only be halted via JTAG DMI commands. | `rtl/soc_top.v:1784, 1790` |
| **Scan Test Mode** | `scan_mode` | Hardwired constant in `soc_top.v:1796` | `1'b0` (Functional Mode) | Disables manufacturing scan chain shifting during normal SoC operation. | `rtl/soc_top.v:1796` |
| **Memory BIST Mode** | `mbist_mode` | Hardwired constant in `soc_top.v:1797` | `1'b0` (Functional Mode) | Disables built-in self-test memory controllers during normal SoC operation. | `rtl/soc_top.v:1797` |
| **JTAG DMI Access** | `jtag_tck`, `tms`, `tdi`, `tdo`, `trst_n` | External 5-pin JTAG connector | Driven by external debugger | Full IEEE 1149.1 TAP interface allowing register inspection, breakpoint insertion, and memory dumping. | `rtl/soc_top.v:1761-1767`<br>`core/Cores-VeeR-EL2/design/dmi/rvjtag_tap.v:23` |
