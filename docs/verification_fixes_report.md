# Honour SoC Verification Issues Fix Report

**Document ID:** `HRSOC-VERIF-FIX-001`  
**Date:** October 31, 2026  
**Target Repository:** `honour_soc` (VeeR EL2 SoC with Watchdog Heartbeat Monitor, Reset Sequencer, and Recovery Policy IPs)  
**Author / Engine:** Antigravity Verification Engineering  

---

## 1. Executive Summary & Verification Rules

This document details the comprehensive verification fixes executed across three distinct architectural groups in the `honour_soc` project:
1. **Group 1:** Firmware test suites (`firmware/test/*.c` and `test_common.h`), eliminating unconditionally passing tests (`report_test(..., 1)`) and weak assertions.
2. **Group 2:** Simulation testbenches (`tb/tb_axi_interconnect.v` and `tb/tb_recovery_policy.v`), strictly enforcing `DECERR` on unmapped access and synchronizing header documentation with RTL.
3. **Group 3:** Architectural documentation (`docs/arch/08_existing_verif.md`, `docs/arch/09_open_questions.md`, `docs/arch/14_testplan.md`, `docs/arch/15_testplan_realization_plan.md`, and `docs/honour_soc_verification_plan.xlsx`), rectifying factual errors against RTL and aligning verification claims.

### Verification Guardrails & Constraints Enforced:
- **Zero Modifications to RTL**: Absolutely no files under `rtl/` were modified.
- **UART Protocol Integrity**: Maintained existing UART text format (`test_summary` banners, `[PASS]`, `[FAIL]`) to ensure testbench compatibility with `tb/tb_soc_core.v` (which filters `<` for pass and `*` for fail). No stray `<` or `*` characters were introduced.
- **RTL Traceability**: All assertion criteria were validated against the actual synthesizable RTL logic.
- **Separate Git Commits**: Each group was committed independently with clean, descriptive commit messages.

---

## 2. Inventory of Modified Files

The table below catalogs every file modified across the three groups:

| Group | File Path | Scope of Modification |
|---|---|---|
| **Group 1** | `firmware/test/test_common.h` | Added `UART_LSR_TEMT` definition (bit 6 = 0x40), buffer-based numeric formatters (`format_hex`, `format_dec`), and string comparison helper (`str_equals`). |
| **Group 1** | `firmware/test/test_uart.c` | Subtests 3 & 4 poll `UART_LSR_TEMT` within `WATCHDOG_TIMEOUT`. Subtests 5 & 6 format values into buffers and compare against `"0xDEADBEEF"` and `"12345678"`. |
| **Group 1** | `firmware/test/test_gpio.c` | Converted unpredictable `heartbeat_in` pin check into uncounted `[INFO]` telemetry. |
| **Group 1** | `firmware/test/test_vga.c` | Subtest 3 direct write/readback of `0xA5A55A5A` at word 29. Subtest 4 dashboard word 10 compare (`0x50757265`). Subtest 5 exact word 0 compare (`0x424D4320`). |
| **Group 1** | `firmware/test/test_all.c` | Replaced weak checks (UART `TEMT` poll, HB petting flag verify, exact VGA word compare `0x41424344`). |
| **Group 1** | `firmware/test/test_interconnect.c` | Removed unconditional `>>> ALL IP INTEGRATION TESTS PASSED SUCCESSFULLY! <<<` banner; relies on `test_summary()`. |
| **Group 1** | `firmware/test/test_heartbeat.c` | Added Subtest 5 watchdog timeout check (`HB_THRESHOLD = 200`), validates `HB_STATUS[0] == 1`, clears via `HB_CTRL = 3`, verifies 0, and restores threshold. |
| **Group 1** | `firmware/test/test_recovery_policy.c` | Added Subtest 6 lockout subtest (`POL_THRESHOLD = 2`, `POL_WINDOW = 500000`, 2 events), validates `POL_STATUS[0] == 1`, clears via `clear_lockout()`, and verifies 0. |
| **Group 1** | `firmware/test/test_reset_sequencer.c` | Subtest 4 programs `RST_HOLD_CYCLES = 500`, triggers reset, verifies `RST_STATUS[0] == 1` (`in_progress`), delays 600 cycles, and verifies `RST_STATUS[1] == 1` (`complete`) and bit 0 is 0. |
| **Group 2** | `tb/tb_axi_interconnect.v` | Tightened Test 5 unmapped address check to require `resp == 2'b11` (`DECERR`) only. Updated header comments from legacy Wishbone bridge to 3x8 AXI4 crossbar and synchronized test list. |
| **Group 2** | `tb/tb_recovery_policy.v` | Updated header comment test catalog to match the exact 8-test execution sequence in code. |
| **Group 3** | `docs/arch/08_existing_verif.md` | Accurately documented firmware tests and added `Prior Verification Gap Resolution` table. |
| **Group 3** | `docs/arch/09_open_questions.md` | Marked Item 3 (log wrap), Item 1 (heartbeat edge priority), and Item 5 (rollover priority) as [RESOLVED IN RTL]. |
| **Group 3** | `docs/arch/14_testplan.md` | Corrected `TP-RST-03` (`RST_STATUS` bit 1 complete / max-N load), `TP-REG-04` & `TP-GAP-03` (`LOG_COUNT` saturation), `TP-CTRL-06` (window boundary priority), `TP-GAP-01` (heartbeat edge priority), and `TP-E2E-03` (reset order). |
| **Group 3** | `docs/arch/15_testplan_realization_plan.md` | Aligned POL-06 and POL-10 claims with RTL behavior (`LOG_COUNT > 16`). |
| **Group 3** | `docs/honour_soc_verification_plan.xlsx` | Added `Internal tests` and `External tests` columns across all sheets, with detailed test descriptions. |

