# Top-Level Block Roles & Custom IP Behavioral Specifications

**Document ID:** `docs/arch/02_blocks.md`  
**Stage:** Stage 2 — Block Roles, Interconnect Connectivity, and Custom IP Behavioral Summaries  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md)  

---

## 1. Top-Level Module Sub-Block Catalog

The table below catalogs every block instantiated directly under the SoC top-level module [`soc_top`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L162-L1891) (`rtl/soc_top.v:162-1891`).

| Instance | Module | Type | Role in the SoC | Bus Interface(s) | Other Ports (Events, IRQs, Resets, External Pins) | Clock | Reset | Source Citation |
|---|---|---|---|---|---|---|---|---|
| `u_veer` | `el2_veer_wrapper` | Core / Bus Master | Central 32-bit RISC-V processor executing management firmware, servicing console commands, and enforcing supervisory policies. | • **Master 0 (IFU)**: 64-bit AXI4 Instruction Fetch (`ifu_axi_*`)<br>• **Master 1 (LSU)**: 64-bit AXI4 Load/Store (`lsu_axi_*`)<br>• **Master 2 (SB)**: 64-bit AXI4 System Bus / Debug (`sb_axi_*`)<br>• **Slave (DMA)**: 64-bit AXI4 (tied off to 0) | • **IRQs**: `extintsrc_req[30:0]` receiving `lockout_irq`, `vblank_irq`, `hb_irq`, `uart_irq`<br>• **JTAG**: `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo`, `jtag_trst_n`<br>• **Memory Export**: `el2_mem_export` (DCCM interface), `el2_icache_export` (tied off) | `clk` (100 MHz) | `rst_n` (active-low via `rst_l` and `dbg_rst_l`) | `rtl/soc_top.v:1586-1811` |
| `gen_dccm_banks[0..3].u_dccm_bank` | `ram_4096x39` | Memory (Tightly Coupled) | Four parallel SRAM banks providing 64 KB of tightly coupled data memory (DCCM) with 7-bit SECDED ECC for low-latency stack, heap, and BSS execution. | Dedicated synchronous memory port driven by `el2_mem_export` (`dccm_clken`, `dccm_wren_bank`, `dccm_addr_bank`, `dccm_wr_data_bank`, `dccm_wr_ecc_bank`) | • **Data Out**: `dccm_bank_fdout[3:0][38:0]` feeding `dccm_bank_dout` (bits 31:0) and `dccm_bank_ecc` (bits 38:32) | `clk` (100 MHz) | Unreset synchronous RAM macro | `rtl/soc_top.v:1817-1839` |
| `u_axi_intercon` | `axi_interconnect_wrap_3x8` | Interconnect / Crossbar | 3-Master $\times$ 8-Slave crossbar switch matrix arbitrating memory requests from VeeR IFU, LSU, and SB, and steering transactions to peripherals based on high-order address bits. | • **Slaves (from Masters)**:<br>&nbsp;&nbsp;`s00_axi_*` (IFU, 64-bit)<br>&nbsp;&nbsp;`s01_axi_*` (LSU, 64-bit)<br>&nbsp;&nbsp;`s02_axi_*` (SB, 64-bit)<br>• **Masters (to Slaves)**:<br>&nbsp;&nbsp;`m00_axi_*` to `m07_axi_*` (64-bit down-steered) | None (pure bus routing crossbar) | `clk` (100 MHz) | `rst` (`~rst_n`, active-high synchronous) | `rtl/soc_top.v:751-1300` |
| `u_uart` | `axi_uart_top` | Peripheral / Bus Slave | 16550-compatible serial communications controller providing out-of-band management console telemetry, boot logging, and command parsing at 115200 baud. | • **Slave 0 (M00)**: 32-bit AXI-Lite read/write channel (window `0x0002_0000`–`0x0002_00FF`) | • **External Pins**: `uart_rx` (input), `uart_tx` (output)<br>• **IRQ**: `read_interrupt_o` (`uart_irq` routed to `u_veer.extintsrc_req[0]`) | `clk` (`fixed_clk_i`, `axi_aclk_i`) | `rst_n` (`axi_aresetn_i`, active-low) | `rtl/soc_top.v:705-739` |
| `u_timer` | `axi_timer` | Peripheral / Bus Slave | 32-bit free-running hardware monotonic uptime counter used for timeout calculation, execution profiling, and event logging timestamps. | • **Slave 1 (M01)**: 64-bit AXI4 read/write slave interface (window `0x0002_0100`–`0x0002_01FF`) | None | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1303-1341` |
| `u_gpio` | `axi_gpio` | Peripheral / Bus Slave | General-purpose pin status register mirroring physical external input and output lines to allow software readback of board state. | • **Slave 2 (M02)**: 64-bit AXI4 read/write slave interface (window `0x0002_0200`–`0x0002_02FF`) | • **Sensed Signals**: `heartbeat_in` (external pin), `reset_out_internal` (from Reset Sequencer) | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1346-1386` |
| `u_heartbeat` | `axi_heartbeat_monitor` | Peripheral / Bus Slave (Custom IP) | Hardware watchdog tracking host system alive pulses; automatically latches a sticky fault and asserts an interrupt if pulse interval exceeds programmed threshold. | • **Slave 3 (M03)**: 64-bit AXI4 read/write slave interface (window `0x0002_0300`–`0x0002_03FF`) | • **External Pin**: `heartbeat_in` (sensed pulse input)<br>• **IRQ**: `hb_irq` (routed to `u_veer.extintsrc_req[1]`) | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1391-1430` |
| `u_reset_seq` | `axi_reset_sequencer` | Peripheral / Bus Slave (Custom IP) | Hardware reset pulse engine delivering an atomic, glitch-free active-low reset pulse of programmable clock duration to power-cycle the host CPU. | • **Slave 4 (M04)**: 64-bit AXI4 read/write slave interface (window `0x0002_0400`–`0x0002_04FF`) | • **External Pin**: `reset_out` (`reset_out_internal`, active-low reset pulse to host system) | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1437-1475` |
| `u_rec_policy` | `axi_recovery_policy` | Peripheral / Bus Slave (Custom IP) | Fault escalation engine logging recovery events into a 16-entry circular RAM and latching a crash-loop lockout if recoveries exceed threshold in a rolling window. | • **Slave 5 (M05)**: 64-bit AXI4 read/write slave interface (window `0x0002_0500`–`0x0002_05FF`) | • **IRQ**: `lockout_irq` (routed to `u_veer.extintsrc_req[3]`) | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1490-1525` |
| `u_vga` | `axi_vga_controller` | Peripheral / Bus Slave (Custom IP) | Dedicated video display controller rendering a 3-row $\times$ 40-column hardware text console at 640x480 @ 60Hz for local rack-level monitoring. | • **Slave 6 (M06)**: 64-bit AXI4 read/write slave interface (window `0x0002_0600`–`0x0002_06FF`) | • **External Pins**: `vga_hsync`, `vga_vsync`, `vga_rgb[11:0]`<br>• **IRQ**: `vblank_irq` (routed to `u_veer.extintsrc_req[2]`) | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1535-1578` |
| `u_rom` | `axi_rom` | Memory / Bus Slave (Custom IP) | 8 KB read-only memory mapped at boot vector `0x8000_0000`, containing initial hardware startup instructions and bare-metal firmware. | • **Slave 7 (M07)**: 64-bit AXI4 read/write slave interface (window `0x8000_0000`–`0x8000_1FFF`) | None (preloaded via `$readmemh` from `firmware.hex`) | `clk` (100 MHz) | `rst_n` (active-low) | `rtl/soc_top.v:1856-1888` |

