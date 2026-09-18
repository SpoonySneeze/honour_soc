# BMC SoC Custom IP Register Map

This document outlines the register mappings for the custom IPs developed for the RISC-V BMC SoC. All registers are 32-bit (word-aligned) and map to a standard Wishbone B4 slave interface.

## System Memory Map (Peripherals)

| Peripheral | Base Address | Size |
|---|---|---|
| UART (Stub) | `0x0002_0000` | 256 bytes |
| Timer (Stub) | `0x0002_0100` | 256 bytes |
| GPIO (Stub) | `0x0002_0200` | 256 bytes |
| **Heartbeat Monitor** | `0x0002_0300` | 256 bytes |
| **Power/Reset Sequencer** | `0x0002_0400` | 256 bytes |
| **Recovery Policy** | `0x0002_0500` | 256 bytes |
| **VGA Controller** | `0x0002_0600` | 256 bytes |

---

## 1. Heartbeat Monitor
**Base Address:** `0x0002_0300`

Monitors a periodic hardware pulse from the main system and triggers a timeout if the threshold is exceeded.

| Offset | Register Name | Access | Description |
|---|---|---|---|
| `0x00` | `HB_CTRL` | R/W | **[0]** `enable`: 1 = monitoring active<br>**[1]** `clear_flag`: 1 = clears unresponsive state (self-clearing) |
| `0x04` | `HB_THRESHOLD` | R/W | Maximum allowed clock cycles between heartbeat edges before triggering timeout. |
| `0x08` | `HB_STATUS` | R/O | **[0]** `unresponsive`: 1 = timeout occurred (sticky)<br>**[1]** `heartbeat_in`: Live state of the external heartbeat pin |
| `0x0C` | `HB_ELAPSED` | R/O | Live counter of clock cycles elapsed since the last heartbeat edge. |

---

## 2. Power/Reset Sequencer
**Base Address:** `0x0002_0400`

Generates a precisely timed active-low reset pulse to the external system. Hardware handles the timing so the firmware doesn't have to block.

| Offset | Register Name | Access | Description |
|---|---|---|---|
| `0x00` | `RST_CTRL` | W/O | **[0]** `trigger`: 1 = initiates the reset sequence (self-clearing) |
| `0x04` | `RST_HOLD_CYCLES` | R/W | Duration (in clock cycles) to hold the `reset_out` line low. |
| `0x08` | `RST_STATUS` | R/O | **[0]** `in_progress`: 1 = sequence currently active<br>**[1]** `complete`: 1 = sequence finished (cleared on next trigger) |

---

## 3. Recovery Policy & Event Log
**Base Address:** `0x0002_0500`

Tracks the history of reset recoveries and implements a fixed-window lockout policy to prevent infinite crash loops.

| Offset | Register Name | Access | Description |
|---|---|---|---|
| `0x00` | `POL_CTRL` | W/O | **[0]** `record_event`: 1 = pushes staged TS to log (self-clearing)<br>**[1]** `clear_lockout`: 1 = resets lockout flag and window (self-clearing) |
| `0x04` | `POL_WINDOW` | R/W | Size of the fixed evaluation window in clock cycles. |
| `0x08` | `POL_THRESHOLD` | R/W | **[7:0]** Maximum allowed recoveries per window before triggering lockout. |
| `0x0C` | `POL_STATUS` | R/O | **[0]** `lockout_flag`: 1 = system locked out (sticky)<br>**[15:8]** `window_recovery_count`: Recoveries in current window |
| `0x10` | `POL_EVENT_TS` | W/O | Staged 32-bit timestamp. Must be written *before* triggering `record_event`. |
| `0x14` | `LOG_READ_IDX` | R/W | **[3:0]** Read pointer (0–15) into the circular event log buffer. |
| `0x18` | `LOG_READ_DATA` | R/O | The 32-bit timestamp residing at `LOG_READ_IDX`. |
| `0x1C` | `LOG_COUNT` | R/O | Total lifetime events logged (saturates at `0xFFFFFFFF`). |

---

## 4. VGA Controller (Optional)
**Base Address:** `0x0002_0600`

Provides a hardware-accelerated text dashboard (640x480 @ 60Hz) using a firmware-written ASCII buffer.

| Offset | Register Name | Access | Description |
|---|---|---|---|
| `0x00` | `VGA_CTRL` | R/W | **[0]** `enable`: 1 = active VGA output, 0 = black screen |
| `0x04` | `VGA_STATUS` | R/O | **[0]** `refresh_flag`: 1 = frame currently rendering, 0 = frame complete |
| `0x08` – `0x7F` | `VGA_BUFFER` | W/O | Dashboard text buffer. 30 registers × 4 bytes = 120 ASCII characters. Writing here automatically updates the screen. |