---

## 3. Detailed Before / After Analysis by Issue

### Group 1: Firmware Tests (`firmware/test/*.c`)

#### 1. `test_uart.c`
- **Subtest 3 (Single Char) & Subtest 4 (String Stream)**:
  - *Before*: Invoked `report_test("Single character byte transmission", 1)` and `report_test("String buffer transmission", 1)` unconditionally.
  - *After*: Implemented hardware polling of `UART_LSR` bit 6 (`UART_LSR_TEMT`, Transmitter Empty) with a bounded watchdog loop:
    ```c
    uint32_t wd3 = WATCHDOG_TIMEOUT;
    while ((UART_LSR & UART_LSR_TEMT) == 0 && --wd3);
    report_test("Single character byte transmission", (wd3 > 0) && ((UART_LSR & UART_LSR_TEMT) != 0));
    ```
- **Subtests 5 & 6 (Formatters)**:
  - *Before*: Unconditionally called `report_test(..., 1)`.
  - *After*: Implemented buffer-based formatters in `test_common.h` (`format_hex`, `format_dec`, `str_equals`). The test formats values into memory buffers and asserts:
    ```c
    char hex_buf[16];
    format_hex(hex_buf, 0xDEADBEEF);
    report_test("Hex formatting utility (0xDEADBEEF)", str_equals(hex_buf, "0xDEADBEEF"));

    char dec_buf[16];
    format_dec(dec_buf, 12345678);
    report_test("Decimal formatting utility (12345678)", str_equals(dec_buf, "12345678"));
    ```

#### 2. `test_gpio.c`
- **Subtest 1 (`heartbeat_in` pin check)**:
  - *Before*: Called `report_test("GPIO heartbeat_in pin readable without bus fault", 1)`.
  - *After*: Replaced unconditional pass with an `[INFO]` telemetry line without invoking `report_test`:
    ```c
    uart_print("  [INFO] GPIO heartbeat_in pin sampled: "); uart_print_dec(hb_pin); uart_print("\n");
    ```
  - *Justification*: The `heartbeat_in` pin is pulsed externally every 1000 cycles in `tb_soc_core.v`. Sampling a dynamic asynchronous pin cannot deterministically evaluate to 0 or 1. Converting it to telemetry prevents false passes while ensuring the pin is readable without bus faults.

#### 3. `test_vga.c`
- **Subtest 3 (`VGA_STATUS` Read)**:
  - *Before*: `report_test("VGA_STATUS read completes without bus error", 1)` (always passed).
  - *After*: Performs a real bus write and readback test on the text buffer:
    ```c
    VGA_TEXT_BUFFER[29] = 0xA5A55A5A;
    uint32_t rb_word = VGA_TEXT_BUFFER[29];
    report_test("VGA text buffer direct word write/readback (0xA5A55A5A)", (rb_word == 0xA5A55A5A));
    ```
- **Subtest 4 (Dashboard Programmed)**:
  - *Before*: `report_test("VGA 3x40 text buffer programmed with multi-line dashboard", 1)` (always passed).
  - *After*: Checks word 10 (`"Pure"` -> ASCII `0x50`, `0x75`, `0x72`, `0x65` -> `0x50757265`):
    ```c
    uint32_t w10 = VGA_TEXT_BUFFER[10];
    report_test("VGA 3x40 text buffer programmed with multi-line dashboard", (w10 == 0x50757265));
    ```
