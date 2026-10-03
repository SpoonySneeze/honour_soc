# Honour SoC — Complete Memory Map & Register Reference Manual

**Document Revision:** 2.0  
**Date:** October 3, 2026  
**System Architecture:** Native Pure AXI4 Bus Matrix (64-bit Crossbar)  
**Processor Core:** Western Digital VeeR EL2 (RV32IMC Bare-Metal RISC-V)  
**Status:** Verified & Active  

---

## 1. Top-Level Physical Memory Map Architecture

The Honour Baseboard Management Controller (BMC) SoC utilizes a unified 32-bit physical address space (`0x0000_0000` to `0xFFFFFFFF`).

High-speed execution memory is split between core-local Closely Coupled Memories (ICCM/DCCM) and external AXI4 targets. The AXI4 Interconnect routes transactions across two distinct segments:
1. **Peripheral Subsystem Window (`0x0002_0000` – `0x0002_06FF`):** Memory-mapped registers for 7 distinct peripheral slaves (256 bytes allocated per slave).
2. **System Boot ROM (`0x8000_0000` – `0x8000_1FFF`):** 8 KB instruction memory mapped to reset vector `0x8000_0000`.

```
+-------------------+ 0x0000_0000
|     Core ICCM     |  64 KB Instruction Local Memory (TCM)
+-------------------+ 0x0000_FFFF
|     Core DCCM     |  64 KB Data Local Memory (TCM)
+-------------------+ 0x0001_FFFF
| Peripheral Window |  Native AXI4 64-bit Crossbar (Slaves 0 to 6)
|   - 0x0002_0000   |    Slave 0: UART 16550 Serial Controller
|   - 0x0002_0100   |    Slave 1: AXI System Timer
|   - 0x0002_0200   |    Slave 2: AXI GPIO Status
|   - 0x0002_0300   |    Slave 3: AXI Heartbeat Monitor Watchdog
|   - 0x0002_0400   |    Slave 4: AXI Power/Reset Sequencer
|   - 0x0002_0500   |    Slave 5: AXI Recovery Policy & Circular Event Log
|   - 0x0002_0600   |    Slave 6: AXI VGA Status Dashboard Controller
+-------------------+ 0x0002_06FF
|     Reserved      |  Unmapped / Bus Trap
+-------------------+ 0x7FFF_FFFF
|   AXI Boot ROM    |  8 KB Native AXI4 Read-Only Slave (Slave 7)
|  (Reset Vector)   |  VeeR EL2 Core Boots Here at 0x8000_0000
+-------------------+ 0x8000_1FFF
|     Reserved      |  Unmapped / Bus Trap
+-------------------+ 0xFFFF_FFFF
```

---

## 2. AXI4 Interconnect Routing & Slave Decode Matrix

The SoC uses an auto-generated 64-bit native AXI4 crossbar interconnect (`u_axi_intercon`) with 8 slave ports (`M00` to `M07`).

| Port | Peripheral Target | Base Address | Address Range | Size | Addr Width | Read Conn | Write Conn |
|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| — | **ICCM (Local)** | `0x0000_0000` | `0x0000_0000` – `0x0000_FFFF` | 64 KB | 16-bit | Core IFU | Core LSU |
| — | **DCCM (Local)** | `0x0001_0000` | `0x0001_0000` – `0x0001_FFFF` | 64 KB | 16-bit | Core LSU | Core LSU |
| **M00** | **UART 16550** | `0x0002_0000` | `0x0002_0000` – `0x0002_00FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M01** | **System Timer** | `0x0002_0100` | `0x0002_0100` – `0x0002_01FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M02** | **GPIO Status** | `0x0002_0200` | `0x0002_0200` – `0x0002_02FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M03** | **Heartbeat Monitor** | `0x0002_0300` | `0x0002_0300` – `0x0002_03FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M04** | **Reset Sequencer** | `0x0002_0400` | `0x0002_0400` – `0x0002_04FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M05** | **Recovery Policy** | `0x0002_0500` | `0x0002_0500` – `0x0002_05FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M06** | **VGA Dashboard** | `0x0002_0600` | `0x0002_0600` – `0x0002_06FF` | 256 B | 8-bit | 2'b11 | 2'b11 |
| **M07** | **AXI Boot ROM** | `0x8000_0000` | `0x8000_0000` – `0x8000_1FFF` | 8 KB | 13-bit | 2'b11 | 2'b11 |

