# BMC SoC — C Application (Firmware) Documentation

## RISC-V-Based Server BMC — Detailed Firmware Reference

---

# 1. Purpose of This Document

This document is the dedicated, deep-dive reference for the firmware running on the VeeR EL2 core in the BMC SoC project. It expands on Section 10 of the main Architecture/Specification Manual with full source listings for every module (including UART, Timer, and VGA drivers not fully listed there), complete function-level documentation (signature, parameters, return value, side effects, register interactions), sequence walkthroughs for every operational scenario, a configuration constants reference, and a firmware testing/validation approach. This is the document to hand to anyone who needs to read, modify, extend, or defend the C code specifically.

---

# 2. Firmware Architecture Overview

## 2.1 Layering Model

The firmware is organized into three strict layers, each only allowed to call downward:

```
┌─────────────────────────────────────────┐
│  Application Layer                        │
│  main.c, console.c                        │
│  — orchestration, policy decisions,       │
│    command parsing                        │
└───────────────────┬───────────────────────┘
                    │ calls
┌───────────────────▼───────────────────────┐
│  Driver Layer                              │
│  drivers/heartbeat.c, reset_seq.c,        │
│  policy.c, uart.c, timer.c, vga.c         │
│  — register-level access, one function    │
│    per hardware operation                  │
└───────────────────┬───────────────────────┘
                    │ reads/writes
┌───────────────────▼───────────────────────┐
│  Hardware (memory-mapped registers)        │
│  Custom IPs + mandatory peripherals        │
│  over the Wishbone bus                     │
└─────────────────────────────────────────────┘
```

**Rule enforced throughout:** application-layer code (`main.c`, `console.c`) never dereferences a hardware register pointer directly. Every hardware interaction goes through a named driver function. This keeps register addresses and bit-field layouts in exactly one place per peripheral, makes the code readable without memorizing offsets, and means a register map change only requires editing one driver file, not hunting through the whole codebase.

## 2.2 Execution Model

- **No RTOS, no task scheduler, no interrupts in the baseline design** (see Section 8 of the main spec for the full interrupt-vs-polling rationale). Firmware is a single `main()` that initializes hardware once, then runs one infinite superloop for the lifetime of the system.
- Every iteration of the superloop performs, in fixed order: (1) automatic fault-check and recovery, (2) console command service, (3) VGA dashboard refresh. This fixed ordering is deliberate — fault recovery always takes priority over console/display work within a single iteration.
- All hardware waits (e.g., waiting for a reset sequence to complete) are simple busy-wait polling loops, not blocking system calls — there is no OS to yield to.

## 2.3 Design Rationale Recap

The firmware is deliberately simple. Nearly all correctness and timing guarantees are enforced in hardware (the custom IPs); the C application exists only to sequence operations, hold configuration, and present information to a human. If the firmware crashed or froze entirely, the Heartbeat Monitor and Reset Sequencer would continue operating exactly as designed — the firmware's own health is not part of the system's reliability guarantee, by design (see Core Design Principle, Section 1.3 of the main spec).

---

# 3. Directory / File Structure

```
firmware/
├── main.c                  - entry point, initialization, superloop
├── console.c
├── console.h                - command parser
├── drivers/
│   ├── heartbeat.c
│   ├── heartbeat.h          - Heartbeat Monitor register access
│   ├── reset_seq.c
│   ├── reset_seq.h          - Power/Reset Sequencer register access
│   ├── policy.c
│   ├── policy.h             - Recovery Policy/Event Log register access
│   ├── uart.c
│   ├── uart.h               - UART peripheral driver
│   ├── timer.c
│   ├── timer.h              - Timer peripheral driver
│   ├── vga.c
│   └── vga.h                - VGA dashboard driver
├── config.h                  - all tunable constants in one place
└── linker.ld                 - memory layout for VeeR EL2 toolchain
```

---

# 4. Build & Toolchain

## 4.1 Toolchain

- **Compiler:** `riscv32-unknown-elf-gcc`, targeting `-march=rv32imc -mabi=ilp32` to match VeeR EL2's supported instruction set.
- **Recommended flags:** `-O1` (avoid aggressive optimization reordering volatile register accesses; `-O0` is also acceptable and safer for a first working version, at the cost of code size/speed which is not a concern here), `-ffreestanding` (no hosted C library assumptions), `-nostdlib` (no OS to link against).
- **Output:** ELF binary, converted to a `.hex`/`.mem` file (via `riscv32-unknown-elf-objcopy` and a hex-formatting step, or directly via `elf2hex`/similar) for instruction memory preload in RTL simulation (`$readmemh`).

## 4.2 Example Build Commands

```bash
riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -O1 -ffreestanding -nostdlib \
    -T linker.ld -o firmware.elf \
    main.c console.c \
    drivers/heartbeat.c drivers/reset_seq.c drivers/policy.c \
    drivers/uart.c drivers/timer.c drivers/vga.c

riscv32-unknown-elf-objcopy -O binary firmware.elf firmware.bin
# convert firmware.bin to hex format for $readmemh, per your simulation toolchain's exact expected format
```