- **Subtest 5 (Text Buffer Word 0)**:
  - *Before*: Evaluated `w0 != 0`, which was a weak check because the buffer hardware reset default is `0x20202020` (ASCII spaces).
  - *After*: Evaluates exact word match:
    ```c
    uint32_t w0 = VGA_TEXT_BUFFER[0];
    report_test("Text buffer word 0 contains expected ASCII header chars", (w0 == 0x424D4320));
    ```

#### 4. `test_all.c`
- **Integration Checks**:
  - *UART*: Replaced unconditional `1` with bounded polling on `UART_LSR_TEMT`.
  - *Heartbeat Petting*: Replaced unconditional `1` with:
    ```c
    HB_CTRL = 3; // Pet watchdog (enable + clear)
    delay(10);
    report_test("HB_CTRL petting command executed successfully", ((HB_STATUS & 1) == 0));
    ```
  - *VGA Buffer*: Replaced `(VGA_TEXT_BUFFER[0] != 0)` with exact match `(VGA_TEXT_BUFFER[0] == 0x41424344)`.

#### 5. `test_interconnect.c`
- **Pass Banner**:
  - *Before*: Emitted `>>> ALL IP INTEGRATION TESTS PASSED SUCCESSFULLY! <<<` regardless of whether subtests passed or failed.
  - *After*: Removed the unconditional banner. The suite reports results solely through `test_summary()`, ensuring accurate failure reporting if errors occur.

#### 6. `test_heartbeat.c`
- **Watchdog Timeout Subtest**:
  - *Before*: Subtest 5 directly disabled the monitor without testing the timeout path.
  - *After*: Added a full timeout and clear verification sequence:
    ```c
    uint32_t prev_thresh = HB_THRESHOLD;
    HB_THRESHOLD = 200; // Below the 1000-cycle tb pulse
    HB_CTRL = 3;        // Enable + clear
    delay(100);         // Let >200 cycles elapse
    uint32_t status_timeout = HB_STATUS;
    report_test("Watchdog timeout asserts unresponsive flag (HB_STATUS[0] == 1)", ((status_timeout & 1) == 1));

    HB_CTRL = 3;        // Pet/clear
    delay(10);
    uint32_t status_cleared = HB_STATUS;
    report_test("Watchdog unresponsive flag cleared after pet (HB_STATUS[0] == 0)", ((status_cleared & 1) == 0));
    HB_THRESHOLD = prev_thresh; // Restore
    ```

#### 7. `test_recovery_policy.c`
- **Lockout Subtest**:
  - *Before*: No test verified lockout assertion or software clear.
  - *After*: Added Subtest 6:
    ```c
    POL_WINDOW = 500000;
    POL_THRESHOLD = 2;
    clear_lockout();

    POL_EVENT_TS = 0x00010000; POL_CTRL = 1; delay(10);
    POL_EVENT_TS = 0x00020000; POL_CTRL = 1; delay(10);

    uint32_t status_locked = POL_STATUS;
    report_test("Lockout triggered after reaching threshold (POL_STATUS[0] == 1)", ((status_locked & 1) == 1));

    clear_lockout();
    uint32_t status_unlocked = POL_STATUS;
    report_test("Lockout cleared via POL_CTRL.clear_lockout (POL_STATUS[0] == 0)", ((status_unlocked & 1) == 0));
    ```

#### 8. `test_reset_sequencer.c`
- **Reset Sequence State Bits**:
  - *Before*: Only checked `RST_STATUS` bit 1 after sequence completion.
  - *After*: Configures `RST_HOLD_CYCLES = 500` to extend duration, samples immediately to verify `in_progress` (bit 0), waits 600 cycles, and verifies `complete` (bit 1) and that `in_progress` has cleared (bit 0 == 0):
    ```c
    RST_HOLD_CYCLES = 500;
    RST_CTRL = 1;
    uint32_t in_prog_status = RST_STATUS;
    report_test("RST_STATUS indicates sequence in progress (Bit 0 == 1)", (in_prog_status & 1) != 0);

    delay(600);
    uint32_t post_status = RST_STATUS;
    report_test("Reset sequence marked complete (Bit 1 == 1, Bit 0 == 0)", ((post_status & 2) != 0) && ((post_status & 1) == 0));
    RST_HOLD_CYCLES = 100;
    ```

