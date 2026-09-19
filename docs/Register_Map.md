# BMC SoC Complete Hardware Register Specification

This specification document serves as the complete, authoritative register reference manual for all peripherals and custom IPs integrated into the **RISC-V Baseboard Management Controller (BMC) SoC**.

---

## 1. System Memory Architecture & Bus Interconnect

The BMC SoC utilizes a 32-bit memory-mapped address space. The **VeeR EL2** processor accesses peripherals through its 32-bit AXI4-Lite System Bus (SB) master port, which connects to the **AXI4-Lite to Wishbone B4 Bridge** (`u_axi2wb`). The bridge routes single-cycle transactions into a 1-to-7 **Wishbone B4 Interconnect** (`u_wb_intercon`).

```
+---------------------------------------------------------------------------------+
|                                 VeeR EL2 Core                                   |
|   ICCM: 0x0000_0000 - 0x0000_FFFF        DCCM: 0x0001_0000 - 0x0001_FFFF        |
+---------------------------------------------------------------------------------+
                                      | AXI4-Lite (System Bus)
                                      v
+---------------------------------------------------------------------------------+
|                       AXI4-Lite to Wishbone B4 Bridge                           |
+---------------------------------------------------------------------------------+
                                      | Wishbone B4 Master (wbm_*)
                                      v
+---------------------------------------------------------------------------------+
|                     Wishbone Interconnect (1-to-7 Decoder)                      |
+---------------------------------------------------------------------------------+
     |          |          |          |          |          |          |
  Slave 0    Slave 1    Slave 2    Slave 3    Slave 4    Slave 5    Slave 6
   UART       Timer      GPIO     Heartbeat    Reset     Recovery     VGA
  0x00020000 0x00020100 0x00020200 0x00020300 0x00020400 0x00020500 0x00020600
```

### 1.1 Address Decoding Logic
- **Peripheral Base Address**: `0x0002_0000`
- **Slave Page Selection**: Decoded from address bits `wbm_adr_i[15:8]`:
  - `8'h00` → Slave 0: UART
  - `8'h01` → Slave 1: Timer
  - `8'h02` → Slave 2: GPIO
  - `8'h03` → Slave 3: Heartbeat Monitor
  - `8'h04` → Slave 4: Power/Reset Sequencer
  - `8'h05` → Slave 5: Recovery Policy & Event Log
  - `8'h06` → Slave 6: VGA Controller
- **Local Register Offset**: Lower 8 bits `wbm_adr_i[7:0]` are passed directly to the selected slave.
- **Access Granularity**: All custom IPs accept 32-bit word accesses. Byte select (`wb_sel_i[3:0]`) is supported across the interconnect.

---

## 2. System Memory Map Summary

| Slave | Peripheral / Target | Base Address | Address Range | Size | Bus Protocol |
|---|---|---|---|---|---|
| — | **ICCM** (Instruction Memory) | `0x0000_0000` | `0x0000_0000` – `0x0000_FFFF` | 64 KB | Core TCM |
| — | **DCCM** (Data Memory) | `0x0001_0000` | `0x0001_0000` – `0x0001_FFFF` | 64 KB | Core TCM |
| **Slave 0** | **UART Controller** | `0x0002_0000` | `0x0002_0000` – `0x0002_00FF` | 256 B | Wishbone B4 |
| **Slave 1** | **Timer** | `0x0002_0100` | `0x0002_0100` – `0x0002_01FF` | 256 B | Wishbone B4 |
| **Slave 2** | **GPIO** | `0x0002_0200` | `0x0002_0200` – `0x0002_02FF` | 256 B | Wishbone B4 |
| **Slave 3** | **Heartbeat Monitor** | `0x0002_0300` | `0x0002_0300` – `0x0002_03FF` | 256 B | Wishbone B4 |
| **Slave 4** | **Power/Reset Sequencer** | `0x0002_0400` | `0x0002_0400` – `0x0002_04FF` | 256 B | Wishbone B4 |
| **Slave 5** | **Recovery Policy & Log** | `0x0002_0500` | `0x0002_0500` – `0x0002_05FF` | 256 B | Wishbone B4 |
| **Slave 6** | **VGA Controller** | `0x0002_0600` | `0x0002_0600` – `0x0002_06FF` | 256 B | Wishbone B4 |