## 4.3 Linker Script Placement (`linker.ld`, sketch)

```
MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K   /* Instruction Memory */
    DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 64K   /* Data Memory        */
}

SECTIONS {
    .text : { *(.text*) }           > IMEM
    .rodata : { *(.rodata*) }       > IMEM
    .data : { *(.data*) }           > DMEM
    .bss : { *(.bss*) }             > DMEM
    . = ALIGN(16);
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
```

**Note:** Exact origins must be finalized against the actual provided VeeR reference SoC memory map (flagged as an Open Item in the main spec) — this is a placeholder sketch matching the illustrative addresses used throughout this document set.

---

# 5. Conventions Used Throughout the Firmware

| Convention | Rule |
|---|---|
| Register access | Always through `volatile uint32_t*` pointers, never cached in a non-volatile local across a hardware-dependent wait |
| Naming | Driver functions: `<ip>_<action>()`, e.g. `heartbeat_init()`, `policy_record_event()` |
| Return types | `bool` for status queries, `uint32_t` for raw register-width values, `void` for fire-and-forget actions |
| Error handling | Driver layer returns raw hardware state; interpretation/decision-making happens only in `main.c`/`console.c` (see Section 9) |
| Constants | All tunable values (thresholds, base addresses, buffer sizes) centralized in `config.h` — no magic numbers in driver `.c` files |

---

# 6. `config.h` — Centralized Configuration

```c
#ifndef CONFIG_H
#define CONFIG_H

// ---- Peripheral base addresses (placeholders - confirm against provided SoC) ----
#define UART_BASE           0x10000000u
#define GPIO_BASE            0x10001000u
#define TIMER_BASE           0x10002000u
#define HB_BASE               0x10010000u
#define RST_BASE              0x10010100u
#define POL_BASE              0x10010200u
#define VGA_BASE              0x10010300u

// ---- Heartbeat Monitor defaults ----
#define HB_THRESHOLD_DEFAULT      1000000u   // cycles

// ---- Power/Reset Sequencer defaults ----
#define RST_HOLD_DEFAULT          10000u     // cycles

// ---- Recovery Policy defaults ----
#define POL_WINDOW_DEFAULT        1000000u   // cycles
#define POL_THRESHOLD_DEFAULT     3u          // max recoveries per window

// ---- UART ----
#define UART_BAUD_115200          115200u
#define UART_CMD_BUF_LEN          64u

// ---- Recovery wait safety cap ----
// Prevents an unbounded busy-wait if hardware never completes (defensive; see Section 9.5)
#define RESET_WAIT_MAX_POLLS      100000u

#endif
```

---

# 7. Driver Module Documentation

Each subsection below documents one driver module completely: purpose, full header (public interface), full implementation, and a per-function reference table.

## 7.1 `drivers/heartbeat.h` / `.c` — Heartbeat Monitor Driver

**Purpose:** Provide a clean function-call interface to the Heartbeat Monitor custom IP's registers (see main spec Section 9.1 for the register map).

### Header

```c
#ifndef HEARTBEAT_H
#define HEARTBEAT_H
#include <stdint.h>
#include <stdbool.h>

void     heartbeat_init(uint32_t threshold_cycles);
bool     heartbeat_is_unresponsive(void);
uint32_t heartbeat_elapsed(void);
void     heartbeat_clear_flag(void);
bool     heartbeat_current_level(void);   // live heartbeat_in level, informational

#endif
```

### Implementation

```c
#include "heartbeat.h"
#include "../config.h"

#define HB_CTRL        (*(volatile uint32_t*)(HB_BASE + 0x00))
#define HB_THRESHOLD    (*(volatile uint32_t*)(HB_BASE + 0x04))
#define HB_STATUS       (*(volatile uint32_t*)(HB_BASE + 0x08))
#define HB_ELAPSED      (*(volatile uint32_t*)(HB_BASE + 0x0C))

void heartbeat_init(uint32_t threshold_cycles) {
    HB_THRESHOLD = threshold_cycles;
    HB_CTRL = 0x1;               // enable = 1, clear = 0
}

bool heartbeat_is_unresponsive(void) {
    return (HB_STATUS & 0x1) != 0;
}

uint32_t heartbeat_elapsed(void) {
    return HB_ELAPSED;
}

void heartbeat_clear_flag(void) {
    HB_CTRL = 0x3;               // enable = 1, clear = 1 (self-clearing on hardware side)
}

bool heartbeat_current_level(void) {
    return (HB_STATUS & 0x2) != 0;
}
```

### Function Reference