> [!NOTE]
> **VeeR EL2 MRAC CSR Configuration Required:**  
> When accessing peripherals in Region 0 (`0x0000_0000`–`0x0FFF_FFFF`), the core's `MRAC` CSR (`0x7C0`) must be configured with `side_effect = 1` (`csrw 0x7c0, 0x00000002`). Without this bit set, the core LSU zeroes bits `[2:0]` on peripheral accesses, causing sub-word register aliasing.

---

## 3. Detailed Per-IP Memory & Register Specifications

---

### 3.1 Slave 0: UART 16550 Serial Controller (`0x0002_0000`)
* **Base Address:** `0x0002_0000`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v`
* **Default Baud Rate:** 115,200 baud (Divisor = 16 at 100 MHz clock)

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `UART_RBR` | RO | `0x0000_0000` | Receiver Buffer Register (Read received character byte) |
| `0x00` | `UART_THR` | WO | `0x0000_0000` | Transmitter Holding Register (Write character byte to transmit) |
| `0x04` | `UART_IER` | WO | `0x0000_0000` | Interrupt Enable Register |
| `0x08` | `UART_IIR` | RO | `0x0000_0001` | Interrupt Identification Register |
| `0x08` | `UART_FCR` | WO | `0x0000_0000` | FIFO Control Register |
| `0x0C` | `UART_LCR` | WO | `0x0000_0000` | Line Control Register (DLAB, Parity, Stop bits, Word length) |
| `0x10` | `UART_MCR` | WO | `0x0000_0000` | Modem Control Register |
| `0x14` | `UART_LSR` | RO | `0x0000_0060` | Line Status Register |

#### Register Bitfields

##### `UART_LSR` — Line Status Register (Offset `0x14`, Read-Only)
```
 31                                       7   6     5    4   3   2   1   0
+---------------------------------------+---+-----+----+---+---+---+---+---+
|               Reserved                | - | TEMT|THRE| BI| FE| PE| OE| DR|
+---------------------------------------+---+-----+----+---+---+---+---+---+
```
* **Bit `[0]` (`DR`)**: Data Ready. Set when incoming byte is in RX FIFO.
* **Bit `[1]` (`OE`)**: Overrun Error.
* **Bit `[2]` (`PE`)**: Parity Error.
* **Bit `[3]` (`FE`)**: Framing Error.
* **Bit `[4]` (`BI`)**: Break Interrupt indicator.
* **Bit `[5]` (`THRE`)**: Transmitter Holding Register Empty (`1` = TX FIFO can accept new character).
* **Bit `[6]` (`TEMT`)**: Transmitter Empty (`1` = Transmitter FIFO and Shift Register are completely idle).
* **Bits `[31:7]`**: Reserved.

---

### 3.2 Slave 1: System Timer Peripheral (`0x0002_0100`)
* **Base Address:** `0x0002_0100`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/custom_ips/axi_timer.v`
* **Clock Domain:** 100 MHz System Clock (`clk`)

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `TMR_CTR` | RO | `0x0000_0000` | 32-Bit Monotonic Free-Running Hardware Cycle Counter |

#### Register Bitfields

##### `TMR_CTR` — Tick Counter Register (Offset `0x00`, Read-Only)
```
 31                                                                   0
+----------------------------------------------------------------------+
|                           TICK_COUNT [31:0]                          |
+----------------------------------------------------------------------+
```
* **Bits `[31:0]` (`TICK_COUNT`)**: Increments by `1` every clock cycle. Provides microsecond-precision hardware timestamps for logging recovery events and software delays. Rolls over from `0xFFFFFFFF` to `0x00000000` every ~42.94 seconds at 100 MHz.

---

