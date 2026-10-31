# Existing Verification Environment & Software Analysis

**Document ID:** `docs/arch/08_existing_verif.md`  
**Stage:** Stage 8 — Existing Testbenches, Firmware Suites, Build Infrastructure, and Toolchain Audit  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) through [`docs/arch/07_clk_rst_irq.md`](file:///home/student/sriv_183/honour_soc/docs/arch/07_clk_rst_irq.md)  

---

## 1. Existing Testbench Inventory & Coverage Assessment

The repository currently relies entirely on directed Verilog-2001 testbenches without a UVM class library. The table below catalogs all existing simulation testbenches, what each covers, and its underlying architectural assumptions.

| Testbench File | Top Module | Target Under Test | Test Scenarios Covered | Key Assumptions & Limitations | Source Citation |
|---|---|---|---|---|---|
| `tb/tb_soc_core.v` | `tb_soc_core` | Full SoC (`soc_top`) + VeeR Core + Boot ROM + All Peripherals | • Real-time UART serial character reception and console snooping at 115200 baud<br>• End-to-end boot from AXI Boot ROM (`firmware.hex`)<br>• Execution of C firmware test suites on the VeeR core<br>• Dynamic FSDB/VCD waveform generation | • Assumes fixed 100 MHz clock (10 ns period)<br>• Assumes fast baud divisor (`BAUD_DIV = 16`) under `+define+SIMULATION`<br>• Pass/fail criteria relies on detecting ASCII strings in console stream (`"ALL TESTS PASSED"`) rather than bus-level scoreboard assertions. | `tb/tb_soc_core.v:1-60`<br>`Makefile:195-205` |
| `tb/tb_soc_top.v` | `tb_soc_top` | Peripheral Subsystem (`soc_top` without VeeR core) | • **Scenario 1**: Normal heartbeat pulse stream (system remains online)<br>• **Scenario 2**: Single heartbeat freeze $\rightarrow$ timeout $\rightarrow$ reset pulse $\rightarrow$ event log<br>• **Scenario 3**: Repeated freezes $\rightarrow$ crash-loop lockout trigger<br>• **Scenario 4**: Manual override via register writes (force reset, clear lockout) | • Testbench stands in for CPU by directly driving AXI bus channels (`lsu_axi_*`)<br>• Bypasses RISC-V core instruction execution latency | `tb/tb_soc_top.v:1-30`<br>`Makefile:249-266` |
| `tb/tb_axi_interconnect.v` | `tb_axi_interconnect` | AXI4 Interconnect (`axi_interconnect_wrap_3x8`) | • Master 0 single-beat write/read with ID reflection (Heartbeat Monitor)<br>• Master 1 single-beat write/read with ID reflection (Reset Sequencer)<br>• 64-bit to 32-bit address/data steering (`addr[2] == 0` vs `addr[2] == 1`)<br>• Read data word replication across 64-bit bus lanes<br>• Simultaneous concurrent master request arbitration<br>• Unmapped address decode error handling (`DECERR`) | • Verifies bus routing in isolation with mock slaves<br>• Limited to single-beat and basic burst transactions | `tb/tb_axi_interconnect.v:1-35`<br>`Makefile:271-278` |
| `tb/tb_heartbeat_monitor.v` | `tb_heartbeat_monitor` | Heartbeat Monitor (`axi_heartbeat_monitor`) | • **Test 1**: Happy path (pulses faster than threshold $\rightarrow$ no flag)<br>• **Test 2**: Timeout detection (pulses cease $\rightarrow$ flag asserts, `hb_irq` asserts)<br>• **Test 3**: Sticky flag latching (pulses resume $\rightarrow$ flag stays 1 until cleared)<br>• **Test 4**: Counter accuracy (`HB_ELAPSED` matches clock count)<br>• **Test 5**: Disable / re-enable state machine flush | • Standalone unit test driving local AXI-Lite write/read tasks<br>• Does not evaluate PIC interrupt handling | `tb/tb_heartbeat_monitor.v:1-35, 216-370`<br>`Makefile:280-287` |
| `tb/tb_reset_sequencer.v` | `tb_reset_sequencer` | Reset Sequencer (`axi_reset_sequencer`) | • **Test 1**: Basic active-low reset pulse generation<br>• **Test 2**: Status flags (`in_progress`, `complete`)<br>• **Test 3**: Re-trigger protection (second trigger ignored while busy)<br>• **Test 4**: Configurable hold duration (`RST_HOLD_CYCLES`)<br>• **Test 5**: Sequential back-to-back pulses | • Standalone unit testbench<br>• Verifies output pulse timing against internal countdown | `tb/tb_reset_sequencer.v:1-35`<br>`Makefile:289-296` |
| `tb/tb_recovery_policy.v` | `tb_recovery_policy` | Recovery Policy (`axi_recovery_policy`) | • **Test 1**: Single event timestamp recording<br>• **Test 2**: Multiple event recording & log index readback<br>• **Test 3**: Circular buffer pointer wrap-around (17+ events)<br>• **Test 4**: Threshold comparator (no lockout below threshold)<br>• **Test 5**: Lockout assertion at threshold (`lockout_flag = 1`, `lockout_irq = 1`)<br>• **Test 6**: Sticky lockout persistence across windows<br>• **Test 7**: Firmware clear lockout (`POL_CTRL.clear_lockout = 1`)<br>• **Test 8**: Window expiration count flush | • Standalone unit testbench<br>• Directly verifies 16-entry circular RAM logic | `tb/tb_recovery_policy.v:1-35`<br>`Makefile:298-305` |

---

## 2. Firmware Test Suites & Bare-Metal Software

Firmware executes bare-metal on the VeeR EL2 processor core (`RV32IMC`). The test suites in [`firmware/test/`](file:///home/student/sriv_183/honour_soc/firmware/test) validate individual hardware blocks and end-to-end integration.

| Firmware File | Test Target | Executed Test Cases & Verifications | Hardware Interaction Method | Source Citation |
|---|---|---|---|---|
| `firmware/start.S` | Processor Startup | • Disables interrupts globally (`csrw mstatus, zero`)<br>• Configures MRAC (CSR `0x7c0 = 0x2`) to mark peripheral space `0x0002_xxxx` as side-effect device memory<br>• Sets stack pointer `sp = 0xF005_0000` (top of 64KB DCCM)<br>• Zeroes `.bss` segment in DCCM<br>• Jumps to C runtime `main()` | Low-level RISC-V assembly initialization | `firmware/start.S:1-32` |
| `firmware/link.ld` | Memory Layout | • Mapped ROM: `ORIGIN = 0x8000_0000, LENGTH = 8K`<br>• Mapped RAM: `ORIGIN = 0xF004_0000, LENGTH = 64K`<br>• Positions `.text`, `.rodata` in ROM; `.data`, `.bss` in DCCM | GNU ld linker script | `firmware/link.ld:1-36` |
| `firmware/test/test_uart.c` | UART 16550 IP | • Verifies Line Status Register (`LSR.THRE = 1`, `LSR.TEMT = 1`)<br>• Tests single-character streaming (`uart_putc`)<br>• Tests burst string transmission (`uart_print`)<br>• Tests baud rate reconfiguration | Memory-mapped register reads/writes to `0x0002_0000`–`0x0002_001C` | `firmware/test/test_uart.c:1-39`<br>`Makefile:222-224` |
| `firmware/test/test_timer.c` | System Timer IP | • Verifies monotonic tick increment<br>• Benchmarks cycle counting precision<br>• Validates non-zero uptime delta over execution loops | Memory-mapped read of `TMR_CTR` (`0x0002_0100`) | `Makefile:225-227` |
| `firmware/test/test_gpio.c` | GPIO Status IP | • Reads real-time pin levels from `GPIO_STATUS`<br>• Verifies `reset_out` status line reflection<br>• Senses external `heartbeat_in` level | Memory-mapped read of `GPIO_STATUS` (`0x0002_0200`) | `Makefile:228-230` |
| `firmware/test/test_heartbeat.c` | Watchdog IP | • Verifies initial `HB_STATUS` unresponsive flag is 0<br>• Configures `HB_THRESHOLD` (write/readback)<br>• Arms watchdog via `HB_CTRL.enable = 1`<br>• Reads real-time counter progression from `HB_ELAPSED`<br>• Verifies watchdog petting/servicing via `HB_CTRL = 3`<br>• Verifies timeout detection asserting `unresponsive_flag` when threshold is exceeded without heartbeat and clears via `HB_CTRL = 3`<br>• Disables monitor via `HB_CTRL.enable = 0` | Memory-mapped reads/writes to `0x0002_0300`–`0x0002_030C` | `Makefile:231-233` |
| `firmware/test/test_reset_sequencer.c` | Reset Sequencer IP | • Configures `RST_HOLD_CYCLES`<br>• Triggers pulse via `RST_CTRL.trigger = 1`<br>• Verifies `RST_STATUS.in_progress == 1` during active pulse<br>• Verifies `RST_STATUS.complete == 1` and `in_progress == 0` upon finish | Memory-mapped reads/writes to `0x0002_0400`–`0x0002_0408` | `Makefile:234-236` |
| `firmware/test/test_recovery_policy.c` | Recovery Policy IP | • Configures `POL_WINDOW` and `POL_THRESHOLD`<br>• Clears initial lockout<br>• Stages timestamps in `POL_EVENT_TS` and commits via `record_event`<br>• Verifies sequential `LOG_COUNT` increment and circular log buffer readback via `LOG_READ_IDX` and `LOG_READ_DATA`<br>• Verifies crash-loop lockout activation (`POL_STATUS[0] == 1`) when threshold is reached and software clear via `clear_lockout` | Memory-mapped reads/writes to `0x0002_0500`–`0x0002_051C` | `Makefile:237-239` |
| `firmware/test/test_vga.c` | VGA Controller IP | • Verifies display enable/disable control via `VGA_CTRL.enable`<br>• Reads `VGA_STATUS` register without bus fault<br>• Direct word write and readback verification on `VGA_TEXT_BUFFER`<br>• Programs 3x40 multi-line dashboard buffer and verifies exact word readbacks (e.g. `0x50757265` and `0x424D4320`) | Memory-mapped reads/writes to `0x0002_0600`–`0x0002_067C` | `Makefile:240-242` |
| `firmware/test/test_all.c` | Full SoC Regression | Composite firmware linking all individual test suites into a single unified binary image for regression testing | Sequential execution across all peripheral base addresses | `Makefile:243-245` |

> [!NOTE]
> **Prior Verification Gap Resolution**:
> Prior to the verification hardening fix, several firmware checks used unconditional pass calls (`report_test(..., 1)`), which tested nothing:
> - `test_uart.c`: Subtest 3 (single character), Subtest 4 (string burst), and Subtests 5/6 (hex/decimal formatters) passed unconditionally. (Now hardened to poll `LSR.TEMT` with `WATCHDOG_TIMEOUT` and verify formatted buffers).
> - `test_gpio.c`: The `heartbeat_in` pin readability passed unconditionally. (Now converted to an informational `[INFO]` print because pin state toggles asynchronously).
> - `test_vga.c`: `VGA_STATUS` read and dashboard programming passed unconditionally, while word 0 only checked `w0 != 0` (which always held due to `0x20202020` reset value). (Now hardened to direct word write/readback and exact big-endian ASCII comparison `w0 == 0x424D4320`).
> - `test_all.c`: Contained unconditional passes for UART stream, watchdog petting, and weak VGA `!= 0` check. (Now hardened to `TEMT` poll, `HB_STATUS` 0 verification after pet, and exact VGA word compare).
> - `test_interconnect.c`: Printed an unconditional pass banner regardless of test failures. (Now removed; pass/fail relies strictly on `test_summary()`).

---

## 3. Build Systems, Simulation Tools, and Flow Requirements

| Tool Category | Tool Identified | Configuration / Invocation in Repository | Role in Verification Flow | Source Citation |
|---|---|---|---|---|
| **Primary Simulator** | Synopsys VCS (`U-2023.03`) | `vcs -full64 -sverilog +v2k -notice -debug_access+all -kdb -timescale=1ns/1ps +define+SIMULATION=1 +define+GTLSIM=1` | Compiles synthesizable RTL and testbenches into simulation executables (`simv_*`) | `Makefile:15, 35-36` |
| **Secondary Simulator** | AMD Vivado XSIM (`2023.1`) | `xvlog -sv ...`, `xvlog ...`, `xelab -debug typical -top tb_soc_top`, `xsim tb_soc_top_snap` | Standalone batch simulation flow for Windows / WSL environments | `run_xsim.bat:1-31`<br>`Makefile:374-380` |
| **Waveform Debugger** | Synopsys Verdi (`U-2023.03-SP1`) | `verdi -ssf <target>.fsdb -sswr <target>.rc &` | Visual waveform debugging using pre-configured signal restoration layouts (`waves/*.rc`) | `Makefile:16, 37, 326-369` |
| **Cross-Compiler Toolchain** | GNU RISC-V GCC (`riscv64-unknown-elf-gcc`) | `riscv64-unknown-elf-gcc -march=rv32imc_zicsr -mabi=ilp32 -mcmodel=medany -Wall -O2 -ffreestanding -nostdlib` | Compiles C/assembly firmware into ELF binaries (`program.elf`) | `Makefile:21-27, 177-182` |
| **Binary Conversion Utilities** | GNU Objcopy / Objdump | `riscv64-unknown-elf-objcopy --change-addresses -0x80000000 -O verilog` | Converts ELF executable into hex memory initialization format (`firmware.hex`) preloaded by Boot ROM | `Makefile:23-24, 183-191` |
| **Interconnect Generator** | Python 3 + Jinja2 | `python scripts/axi_interconnect_wrap.py` | Generates parameterized multi-port AXI interconnect wrappers | `scripts/axi_interconnect_wrap.py:1-25` |
| **UVM Version** | **NONE / NOT FOUND** | No UVM packages, macros, or base classes are utilized in the current environment. | Current testbenches are directed procedural Verilog benches. A UVM verification environment must be created from scratch. | Verified across repository |
| **FPGA / Synthesis Flow** | Incomplete / Not Implemented | `run_xsim.bat:2` invokes `settings64.bat` from Vivado 2023.1; no physical constraints (`*.xdc`) or synthesis run scripts exist. | Functional simulation only; hardware implementation scripts not provided. | `Makefile:1-391`<br>`run_xsim.bat:1-31` |

---

## 4. Boot Execution & Firmware-to-Hardware Interaction Flow

### 4.1 Boot Sequence Execution
1. **Reset Release**:
   - `rst_n` deasserts. VeeR core PC is initialized by hardware to `rst_vec = boot_vector[31:1]` (`soc_top.v:1590`), branching to `0x8000_0000`.
2. **Assembly Startup (`firmware/start.S`)**:
   - `csrw mstatus, zero` and `csrw mie, zero`: Disables interrupts globally (`start.S:6-7`).
   - `csrw 0x7c0, 0x2`: Configures VeeR Machine Region Access Control (MRAC) register to designate memory region `0x0002_xxxx` as side-effect device space (`start.S:9-11`).
   - `li sp, 0xF005_0000`: Sets stack pointer to the top of the 64KB DCCM SRAM (`start.S:14`).
   - Loops from `_sbss` to `_ebss`, clearing uninitialized variables in DCCM to zero (`start.S:16-24`).
   - Branches to `main()` in C runtime (`start.S:26`).
3. **C Runtime Initialization (`main.c` / `test_all.c`)**:
   - Programs UART 16550 baud rate divisor and line control registers.
   - Streams boot banner message through `UART_THR`.

### 4.2 Firmware-to-Custom-IP Interaction Model
Firmware interacts with the custom BMC hardware IPs exclusively through memory-mapped 32-bit word loads and stores across the 64-bit AXI bus:
1. **Watchdog Management**:
   - Firmware initializes `HB_THRESHOLD` (`0x0002_0304`).
   - Arms watchdog by writing `1` to `HB_CTRL.enable` (`0x0002_0300`).
   - In supervisory loop, reads `HB_STATUS` (`0x0002_0308`) to check `unresponsive_flag`.
   - Clears faults by writing `1` to `HB_CTRL.clear_flag`.
2. **Host Reset Activation**:
   - Firmware programs pulse duration into `RST_HOLD_CYCLES` (`0x0002_0404`).
   - Checks `RST_STATUS.in_progress` (`0x0002_0408`) to verify engine is idle.
   - Triggers reset by writing `1` to `RST_CTRL.trigger` (`0x0002_0400`).
   - Polls `RST_STATUS.complete` until pulse deassertion finishes.
3. **Policy Event Stamping & Lockout Check**:
   - Prior to reset, reads uptime counter from `TMR_CTR` (`0x0002_0100`).
   - Writes timestamp into `POL_EVENT_TS` (`0x0002_0510`).
   - Commits event into circular log by writing `1` to `POL_CTRL.record_event` (`0x0002_0500`).
   - Reads `POL_STATUS` (`0x0002_050C`) to check `lockout_flag`; if set, suspends further automatic reboots.