| Function | Parameters | Returns | Side Effects | Notes |
|---|---|---|---|---|
| `heartbeat_init` | `threshold_cycles`: max cycles before unresponsive | — | Writes `HB_THRESHOLD`, then enables monitor via `HB_CTRL` | Call once at boot; hardware clamps threshold to a safe minimum if too low (Error 7.1.1 in main spec) |
| `heartbeat_is_unresponsive` | — | `true` if flag latched | Read-only | Poll every main-loop iteration |
| `heartbeat_elapsed` | — | Live cycle count since last pulse | Read-only | Used for both decision logic and display |
| `heartbeat_clear_flag` | — | — | Writes `HB_CTRL` clear bit | Must be called after every handled unresponsive event — see Control Path Section 5.1 step 10 of main spec |
| `heartbeat_current_level` | — | Live level of `heartbeat_in` | Read-only | Informational/diagnostic only, not used in core decision logic |

---

## 7.2 `drivers/reset_seq.h` / `.c` — Power/Reset Sequencer Driver

**Purpose:** Provide a clean function-call interface to the Power/Reset Sequencer custom IP.

### Header

```c
#ifndef RESET_SEQ_H
#define RESET_SEQ_H
#include <stdint.h>
#include <stdbool.h>

void reset_seq_init(uint32_t hold_cycles);
void reset_seq_trigger(void);
bool reset_seq_is_in_progress(void);
bool reset_seq_is_complete(void);

#endif
```

### Implementation

```c
#include "reset_seq.h"
#include "../config.h"

#define RST_CTRL       (*(volatile uint32_t*)(RST_BASE + 0x00))
#define RST_HOLD        (*(volatile uint32_t*)(RST_BASE + 0x04))
#define RST_STATUS      (*(volatile uint32_t*)(RST_BASE + 0x08))

void reset_seq_init(uint32_t hold_cycles) {
    RST_HOLD = hold_cycles;
}

void reset_seq_trigger(void) {
    RST_CTRL = 0x1;
}

bool reset_seq_is_in_progress(void) {
    return (RST_STATUS & 0x1) != 0;
}

bool reset_seq_is_complete(void) {
    return (RST_STATUS & 0x2) != 0;
}
```

### Function Reference

| Function | Parameters | Returns | Side Effects | Notes |
|---|---|---|---|---|
| `reset_seq_init` | `hold_cycles`: reset pulse hold duration | — | Writes `RST_HOLD` | Call once at boot; hardware clamps to a safe minimum if too low |
| `reset_seq_trigger` | — | — | Writes `RST_CTRL` trigger bit | Ignored by hardware if a sequence is already in progress (main spec Error 7.2.1) — safe to call without pre-checking |
| `reset_seq_is_in_progress` | — | `true` while pulse is asserting | Read-only | Useful for non-blocking callers; the reference `main.c` uses a blocking wait instead (Section 9.2) |
| `reset_seq_is_complete` | — | `true` once sequence finished | Read-only | Sticky until next trigger |

---

## 7.3 `drivers/policy.h` / `.c` — Recovery Policy / Event Log Driver

**Purpose:** Provide a clean function-call interface to the Recovery Policy / Event Log custom IP, including event recording and log readback.

### Header

```c
#ifndef POLICY_H
#define POLICY_H
#include <stdint.h>
#include <stdbool.h>

void     policy_init(uint32_t window_cycles, uint8_t threshold);
bool     policy_is_locked_out(void);
uint8_t  policy_window_count(void);
void     policy_record_event(uint32_t timestamp);
void     policy_clear_lockout(void);
uint32_t policy_log_count(void);
uint32_t policy_log_read(uint8_t idx);

#endif
```

### Implementation

```c
#include "policy.h"
#include "../config.h"

#define POL_CTRL        (*(volatile uint32_t*)(POL_BASE + 0x00))
#define POL_EVENT_TS     (*(volatile uint32_t*)(POL_BASE + 0x04))
#define POL_WINDOW       (*(volatile uint32_t*)(POL_BASE + 0x08))
#define POL_THRESHOLD    (*(volatile uint32_t*)(POL_BASE + 0x0C))
#define POL_STATUS       (*(volatile uint32_t*)(POL_BASE + 0x10))
#define LOG_READ_IDX     (*(volatile uint32_t*)(POL_BASE + 0x14))
#define LOG_READ_DATA    (*(volatile uint32_t*)(POL_BASE + 0x18))
#define LOG_COUNT_REG    (*(volatile uint32_t*)(POL_BASE + 0x1C))

void policy_init(uint32_t window_cycles, uint8_t threshold) {
    POL_WINDOW = window_cycles;
    POL_THRESHOLD = threshold;
}

bool policy_is_locked_out(void) {
    return (POL_STATUS & 0x1) != 0;
}

uint8_t policy_window_count(void) {
    return (uint8_t)((POL_STATUS >> 8) & 0xFF);
}

void policy_record_event(uint32_t timestamp) {
    POL_EVENT_TS = timestamp;
    POL_CTRL = 0x1;             // record_event
}

void policy_clear_lockout(void) {
    POL_CTRL = 0x2;             // clear_lockout
}

uint32_t policy_log_count(void) {
    return LOG_COUNT_REG;
}

uint32_t policy_log_read(uint8_t idx) {
    LOG_READ_IDX = idx;
    return LOG_READ_DATA;
}
```