### 3.3 Slave 2: GPIO Status Peripheral (`0x0002_0200`)
* **Base Address:** `0x0002_0200`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/custom_ips/axi_gpio.v`

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `GPIO_STAT` | RO | `0x0000_0002` | Live Hardware Pin Levels & Status Flags |

#### Register Bitfields

##### `GPIO_STAT` — Pin Status Register (Offset `0x00`, Read-Only)
```
 31                                                            2    1     0
+------------------------------------------------------------+----+-----+-----+
|                          Reserved                          | -  | RST | HB  |
+------------------------------------------------------------+----+-----+-----+
```
* **Bit `[0]` (`HB`)**: Live level of incoming external `heartbeat_in` pin.
* **Bit `[1]` (`RST`)**: Live level of outgoing SoC system reset line `reset_out` (`1` = normal operational state / reset deasserted; `0` = system held in reset).
* **Bits `[31:2]`**: Reserved, reads `0`.

---

### 3.4 Slave 3: Heartbeat Monitor Watchdog IP (`0x0002_0300`)
* **Base Address:** `0x0002_0300`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/custom_ips/axi_heartbeat_monitor.v`

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `HB_CTRL` | WO | `0x0000_0000` | Software Watchdog Pet / Heartbeat Stroke Command |
| `0x04` | `HB_THRESHOLD` | R/W | `0x0001_86A0` | Watchdog Expiration Threshold (Cycles, default 100,000) |
| `0x08` | `HB_STATUS` | RO | `0x0000_0001` | Watchdog Monitor State & Timeout Expiration Alarm |
| `0x0C` | `HB_ELAPSED` | RO | `0x0000_0000` | Clock Cycles Elapsed Since Last Valid Heartbeat Stroke |

#### Register Bitfields

##### `HB_CTRL` — Heartbeat Control Register (Offset `0x00`, Write-Only)
* **Bit `[0]` (`PET`)**: Write `1` to reset internal elapsed watchdog counter (`hb_elapsed <= 0`) and clear timeout condition.

##### `HB_THRESHOLD` — Expiration Threshold Register (Offset `0x04`, Read/Write)
* **Bits `[31:0]` (`THRESHOLD`)**: Maximum allowed clock cycles between heartbeats. When `HB_ELAPSED >= HB_THRESHOLD`, watchdog sets `unresponsive = 1` and asserts hardware alert.

##### `HB_STATUS` — Monitor Status Register (Offset `0x08`, Read-Only)
```
 31                                                            2      1      0
+------------------------------------------------------------+---+----------+----+
|                          Reserved                          | - | TIMEOUT  | EN |
+------------------------------------------------------------+---+----------+----+
```
* **Bit `[0]` (`EN / ACTIVE`)**: Heartbeat monitor enabled status (`1` = active).
* **Bit `[1]` (`TIMEOUT / UNRESPONSIVE`)**: Watchdog timeout alarm (`1` = monitored entity missed heartbeat; `0` = normal operation).
* **Bits `[31:2]`**: Reserved.

##### `HB_ELAPSED` — Elapsed Cycle Counter (Offset `0x0C`, Read-Only)
* **Bits `[31:0]` (`ELAPSED`)**: Running cycle counter since the last pet or pulse.

---

### 3.5 Slave 4: Power/Reset Sequencer IP (`0x0002_0400`)
* **Base Address:** `0x0002_0400`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/custom_ips/axi_reset_sequencer.v`

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `RST_CTRL` | WO | `0x0000_0000` | Reset Initiation Command Register |
| `0x04` | `RST_HOLD_CYCLES`| R/W | `0x0000_0064` | Hold Duration for Power Transitions (Default 100 cycles)|
| `0x08` | `RST_STATUS` | RO | `0x0000_0000` | Sequencer State Machine Status & Active Flags |

#### Register Bitfields

##### `RST_CTRL` — Reset Trigger Control (Offset `0x00`, Write-Only)
```
 31                                                        3      2      1      0
