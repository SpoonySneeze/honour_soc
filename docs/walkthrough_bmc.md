# BMC SoC Implementation — Walkthrough

## Summary

All RTL modules, bus infrastructure, SoC integration, testbenches, and the build system for the BMC SoC project have been implemented. Firmware is deferred for a later phase.

---

## What Was Built

### Bus Infrastructure (Phase 1)

| File | Purpose |
|---|---|
| [`axi4_to_wb_bridge.v`](file:///e:/Projects/honours_project/rtl/custom/axi4_to_wb_bridge.v) | AXI4-Lite slave → Wishbone B4 master bridge. 6-state FSM handles write-priority arbitration, latches AXI transactions, drives WB bus cycles, and propagates errors. |
| [`wb_interconnect.v`](file:///e:/Projects/honours_project/rtl/custom/wb_interconnect.v) | 7-slave Wishbone address decoder using `addr[15:8]` for one-hot slave select. Combinational data/ack mux with error on unmapped addresses. |

### Custom IPs (Phase 2–3 + VGA)

| File | IP | Key Design |
|---|---|---|
| [`heartbeat_monitor.v`](file:///e:/Projects/honours_project/rtl/custom/heartbeat_monitor.v) | Heartbeat Monitor | 4-state FSM (DISABLED→IDLE→COUNTING→UNRESPONSIVE), edge detector, 32-bit cycle counter, threshold comparator, sticky unresponsive flag |
| [`reset_sequencer.v`](file:///e:/Projects/honours_project/rtl/custom/reset_sequencer.v) | Power/Reset Sequencer | 4-state FSM (IDLE→ASSERT→DEASSERT→DONE), countdown timer from configurable hold register, active-low `reset_out`, trigger-while-busy ignored |
| [`recovery_policy.v`](file:///e:/Projects/honours_project/rtl/custom/recovery_policy.v) | Recovery Policy & Event Log | 16×32 circular log buffer, fixed-window lockout policy (window counter + recovery counter + threshold comparator), sticky lockout flag |
| [`vga_controller.v`](file:///e:/Projects/honours_project/rtl/custom/vga_controller.v) | VGA Controller | 640×480@60Hz timing, pixel clock divider (÷4), scan counters, 120-char dashboard buffer, simplified block-char rendering, green-on-dark-blue style |

### SoC Integration (Phase 4)

| File | Purpose |
|---|---|
| [`soc_top.v`](file:///e:/Projects/honours_project/rtl/soc_top.v) | Top-level SoC wiring all modules together. Includes stub implementations for UART (with `$write` sim output), Timer (free-running 32-bit counter), and GPIO (input/output registers). VeeR EL2 core left as placeholder interface. |

### Testbenches (Phase 2–3 + System)

| File | Coverage |
|---|---|
| [`tb_heartbeat_monitor.v`](file:///e:/Projects/honours_project/tb/tb_heartbeat_monitor.v) | Happy path, timeout detection, flag latching, counter accuracy, disable/re-enable |
| [`tb_reset_sequencer.v`](file:///e:/Projects/honours_project/tb/tb_reset_sequencer.v) | Basic pulse timing, status flags, re-trigger while busy, configurable hold, back-to-back triggers |
| [`tb_recovery_policy.v`](file:///e:/Projects/honours_project/tb/tb_recovery_policy.v) | Event recording, log readback, circular wrap, lockout at threshold, lockout sticky, clear lockout, window reset, rapid events |
| [`tb_soc_top.v`](file:///e:/Projects/honours_project/tb/tb_soc_top.v) | End-to-end via AXI bus: nominal operation, single freeze-recover, crash-loop lockout, lockout blocking, manual clear, log history readback |

### Build System (Phase 7)

| File | Purpose |
|---|---|
| [`Makefile`](file:///e:/Projects/honours_project/Makefile) | Targets: `sim_hbm`, `sim_rst`, `sim_pol`, `sim_soc`, `sim_all`, `waves_*`, `clean` |

---

## Key Design Decisions

1. **Wishbone over AXI-Lite for peripheral interfaces** — Matches the spec diagrams, simpler to implement per-IP, only one bridge needed.

2. **Self-clearing control bits** — `HB_CTRL.clear_flag`, `RST_CTRL.trigger`, `POL_CTRL.record_event` all self-clear after one cycle. Firmware writes a `1`, hardware consumes it — no second write needed to deassert.

3. **Fixed-window policy (not sliding window)** — Deliberate simplification documented in spec. `window_counter` counts up to `policy_window_reg`, then resets both itself and `window_recovery_count`. Simpler to implement, verify, and explain.

4. **Trigger-while-busy ignored** — Reset Sequencer silently ignores trigger writes while `rst_state != IDLE`. No queueing complexity.

5. **Stub IPs for UART/Timer/GPIO** — Provide enough functionality for simulation (Timer counts, UART prints via `$write`, GPIO has I/O registers) without requiring full IP integration.

6. **Testbench drives AXI directly** — System testbench bypasses VeeR core and drives AXI transactions from `initial` block, simulating what firmware would do. Allows end-to-end verification of bus infrastructure + custom IPs without needing compiled firmware.

---

## How to Run

```bash
# Run all unit tests + system test
make sim_all

# Run individual tests
make sim_hbm    # Heartbeat Monitor
make sim_rst    # Reset Sequencer  
make sim_pol    # Recovery Policy
make sim_soc    # Full SoC integration

# View waveforms
make waves_hbm  # etc.

# Clean build artifacts
make clean
```

---

## Remaining Work

| Phase | Status |
|---|---|
| Phase 5 — Firmware | **Deferred** (drivers, main loop, console, linker script) |
| VeeR EL2 core integration | Placeholder in `soc_top.v` — connect when ready |
| Real UART/Timer/GPIO IPs | Replace stubs with actual implementations |