### Function Reference

| Function | Parameters | Returns | Side Effects | Notes |
|---|---|---|---|---|
| `policy_init` | `window_cycles`, `threshold` | — | Writes `POL_WINDOW`, `POL_THRESHOLD` | Call once at boot |
| `policy_is_locked_out` | — | `true` if lockout latched | Read-only | Checked before every automatic recovery attempt |
| `policy_window_count` | — | Recoveries in current window | Read-only | Display/diagnostic use |
| `policy_record_event` | `timestamp`: current time (from `timer_now()`) | — | Writes `POL_EVENT_TS` then `POL_CTRL` | Must always be called immediately after a reset is triggered, automatic or manual |
| `policy_clear_lockout` | — | — | Writes `POL_CTRL` clear bit | Only ever called from the `clear lockout` console command — a deliberate human action |
| `policy_log_count` | — | Total events logged (saturates at 16) | Read-only | Used by `history` command |
| `policy_log_read` | `idx`: 0–15 | Timestamp at that log index | Writes `LOG_READ_IDX`, then reads `LOG_READ_DATA` | Two-step register access — see Section 9.4 for the read protocol detail |

---

## 7.4 `drivers/uart.h` / `.c` — UART Driver

**Purpose:** Provide byte- and line-level UART I/O on top of the mandatory UART peripheral, used for the management console.

### Header

```c
#ifndef UART_H
#define UART_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

void uart_init(uint32_t baud);
bool uart_has_byte(void);
uint8_t uart_read_byte(void);
void uart_write_byte(uint8_t b);
void uart_print(const char *s);
void uart_printf(const char *fmt, ...);   // minimal printf subset: %s %u %lu %d
bool uart_has_line(void);
void uart_read_line(char *buf, size_t buf_len);

#endif
```

### Implementation (key portions)

```c
#include "uart.h"
#include "../config.h"
#include <stdarg.h>

#define UART_TX_DATA    (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_RX_DATA    (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_STATUS     (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_TX_READY_BIT  0x1u   // UART_STATUS bit0: TX FIFO not full
#define UART_RX_VALID_BIT  0x2u   // UART_STATUS bit1: RX FIFO not empty
#define UART_BAUDDIV    (*(volatile uint32_t*)(UART_BASE + 0x0C))

void uart_init(uint32_t baud) {
    // exact divisor calculation depends on the provided UART core's clock/baud formula;
    // placeholder shows the pattern, not the final constant
    UART_BAUDDIV = (SYSTEM_CLOCK_HZ / baud);
}

bool uart_has_byte(void) {
    return (UART_STATUS & UART_RX_VALID_BIT) != 0;
}

uint8_t uart_read_byte(void) {
    while (!uart_has_byte()) { /* wait */ }
    return (uint8_t)(UART_RX_DATA & 0xFF);
}

void uart_write_byte(uint8_t b) {
    while (!(UART_STATUS & UART_TX_READY_BIT)) { /* wait */ }
    UART_TX_DATA = b;
}

void uart_print(const char *s) {
    while (*s) {
        uart_write_byte((uint8_t)*s);
        s++;
    }
}

// Minimal printf-style formatter - supports %s, %u, %lu, %d only,
// sufficient for this project's status/log output needs.
void uart_printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char numbuf[12];
    while (*fmt) {
        if (*fmt == '%' && *(fmt + 1)) {
            fmt++;
            if (*fmt == 's') {
                uart_print(va_arg(args, const char*));
            } else if (*fmt == 'u' || *fmt == 'd') {
                uint32_t v = va_arg(args, uint32_t);
                itoa_simple(v, numbuf);
                uart_print(numbuf);
            } else if (*fmt == 'l') {
                fmt++; // expect 'lu'
                uint32_t v = va_arg(args, uint32_t);
                itoa_simple(v, numbuf);
                uart_print(numbuf);
            }
        } else {
            uart_write_byte((uint8_t)*fmt);
        }
        fmt++;
    }
    va_end(args);
}

// Line buffering: accumulates bytes until '\n', with overflow protection (Error 7.4.2, main spec)
static char line_buf[UART_CMD_BUF_LEN];
static size_t line_pos = 0;
static bool line_ready = false;

bool uart_has_line(void) {
    while (uart_has_byte() && !line_ready) {
        uint8_t b = uart_read_byte();
        if (b == '\n' || b == '\r') {
            line_buf[line_pos] = '\0';
            line_ready = (line_pos > 0);   // ignore empty lines
            line_pos = 0;
        } else if (line_pos < UART_CMD_BUF_LEN - 1) {
            line_buf[line_pos++] = (char)b;
        } else {
            // overflow: discard partial line (Error 7.4.2)
            uart_print("Command too long, discarded\n");
            line_pos = 0;
        }
    }
    return line_ready;
}

void uart_read_line(char *buf, size_t buf_len) {
    size_t i = 0;
    while (line_buf[i] && i < buf_len - 1) {
        buf[i] = line_buf[i];
        i++;
    }
    buf[i] = '\0';
    line_ready = false;
}
```