---

## 2. Detailed Behavioral Summaries for Custom IP Blocks

### 2.1 Heartbeat Monitor (`axi_heartbeat_monitor` / `heartbeat_monitor`)

* **Primary Purpose**: Provides fully autonomous, hardware-enforced health monitoring of the external host system without requiring firmware execution to detect timeouts.
* **Source Files**: 
  - Wrapper: [`rtl/custom_ips/axi_heartbeat_monitor.v:4`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_heartbeat_monitor.v#L4)
  - Core: [`rtl/custom_ips/heartbeat_monitor.v:4`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/heartbeat_monitor.v#L4)
  - Unit TB: [`tb/tb_heartbeat_monitor.v:14`](file:///home/student/sriv_183/honour_soc/tb/tb_heartbeat_monitor.v#L14)
* **Parameters**:
  - `AXI_ADDR_WIDTH = 32`, `AXI_DATA_WIDTH = 64`, `AXI_ID_WIDTH = 8` (`soc_top.v:1391-1430`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, `heartbeat_in`, AXI4 write/read channel signals (`s_axi_aw*`, `s_axi_w*`, `s_axi_b*`, `s_axi_ar*`, `s_axi_r*`).
  - **Outputs**: `hb_irq` (interrupt line), AXI4 slave response signals.
* **Internal State & Storage**:
  - **FSM State Register (`hb_state`)**: 2-bit state encoding:
    - `2'b00` (`DISABLED`): Monitor is inactive, `hb_counter` held at 0, `hb_unresponsive_flag` cleared.
    - `2'b01` (`IDLE`): Monitor enabled by firmware, waiting for the first rising edge on `heartbeat_in`.
    - `2'b10` (`COUNTING`): Actively incrementing `hb_counter` on each clock cycle between heartbeats.
    - `2'b11` (`UNRESPONSIVE`): Terminal timeout state entered when `hb_counter >= hb_threshold_reg`.
  - **Counter (`hb_counter`)**: 32-bit register incrementing every clock cycle while in `COUNTING` state. Resets synchronously to 0 upon detection of a rising edge on `heartbeat_in`.
  - **Edge Detector (`hb_prev_sample`)**: 1-bit register latching previous value of `heartbeat_in` to detect `heartbeat_in && !hb_prev_sample`.
  - **Sticky Fault Flag (`hb_unresponsive_flag`)**: 1-bit latch asserted upon timeout; remains set even if heartbeats resume until explicitly cleared by software.
* **Register Map (Base Address: `0x0002_0300`)**:
  - `0x00` — `HB_CTRL` (WO/RW):
    - `bit[0]`: `enable` (1 = active, 0 = disabled/reset).
    - `bit[1]`: `clear_flag` (Write 1 to clear `hb_unresponsive_flag`; self-clearing).
  - `0x04` — `HB_THRESHOLD` (RW): `[31:0]` maximum allowable clock cycles between heartbeat pulses before timeout triggers.
  - `0x08` — `HB_STATUS` (RO):
    - `bit[0]`: `unresponsive_flag` (1 = host frozen / timed out, 0 = normal).
  - `0x0C` — `HB_ELAPSED` (RO): `[31:0]` current value of `hb_counter` exposing real-time cycle latency to firmware.
* **Main Behaviors**:
  1. *Timeout Detection*: If `hb_counter` matches or exceeds `HB_THRESHOLD`, `hb_unresponsive_flag` asserts and `hb_irq` is driven high (`tb/tb_heartbeat_monitor.v:264-270`).
  2. *Sticky Latching*: Resumption of heartbeat pulses while in `UNRESPONSIVE` resets `hb_counter` but **does not** clear `hb_unresponsive_flag` (`tb/tb_heartbeat_monitor.v:290-308`).
  3. *Firmware Clear*: Writing `bit[1] = 1` to `HB_CTRL` clears `hb_unresponsive_flag` and deasserts `hb_irq`.
  4. *Disable Flush*: Writing `enable = 0` forces FSM to `DISABLED`, flushes `hb_counter = 0`, and clears flags (`tb/tb_heartbeat_monitor.v:361-366`).

---

### 2.2 Power/Reset Sequencer (`axi_reset_sequencer` / `reset_sequencer`)

* **Primary Purpose**: Hardware engine designed to assert and hold an atomic, glitch-free active-low power reset pulse of precisely calibrated cycle length to reboot a frozen host system.
* **Source Files**:
  - Wrapper: [`rtl/custom_ips/axi_reset_sequencer.v:4`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_reset_sequencer.v#L4)
  - Core: [`rtl/custom_ips/reset_sequencer.v:4`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/reset_sequencer.v#L4)
  - Unit TB: [`tb/tb_reset_sequencer.v:14`](file:///home/student/sriv_183/honour_soc/tb/tb_reset_sequencer.v#L14)
* **Parameters**:
  - `AXI_ADDR_WIDTH = 32`, `AXI_DATA_WIDTH = 64`, `AXI_ID_WIDTH = 8` (`soc_top.v:1437-1472`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, AXI4 write/read channel signals.
  - **Outputs**: `reset_out` (`reset_out_internal`), AXI4 slave responses.
* **Internal State & Storage**:
  - **FSM State Register (`rst_state`)**: 2-bit state encoding:
    - `2'b00` (`IDLE`): Output `reset_out = 1'b1` (deasserted). Waiting for trigger.
    - `2'b01` (`ASSERT`): Output `reset_out = 1'b0` (asserted). Countdown decrementing.
    - `2'b10` (`DEASSERT`): Output `reset_out = 1'b1`. Pipeline settling.
    - `2'b11` (`DONE`): Pulse complete. Sticky `rst_complete` bit asserted.
  - **Duration Register (`rst_hold_reg`)**: 32-bit register holding the target pulse width.
  - **Down-Counter (`rst_countdown`)**: 32-bit counter loaded from `rst_hold_reg` on trigger; decrements each clock cycle until reaching 0.
  - **Status Flags**: `rst_in_progress` (high during `ASSERT` state) and `rst_complete` (sticky completion indicator).
* **Register Map (Base Address: `0x0002_0400`)**:
  - `0x00` — `RST_CTRL` (WO):
    - `bit[0]`: `trigger` (Self-clearing write-1 to launch reset sequence).
  - `0x04` — `RST_HOLD_CYCLES` (RW): `[31:0]` number of clock cycles to hold `reset_out` low.
  - `0x08` — `RST_STATUS` (RO):
    - `bit[0]`: `in_progress` (1 = reset pulse currently asserting low).
    - `bit[1]`: `complete` (1 = reset sequence finished; sticky).
* **Main Behaviors**:
  1. *Reset Driving*: In `IDLE`, drives `reset_out = 1'b1`. On `trigger`, immediately asserts `reset_out = 1'b0`, sets `in_progress = 1`, and clears `complete = 0` (`tb/tb_reset_sequencer.v:1-10`).
  2. *Re-trigger Protection*: If firmware writes `trigger = 1` while `in_progress == 1`, the write is ignored without altering the ongoing countdown (`tb/tb_reset_sequencer.v:7`).
  3. *Pulse Termination*: When `rst_countdown == 0`, output returns to `1'b1`, `in_progress` clears, and `complete` asserts (`soc_top.v:1436`).

---

### 2.3 Recovery Policy & Event Log (`axi_recovery_policy` / `recovery_policy`)

* **Primary Purpose**: Tracks recovery frequency over a rolling time window, stores a circular history of failure timestamps, and triggers an autonomous hardware lockout if the system enters a crash-loop.
* **Source Files**:
  - Wrapper: [`rtl/custom_ips/axi_recovery_policy.v:4`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_recovery_policy.v#L4)
  - Core: [`rtl/custom_ips/recovery_policy.v:23`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/recovery_policy.v#L23)
  - Unit TB: [`tb/tb_recovery_policy.v:17`](file:///home/student/sriv_183/honour_soc/tb/tb_recovery_policy.v#L17)
* **Parameters**:
  - `AXI_ADDR_WIDTH = 32`, `AXI_DATA_WIDTH = 64`, `AXI_ID_WIDTH = 8` (`soc_top.v:1490-1525`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, AXI4 write/read channel signals.
  - **Outputs**: `lockout_irq` (interrupt line), AXI4 slave responses.
* **Internal State & Storage**:
  - **Circular Event Log (`log_buffer`)**: 16-entry $\times$ 32-bit array storing recovery timestamps.
  - **Write Pointer (`log_wr_ptr`)**: 4-bit pointer indexing next write slot (wraps naturally 0..15).
  - **Cumulative Event Counter (`log_count`)**: 32-bit counter of all recorded recoveries since reset.
  - **Window Cycle Counter (`window_counter`)**: 32-bit timer tracking elapsed cycles in current evaluation window.
  - **Window Recovery Counter (`window_recovery_count`)**: 8-bit counter tracking recoveries within the current window.
  - **Sticky Lockout Flag (`lockout_flag`)**: 1-bit latch asserted when `window_recovery_count >= policy_threshold_reg`.
  - **Staged Timestamp (`staged_event_ts`)**: 32-bit register holding timestamp to be recorded on trigger.
* **Register Map (Base Address: `0x0002_0500`)**:
  - `0x00` — `POL_CTRL` (WO):
    - `bit[0]`: `record_event` (Self-clearing write-1 committing `staged_event_ts` to log).
    - `bit[1]`: `clear_lockout` (Self-clearing write-1 clearing `lockout_flag` and `lockout_irq`).
  - `0x04` — `POL_WINDOW` (RW): `[31:0]` rolling window duration in clock cycles.
  - `0x08` — `POL_THRESHOLD` (RW): `[7:0]` maximum allowable recoveries per window before lockout.
  - `0x0C` — `POL_STATUS` (RO):
    - `bit[0]`: `lockout_flag` (1 = crash-loop lockout active).
    - `bits[15:8]`: `window_recovery_count` (current recovery count in active window).
  - `0x10` — `POL_EVENT_TS` (WO): `[31:0]` timestamp written by firmware prior to asserting `record_event`.
  - `0x14` — `LOG_READ_IDX` (RW): `[3:0]` read index selector for circular log buffer.
  - `0x18` — `LOG_READ_DATA` (RO): `[31:0]` timestamp entry read from `log_buffer[LOG_READ_IDX]`.
  - `0x1C` — `LOG_COUNT` (RO): `[31:0]` cumulative total recovery events recorded.
* **Main Behaviors**:
  1. *Event Logging*: Writing `POL_CTRL.record_event = 1` writes `staged_event_ts` into `log_buffer[log_wr_ptr]`, advances `log_wr_ptr = (log_wr_ptr + 1) & 4'hF`, increments `log_count`, and increments `window_recovery_count` (`tb/tb_recovery_policy.v:1-13`).
  2. *Window Expiration*: `window_counter` increments each clock. When `window_counter >= POL_WINDOW`, both `window_counter` and `window_recovery_count` reset to 0 (`docs/BMC_Architecture_MicroArchitecture_Spec.md:496-497`).
  3. *Crash-Loop Lockout*: When `window_recovery_count >= POL_THRESHOLD`, `lockout_flag` sets to 1 and asserts `lockout_irq` to the CPU (`tb/tb_recovery_policy.v:9-10`).
  4. *Lockout Persistence*: `lockout_flag` is sticky; window expirations do not clear it. Only an explicit firmware write of `POL_CTRL.clear_lockout = 1` clears `lockout_flag` and `lockout_irq` (`tb/tb_recovery_policy.v:10-11`).

---

### 2.4 VGA Controller (`axi_vga_controller` / `vga_controller`)

* **Primary Purpose**: Autonomous video display engine rendering a real-time 3-row $\times$ 40-column text console on an external monitor at 640x480 @ 60Hz.
* **Source Files**:
  - Wrapper: [`rtl/custom_ips/axi_vga_controller.v:4`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_vga_controller.v#L4)
  - Core: [`rtl/custom_ips/vga_controller.v:18`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/vga_controller.v#L18)
* **Parameters**:
  - `AXI_ADDR_WIDTH = 32`, `AXI_DATA_WIDTH = 64`, `AXI_ID_WIDTH = 8` (`soc_top.v:1535-1578`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, AXI4 write/read channel signals.
  - **Outputs**: `vga_hsync`, `vga_vsync`, `vga_rgb[11:0]` (external video pins), `vblank_irq` (interrupt line), AXI4 slave responses.
* **Internal State & Storage**:
  - **Character Buffer (`vga_buffer`)**: 30 words $\times$ 4 bytes = 120 bytes of ASCII character storage arranged as 3 rows of 40 columns (`soc_top.v:1534`).
  - **Timing Beam Counters**: Horizontal counter `h_count` (0..799) and vertical counter `v_count` (0..524) for standard 640x480 timing.
  - **Pixel Clock Generator**: Clock divider generating 25 MHz pixel strobe from 100 MHz input clock (`docs/BMC_Architecture_MicroArchitecture_Spec.md:328`).
  - **Refresh Flag**: Latched flag set when frame begins to inform CPU of vertical blanking window.
* **Register Map (Base Address: `0x0002_0600`)**:
  - `0x00` — `VGA_CTRL` (RW): `bit[0]` = `enable` (1 = active display, 0 = video engine halted).
  - `0x04` — `VGA_STATUS` (RO): `bit[0]` = `refresh_flag` (cleared at frame start).
  - `0x08`–`0x7C` — `VGA_BUFFER` (WO): 30 consecutive 32-bit words containing packed ASCII characters for the 120-character display grid.
* **Main Behaviors**:
  1. *Video Synchronization*: Generates 31.468 kHz horizontal sync and 59.94 Hz vertical sync pulses matching standard VGA timing specifications.
  2. *Character Rendering*: Maps pixel coordinates to character cell positions in `VGA_BUFFER` and outputs active pixel colors via `vga_rgb[11:0]`.
  3. *Vertical Blank Interrupt*: Asserts `vblank_irq` during the vertical blanking porch to allow tear-free buffer updates by firmware.

---

### 2.5 System Timer (`axi_timer`)

* **Primary Purpose**: Monotonic free-running hardware counter providing high-precision cycle timestamps for bare-metal firmware.
* **Source Files**: [`rtl/custom_ips/axi_timer.v:10`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_timer.v#L10)
* **Parameters**: `DATA_WIDTH = 64`, `ADDR_WIDTH = 32`, `ID_WIDTH = 8` (`soc_top.v:1304-1306`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, AXI4 write/read channel signals.
  - **Outputs**: AXI4 slave responses. No external pins or interrupts.
* **Internal State & Storage**:
  - `cycle_counter`: 32-bit unsigned register incrementing continuously on every rising edge of `clk` while `rst_n` is high.
* **Register Map (Base Address: `0x0002_0100`)**:
  - `0x00` — `TMR_CTR` (RO): `[31:0]` current cycle count.
* **Main Behaviors**:
  - Always active; increments every clock cycle from system reset release.
  - Provides unmodifiable, monotonic reference time for latency benchmarking and Recovery Policy event stamping.

---

### 2.6 GPIO Status Register (`axi_gpio`)

* **Primary Purpose**: Memory-mapped status register exposing external physical pin levels to the processor.
* **Source Files**: [`rtl/custom_ips/axi_gpio.v:13`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_gpio.v#L13)
* **Parameters**: `DATA_WIDTH = 64`, `ADDR_WIDTH = 32`, `ID_WIDTH = 8` (`soc_top.v:1347-1349`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, `heartbeat_in`, `reset_out_internal`, AXI4 write/read channel signals.
  - **Outputs**: AXI4 slave responses.
* **Internal State & Storage**:
  - Two-stage synchronizer/sampling flops capturing external input `heartbeat_in` and driven output `reset_out_internal`.
* **Register Map (Base Address: `0x0002_0200`)**:
  - `0x00` — `GPIO_STATUS` (RO):
    - `bit[0]`: `heartbeat_in` (sensed real-time logic level of external heartbeat line).
    - `bit[1]`: `reset_out` (sensed real-time logic level of active-low host reset line).
* **Main Behaviors**:
  - Enables diagnostic readback of pin states during firmware self-test.

---

### 2.7 Boot ROM (`axi_rom`)

* **Primary Purpose**: Read-only boot memory mapped at processor reset vector `0x8000_0000` containing startup instructions and firmware binary.
* **Source Files**: [`rtl/custom_ips/axi_rom.v:11`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi_rom.v#L11)
* **Parameters**: Mapped window size 8 KB (`soc_top.v:809`, `M07_ADDR_WIDTH = 13`).
* **Interface Ports**:
  - **Inputs**: `clk`, `rst_n`, AXI4 write and read channel signals.
  - **Outputs**: AXI4 slave read and write responses.
* **Internal State & Storage**:
  - 8192-byte array preloaded at simulation startup via `$readmemh("firmware.hex", mem)`.
* **Register / Address Space (Base Address: `0x8000_0000`–`0x8000_1FFF`)**:
  - Supports 32-bit and 64-bit aligned read bursts from VeeR IFU and LSU.
* **Main Behaviors**:
  - Services instruction fetch bursts from address `0x8000_0000`.
  - Write attempts return standard AXI error responses or are discarded with zero write acknowledgement.

---

### 2.8 AXI-to-Wishbone Bridge (`axi4_to_wb_bridge`) [Uninstantiated / Standalone IP]

* **Primary Purpose**: Protocol translation bridge converting 64-bit AXI4 single-beat transactions into 32-bit Wishbone B4 bus cycles.
* **Source Files**: [`rtl/custom_ips/axi4_to_wb_bridge.v:17`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi4_to_wb_bridge.v#L17)
* **Status**: Uninstantiated in `soc_top.v` [INFERRED: Retained from predecessor design; custom IPs now wrap AXI4 natively].
* **Parameters**: `AXI_ADDR_WIDTH = 32`, `AXI_DATA_WIDTH = 64`, `AXI_ID_WIDTH = 9`, `WB_ADDR_WIDTH = 32`, `WB_DATA_WIDTH = 32`.
* **Interface Ports**:
  - **AXI4 Slave Side**: Full AXI4 read and write slave interfaces.
  - **Wishbone B4 Master Side**: `wb_adr_o`, `wb_dat_o`, `wb_dat_i`, `wb_we_o`, `wb_stb_o`, `wb_cyc_o`, `wb_ack_i`, `wb_err_i`, `wb_sel_o`.
* **Internal State & Storage**:
  - Translation FSM (`IDLE`, `WB_WRITE`, `WB_READ`, `AXI_RESP`).
  - Latched transaction ID (`awid_reg`, `arid_reg`) and address/data registers.
* **Main Behaviors**:
  - Steers 64-bit write data to 32-bit Wishbone data bus using address bit `addr[2]`.
  - Replicates 32-bit Wishbone read data across both 32-bit lanes of the 64-bit AXI read bus.
  - Translates Wishbone `wb_err_i` assertion into AXI `SLVERR` (`2'b10`) response.

---

## 3. Discrepancy Analysis: RTL Implementation vs. Architectural Documentation

In accordance with Ground Rule 4, the following discrepancies between repository documentation ([`docs/BMC_Architecture_MicroArchitecture_Spec.md`](file:///home/student/sriv_183/honour_soc/docs/BMC_Architecture_MicroArchitecture_Spec.md)) and the actual RTL ([`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v)) were identified:

| Subject | Documentation Claim | Actual RTL Implementation | Verification Impact |
|---|---|---|---|
| **Peripheral Interconnect Bus Protocol** | Specification describes all peripherals connected via an **AXI-to-Wishbone Bridge** to a shared 32-bit Wishbone B4 peripheral bus (`BMC_Architecture_MicroArchitecture_Spec.md:33, 261-277, 351`). | `soc_top.v` instantiates a **pure AXI4 3x8 crossbar** (`axi_interconnect_wrap_3x8`). All peripherals have native AXI4 slave wrappers (`axi_heartbeat_monitor`, `axi_reset_sequencer`, etc.). The bridge `axi4_to_wb_bridge.v` is **uninstantiated** (`soc_top.v:751-1578`). | Testbench agents must drive and monitor pure AXI4 / AXI-Lite transactions at the peripheral interfaces, rather than Wishbone signals. |
| **Heartbeat Interrupt Routing** | Documentation labels `hb_irq` as "optional" and describes software polling `HB_STATUS` as the primary mechanism (`BMC_Architecture_MicroArchitecture_Spec.md:286, 598`). | `soc_top.v` hard-wires `hb_irq` directly into the VeeR core's interrupt line: `.extintsrc_req({27'd0, lockout_irq, vblank_irq, hb_irq, uart_irq})` (`rtl/soc_top.v:1600`). | Verification must validate both interrupt-driven handling and register polling. |
| **AES Core Integration** | Directory contains an ingested 128-bit AES IP core (`rtl/ips/aes_core/rtl/verilog/aes_axi.v:14`). | The AES module is **not instantiated** anywhere in `soc_top.v` and is not allocated a slave port in `axi_interconnect_wrap_3x8` (`rtl/soc_top.v:751-810`). [INFERRED: Future expansion]. | AES core is out of scope for the SoC top-level UVM verification plan. |

---

## 4. Corrections (Audit Task 13)

1. **Reset Sequencer FSM States (`reset_sequencer.v:21-23`)**:
   - Section 2.2 previously claimed a 4th state `2'b11 (DONE)`.
   - **Correction**: Synthesizable RTL defines exactly 3 states: `ST_IDLE = 2'b00`, `ST_ASSERT = 2'b01`, and `ST_DEASSERT = 2'b10`. Completion flag `complete` is set in `ST_DEASSERT`, which returns unconditionally to `ST_IDLE` on the subsequent clock cycle.