---

## 3. Slave 0: UART Controller (`0x0002_0000`)

Standard National Semiconductor 16550-compatible UART register layout. In `soc_top.v`, Slave 0 provides a 1-cycle acknowledge stub returning `32'd0` until a full UART IP is attached.

| Address | Offset | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0000` | `0x00` | `UART_RBR` | RO | `0x0000_0000` | Receiver Buffer Register (when DLAB = 0) |
| `0x0002_0000` | `0x00` | `UART_THR` | WO | `0x0000_0000` | Transmitter Holding Register (when DLAB = 0) |
| `0x0002_0000` | `0x00` | `UART_DLL` | R/W | `0x0000_0000` | Divisor Latch LSB (when DLAB = 1) |
| `0x0002_0004` | `0x04` | `UART_IER` | R/W | `0x0000_0000` | Interrupt Enable Register (when DLAB = 0) |
| `0x0002_0004` | `0x04` | `UART_DLM` | R/W | `0x0000_0000` | Divisor Latch MSB (when DLAB = 1) |
| `0x0002_0008` | `0x08` | `UART_IIR` | RO | `0x0000_0001` | Interrupt Identification Register |
| `0x0002_0008` | `0x08` | `UART_FCR` | WO | `0x0000_0000` | FIFO Control Register |
| `0x0002_000C` | `0x0C` | `UART_LCR` | R/W | `0x0000_0000` | Line Control Register (Bit 7 = DLAB) |
| `0x0002_0010` | `0x10` | `UART_MCR` | R/W | `0x0000_0000` | Modem Control Register |
| `0x0002_0014` | `0x14` | `UART_LSR` | RO | `0x0000_0060` | Line Status Register (Bit 5 = THRE, Bit 6 = TEMT) |
| `0x0002_0018` | `0x18` | `UART_MSR` | RO | `0x0000_0000` | Modem Status Register |
| `0x0002_001C` | `0x1C` | `UART_SCR` | R/W | `0x0000_0000` | Scratchpad Register |

---

## 4. Slave 1: Timer Peripheral (`0x0002_0100`)

Provides a 32-bit hardware reference clock for system uptime and timestamping recovery events.

| Address | Offset | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0100` | `0x00` | `TMR_CTR` | RO | `0x0000_0000` | Free-Running Tick Counter |

### Bitfield Breakdown: `TMR_CTR` (Offset `0x00`)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                              TICK_COUNT                               |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`TICK_COUNT`)**: Increments by 1 on every positive clock edge (`clk`). Rolls over from `0xFFFFFFFF` to `0x00000000`. At 100 MHz, rollover period is ~42.94 seconds.

---

## 5. Slave 2: GPIO Peripheral (`0x0002_0200`)

Exposes direct physical pin status between the BMC and the monitored host system.

| Address | Offset | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0200` | `0x00` | `GPIO_STAT` | RO | `0x0000_0000` | Hardware Pin Status Register |

### Bitfield Breakdown: `GPIO_STAT` (Offset `0x00`)
```
 31                                                    2       1       0
+-------------------------------------------------------+-------+-------+
|                       RESERVED (0)                    |  RST  |  HB   |
+-------------------------------------------------------+-------+-------+
```
- **Bit `[0]` (`HB`)**: Live logic level of the external `heartbeat_in` pad.
- **Bit `[1]` (`RST`)**: Live logic level driven on `reset_out` by the Power/Reset Sequencer (active-low: `0` = in reset, `1` = normal).
- **Bits `[31:2]`**: Reserved, reads back `0`.

---

## 6. Slave 3: Heartbeat Monitor IP (`0x0002_0300`)

Continuously measures the elapsed time between rising edges on `heartbeat_in`. If the duration exceeds `HB_THRESHOLD`, hardware autonomously asserts `unresponsive` and generates an optional interrupt (`hb_irq`).

### Register Map
| Address | Offset | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0300` | `0x00` | `HB_CTRL` | R/W | `0x0000_0000` | Heartbeat Monitor Control Register |
| `0x0002_0304` | `0x04` | `HB_THRESHOLD` | R/W | `0x0000_0000` | Timeout Threshold Register (clock cycles) |
| `0x0002_0308` | `0x08` | `HB_STATUS` | RO | `0x0000_0000` | Heartbeat Monitor Status Register |
| `0x0002_030C` | `0x0C` | `HB_ELAPSED` | RO | `0x0000_0000` | Live Elapsed Cycle Counter |