+--------------------------------------------------------+---+--------+------+------+
|                        Reserved                        | - | OVERRIDE| WARM | COLD |
+--------------------------------------------------------+---+--------+------+------+
```
* **Bit `[0]` (`COLD_RST`)**: Write `1` to initiate cold power-cycle reset sequence.
* **Bit `[1]` (`WARM_RST`)**: Write `1` to initiate warm logic-only reset sequence.
* **Bit `[2]` (`MANUAL_OVERRIDE`)**: Assert manual reset override line.

##### `RST_HOLD_CYCLES` — Hold Timing Configuration (Offset `0x04`, Read/Write)
* **Bits `[31:0]` (`HOLD_CYCLES`)**: Duration (in system clock cycles) that power/reset lines are held during state transitions.

##### `RST_STATUS` — FSM Sequencer Status (Offset `0x08`, Read-Only)
```
 31                                              5       4       3   2       0
+----------------------------------------------+---+-----------+----+---------+
|                   Reserved                   | - | WARM_ACT  |COLD|FSM_STATE|
+----------------------------------------------+---+-----------+----+---------+
```
* **Bits `[2:0]` (`FSM_STATE`)**:
  - `3'b000` (0): `IDLE` (Normal operating mode)
  - `3'b001` (1): `ASSERT_PWR` (Power rail cycling)
  - `3'b010` (2): `WAIT_PWR` (Waiting for power good)
  - `3'b011` (3): `DEASSERT_RST` (Deasserting reset lines)
  - `3'b100` (4): `RUNNING` (Reset sequence finished)
  - `3'b101` (5): `FAULT_RECOVERY` (Brownout/fault state)
* **Bit `[3]` (`COLD_ACT`)**: Cold reset in progress.
* **Bit `[4]` (`WARM_ACT`)**: Warm reset in progress.

---

### 3.6 Slave 5: Recovery Policy & Circular Event Log IP (`0x0002_0500`)
* **Base Address:** `0x0002_0500`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/custom_ips/axi_recovery_policy.v`

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `POL_CTRL` | WO | `0x0000_0000` | Fault Trigger Injection & Lockout Reset Command |
| `0x04` | `POL_WINDOW` | R/W | `0x0007_A120` | Sliding Temporal Fault Window (Default 500,000 cycles) |
| `0x08` | `POL_THRESHOLD` | R/W | `0x0000_0003` | Fault Count Escalation Threshold (Default 3) |
| `0x0C` | `POL_STATUS` | RO | `0x0000_0000` | Escalation State, Fault Counter & Lockout Flag |
| `0x10` | `POL_EVENT_TS` | WO | `0x0000_0000` | Hardware/Software Event Logging Input Port |
| `0x14` | `LOG_READ_IDX` | R/W | `0x0000_0000` | Target Circular Buffer Read Index Pointer (0 to 15) |
| `0x18` | `LOG_READ_DATA`| RO | `0x0000_0000` | Event Timestamp Data Stored at `LOG_READ_IDX` |
| `0x1C` | `LOG_COUNT` | RO | `0x0000_0000` | Total Number of Logged Events in Circular FIFO |

#### Register Bitfields

##### `POL_CTRL` — Policy Control Register (Offset `0x00`, Write-Only)
* **Bit `[0]` (`FAULT_INJECT`)**: Write `1` to inject a synthetic fault into the escalation pipeline.
* **Bit `[1]` (`CLR_LOCKOUT`)**: Write `1` to clear Safe Mode Lockout and reset fault counter to 0.

##### `POL_STATUS` — Policy Status Register (Offset `0x0C`, Read-Only)
```
 31                                       8   7         5   4    3          0
+---------------------------------------+---+-------------+----+--------------+
|               Reserved                | - | ESCAL_STATE |LOCK| FAULT_COUNT  |
+---------------------------------------+---+-------------+----+--------------+
```
* **Bits `[3:0]` (`FAULT_COUNT`)**: Number of faults recorded within active sliding temporal window.
* **Bit `[4]` (`LOCKOUT`)**: Safe Mode Lockout active (`1` = threshold exceeded, system locked).
* **Bits `[7:5]` (`ESCAL_STATE`)**:
  - `3'b000` (0): Normal State
  - `3'b001` (1): Alert Level 1
  - `3'b010` (2): Warm Reset Escalation
  - `3'b011` (3): Cold Reset Escalation
  - `3'b100` (4): Safe Mode Lockout Shutdown

