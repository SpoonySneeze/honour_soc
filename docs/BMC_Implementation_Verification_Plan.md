# BMC SoC — Implementation, Simulation & Verification Plan

## 1. System Overview

A RISC-V based SoC implementing a simplified Baseboard Management Controller: detects loss of heartbeat from a simulated "main system," automatically triggers recovery, tracks recovery history, escalates to lockout after repeated failures, and exposes status via a UART console and a live VGA dashboard.

**Pre-built IPs (integrated, not designed):** RISC-V core (PicoRV32), Instruction Memory, Data Memory, Wishbone Bus Interconnect, UART, Timer, GPIO, base VGA Controller (sync generator + pixel logic, adapted for dashboard content).

**Custom IPs (designed from scratch, this plan covers them):** Heartbeat Monitor, Power/Reset Sequencer, Recovery Policy & Event Log.

---

## 2. Memory Map

| Address Range | Block | Notes |
|---|---|---|
| `0x0000_0000 – 0x0000_FFFF` | Instruction Memory | Program code |
| `0x0001_0000 – 0x0001_FFFF` | Data Memory | Stack, heap, buffers |
| `0x0002_0000 – 0x0002_00FF` | UART | Wishbone UART regs |
| `0x0002_0100 – 0x0002_01FF` | Timer | Wishbone timer regs |
| `0x0002_0200 – 0x0002_02FF` | GPIO | Heartbeat in, reset out |
| `0x0002_0300 – 0x0002_03FF` | **Heartbeat Monitor** | Custom IP |
| `0x0002_0400 – 0x0002_04FF` | **Power/Reset Sequencer** | Custom IP |
| `0x0002_0500 – 0x0002_05FF` | **Recovery Policy / Event Log** | Custom IP |
| `0x0002_0600 – 0x0002_06FF` | VGA Controller | Dashboard control regs |