---

### Bitfield Details

#### `HB_CTRL` — Offset `0x00` (Read/Write)
```
 31                                                    2       1       0
+-------------------------------------------------------+-------+-------+
|                       RESERVED (0)                    | CLR_F |  EN   |
+-------------------------------------------------------+-------+-------+
```
- **Bit `[0]` (`EN`, R/W)**: Monitoring Enable.
  - `0`: Monitor disabled; state machine forced to `ST_DISABLED`, `hb_counter` and `hb_unresponsive_flag` cleared.
  - `1`: Monitor enabled; transitions to `ST_IDLE` waiting for the first heartbeat pulse.
- **Bit `[1]` (`CLR_F`, WO, Self-Clearing)**: Clear Unresponsive Flag.
  - Write `1`: Deasserts `hb_unresponsive_flag`, resets `hb_counter` to 0, and returns state machine to `ST_IDLE`. Auto-clears after one cycle; reads return `0`.
- **Bits `[31:2]`**: Reserved, reads return `0`.

#### `HB_THRESHOLD` — Offset `0x04` (Read/Write)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                             HB_THRESHOLD                              |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`HB_THRESHOLD`)**: Timeout threshold in clock cycles. If `hb_counter >= HB_THRESHOLD` while in `ST_COUNTING`, the system enters `ST_UNRESPONSIVE` and latches `hb_unresponsive_flag = 1`. Setting to `0` disables timeout checking.

#### `HB_STATUS` — Offset `0x08` (Read-Only)
```
 31                                                    2       1       0
+-------------------------------------------------------+-------+-------+
|                       RESERVED (0)                    | HB_PIN| UNRESP|
+-------------------------------------------------------+-------+-------+
```
- **Bit `[0]` (`UNRESP`, RO)**: Unresponsive State Flag.
  - `0`: Normal operation; heartbeat is arriving within threshold.
  - `1`: Timeout expired. Latched sticky until cleared by writing `HB_CTRL[1] = 1`.
- **Bit `[1]` (`HB_PIN`, RO)**: Live logic state of the external `heartbeat_in` signal.
- **Bits `[31:2]`**: Reserved, reads return `0`.

#### `HB_ELAPSED` — Offset `0x0C` (Read-Only)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                              HB_COUNTER                               |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`HB_COUNTER`)**: Live count of clock cycles elapsed since the most recent rising edge of `heartbeat_in`. In `ST_UNRESPONSIVE`, it continues counting up to `0xFFFFFFFF` to measure total freeze duration.

---

## 7. Slave 4: Power/Reset Sequencer IP (`0x0002_0400`)

Generates an autonomous, active-low reset pulse on `reset_out` without requiring the processor to execute delay loops.

### Register Map
| Address | Offset | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0400` | `0x00` | `RST_CTRL` | WO | `0x0000_0000` | Reset Sequence Trigger Register |
| `0x0002_0404` | `0x04` | `RST_HOLD_CYCLES` | R/W | `0x0000_0064` | Pulse Duration in Clock Cycles (default 100) |
| `0x0002_0408` | `0x08` | `RST_STATUS` | RO | `0x0000_0000` | Reset Sequencer Status Register |

---

### Bitfield Details

#### `RST_CTRL` — Offset `0x00` (Write-Only)
```
 31                                                            1       0
+---------------------------------------------------------------+-------+
|                          RESERVED (0)                         | TRIG  |
+---------------------------------------------------------------+-------+
```
- **Bit `[0]` (`TRIG`, WO, Self-Clearing)**: Reset Sequence Trigger.
  - Write `1`: Initiates the reset sequence. Hardware drives `reset_out = 0`, sets `in_progress = 1`, and loads `rst_countdown` from `RST_HOLD_CYCLES`. Clears previous `complete` flag. Auto-clears after 1 cycle; reads return `0`.
- **Bits `[31:1]`**: Reserved.

#### `RST_HOLD_CYCLES` — Offset `0x04` (Read/Write)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                            RST_HOLD_CYCLES                            |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`RST_HOLD_CYCLES`)**: Number of clock cycles to assert `reset_out` LOW. Reset default is `100` (`32'd100`). At 100 MHz, 100 cycles = 1.0 µs.