### Function Reference

| Function | Parameters | Returns | Side Effects | Notes |
|---|---|---|---|---|
| `uart_init` | `baud`: desired baud rate | — | Configures baud divisor register | Call once at boot |
| `uart_has_byte` | — | `true` if a byte is available | Read-only | Non-blocking check |
| `uart_read_byte` | — | Next received byte | Blocks until byte available | Rarely called directly; used internally by `uart_has_line` |
| `uart_write_byte` | `b`: byte to send | — | Blocks until TX ready, then writes | Low-level primitive |
| `uart_print` | `s`: null-terminated string | — | Writes each byte | Simple string output |
| `uart_printf` | `fmt`, variadic args | — | Formats and writes | Minimal subset (`%s`,`%u`,`%d`,`%lu`) — sufficient for this project, not a full libc printf |
| `uart_has_line` | — | `true` if a complete line is buffered | Consumes available bytes, handles overflow (Error 7.4.2) | Call every main-loop iteration; non-blocking |
| `uart_read_line` | `buf`, `buf_len` | — | Copies buffered line out, resets internal state | Call only after `uart_has_line()` returns `true` |

---

## 7.5 `drivers/timer.h` / `.c` — Timer Driver

**Purpose:** Thin wrapper over the mandatory Timer peripheral, used as the timestamp source for event logging.

### Header

```c
#ifndef TIMER_H
#define TIMER_H
#include <stdint.h>

void     timer_init(void);
uint32_t timer_now(void);

#endif
```

### Implementation

```c
#include "timer.h"
#include "../config.h"

#define TIMER_COUNT   (*(volatile uint32_t*)(TIMER_BASE + 0x00))
#define TIMER_CTRL    (*(volatile uint32_t*)(TIMER_BASE + 0x04))

void timer_init(void) {
    TIMER_CTRL = 0x1;   // enable free-running count, per provided Timer core's own spec
}

uint32_t timer_now(void) {
    return TIMER_COUNT;
}
```

### Function Reference

| Function | Parameters | Returns | Side Effects | Notes |
|---|---|---|---|---|
| `timer_init` | — | — | Enables free-running counter | Call once at boot |
| `timer_now` | — | Current cycle count | Read-only | The sole source of timestamps for `policy_record_event()` |

---

## 7.6 `drivers/vga.h` / `.c` — VGA Dashboard Driver (Optional 4th IP)

**Purpose:** Format current system status into the VGA Controller's dashboard buffer.

### Header

```c
#ifndef VGA_H
#define VGA_H
#include <stdint.h>
#include <stdbool.h>

void vga_init(void);
void vga_update_dashboard(bool unresponsive, uint32_t elapsed,
                           bool locked_out, uint8_t window_count,
                           uint32_t log_count);

#endif
```

### Implementation

```c
#include "vga.h"
#include "../config.h"
#include "policy.h"
#include <string.h>

#define VGA_CTRL           (*(volatile uint32_t*)(VGA_BASE + 0x00))
#define VGA_BUFFER_BASE     (VGA_BASE + 0x08)

void vga_init(void) {
    VGA_CTRL = 0x1;   // enable dashboard rendering
}

// Writes a null-terminated string into the character-cell dashboard buffer
// starting at (row, col). Exact buffer layout depends on the chosen base VGA
// core (see main spec Section 9.4, Open Items) - this shows the general pattern.
static void vga_write_text(uint8_t row, uint8_t col, const char *s) {
    volatile uint8_t *cell = (volatile uint8_t*)(VGA_BUFFER_BASE + row * 80 + col);
    while (*s) {
        *cell++ = (uint8_t)*s++;
    }
}

void vga_update_dashboard(bool unresponsive, uint32_t elapsed,
                           bool locked_out, uint8_t window_count,
                           uint32_t log_count) {
    char linebuf[32];

    const char *status_str = locked_out ? "LOCKED OUT"
                            : unresponsive ? "UNRESPONSIVE"
                            : "ONLINE";
    vga_write_text(0, 0, "Status: ");
    vga_write_text(0, 8, status_str);

    itoa_simple(elapsed, linebuf);
    vga_write_text(1, 0, "Elapsed: ");
    vga_write_text(1, 9, linebuf);

    itoa_simple(window_count, linebuf);
    vga_write_text(2, 0, "Recoveries this window: ");
    vga_write_text(2, 25, linebuf);

    itoa_simple(log_count, linebuf);
    vga_write_text(3, 0, "Total events logged: ");
    vga_write_text(3, 22, linebuf);

    // Recent log entries (last up to 3, most recent first)
    uint32_t shown = (log_count < 3) ? log_count : 3;
    for (uint32_t i = 0; i < shown; i++) {
        uint32_t idx = (log_count - 1 - i) % 16;
        uint32_t ts = policy_log_read((uint8_t)idx);
        itoa_simple(ts, linebuf);
        vga_write_text((uint8_t)(5 + i), 0, "Event t=");
        vga_write_text((uint8_t)(5 + i), 8, linebuf);
    }
}
```

