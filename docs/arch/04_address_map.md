# Complete SoC Address Map & Register Specifications

**Document ID:** `docs/arch/04_address_map.md`  
**Stage:** Stage 4 — Address Map, Register Definitions, Undecoded Space, and Spec Gaps  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md), [`docs/arch/02_blocks.md`](file:///home/student/sriv_183/honour_soc/docs/arch/02_blocks.md), and [`docs/arch/03_bus_matrix.md`](file:///home/student/sriv_183/honour_soc/docs/arch/03_bus_matrix.md)  

---

## 1. Full SoC Memory & Peripheral Address Map

The table below catalogs every memory and peripheral address region across the 32-bit physical address space of the BMC SoC, citing interconnect decoders and architectural declarations.

| Base Address | Size | End Address | Target Block / Module | Interconnect Port | Access Restrictions | Role / Description | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x0002_0000` | 256 B | `0x0002_00FF` | `u_uart` (`axi_uart_top`) | Slave 0 (`M00`) | R/W (IFU & LSU connected; SB disconnected) | 16550-compatible serial management console registers | `rtl/soc_top.v:760-764`<br>`firmware/test/test_common.h:9` |
| `0x0002_0100` | 256 B | `0x0002_01FF` | `u_timer` (`axi_timer`) | Slave 1 (`M01`) | RO (Writes ignored; SB disconnected) | 32-bit monotonic uptime tick counter register | `rtl/soc_top.v:767-771`<br>`firmware/test/test_common.h:10` |
| `0x0002_0200` | 256 B | `0x0002_02FF` | `u_gpio` (`axi_gpio`) | Slave 2 (`M02`) | RO (Writes ignored; SB disconnected) | External pin (`heartbeat_in`, `reset_out`) status register | `rtl/soc_top.v:774-778`<br>`firmware/test/test_common.h:11` |
| `0x0002_0300` | 256 B | `0x0002_03FF` | `u_heartbeat` (`axi_heartbeat_monitor`) | Slave 3 (`M03`) | R/W (IFU & LSU connected; SB disconnected) | Hardware watchdog timeout detection & sticky latch registers | `rtl/soc_top.v:781-785`<br>`firmware/test/test_common.h:12` |
| `0x0002_0400` | 256 B | `0x0002_04FF` | `u_reset_seq` (`axi_reset_sequencer`) | Slave 4 (`M04`) | R/W (IFU & LSU connected; SB disconnected) | Atomic power reset pulse trigger & duration registers | `rtl/soc_top.v:788-792`<br>`firmware/test/test_common.h:13` |
| `0x0002_0500` | 256 B | `0x0002_05FF` | `u_rec_policy` (`axi_recovery_policy`) | Slave 5 (`M05`) | R/W (IFU & LSU connected; SB disconnected) | Recovery threshold, circular log RAM & lockout registers | `rtl/soc_top.v:795-799`<br>`firmware/test/test_common.h:14` |
| `0x0002_0600` | 256 B | `0x0002_06FF` | `u_vga` (`axi_vga_controller`) | Slave 6 (`M06`) | R/W (IFU & LSU connected; SB disconnected) | 640x480 @ 60Hz 3x40 text console & character buffer | `rtl/soc_top.v:802-806`<br>`firmware/test/test_common.h:15` |
| `0x8000_0000` | 8 KB | `0x8000_1FFF` | `u_rom` (`axi_rom`) | Slave 7 (`M07`) | RO (Writes return error / ignored; All masters connected) | Hardware boot ROM preloaded with `firmware.hex` | `rtl/soc_top.v:808-809`<br>`firmware/link.ld:7` |
| `0xF004_0000` | 64 KB | `0xF004_FFFF` | `u_dccm_bank[0..3]` (`ram_4096x39`) | Internal Memory Export (`el2_mem_export`) | R/W (VeeR core internal only; Bypass crossbar) | Tightly-Coupled Data Memory (DCCM) with 7-bit ECC | `firmware/link.ld:9`<br>`snapshots/default/common_defines.vh:44` |
| `0xF00C_0000` | 32 KB | `0xF00C_7FFF` | `u_veer.pic_ctrl_inst` (`el2_pic_ctrl`) | Internal Core Bus | R/W (Core internal only) | Programmable Interrupt Controller (PIC) control registers | `core/Cores-VeeR-EL2/design/el2_pic_ctrl.sv:24`<br>`snapshots/default/common_defines.vh:112` |

---

## 2. Comprehensive Register Tables by Slave

### 2.1 Slave 0: UART Controller (`u_uart`, Base: `0x0002_0000`)
*Protocol: 32-bit AXI-Lite through 64-to-32 bit bus gasket (`soc_top.v:685-739`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `UART_RBR` (DLAB=0) | 32 (8 eff) | RO | `0x00` | `[7:0]`: Receiver Buffer Register (oldest received ASCII character) | Reading pops next character from the 16-byte internal RX FIFO. | `firmware/test/test_common.h:21`<br>`axi_uart_top.v:28-150` |
| `0x00` | `UART_THR` (DLAB=0) | 32 (8 eff) | WO | `0x00` | `[7:0]`: Transmitter Holding Register (character to transmit) | Writing pushes character into the 16-byte TX FIFO; starts transmission serializer. | `firmware/test/test_common.h:22`<br>`axi_uart_top.v:28-150` |
| `0x00` | `UART_DLL` (DLAB=1) | 32 (8 eff) | RW | `0x00` | `[7:0]`: Divisor Latch LSB (baud rate generator divisor low byte) | Configures baud rate when DLAB (`LCR[7]`) is 1. | `axi_uart_top.v:110-180` |
| `0x04` | `UART_IER` (DLAB=0) | 32 (4 eff) | RW | `0x00` | • `[0]`: Enable Received Data Available Interrupt<br>• `[1]`: Enable Transmitter Holding Register Empty Interrupt<br>• `[2]`: Enable Receiver Line Status Interrupt<br>• `[3]`: Enable Modem Status Interrupt | Enables interrupt generation on `uart_irq`. | `firmware/test/test_common.h:23`<br>`axi_uart_top.v:110-180` |
| `0x04` | `UART_DLM` (DLAB=1) | 32 (8 eff) | RW | `0x00` | `[7:0]`: Divisor Latch MSB (baud rate generator divisor high byte) | Configures baud rate when DLAB (`LCR[7]`) is 1. | `axi_uart_top.v:110-180` |
| `0x08` | `UART_IIR` | 32 (4 eff) | RO | `0x01` | • `[0]`: Interrupt Pending Flag (0 = pending, 1 = no interrupt)<br>• `[3:1]`: Interrupt Identification Priority Level | Reading clears specific pending interrupt status. | `firmware/test/test_common.h:24`<br>`axi_uart_top.v:110-180` |
| `0x08` | `UART_FCR` | 32 (8 eff) | WO | `0x00` | • `[0]`: FIFO Enable<br>• `[1]`: Clear RX FIFO (self-clearing)<br>• `[2]`: Clear TX FIFO (self-clearing)<br>• `[7:6]`: RX FIFO Trigger Threshold Level | Writing resets internal FIFO pointers. | `firmware/test/test_common.h:25`<br>`axi_uart_top.v:110-180` |
| `0x0C` | `UART_LCR` | 32 (8 eff) | RW | `0x03` | • `[1:0]`: Word Length Select (11 = 8 bits)<br>• `[2]`: Number of Stop Bits (0 = 1 stop bit)<br>• `[3]`: Parity Enable<br>• `[4]`: Even Parity Select<br>• `[7]`: Divisor Latch Access Bit (DLAB) | Switching DLAB changes mapping of offsets `0x00` and `0x04`. | `firmware/test/test_common.h:26`<br>`axi_uart_top.v:110-180` |
| `0x10` | `UART_MCR` | 32 (5 eff) | RW | `0x00` | • `[0]`: Data Terminal Ready (DTR)<br>• `[1]`: Request to Send (RTS)<br>• `[4]`: Loopback Mode Enable | Controls modem lines and hardware loopback. | `firmware/test/test_common.h:27`<br>`axi_uart_top.v:110-180` |
| `0x14` | `UART_LSR` | 32 (7 eff) | RO | `0x60` | • `[0]`: Data Ready (DR, RX FIFO has data)<br>• `[1]`: Overrun Error<br>• `[2]`: Parity Error<br>• `[3]`: Framing Error<br>• `[4]`: Break Interrupt<br>• `[5]`: Transmitter Holding Register Empty (`THRE = 1`, `0x20`)<br>• `[6]`: Transmitter Empty (`TEMT = 1`, `0x40`) | Informs firmware whether UART can accept more TX characters. | `firmware/test/test_common.h:28, 31`<br>`firmware/test/test_uart.c:7-13` |
| `0x18` | `UART_MSR` | 32 (8 eff) | RO | `0x00` | `[7:4]`: Modem Status Signals (CTS, DSR, RI, DCD) | Reading clears delta flags. | `firmware/test/test_common.h:29` |
| `0x1C` | `UART_SCR` | 32 (8 eff) | RW | `0x00` | `[7:0]`: Scratchpad byte | General-purpose read/write byte storage. | `firmware/test/test_common.h:30` |

---

### 2.2 Slave 1: System Timer (`u_timer`, Base: `0x0002_0100`)
*Protocol: 64-bit native AXI4 (`soc_top.v:1303-1341`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `TMR_CTR` | 32 | RO | `0x0000_0000` | `[31:0]`: Free-running hardware clock cycle counter | Increments every clock cycle. Writes are ignored by hardware. | `rtl/soc_top.v:1303-1341`<br>`firmware/test/test_common.h:34` |
| `0x04`–`0xFF` | *Undecoded* | — | — | `0x0000_0000` | Unused address offsets within 256-byte window | Returns 0; writes ignored. Crossbar returns `OKAY`. | `rtl/soc_top.v:767-771` |

---

### 2.3 Slave 2: GPIO Status (`u_gpio`, Base: `0x0002_0200`)
*Protocol: 64-bit native AXI4 (`soc_top.v:1346-1386`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `GPIO_STATUS` | 32 | RO | `0x0000_0002` [INFERRED: bit 1 reset_out defaults high] | • `[0]`: `heartbeat_in` (Current logic level of external heartbeat input pin)<br>• `[1]`: `reset_out` (Current logic level of host power reset output line)<br>• `[31:2]`: Reserved (tied to 0) | Real-time pin sampling. Writes are ignored by hardware. | `rtl/soc_top.v:1346-1386`<br>`firmware/test/test_common.h:11` |
| `0x04`–`0xFF` | *Undecoded* | — | — | `0x0000_0000` | Unused address offsets within 256-byte window | Returns 0; writes ignored. Crossbar returns `OKAY`. | `rtl/soc_top.v:774-778` |

---

### 2.4 Slave 3: Heartbeat Monitor (`u_heartbeat`, Base: `0x0002_0300`)
*Protocol: 64-bit native AXI4 (`soc_top.v:1391-1430`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `HB_CTRL` | 32 | WO/RW | `0x0000_0000` | • `[0]`: `enable` (1 = active monitoring, 0 = disabled/reset)<br>• `[1]`: `clear_flag` (Write 1 to clear `unresponsive_flag`; self-clearing)<br>• `[31:2]`: Reserved | Writing `enable=0` resets counter to 0 and clears sticky flag. Writing `clear_flag=1` clears `unresponsive_flag` and deasserts `hb_irq`. | `rtl/soc_top.v:1391`<br>`tb/tb_heartbeat_monitor.v:22, 303, 362` |
| `0x04` | `HB_THRESHOLD` | 32 | RW | `0x0000_0000` | `[31:0]`: Maximum allowable clock cycles between rising edges on `heartbeat_in` before timeout is declared | Modifies timeout comparator threshold immediately. | `tb/tb_heartbeat_monitor.v:23, 223`<br>`firmware/test/test_common.h:12` |
| `0x08` | `HB_STATUS` | 32 | RO | `0x0000_0000` | • `[0]`: `unresponsive_flag` (1 = host frozen / timed out, 0 = normal)<br>• `[31:1]`: Reserved (tied to 0) | Mirrors internal sticky latch. Asserting drives `hb_irq = 1`. | `tb/tb_heartbeat_monitor.v:24, 240, 266` |
| `0x0C` | `HB_ELAPSED` | 32 | RO | `0x0000_0000` | `[31:0]`: Current elapsed clock cycles since last detected heartbeat rising edge | Returns real-time value of internal `hb_counter`. | `tb/tb_heartbeat_monitor.v:25, 330` |
| `0x10`–`0xFF` | *Undecoded* | — | — | `0x0000_0000` | Unused address offsets within 256-byte window | Returns 0; writes ignored. Crossbar returns `OKAY`. | `rtl/soc_top.v:781-785` |

---

### 2.5 Slave 4: Power/Reset Sequencer (`u_reset_seq`, Base: `0x0002_0400`)
*Protocol: 64-bit native AXI4 (`soc_top.v:1437-1472`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `RST_CTRL` | 32 | WO | `0x0000_0000` | • `[0]`: `trigger` (Self-clearing write-1 to launch reset sequence)<br>• `[31:1]`: Reserved | Writing 1 while `in_progress == 0` drives `reset_out = 1'b0`, enters `ASSERT`, and clears `complete`. Ignored if `in_progress == 1`. Reads return 0. | `rtl/soc_top.v:1434`<br>`tb/tb_reset_sequencer.v:22` |
| `0x04` | `RST_HOLD_CYCLES` | 32 | RW | `0x0000_0000` | `[31:0]`: Duration of the reset pulse in clock cycles | Loaded into countdown timer upon trigger. | `rtl/soc_top.v:1435`<br>`tb/tb_reset_sequencer.v:23` |
| `0x08` | `RST_STATUS` | 32 | RO | `0x0000_0000` | • `[0]`: `in_progress` (1 = active-low reset pulse asserting)<br>• `[1]`: `complete` (1 = reset pulse finished; sticky until next trigger)<br>• `[31:2]`: Reserved | Informs firmware whether reset sequence has completed. | `rtl/soc_top.v:1436`<br>`tb/tb_reset_sequencer.v:24` |
| `0x0C`–`0xFF` | *Undecoded* | — | — | `0x0000_0000` | Unused address offsets within 256-byte window | Returns 0; writes ignored. Crossbar returns `OKAY`. | `rtl/soc_top.v:788-792` |

---

### 2.6 Slave 5: Recovery Policy & Event Log (`u_rec_policy`, Base: `0x0002_0500`)
*Protocol: 64-bit native AXI4 (`soc_top.v:1490-1525`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `POL_CTRL` | 32 | WO | `0x0000_0000` | • `[0]`: `record_event` (Self-clearing write-1 committing `staged_event_ts` to log)<br>• `[1]`: `clear_lockout` (Self-clearing write-1 clearing `lockout_flag` and `lockout_irq`)<br>• `[31:2]`: Reserved | Writing `record_event=1` writes timestamp to circular RAM and advances write pointer. Writing `clear_lockout=1` deasserts lockout. | `rtl/soc_top.v:1482`<br>`tb/tb_recovery_policy.v:25` |
| `0x04` | `POL_WINDOW` | 32 | RW | `0x0000_0000` | `[31:0]`: Rolling evaluation window size in clock cycles | Defines duration before window recovery counter resets to 0. | `rtl/soc_top.v:1483`<br>`tb/tb_recovery_policy.v:26` |
| `0x08` | `POL_THRESHOLD` | 32 (8 eff) | RW | `0x0000_0000` | `[7:0]`: Maximum recoveries permitted per window before lockout triggers | Modifies crash-loop threshold comparator. | `rtl/soc_top.v:1484`<br>`tb/tb_recovery_policy.v:27` |
| `0x0C` | `POL_STATUS` | 32 | RO | `0x0000_0000` | • `[0]`: `lockout_flag` (1 = crash-loop lockout active)<br>• `[15:8]`: `window_recovery_count` (recoveries in active window)<br>• `[31:16]`, `[7:1]`: Reserved | Asserting `lockout_flag` drives `lockout_irq = 1`. Sticky across windows. | `rtl/soc_top.v:1485`<br>`tb/tb_recovery_policy.v:28` |
| `0x10` | `POL_EVENT_TS` | 32 | WO | `0x0000_0000` | `[31:0]`: Staged timestamp value supplied by firmware prior to event recording | Latches timestamp into internal holding register. | `rtl/soc_top.v:1486`<br>`tb/tb_recovery_policy.v:29` |
| `0x14` | `LOG_READ_IDX` | 32 (4 eff) | RW | `0x0000_0000` | `[3:0]`: Read index selecting slot (0..15) in circular event RAM | Updates read address multiplexer for `LOG_READ_DATA`. | `rtl/soc_top.v:1487`<br>`tb/tb_recovery_policy.v:30` |
| `0x18` | `LOG_READ_DATA` | 32 | RO | `0x0000_0000` | `[31:0]`: Timestamp entry stored at `log_buffer[LOG_READ_IDX]` | Reading returns historical failure timestamp. | `rtl/soc_top.v:1488`<br>`tb/tb_recovery_policy.v:31` |
| `0x1C` | `LOG_COUNT` | 32 | RO | `0x0000_0000` | `[31:0]`: Cumulative total recovery events recorded since system reset | Increments on every committed `record_event`. | `rtl/soc_top.v:1489`<br>`tb/tb_recovery_policy.v:32` |
| `0x20`–`0xFF` | *Undecoded* | — | — | `0x0000_0000` | Unused address offsets within 256-byte window | Returns 0; writes ignored. Crossbar returns `OKAY`. | `rtl/soc_top.v:795-799` |

---

### 2.7 Slave 6: VGA Controller (`u_vga`, Base: `0x0002_0600`)
*Protocol: 64-bit native AXI4 (`soc_top.v:1535-1578`).*

| Offset | Register Name | Width | Access | Reset Value | Bit Breakdown & Field Description | Read / Write Side Effects | Source Citation |
|---|---|---|---|---|---|---|---|
| `0x00` | `VGA_CTRL` | 32 | RW | `0x0000_0000` | • `[0]`: `enable` (1 = video engine active, 0 = halted)<br>• `[31:1]`: Reserved | Enables 25MHz pixel clock divider and raster beam counters. | `rtl/soc_top.v:1532` |
| `0x04` | `VGA_STATUS` | 32 | RO | `0x0000_0000` | • `[0]`: `refresh_flag` (cleared at start of frame)<br>• `[31:1]`: Reserved | Informs CPU of vertical frame refresh status. | `rtl/soc_top.v:1533` |
| `0x08`–`0x7C` | `VGA_BUFFER` | 32 $\times$ 30 words | WO | All `0x00` | Packed ASCII character array: 30 words $\times$ 4 bytes = 120 characters representing a 3-row $\times$ 40-column hardware text console | Stores characters rendered to video output. | `rtl/soc_top.v:1534` |
| `0x80`–`0xFF` | *Undecoded* | — | — | `0x0000_0000` | Unused address offsets within 256-byte window | Returns 0; writes ignored. Crossbar returns `OKAY`. | `rtl/soc_top.v:802-806` |

---

## 3. Address Map Gaps, Overlaps, and Specification Discrepancies

### 3.1 Address Gaps and Undecoded Space
1. **Unmapped Address Spaces (Decoder Return `DECERR = 2'b11`)**:
   - `0x0000_0000` to `0x0001_FFFF` (128 KB unmapped region below peripherals).
   - `0x0002_0700` to `0x7FFF_FFFF` (~2 GB unmapped window between peripherals and Boot ROM).
   - `0x8000_2000` to `0xF003_FFFF` (~1.75 GB unmapped window above Boot ROM).
   - Any transaction targeting these gaps fails crossbar decode and receives immediate AXI `DECERR` (`2'b11`).
2. **Undecoded Space within Peripheral Windows (Return `OKAY = 2'b00`)**:
   - Each peripheral is assigned a 256-byte (`M_ADDR_WIDTH = 8`) window by the crossbar.
   - However, registers within each peripheral only occupy lower offsets (e.g., offsets `0x10`–`0xFF` in `axi_timer` and `axi_gpio` are unused).
   - Because the crossbar address match succeeds on `addr[31:8] == 0x000201`, transactions to offsets `0x20`–`0xFF` are forwarded to the peripheral. The peripheral's internal decode logic returns `0x0000_0000` on reads and discards writes, returning `bresp = OKAY` (`2'b00`) rather than `DECERR`.
3. **No Address Overlaps**:
   - All 8 slave windows have non-overlapping base addresses and powers-of-two window sizes (`0x0002_0000`, `0x0002_0100`, `0x0002_0200`, `0x0002_0300`, `0x0002_0400`, `0x0002_0500`, `0x0002_0600`, and `0x8000_0000`).

### 3.2 Documentation vs. RTL Discrepancies
1. **Base Address Mismatch in Spec Document**:
   - [`docs/BMC_Architecture_MicroArchitecture_Spec.md:26-30`](file:///home/student/sriv_183/honour_soc/docs/BMC_Architecture_MicroArchitecture_Spec.md#L26-L30) and earlier notes discuss legacy 16-bit Wishbone addressing.
   - **RTL Reality**: Pure 32-bit AXI memory map where all peripherals reside in upper space `0x0002_0xxx`, confirmed by [`rtl/soc_top.v:760-809`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L760-L809) and [`firmware/test/test_common.h:9-15`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L9-L15).
2. **Unmapped Address Error Response Code**:
   - `docs/BMC_Architecture_MicroArchitecture_Spec.md:23` states that unmapped address accesses return `SLVERR` (`2'b10`).
   - **RTL Reality**: The crossbar decoder logic in [`rtl/interconnect/axi_interconnect.v:642, 734`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L642) explicitly drives `2'b11` (`DECERR`).

---

## 4. Corrections: RTL-Extracted Register Reset Values (Audit Task 14)

In accordance with Ground Rule 1 and Ground Rule 3, the table below provides the exact synthesizable RTL reset values extracted directly from the register initialization logic in `rtl/custom_ips/*` and `rtl/ips/*`.

| Slave ID | Base Address | Offset | Register Name | Width | Access Type | Actual RTL Reset Value | Verified RTL Source Citation | Notes & Side Effects |
|---|---|---|---|---|---|---|---|---|
| **M00 (UART)** | `0x0002_0000` | `0x00` | `UART_RBR` (DLAB=0) | 8 | RO | `0x00` | `axi_uart_top.v:347` | Receiver FIFO is empty at reset. |
| **M00 (UART)** | `0x0002_0000` | `0x00` | `UART_THR` (DLAB=0) | 8 | WO | `0x00` | `axi_uart_top.v:530` | Pushes into TX FIFO. |
| **M00 (UART)** | `0x0002_0000` | `0x00` | `UART_DLL` (DLAB=1) | 8 | RW | `0x00` | `axi_uart_top.v:531` | Baudrate divisor low byte. |
| **M00 (UART)** | `0x0002_0000` | `0x04` | `UART_IER` (DLAB=0) | 4 | RW | `0x00` | `axi_uart_top.v:534` | All UART interrupts disabled. |
| **M00 (UART)** | `0x0002_0000` | `0x04` | `UART_DLM` (DLAB=1) | 8 | RW | `0x00` | `axi_uart_top.v:532` | Baudrate divisor high byte. |
| **M00 (UART)** | `0x0002_0000` | `0x08` | `UART_IIR` | 4 | RO | **`0x01`** | `axi_uart_top.v:47` | Bit 0=1 indicates no interrupt pending. |
| **M00 (UART)** | `0x0002_0000` | `0x08` | `UART_FCR` | 8 | WO | `0x00` | `axi_uart_top.v:48` | Writes clear/enable FIFOs. |
| **M00 (UART)** | `0x0002_0000` | `0x0C` | `UART_LCR` | 8 | RW | `0x00` | `axi_uart_top.v:533` | Bit 7 is DLAB selector. |
| **M00 (UART)** | `0x0002_0000` | `0x10` | `UART_MCR` | 5 | RW | `0x00` | `axi_uart_top.v:50` | Modem control / loopback. |
| **M00 (UART)** | `0x0002_0000` | `0x14` | `UART_LSR` | 7 | RO | **`0x60`** | `axi_uart_top.v:628-634` | Bit 5 (`THRE`)=1 and Bit 6 (`TEMT`)=1 (TX FIFO empty). |
| **M00 (UART)** | `0x0002_0000` | `0x18` | `UART_MSR` | 8 | RO | `0x00` | `axi_uart_top.v:52` | Modem status flags. |
| **M00 (UART)** | `0x0002_0000` | `0x1C` | `UART_SCR` | 8 | RW | `0x00` | `axi_uart_top.v:53` | Scratchpad byte. |
| **M01 (Timer)** | `0x0002_0100` | `0x00` | `TMR_CTR` | 32 | RO | `0x0000_0000` | `axi_timer.v:35-45` | Free-running monotonic tick counter; increments immediately. |
| **M02 (GPIO)** | `0x0002_0200` | `0x00` | `GPIO_STAT` | 32 (2 eff) | RO | **`0x0000_0002`** | `axi_gpio.v:4-8, 114` | Bit 0=`heartbeat_in` (0), Bit 1=`reset_out` (1 active-low idle). |
| **M03 (Heartbeat)** | `0x0002_0300` | `0x00` | `HB_CTRL` | 32 (2 eff) | WO/RW | `0x0000_0000` | `heartbeat_monitor.v:58-61` | Bit 0=`enable` (0), Bit 1=`clear_flag` (0). |
| **M03 (Heartbeat)** | `0x0002_0300` | `0x04` | `HB_THRESHOLD` | 32 | RW | `0x0000_0000` | `heartbeat_monitor.v:62` | Timeout threshold in clock cycles. |
| **M03 (Heartbeat)** | `0x0002_0300` | `0x08` | `HB_STATUS` | 32 (2 eff) | RO | `0x0000_0000` | `heartbeat_monitor.v:75` | Bit 0=`unresponsive_flag` (0), Bit 1=`heartbeat_in` (0). |
| **M03 (Heartbeat)** | `0x0002_0300` | `0x0C` | `HB_ELAPSED` | 32 | RO | `0x0000_0000` | `heartbeat_monitor.v:76, 81` | Real-time cycle latency (`hb_counter`). |
| **M04 (Reset Seq)** | `0x0002_0400` | `0x00` | `RST_CTRL` | 32 (1 eff) | WO | `0x0000_0000` | `reset_sequencer.v:48` | Bit 0=`trigger_req` (self-clearing write-1). |
| **M04 (Reset Seq)** | `0x0002_0400` | `0x04` | `RST_HOLD_CYCLES` | 32 | RW | **`0x0000_0064`** | `reset_sequencer.v:47` | **Default is `32'd100` (`100` clock cycles)**, not `0`. |
| **M04 (Reset Seq)** | `0x0002_0400` | `0x08` | `RST_STATUS` | 32 (2 eff) | RO | `0x0000_0000` | `reset_sequencer.v:59, 72-73` | Bit 0=`in_progress` (0), Bit 1=`complete` (0). |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x00` | `POL_CTRL` | 32 (2 eff) | WO | `0x0000_0000` | `recovery_policy.v:70-71` | Bit 0=`record_event`, Bit 1=`clear_lockout`. |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x04` | `POL_WINDOW` | 32 | RW | `0x0000_0000` | `recovery_policy.v:72` | Evaluation window in clock cycles. |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x08` | `POL_THRESHOLD` | 32 (8 eff) | RW | **`0x0000_0003`** | `recovery_policy.v:73` | **Default is `8'd3` (`3` recoveries)**, not `0`. |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x0C` | `POL_STATUS` | 32 (9 eff) | RO | `0x0000_0000` | `recovery_policy.v:107, 129` | Bit 0=`lockout_flag` (0), Bits [15:8]=`window_recovery_count` (0). |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x10` | `POL_EVENT_TS` | 32 | WO | `0x0000_0000` | `recovery_policy.v:74` | Staged timestamp holding register. Reads return 0. |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x14` | `LOG_READ_IDX` | 32 (4 eff) | RW | `0x0000_0000` | `recovery_policy.v:75` | Read index selecting circular buffer slot (0..15). |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x18` | `LOG_READ_DATA` | 32 | RO | `0x0000_0000` | `recovery_policy.v:108, 133` | Historical timestamp stored at `log_buffer[LOG_READ_IDX]`. |
| **M05 (Rec Policy)**| `0x0002_0500` | `0x1C` | `LOG_COUNT` | 32 | RO | `0x0000_0000` | `recovery_policy.v:109, 128` | Cumulative total recovery count since reset. |
| **M06 (VGA)** | `0x0002_0600` | `0x00` | `VGA_CTRL` | 32 (1 eff) | RW | `0x0000_0000` | `vga_controller.v:112` | Bit 0=`enable` (video engine off). |
| **M06 (VGA)** | `0x0002_0600` | `0x04` | `VGA_STATUS` | 32 (1 eff) | RO | `0x0000_0000` | `vga_controller.v:113` | Bit 0=`refresh_flag` (0). |
| **M06 (VGA)** | `0x0002_0600` | `0x08`–`0x7C` | `VGA_BUFFER` (30 words) | 32 $\times$ 30 | RW | **`0x2020_2020`** | `vga_controller.v:114-115, 142` | **All 30 words reset to ASCII spaces (`32'h20202020`)**. Readable and writable. |
| **M07 (Boot ROM)** | `0x8000_0000` | `0x0000`–`0x1FFC` | `ROM_DATA` (2048 words) | 64 | RO | Preloaded Image | `axi_rom.v:11-30`, `firmware/start.S:8` | Preloaded with `firmware.hex` bootloader instructions. |