#### `RST_STATUS` — Offset `0x08` (Read-Only)
```
 31                                                    2       1       0
+-------------------------------------------------------+-------+-------+
|                       RESERVED (0)                    | COMP  | IN_PRG|
+-------------------------------------------------------+-------+-------+
```
- **Bit `[0]` (`IN_PRG`, RO)**: Reset in progress. `1` while `reset_out` is actively held LOW.
- **Bit `[1]` (`COMP`, RO)**: Reset complete. `1` when the pulse has completed and `reset_out` is returned HIGH. Sticky until the next `RST_CTRL[0]` trigger.
- **Bits `[31:2]`**: Reserved, reads return `0`.

---

## 8. Slave 5: Recovery Policy & Event Log IP (`0x0002_0500`)

Combines a 16-entry circular timestamp buffer with a rolling evaluation window to prevent infinite crash reboot loops.

### Register Map
| Address | Offset | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0500` | `0x00` | `POL_CTRL` | WO | `0x0000_0000` | Policy Control Register (Self-Clearing) |
| `0x0002_0504` | `0x04` | `POL_WINDOW` | R/W | `0x0000_0000` | Rolling Window Size (clock cycles) |
| `0x0002_0508` | `0x08` | `POL_THRESHOLD` | R/W | `0x0000_0003` | Max Recoveries per Window (default 3) |
| `0x0002_050C` | `0x0C` | `POL_STATUS` | RO | `0x0000_0000` | Lockout and Window Status Register |
| `0x0002_0510` | `0x10` | `POL_EVENT_TS` | WO | `0x0000_0000` | Staged Event Timestamp Register |
| `0x0002_0514` | `0x14` | `LOG_READ_IDX` | R/W | `0x0000_0000` | Circular Buffer Read Index Pointer |
| `0x0002_0518` | `0x18` | `LOG_READ_DATA` | RO | `0x0000_0000` | Timestamp Readout at `LOG_READ_IDX` |
| `0x0002_051C` | `0x1C` | `LOG_COUNT` | RO | `0x0000_0000` | Total Lifetime Logged Events Counter |

---

### Bitfield Details

#### `POL_CTRL` — Offset `0x00` (Write-Only)
```
 31                                                    2       1       0
+-------------------------------------------------------+-------+-------+
|                       RESERVED (0)                    |CLR_LCK| REC_EV|
+-------------------------------------------------------+-------+-------+
```
- **Bit `[0]` (`REC_EV`, WO, Self-Clearing)**: Record Event.
  - Write `1`: Pushes `POL_EVENT_TS` into `log_buffer[log_wr_ptr]`, increments `log_wr_ptr` (modulo 16), increments `log_count`, increments `window_recovery_count`, and triggers lockout evaluation. Auto-clears; reads return `0`.
- **Bit `[1]` (`CLR_LCK`, WO, Self-Clearing)**: Clear Lockout.
  - Write `1`: Clears `lockout_flag` to `0`, resets `window_recovery_count` to `0`, and resets `window_counter` to `0`. Auto-clears; reads return `0`.
- **Bits `[31:2]`**: Reserved.

#### `POL_WINDOW` — Offset `0x04` (Read/Write)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                             POL_WINDOW                                |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`POL_WINDOW`)**: Evaluation window period in clock cycles. Internal `window_counter` resets to 0 and clears `window_recovery_count` whenever `window_counter >= POL_WINDOW`.

#### `POL_THRESHOLD` — Offset `0x08` (Read/Write)
```
 31                                            8       7               0
+-----------------------------------------------+-----------------------+
|                  RESERVED (0)                 |     POL_THRESHOLD     |
+-----------------------------------------------+-----------------------+
```
- **Bits `[7:0]` (`POL_THRESHOLD`)**: Maximum allowed recovery events per window before lockout triggers. Default is `3`.
- **Bits `[31:8]`**: Reserved, reads return `0`.

#### `POL_STATUS` — Offset `0x0C` (Read-Only)
```
 31                             16 15           8 7           1       0