### Function Reference

| Function | Parameters | Returns | Side Effects | Notes |
|---|---|---|---|---|
| `vga_init` | — | — | Enables dashboard rendering | Call once at boot |
| `vga_update_dashboard` | current status/count values | — | Writes formatted text into VGA buffer | Called once per main-loop iteration (Control Path 5.3, main spec) |
| `vga_write_text` (internal) | `row`, `col`, `s` | — | Writes characters into buffer | Internal helper, not exposed in header |

---

## 7.7 Shared Utility — `itoa_simple`

Used by both `uart.c` and `vga.c`; a minimal unsigned-integer-to-string converter, since freestanding firmware (`-nostdlib`) has no libc `itoa`/`sprintf` available.

```c
// Converts an unsigned 32-bit value to a null-terminated decimal string.
// Buffer must be at least 11 bytes (10 digits + null).
void itoa_simple(uint32_t val, char *buf) {
    char tmp[10];
    int i = 0;
    if (val == 0) {
        buf[0] = '0';
        buf[1] = '\0';
        return;
    }
    while (val > 0) {
        tmp[i++] = (char)('0' + (val % 10));
        val /= 10;
    }
    int j = 0;
    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';
}
```

---

# 8. Application Layer

## 8.1 `console.h` / `.c` — Command Parser

### Header

```c
#ifndef CONSOLE_H
#define CONSOLE_H

void console_handle_command(const char *cmd);

#endif
```

### Implementation

```c
#include "console.h"
#include "drivers/heartbeat.h"
#include "drivers/reset_seq.h"
#include "drivers/policy.h"
#include "drivers/uart.h"
#include "drivers/timer.h"
#include "../config.h"
#include <string.h>

static void do_force_reset(void) {
    reset_seq_trigger();
    uint32_t polls = 0;
    while (!reset_seq_is_complete() && polls < RESET_WAIT_MAX_POLLS) {
        polls++;
    }
    if (polls >= RESET_WAIT_MAX_POLLS) {
        uart_print("WARNING: reset sequence did not complete within expected time\n");
        return;
    }
    policy_record_event(timer_now());
    uart_print("Manual reset triggered and logged.\n");
}

void console_handle_command(const char *cmd) {
    if (strcmp(cmd, "status") == 0) {
        uart_printf("System: %s\n", heartbeat_is_unresponsive() ? "UNRESPONSIVE" : "ONLINE");
        uart_printf("Lockout: %s\n", policy_is_locked_out() ? "YES" : "NO");
        uart_printf("Time since heartbeat: %lu cycles\n", heartbeat_elapsed());
        uart_printf("Recoveries this window: %u\n", policy_window_count());

    } else if (strcmp(cmd, "history") == 0) {
        uint32_t n = policy_log_count();
        if (n == 0) {
            uart_print("No events logged.\n");
        }
        for (uint32_t i = 0; i < n; i++) {
            uart_printf("Event %lu: t=%lu\n", i, policy_log_read((uint8_t)i));
        }

    } else if (strcmp(cmd, "force reset") == 0) {
        do_force_reset();

    } else if (strcmp(cmd, "clear lockout") == 0) {
        policy_clear_lockout();
        uart_print("Lockout cleared. Automatic recovery resumed.\n");

    } else if (strcmp(cmd, "help") == 0) {
        uart_print("Commands: status | history | force reset | clear lockout | help\n");

    } else {
        uart_print("Unknown command. Type 'help' for a list.\n");
    }
}
```

### Command Reference Table

| Command | Action | Driver Calls Used |
|---|---|---|
| `status` | Print online/unresponsive, lockout state, elapsed time, window count | `heartbeat_is_unresponsive`, `policy_is_locked_out`, `heartbeat_elapsed`, `policy_window_count` |
| `history` | Print every logged event timestamp | `policy_log_count`, `policy_log_read` |
| `force reset` | Manually trigger recovery regardless of heartbeat state | `reset_seq_trigger`, `reset_seq_is_complete`, `policy_record_event`, `timer_now` |
| `clear lockout` | Manually clear the lockout flag | `policy_clear_lockout` |
| `help` | List available commands | — |
| *(anything else)* | Print "Unknown command" | — |

## 8.2 `main.c` — Entry Point and Superloop