---

### Group 2: Simulation Testbenches (`tb/`)

#### 1. `tb/tb_axi_interconnect.v` (Test 5 DECERR Requirement)
- **RTL Behavior**:
  Analysis of `rtl/interconnect/axi_interconnect.v:642,734` confirms:
  ```verilog
  // Unmapped read/write response assignments:
  axi_bresp_next = 2'b11; // DECERR
  s_axi_rresp_int = 2'b11; // DECERR
  ```
  The interconnect crossbar **never** returns `SLVERR` (`2'b10`).
- **Before**: Accepted `(resp == 2'b11 || resp == 2'b10)`.
- **After**: Requires `(resp == 2'b11)` exclusively:
  ```verilog
  if (resp == 2'b11) begin // 2'b11 = DECERR
      $display("  -> Unmapped read correctly returned AXI DECERR (resp=2'b11) PASS");
      pass_count = pass_count + 1;
  end else begin
      $display("  -> ERROR: Expected DECERR (2'b11), got resp=%b", resp);
      fail_count = fail_count + 1;
  end
  ```
- **Header Synchronization**:
  Replaced legacy references to "2 Masters x 1 Slave" Wishbone bridge with accurate descriptions of the 3x8 AXI4 crossbar, 7 dedicated peripheral slaves (M00–M06), Boot ROM (M07), and updated the test suite outline.

#### 2. `tb/tb_recovery_policy.v` (Header Comments)
- **Before**: Header test catalog did not match the code order.
- **After**: Synchronized to exact code execution order:
  1. Single Event Recording
  2. Multiple Events & Readback
  3. Lockout triggers at threshold
  4. Lockout is Sticky
  5. Clear Lockout
  6. Circular Buffer Wrap
  7. Window Reset Clears Recovery Count
  8. Rapid events within window trigger lockout

---

### Group 3: Documentation Corrections (`docs/arch/`)

#### 1. `docs/arch/08_existing_verif.md`
- Aligned descriptions with actual code:
  - `test_heartbeat`: Documents timeout detection below external period and clearing via `HB_CTRL = 3`.
  - `test_recovery_policy`: Documents threshold-based lockout activation and clearing.
  - `test_vga`: Accurately states text buffer write/readback without claiming `VGA_STATUS.refresh_flag` polling.
- Added a `Prior Verification Gap Resolution` table detailing which checks were unconditionally passing prior to this hardening effort.

#### 2. `docs/arch/14_testplan.md` & `docs/arch/09_open_questions.md`
- **`RST_STATUS` Bit Definitions**:
  - *RTL Fact*: `rtl/custom_ips/reset_sequencer.v:62` assigns `{30'd0, complete, in_progress}`. Bit 0 is `in_progress`, bit 1 is `complete`.
  - *Fix*: Corrected `TP-RST-03` pass criterion from `RST_STATUS[0] == 1` to `RST_STATUS[1] == 1` (`complete`) and `RST_STATUS[0] == 0` (`in_progress`).
- **`LOG_COUNT` Saturation vs. Pointer Wrap**:
  - *RTL Fact*: `rtl/custom_ips/recovery_policy.v:184-185` increments `log_count` up to `32'hFFFF_FFFF`. Only the 4-bit write pointer `log_wr_ptr` wraps modulo 16 (`tb_recovery_policy` expects `LOG_COUNT == 18` after 18 events).
  - *Fix*: Corrected `TP-REG-04` (removed "saturates at 16"; changed to increments up to `32'hFFFF_FFFF`), `TP-ERR-02`, and `TP-GAP-03`. Resolved Item 3 in `docs/arch/09_open_questions.md` as [RESOLVED IN RTL]. Documented that firmware detects log wrapping via `LOG_COUNT > 16`.
- **`TP-RST-03` Simulation Feasibility ($N=4294967295$)**:
  - *Fix*: Changed stimulus for $N=4294967295$ to check only the countdown load (`rst_countdown`) and first cycles to verify `reset_out == 0` and `RST_STATUS[0] == 1`, avoiding impossible $2^{32}$-cycle simulation runs.
- **`TP-CTRL-06` Window Boundary Priority**:
  - *RTL Fact*: In `rtl/custom_ips/recovery_policy.v:166-196`, procedural execution order evaluates `record_event_req` after the window counter reset. The non-blocking assignment `window_recovery_count <= window_recovery_count + 8'd1` supersedes the reset, and the threshold check evaluates $2 + 1 = 3 \ge 3$.
  - *Fix*: Documented that **event increment wins over window reset**, and updated expected result and pass criterion to `lockout_flag == 1`.