+---------------------------------+---------------+-------------+-------+
|           RESERVED (0)          | WIN_REC_COUNT | RESERVED(0) |LOCKOUT|
+---------------------------------+---------------+-------------+-------+
```
- **Bit `[0]` (`LOCKOUT`, RO)**: Crash-Loop Lockout Active.
  - `1`: System is locked out from automatic rebooting because `window_recovery_count >= POL_THRESHOLD`. Sticky until cleared via `POL_CTRL[1]`.
- **Bits `[7:1]`**: Reserved (`0`).
- **Bits `[15:8]` (`WIN_REC_COUNT`, RO)**: Number of recovery events logged within the current active window.
- **Bits `[31:16]`**: Reserved (`0`).

#### `POL_EVENT_TS` — Offset `0x10` (Write-Only)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                            STAGED_TIMESTAMP                           |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`STAGED_TIMESTAMP`)**: 32-bit timestamp value staged by firmware prior to asserting `POL_CTRL[0]`.

#### `LOG_READ_IDX` — Offset `0x14` (Read/Write)
```
 31                                                    4 3             0
+-------------------------------------------------------+---------------+
|                       RESERVED (0)                    | LOG_READ_IDX  |
+-------------------------------------------------------+---------------+
```
- **Bits `[3:0]` (`LOG_READ_IDX`)**: Index pointer (0–15) into the 16-entry circular log buffer.
- **Bits `[31:4]`**: Reserved (`0`).

#### `LOG_READ_DATA` — Offset `0x18` (Read-Only)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                            ENTRY_TIMESTAMP                            |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`ENTRY_TIMESTAMP`)**: The 32-bit timestamp stored in the circular buffer entry indexed by `LOG_READ_IDX`.

#### `LOG_COUNT` — Offset `0x1C` (Read-Only)
```
 31                                                                    0
+-----------------------------------------------------------------------+
|                               LOG_COUNT                               |
+-----------------------------------------------------------------------+
```
- **Bits `[31:0]` (`LOG_COUNT`)**: Cumulative total of all recovery events recorded since reset. Saturates at `0xFFFFFFFF`.

---

## 9. Slave 6: VGA Status Controller IP (`0x0002_0600`)

Generates standard 640x480 @ 60Hz VGA timing and renders a live 3-row × 40-character text console directly from a memory-mapped ASCII buffer.

### Register Map
| Address Range | Offset Range | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x0002_0600` | `0x00` | `VGA_CTRL` | R/W | `0x0000_0000` | Video Display Output Control |
| `0x0002_0604` | `0x04` | `VGA_STATUS` | RO | `0x0000_0000` | Frame Refresh Status Register |
| `0x0002_0608` – `0x0002_067C` | `0x08` – `0x7C` | `VGA_BUFFER[0:29]` | WO | `0x2020_2020` | 30 Words = 120 ASCII Characters |

---

### Bitfield Details

#### `VGA_CTRL` — Offset `0x00` (Read/Write)
```
 31                                                            1       0
+---------------------------------------------------------------+-------+
|                          RESERVED (0)                         |  EN   |
+---------------------------------------------------------------+-------+
```
- **Bit `[0]` (`EN`, R/W)**: Display Output Enable.
  - `0`: Screen blanked (black output).
  - `1`: Active video rendering enabled.
- **Bits `[31:1]`**: Reserved (`0`).

#### `VGA_STATUS` — Offset `0x04` (Read-Only)
```
 31                                                            1       0
+---------------------------------------------------------------+-------+
|                          RESERVED (0)                         |REFRESH|
+---------------------------------------------------------------+-------+
```
- **Bit `[0]` (`REFRESH`, RO)**: Refresh Pending Flag. Set to `1` whenever firmware writes into `VGA_BUFFER`. Cleared automatically by hardware at the start of the next vertical frame (`h_count == 0 && v_count == 0`).
- **Bits `[31:1]`**: Reserved (`0`).

#### `VGA_BUFFER[0:29]` — Offsets `0x08` to `0x7C` (Write-Only)
- **Organization**: 30 consecutive 32-bit registers representing 120 character cells.
- **Word Index Calculation**:
  $$\text{Word Index} = \frac{\text{Offset} - \text{0x08}}{4}$$