```c
#include "config.h"
#include "console.h"
#include "drivers/heartbeat.h"
#include "drivers/reset_seq.h"
#include "drivers/policy.h"
#include "drivers/uart.h"
#include "drivers/timer.h"
#include "drivers/vga.h"

static void handle_automatic_recovery(void) {
    if (!heartbeat_is_unresponsive()) {
        return;
    }
    if (policy_is_locked_out()) {
        uart_print("LOCKOUT ACTIVE: manual attention required.\n");
        return;
    }
    reset_seq_trigger();
    uint32_t polls = 0;
    while (!reset_seq_is_complete() && polls < RESET_WAIT_MAX_POLLS) {
        polls++;
    }
    if (polls >= RESET_WAIT_MAX_POLLS) {
        uart_print("WARNING: automatic reset sequence did not complete as expected.\n");
        return;
    }
    policy_record_event(timer_now());
    heartbeat_clear_flag();
    uart_print("Recovery triggered and logged.\n");
}

static void service_console(void) {
    if (uart_has_line()) {
        char buf[UART_CMD_BUF_LEN];
        uart_read_line(buf, sizeof(buf));
        console_handle_command(buf);
    }
}

static void refresh_dashboard(void) {
    vga_update_dashboard(
        heartbeat_is_unresponsive(),
        heartbeat_elapsed(),
        policy_is_locked_out(),
        policy_window_count(),
        policy_log_count()
    );
}

static void main_loop(void) {
    while (1) {
        handle_automatic_recovery();   // Control Path 5.1 (main spec)
        service_console();              // Control Path 5.2 (main spec)
        refresh_dashboard();            // Control Path 5.3 (main spec)
    }
}

int main(void) {
    heartbeat_init(HB_THRESHOLD_DEFAULT);
    reset_seq_init(RST_HOLD_DEFAULT);
    policy_init(POL_WINDOW_DEFAULT, POL_THRESHOLD_DEFAULT);
    timer_init();
    uart_init(UART_BAUD_115200);
    vga_init();

    uart_print("BMC firmware initialized. Monitoring active.\n");

    main_loop();
    return 0;   // never reached
}
```

---

# 9. Sequence Walkthroughs

Each walkthrough lists the exact function call sequence for a complete operational scenario, referencing the module documentation above.

## 9.1 Boot / Initialization Sequence

```
main()
 ├─ heartbeat_init(HB_THRESHOLD_DEFAULT)
 │    └─ writes HB_THRESHOLD, HB_CTRL (enable)
 ├─ reset_seq_init(RST_HOLD_DEFAULT)
 │    └─ writes RST_HOLD
 ├─ policy_init(POL_WINDOW_DEFAULT, POL_THRESHOLD_DEFAULT)
 │    └─ writes POL_WINDOW, POL_THRESHOLD
 ├─ timer_init()
 │    └─ writes TIMER_CTRL (enable)
 ├─ uart_init(UART_BAUD_115200)
 │    └─ writes UART_BAUDDIV
 ├─ vga_init()
 │    └─ writes VGA_CTRL (enable)
 ├─ uart_print("BMC firmware initialized...")
 └─ main_loop()   [never returns]
```

## 9.2 Automatic Recovery Sequence (heartbeat lost, not locked out)

```
main_loop() iteration
 └─ handle_automatic_recovery()
      ├─ heartbeat_is_unresponsive() -> true
      ├─ policy_is_locked_out() -> false
      ├─ reset_seq_trigger()
      ├─ [busy-wait loop] reset_seq_is_complete() -> polls until true
      ├─ timer_now() -> ts
      ├─ policy_record_event(ts)
      │    └─ writes POL_EVENT_TS, POL_CTRL (record_event)
      │         └─ [hardware] may set lockout_flag if threshold crossed
      ├─ heartbeat_clear_flag()
      │    └─ writes HB_CTRL (clear)
      └─ uart_print("Recovery triggered and logged.")
```

## 9.3 Automatic Recovery Attempt While Locked Out

```
main_loop() iteration
 └─ handle_automatic_recovery()
      ├─ heartbeat_is_unresponsive() -> true
      ├─ policy_is_locked_out() -> true
      └─ uart_print("LOCKOUT ACTIVE: manual attention required.")
      [no reset triggered, no event recorded - heartbeat flag remains latched]
```

## 9.4 `history` Command Sequence

```
service_console()
 ├─ uart_has_line() -> true (accumulated "history\n")
 ├─ uart_read_line(buf, ...) -> buf = "history"
 └─ console_handle_command("history")
      ├─ policy_log_count() -> n
      └─ for i in [0, n):
             policy_log_read(i)
               ├─ writes LOG_READ_IDX = i
               └─ reads LOG_READ_DATA -> timestamp
             uart_printf("Event %lu: t=%lu\n", i, timestamp)
```