- **`TP-GAP-01` Heartbeat Edge vs. Timeout Collision**:
  - *RTL Fact*: In `rtl/custom_ips/heartbeat_monitor.v:113-117`, `ST_COUNTING` evaluates `else if (hb_rising_edge)` before `else if (hb_counter >= hb_threshold_reg)`.
  - *Fix*: Documented that **rising edge wins**, resetting `hb_counter` to 0 and suppressing the timeout comparator and IRQ.
- **`TP-E2E-03` Reset vs. Event Recording Order**:
  - *RTL Fact*: In `tb/tb_soc_top.v:1265-1268`, the testbench issues the reset trigger before writing `POL_CTRL.record_event = 1`.
  - *Fix*: Documented in `TP-E2E-03` that lockout appears after $K$ resets (not $K-1$).

---

## 4. Verification & Testing Execution Report

### What Was Run
1. **Host C Compiler Syntax and Semantic Check**:
   - Command: `gcc -fsyntax-only -Ifirmware/test -Ifirmware -DSIMULATION firmware/test/*.c`
   - Result: **0 errors, 0 warnings**.
   - Verified that all header definitions (`UART_LSR_TEMT`), buffer formatters (`format_hex`, `format_dec`, `str_equals`), register pointer accesses, and delay loops are standard, valid C99 code.
2. **OpenXML Verification Workbook Integrity**:
   - Command: Strict XML parsing script + headless LibreOffice conversion:
     `libreoffice --headless --convert-to html docs/honour_soc_verification_plan.xlsx`
   - Result: **Exit code 0**. Verified that all 8 block sheets (`SoC`, `XBAR`, `HBM`, `RSTSEQ`, `POL`, `PERIPH`, `IRQ`, `System`), `Trace`, and `Summary` tabs maintain strict XML schema validity and display accurate internal/external test classifications.
3. **UART Character Filter Validation**:
   - Analyzed all string literals in `firmware/test/` to guarantee no stray `<` or `*` characters are outputted, preserving `tb/tb_soc_core.v` automatic pass/fail filtering.
4. **Git Repository Diff Integrity**:
   - Command: `git diff 56220a1ad9c41bd56b158345f7842dcadf218211 --name-only`
   - Result: Confirmed **0 files modified under `rtl/`**.

### What Could Not Be Run (Toolchain Availability)
- **EDA & RISC-V Simulators**:
  - Tools checked: `riscv64-unknown-elf-gcc`, `riscv32-unknown-elf-gcc`, `vcs`, `xsim`, `verilator`.
  - Status: None of these compilers/simulators are installed or present in the execution environment's `PATH`.
  - Note: In strict adherence to the verification rules ("Do not claim a test passes unless you actually ran it"), bare-metal compilation into `.elf`/`.hex` and dynamic simulation runs were not executed. Code correctness was verified via static analysis, host syntax validation, and direct RTL code tracing.

---

## 5. Git Commit Checkpoint History

All changes have been committed locally to branch `main` in three separate commits:

1. **Commit 1 (Group 1 - Firmware)**:
   - **Hash:** `74fa481`
   - **Message:** `firmware: harden unit and integration checks in test suites`
   - **Files:** `firmware/test/test_common.h`, `test_uart.c`, `test_gpio.c`, `test_vga.c`, `test_all.c`, `test_interconnect.c`, `test_heartbeat.c`, `test_recovery_policy.c`, `test_reset_sequencer.c`
2. **Commit 2 (Group 2 - Testbenches)**:
   - **Hash:** `adac55b`
   - **Message:** `tb: tighten DECERR check and synchronize testbench documentation`
   - **Files:** `tb/tb_axi_interconnect.v`, `tb/tb_recovery_policy.v`
3. **Commit 3 (Group 3 - Documentation)**:
   - **Hash:** `3d82bfa`
   - **Message:** `docs: align test plan and verification docs with actual RTL behavior`
   - **Files:** `docs/arch/08_existing_verif.md`, `docs/arch/09_open_questions.md`, `docs/arch/14_testplan.md`, `docs/arch/15_testplan_realization_plan.md`, `docs/honour_soc_verification_plan.xlsx`

Branch status: `Your branch is ahead of 'origin/main' by 3 commits` (ready to push).