##### `LOG_READ_IDX` & `LOG_READ_DATA` (Offsets `0x14` & `0x18`)
* To inspect circular buffer entry $N$ (0–15):
  1. Write $N$ to `LOG_READ_IDX` (`0x0002_0514 = N`).
  2. Read 32-bit timestamp from `LOG_READ_DATA` (`uint32_t ts = *(0x0002_0518)`).

---

### 3.7 Slave 6: VGA Status Dashboard Controller (`0x0002_0600`)
* **Base Address:** `0x0002_0600`
* **Size:** 256 Bytes
* **Source RTL:** `rtl/custom_ips/axi_vga_controller.v`
* **Display Mode:** Standard 640x480 @ 60 Hz (80 columns x 30 rows text mode)

#### Register Map

| Offset | Register | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | `VGA_CTRL` | R/W | `0x0000_0000` | Master Display & Cursor Enable Controls |
| `0x04` | `VGA_STATUS` | RO | `0x0000_0000` | Vertical & Horizontal Blanking Status |
| `0x08` – `0xFF`| `VGA_TEXT_BUF` | R/W | `0x0000_0000` | Memory-Mapped Video Character/Attribute Buffer |

#### Register Bitfields

##### `VGA_CTRL` — Display Control Register (Offset `0x00`, Read/Write)
```
 31                                                       3      2      1      0
+-------------------------------------------------------+---+--------+------+------+
|                        Reserved                       | - | BLINK  |CURSOR| DISP |
+-------------------------------------------------------+---+--------+------+------+
```
* **Bit `[0]` (`DISP_EN`)**: Master display enable (`1` = active video output, `0` = blanked).
* **Bit `[1]` (`CURSOR_EN`)**: Hardware text cursor enable.
* **Bit `[2]` (`CURSOR_BLINK`)**: Hardware cursor blink enable.

##### `VGA_STATUS` — Sync Status Register (Offset `0x04`, Read-Only)
* **Bit `[0]` (`VBLANK`)**: Set `1` during Vertical Blanking interval (safe time for video buffer updates).
* **Bit `[1]` (`HBLANK`)**: Set `1` during Horizontal Blanking interval.

##### `VGA_TEXT_BUF` — Text Buffer (Offsets `0x08` through `0xFF`, Read/Write)
* Words map character glyphs (`bits [7:0]`) and color attributes (`bits [15:8]`) for console output.

---

### 3.8 Slave 7: AXI4 Boot ROM Controller (`0x8000_0000`)
* **Base Address:** `0x8000_0000`
* **Address Range:** `0x8000_0000` – `0x8000_1FFF`
* **Size:** 8 KB (8192 Bytes / 2048 Words)
* **Source RTL:** `rtl/custom_ips/axi_rom.v`
* **Reset Vector:** VeeR EL2 core begins instruction fetch at `0x8000_0000` upon reset deassertion.

#### Characteristics
* **Access Type:** Read-Only (`s_axi_ar*` and `s_axi_r*` channels active). Write requests receive `bresp = 2'b00` without modifying memory array.
* **Memory Initialization:** Preloaded in simulation via `$readmemh("firmware.hex", mem)`.
* **Latency:** Zero-wait-state pipelined response (`s_axi_arready` and `s_axi_rvalid` asserted back-to-back).

---

## 4. Software Header Definitions (`soc_memory_map.h`)

Below is the standard C header file definitions for firmware bare-metal driver access:

```c
#ifndef SOC_MEMORY_MAP_H
#define SOC_MEMORY_MAP_H

#include <stdint.h>

// ============================================================================
// Base Addresses
// ============================================================================
#define AXI_ROM_BASE    0x80000000U
#define UART_BASE       0x00020000U
#define TIMER_BASE      0x00020100U
#define GPIO_BASE       0x00020200U
#define HB_MON_BASE     0x00020300U
#define RESET_SEQ_BASE  0x00020400U
#define REC_POL_BASE    0x00020500U
#define VGA_BASE        0x00020600U

// ============================================================================
// 1. UART Registers
// ============================================================================
#define UART_RBR        (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_THR        (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_IER        (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_IIR        (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_FCR        (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_LCR        (*(volatile uint32_t*)(UART_BASE + 0x0C))
#define UART_MCR        (*(volatile uint32_t*)(UART_BASE + 0x10))
#define UART_LSR        (*(volatile uint32_t*)(UART_BASE + 0x14))
#define UART_LSR_THRE   (1U << 5)
#define UART_LSR_TEMT   (1U << 6)

// ============================================================================
// 2. System Timer Registers
// ============================================================================
#define TMR_CTR         (*(volatile uint32_t*)(TIMER_BASE + 0x00))

// ============================================================================
// 3. GPIO Status Registers
// ============================================================================
#define GPIO_STAT       (*(volatile uint32_t*)(GPIO_BASE + 0x00))
#define GPIO_STAT_HB_IN (1U << 0)
#define GPIO_STAT_RST_N (1U << 1)

// ============================================================================
// 4. Heartbeat Monitor Registers
// ============================================================================
#define HB_CTRL         (*(volatile uint32_t*)(HB_MON_BASE + 0x00))
#define HB_THRESHOLD    (*(volatile uint32_t*)(HB_MON_BASE + 0x04))
#define HB_STATUS       (*(volatile uint32_t*)(HB_MON_BASE + 0x08))
#define HB_ELAPSED      (*(volatile uint32_t*)(HB_MON_BASE + 0x0C))
#define HB_CTRL_PET     (1U << 0)
#define HB_STAT_ACTIVE  (1U << 0)
#define HB_STAT_TIMEOUT (1U << 1)

// ============================================================================
// 5. Power/Reset Sequencer Registers
// ============================================================================
#define RST_CTRL        (*(volatile uint32_t*)(RESET_SEQ_BASE + 0x00))
#define RST_HOLD_CYCLES (*(volatile uint32_t*)(RESET_SEQ_BASE + 0x04))
#define RST_STATUS      (*(volatile uint32_t*)(RESET_SEQ_BASE + 0x08))
#define RST_CTRL_COLD   (1U << 0)
#define RST_CTRL_WARM   (1U << 1)

// ============================================================================
// 6. Recovery Policy & Circular Event Log Registers
// ============================================================================
#define POL_CTRL        (*(volatile uint32_t*)(REC_POL_BASE + 0x00))
#define POL_WINDOW      (*(volatile uint32_t*)(REC_POL_BASE + 0x04))
#define POL_THRESHOLD   (*(volatile uint32_t*)(REC_POL_BASE + 0x08))
#define POL_STATUS      (*(volatile uint32_t*)(REC_POL_BASE + 0x0C))
#define POL_EVENT_TS    (*(volatile uint32_t*)(REC_POL_BASE + 0x10))
#define LOG_READ_IDX    (*(volatile uint32_t*)(REC_POL_BASE + 0x14))
#define LOG_READ_DATA   (*(volatile uint32_t*)(REC_POL_BASE + 0x18))
#define LOG_COUNT       (*(volatile uint32_t*)(REC_POL_BASE + 0x1C))
#define POL_CTRL_INJECT (1U << 0)
#define POL_CTRL_CLR_LCK (1U << 1)
#define POL_STAT_LOCKOUT (1U << 4)

// ============================================================================
// 7. VGA Controller Registers
// ============================================================================
#define VGA_CTRL        (*(volatile uint32_t*)(VGA_BASE + 0x00))
#define VGA_STATUS      (*(volatile uint32_t*)(VGA_BASE + 0x04))
#define VGA_TEXT_BUFFER ((volatile uint32_t*)(VGA_BASE + 0x08))
#define VGA_CTRL_DISP   (1U << 0)
#define VGA_STAT_VBLANK (1U << 0)

#endif // SOC_MEMORY_MAP_H
```