Note the two-step nature of `policy_log_read()`: it is not a single atomic register read but a write-then-read pair. Because there is only one bus master (the core itself, see main spec's master/slave discussion), no other agent can interleave a conflicting write to `LOG_READ_IDX` between these two steps — this is safe by construction.

## 9.5 `force reset` Command Sequence

```
service_console()
 └─ console_handle_command("force reset")
      └─ do_force_reset()
           ├─ reset_seq_trigger()
           ├─ [busy-wait loop] reset_seq_is_complete() -> polls until true
           ├─ timer_now() -> ts
           ├─ policy_record_event(ts)
           └─ uart_print("Manual reset triggered and logged.")
```

Note: `force reset` does **not** check `heartbeat_is_unresponsive()` or `policy_is_locked_out()` — it always executes, by design, since it represents a deliberate human decision to override automatic policy (main spec Control Path 5.2).

## 9.6 VGA Dashboard Refresh Sequence

```
main_loop() iteration
 └─ refresh_dashboard()
      └─ vga_update_dashboard(unresponsive, elapsed, locked_out, window_count, log_count)
           ├─ vga_write_text(...) x4  [status, elapsed, window count, total logged]
           └─ for up to 3 most recent entries:
                  policy_log_read(idx)
                  vga_write_text(...)
```

---

# 10. Firmware-Level Error Handling Summary

This table consolidates every firmware-side error handling behavior, cross-referenced to the corresponding hardware-level error case in the main Architecture/Specification Manual (Section 7).

| Scenario | Firmware Behavior | Corresponding Hardware Error (main spec) |
|---|---|---|
| Reset sequence never completes (hardware fault) | `handle_automatic_recovery()` / `do_force_reset()` cap the busy-wait at `RESET_WAIT_MAX_POLLS`, print a warning, and return — main loop continues rather than hanging forever | Error 7.2.3 (stuck reset_out, verification-only) |
| Unresponsive flag stays latched due to a firmware bug elsewhere | State remains visible via `status`/dashboard; no crash | Error 7.1.3 |
| Malformed/unknown UART command | `console_handle_command()` falls through to default case | Error 7.4.1 |
| Command line exceeds buffer length | `uart_has_line()` discards the partial line and reports it | Error 7.4.2 |
| Log has more than 16 events | `policy_log_count()`/`policy_log_read()` simply reflect hardware's saturating/circular behavior — firmware does no additional handling, none needed | Error 7.3.1 |

---

# 11. Firmware Testing / Validation Approach

Because the custom IP RTL is verified independently (see the project's Verification Plan), firmware testing focuses on validating that the **driver layer correctly maps to the register interface** and that the **application layer sequences calls correctly**.

## 11.1 Driver-Level Validation
- For each driver function, confirm (via RTL simulation with the firmware loaded) that the expected register write/read occurs at the expected address with the expected value — this can be checked directly in the waveform viewer (GTKWave) alongside the existing per-IP unit testbenches.
- Cross-check `config.h` base addresses against whatever final memory map is confirmed for the provided reference SoC (Open Item, main spec).

## 11.2 Application-Level Validation (System-Level Test Scenarios)
Reuses the system-level test scenarios already defined in the project's Implementation & Verification Plan:
1. Nominal operation — confirm `status` output matches actual register state.
2. Single freeze/recover cycle — confirm the exact sequence in Section 9.2 above executes in order, observable via UART output and waveform.
3. Repeated freeze scenario — confirm lockout triggers at the correct count and `handle_automatic_recovery()` correctly takes the "locked out" branch (Section 9.3) afterward.
4. Manual override — confirm `force reset` executes regardless of heartbeat state.
5. History readback — confirm all logged timestamps print correctly and in order.
6. VGA dashboard correctness — visually confirm (SDL viewer) displayed values match register state at each stage.

## 11.3 Suggested Firmware-Only Smoke Test (before full IP integration)
Before integrating with the real custom IP RTL, each driver's register offsets can be sanity-checked against a trivial Verilog "register file stub" that just echoes back writes — confirming the C pointer arithmetic and bit-field masks are correct independent of the real IP's internal FSM logic. This isolates firmware bugs from hardware bugs during early development.

---

# 12. Configuration Constants — Quick Reference

| Constant | Default | Meaning |
|---|---|---|
| `HB_THRESHOLD_DEFAULT` | 1,000,000 cycles | Max time between heartbeats before unresponsive |
| `RST_HOLD_DEFAULT` | 10,000 cycles | Reset pulse hold duration |
| `POL_WINDOW_DEFAULT` | 1,000,000 cycles | Rolling window for recovery counting |
| `POL_THRESHOLD_DEFAULT` | 3 | Max recoveries per window before lockout |
| `UART_BAUD_115200` | 115200 | Console baud rate |
| `UART_CMD_BUF_LEN` | 64 bytes | Max command line length |
| `RESET_WAIT_MAX_POLLS` | 100,000 | Safety cap on busy-wait loops for reset completion |

All values are tunable in `config.h` without touching driver or application logic — deliberately centralized per the conventions in Section 5.