- **Byte Packing**: Big-endian (MSB-first character ordering):
  ```
   31           24 23           16 15            8 7             0
  +---------------+---------------+---------------+---------------+
  |   Char 4*i    |  Char 4*i+1   |  Char 4*i+2   |  Char 4*i+3   |
  +---------------+---------------+---------------+---------------+
  ```
- **Screen Layout**:
  - Row 0 (Chars 0–39): Offsets `0x08` to `0x2C` (10 words) — System Title & State (`ONLINE`, `UNRESPONSIVE`, `LOCKED OUT`).
  - Row 1 (Chars 40–79): Offsets `0x30` to `0x54` (10 words) — Heartbeat elapsed time & threshold.
  - Row 2 (Chars 80–119): Offsets `0x58` to `0x7C` (10 words) — Recovery count vs lockout limit.

---

## 10. C Firmware Register Header Reference (`bmc_regs.h`)

Below is the production-ready C definition header matching this hardware register map:

```c
#ifndef BMC_REGS_H
#define BMC_REGS_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

/* Base Addresses */
#define BASE_UART        0x00020000U
#define BASE_TIMER       0x00020100U
#define BASE_GPIO        0x00020200U
#define BASE_HB_MON      0x00020300U
#define BASE_RESET_SEQ   0x00020400U
#define BASE_REC_POL     0x00020500U
#define BASE_VGA         0x00020600U

/* Timer Registers */
#define TMR_CTR          REG32(BASE_TIMER + 0x00U)

/* GPIO Registers */
#define GPIO_STAT        REG32(BASE_GPIO + 0x00U)
#define GPIO_HB_PIN_BIT  (1U << 0)
#define GPIO_RST_PIN_BIT (1U << 1)

/* Heartbeat Monitor Registers */
#define HB_CTRL          REG32(BASE_HB_MON + 0x00U)
#define HB_THRESHOLD     REG32(BASE_HB_MON + 0x04U)
#define HB_STATUS        REG32(BASE_HB_MON + 0x08U)
#define HB_ELAPSED       REG32(BASE_HB_MON + 0x0CU)

#define HB_CTRL_ENABLE   (1U << 0)
#define HB_CTRL_CLEAR    (1U << 1)
#define HB_STAT_UNRESP   (1U << 0)
#define HB_STAT_PIN      (1U << 1)

/* Reset Sequencer Registers */
#define RST_CTRL         REG32(BASE_RESET_SEQ + 0x00U)
#define RST_HOLD_CYCLES  REG32(BASE_RESET_SEQ + 0x04U)
#define RST_STATUS       REG32(BASE_RESET_SEQ + 0x08U)

#define RST_CTRL_TRIGGER (1U << 0)
#define RST_STAT_IN_PRG  (1U << 0)
#define RST_STAT_COMP    (1U << 1)

/* Recovery Policy & Event Log Registers */
#define POL_CTRL         REG32(BASE_REC_POL + 0x00U)
#define POL_WINDOW       REG32(BASE_REC_POL + 0x04U)
#define POL_THRESHOLD    REG32(BASE_REC_POL + 0x08U)
#define POL_STATUS       REG32(BASE_REC_POL + 0x0CU)
#define POL_EVENT_TS     REG32(BASE_REC_POL + 0x10U)
#define LOG_READ_IDX     REG32(BASE_REC_POL + 0x14U)
#define LOG_READ_DATA    REG32(BASE_REC_POL + 0x18U)
#define LOG_COUNT        REG32(BASE_REC_POL + 0x1CU)

#define POL_CTRL_RECORD  (1U << 0)
#define POL_CTRL_CLEAR   (1U << 1)
#define POL_STAT_LOCKOUT (1U << 0)
#define POL_STAT_WIN_CNT(status) (((status) >> 8) & 0xFFU)

/* VGA Controller Registers */
#define VGA_CTRL         REG32(BASE_VGA + 0x00U)
#define VGA_STATUS       REG32(BASE_VGA + 0x04U)
#define VGA_BUF_WORD(i)  REG32(BASE_VGA + 0x08U + ((i) * 4U))

#define VGA_CTRL_ENABLE  (1U << 0)
#define VGA_STAT_REFRESH (1U << 0)

#endif /* BMC_REGS_H */
```