Exact offsets to be finalized once base IPs are integrated and their existing register maps are confirmed (each pre-built core ships with its own spec — don't reassign addresses that conflict with defaults unless the Wishbone decoder is written to remap them).

---

## 3. Custom IP #1 — Heartbeat Monitor

### Purpose
Detect when the simulated main system has stopped sending its periodic "I'm alive" pulse.

### Register Map (Wishbone slave, 32-bit regs)

| Offset | Name | R/W | Description |
|---|---|---|---|
| `0x00` | `HB_CTRL` | R/W | bit0: enable; bit1: clear-unresponsive-flag |
| `0x04` | `HB_THRESHOLD` | R/W | Max cycles allowed between heartbeat pulses before flagging unresponsive |
| `0x08` | `HB_STATUS` | R | bit0: unresponsive flag; bit1: heartbeat currently high |
| `0x0C` | `HB_ELAPSED` | R | Cycles since last heartbeat pulse (live counter, for dashboard) |

### Internal Design
- One input: `heartbeat_in` (wired to a GPIO pin, driven by testbench to simulate the main system).
- Internal free-running counter, reset to 0 on every rising edge of `heartbeat_in`.
- Counter increments every clock cycle (or every Timer tick, if you prefer sharing the Timer IP instead of a private counter — simpler to verify if it counts its own cycles independently, so recommend a private counter).
- Comparator: if counter > `HB_THRESHOLD`, set `unresponsive` flag and raise an interrupt/status bit (can be polled by firmware instead of a real IRQ, to keep it simple — polling is fine given this isn't latency-critical at the microsecond level).
- `HB_ELAPSED` always reflects live counter value for dashboard display.

### FSM
States: `IDLE` → `MONITORING` → `UNRESPONSIVE` (latched until firmware clears via `HB_CTRL` bit1, typically after triggering recovery).

---

## 4. Custom IP #2 — Power/Reset Sequencer

### Purpose
Drive a correctly-timed reset pulse to the simulated main system, either automatically (triggered by firmware after Heartbeat Monitor flags unresponsive) or manually (`force reset` UART command).

### Register Map

| Offset | Name | R/W | Description |
|---|---|---|---|
| `0x00` | `RST_CTRL` | W | bit0: trigger reset sequence (self-clearing) |
| `0x04` | `RST_HOLD_CYCLES` | R/W | How many cycles to hold reset line low |
| `0x08` | `RST_STATUS` | R | bit0: sequence in progress; bit1: sequence complete (sticky, cleared on next trigger) |

### Internal Design
- One output: `reset_out` (wired to GPIO, drives the simulated main system's reset input).
- FSM: `IDLE` → (on trigger) → `ASSERT_RESET` (drive `reset_out` low, count down `RST_HOLD_CYCLES`) → `DEASSERT` (drive `reset_out` high) → `DONE` → back to `IDLE`.
- Firmware polls `RST_STATUS` or just waits a known number of cycles before checking heartbeat resumes.

---

## 5. Custom IP #3 — Recovery Policy & Event Log

### Purpose
Track how many recoveries have happened recently; lock out further automatic recovery if the system is crash-looping; store a timestamped history.

### Register Map

| Offset | Name | R/W | Description |
|---|---|---|---|
| `0x00` | `POL_CTRL` | W | bit0: record new recovery event (firmware writes this after triggering a reset) |
| `0x04` | `POL_WINDOW` | R/W | Rolling window size, in Timer ticks, for counting recoveries |
| `0x08` | `POL_THRESHOLD` | R/W | Max recoveries allowed within window before lockout |
| `0x0C` | `POL_STATUS` | R | bit0: locked-out flag; bits[15:8]: current recovery count in window |
| `0x10` | `LOG_READ_IDX` | R/W | Index into circular log buffer for readback |
| `0x14` | `LOG_READ_DATA` | R | Timestamp of event at `LOG_READ_IDX` |
| `0x18` | `LOG_COUNT` | R | Total events logged (caps at buffer size, e.g. 16) |

### Internal Design
- Small circular buffer (e.g., 16 entries × 32-bit timestamp) implemented as internal register array — this is your "Event Log."
- On `POL_CTRL` write: fetch current time from Timer IP (firmware passes it in, or IP reads Timer directly if wired to it — simpler to have firmware pass the timestamp as part of the write, avoiding an extra bus master), push into circular buffer, increment `LOG_COUNT` (saturating), increment rolling recovery counter.
- Rolling window logic: simplest correct approach for a first version — a counter that decays/resets based on `POL_WINDOW` elapsed since first event in window, OR (simpler to implement and verify) a straightforward counter that resets to 0 every `POL_WINDOW` cycles, then compares against `POL_THRESHOLD`. Recommend the simpler reset-every-window version for your timeframe — it's not a perfect true rolling window but is correct, explainable, and easy to verify; note this as a design simplification in your report (a real system might use a sliding window; you chose a fixed-window approximation for scope reasons — that's a legitimate, honest engineering tradeoff to state explicitly).
- If count exceeds `POL_THRESHOLD` within the window: set `locked-out` bit, sticky until firmware explicitly clears it (e.g., via a manual admin override command).

---

## 6. C Application Design

### Module Breakdown

```
main.c              - init, main polling loop
drivers/
  heartbeat.c/.h     - HB_* register access wrappers
  reset_seq.c/.h     - RST_* register access wrappers
  policy.c/.h        - POL_*/LOG_* register access wrappers
  uart.c/.h          - UART tx/rx, simple line-based command read
  vga.c/.h           - writes text/state to VGA dashboard region
  timer.c/.h         - Timer read/config wrappers
console.c/.h         - command parser: "status", "history", "force reset"
```

### Main Loop (pseudocode)

```c
int main(void) {
    heartbeat_init(THRESHOLD_CYCLES);
    reset_seq_init(HOLD_CYCLES);
    policy_init(WINDOW, MAX_RESTARTS);
    uart_init(BAUD);
    vga_init();

    while (1) {
        // 1. Check for unresponsive system
        if (heartbeat_is_unresponsive()) {
            if (!policy_is_locked_out()) {
                reset_seq_trigger();
                wait_cycles(RESET_WAIT);
                policy_record_event(timer_now());
                heartbeat_clear_flag();
                uart_print("Recovery triggered\n");
            } else {
                uart_print("LOCKOUT: manual attention required\n");
            }
        }

        // 2. Service UART commands (non-blocking check)
        if (uart_has_line()) {
            char buf[64];
            uart_read_line(buf, sizeof(buf));
            console_handle_command(buf);
        }

        // 3. Refresh VGA dashboard
        vga_update_status(heartbeat_elapsed(), policy_status(), policy_log_count());
    }
}
```

### Console Command Handling (pseudocode)

```c
void console_handle_command(const char *cmd) {
    if (strcmp(cmd, "status") == 0) {
        uart_printf("System: %s\n", heartbeat_is_unresponsive() ? "UNRESPONSIVE" : "ONLINE");
        uart_printf("Lockout: %s\n", policy_is_locked_out() ? "YES" : "NO");
        uart_printf("Time since heartbeat: %lu cycles\n", heartbeat_elapsed());
    } else if (strcmp(cmd, "history") == 0) {
        uint32_t n = policy_log_count();
        for (uint32_t i = 0; i < n; i++) {
            uart_printf("Event %lu: t=%lu\n", i, policy_log_read(i));
        }
    } else if (strcmp(cmd, "force reset") == 0) {
        reset_seq_trigger();
        policy_record_event(timer_now());
        uart_print("Manual reset triggered\n");
    } else if (strcmp(cmd, "clear lockout") == 0) {
        policy_clear_lockout();
        uart_print("Lockout cleared\n");
    } else {
        uart_print("Unknown command\n");
    }
}
```

This is the complete shape of the firmware — register-driver layer, a simple superloop (no RTOS needed, keeps it simple and easy to explain), and a small command parser. I'm confident writing the real, compilable version of this alongside you, including the exact register offsets once IPs are finalized.

---

## 7. Simulation Plan

### Toolchain
- **Icarus Verilog** or **Verilator** for RTL simulation (check which your course uses/provides)
- **GTKWave** for waveform inspection of custom IPs
- **SDL-based VGA viewer** (common testbench utility) for live dashboard viewing
- **RISC-V GCC toolchain** to compile the C application to a `.hex`/`.mem` file for instruction memory preload

### Testbench Structure
```
tb_heartbeat_monitor.v    - standalone unit testbench for IP #1
tb_reset_sequencer.v      - standalone unit testbench for IP #2
tb_recovery_policy.v      - standalone unit testbench for IP #3
tb_soc_top.v              - full-system testbench, drives heartbeat_in,
                             observes reset_out, runs compiled firmware
```

### Simulated Stimuli
- `heartbeat_in` toggled by testbench on a configurable interval — this stands in for "the main system," so you fully control when it "freezes" (stop toggling) and "recovers" (resume toggling).
- Reset events, lockout condition, and recovery all driven purely by this one testbench signal — makes your test scenarios fully deterministic and repeatable.

---

## 8. Verification Plan

### Unit-level tests (per custom IP, before integration)

**Heartbeat Monitor**
1. Heartbeat toggles faster than threshold → `unresponsive` never sets. (Happy path)
2. Heartbeat stops → `unresponsive` sets exactly when elapsed count crosses threshold, not before/after. (Boundary test)
3. Heartbeat resumes after flag set → flag stays latched until firmware clears it. (Latching behavior)
4. `HB_ELAPSED` counts accurately and resets correctly on each pulse. (Counter correctness)

**Power/Reset Sequencer**
1. Trigger → `reset_out` goes low for exactly `RST_HOLD_CYCLES`, then returns high. (Timing correctness)
2. Trigger while already in progress → verify defined behavior (ignored, or queued — decide and document which).
3. `RST_STATUS` correctly reflects in-progress vs. complete.

**Recovery Policy / Event Log**
1. Single event recorded → `LOG_COUNT` increments, `LOG_READ_DATA` at index 0 matches injected timestamp.
2. Events exceeding buffer size → circular buffer wraps correctly, oldest entries overwritten (or count saturates — decide and document).
3. Recoveries within window below threshold → no lockout.
4. Recoveries within window exceeding threshold → lockout flag sets.
5. Lockout persists until explicitly cleared, even if heartbeat later recovers on its own.

### System-level / integration tests

1. **Nominal operation:** heartbeat toggling normally, dashboard shows ONLINE, UART `status` reports correctly.
2. **Single freeze-recover cycle:** stop heartbeat → verify detection → verify reset pulse fires → verify heartbeat resumes → verify event logged → verify dashboard updates live through all stages.
3. **Repeated freeze scenario (the key demo):** simulate freeze/recover multiple times in succession → verify recovery count increments each time → verify lockout triggers once threshold crossed → verify further freezes do NOT trigger auto-reset while locked out → verify UART reports "LOCKOUT" state correctly.
4. **Manual override:** while system is nominal, send `force reset` over UART → verify reset fires and is logged even without a heartbeat failure.
5. **History readback:** after several events, send `history` over UART → verify all timestamps returned match what was actually recorded, in correct order.
6. **VGA dashboard correctness:** visually confirm (via SDL viewer, screenshot for your report) that all displayed values match register state at several points across the above scenarios.

### What "verified" means for your report
For each test above: state the expected behavior, the stimulus applied, the observed result (waveform screenshot or UART log excerpt), and pass/fail. This mirrors real hardware verification methodology and is exactly what your professor will want to see as evidence — not just "it worked once," but a structured test list with reproducible results.

---

## 9. Suggested Timeline (given limited semester time)

| Phase | Work |
|---|---|
| 1 | Integrate mandatory pre-built IPs (core, memory, bus, UART, GPIO, Timer) — confirm basic firmware can run and print over UART |
| 2 | Design + unit-test Heartbeat Monitor and Reset Sequencer (simplest two, and they depend on each other for the core demo) |
| 3 | Design + unit-test Recovery Policy/Event Log |
| 4 | Integrate base VGA controller, adapt pixel logic for dashboard text/status rendering |
| 5 | Write full C application, wire to all custom IP registers |
| 6 | System-level test scenarios (section 8), capture results, screenshots, waveform evidence |
| 7 | Write up report/architecture document using verification results as evidence |

Phases 2–3 are the part where I can help most directly with actual Verilog; phase 5 is where I can help most directly with actual C. Buffer time between phases is worth keeping given your stated time constraints — integration always takes longer than expected the first time through.

---

## 10. Open Design Decisions to Confirm With You

1. Rolling window implementation: fixed-reset window (simpler) vs. true sliding window (more accurate, more complex) — recommend fixed-reset given your timeframe.
2. Circular log buffer size (suggest 16 entries — big enough to demo, small enough to keep register/RTL simple).
3. Whether Heartbeat Monitor uses its own private counter or shares the Timer IP — recommend private counter for simulation clarity.
4. Exact register offsets, once your course's base IP set (and any provided starter memory map) is confirmed — this plan uses placeholder addresses.

