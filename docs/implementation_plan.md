# Initial Project Setup for BMC SoC

This plan outlines the initial directory structure, file scaffolding, and build system setup required to begin development on the BMC SoC project based on the Implementation, Simulation & Verification Plan, the Project Abstract, and the Project Guidelines.

## User Review Required

I have reviewed the `BMC_Project_Abstract.docx` and the `Project Abstract Guidelines.pdf`, as well as your clarification. Since the processor is **VeeR EL2**, we will use an **AXI-lite** bus interconnect instead of Wishbone.

Please review the proposed directory structure and the open questions below. I will proceed with generating these folders and placeholder files once approved.

> [!IMPORTANT]
> **Open Questions:**
> 1. **Simulation Tool:** Which Verilog simulation tool are you required to use for your course: **Icarus Verilog** or **Verilator**?
> 2. **GCC Toolchain:** Do you already have a RISC-V compiler installed? If so, what is the prefix (e.g., `riscv64-unknown-elf-gcc` or `riscv32-unknown-elf-gcc`)?

## Proposed Changes

I will create a standard hardware/firmware co-design project structure.

### Project Scaffolding

#### [NEW] `rtl/` (Hardware Sources)
- `rtl/core/` - To hold the provided RISC-V processor and other mandatory standard IPs (Memory, UART, Timer, GPIO, VGA).
- `rtl/custom/heartbeat_monitor.v` - Placeholder for custom IP #1
- `rtl/custom/reset_sequencer.v` - Placeholder for custom IP #2
- `rtl/custom/recovery_policy.v` - Placeholder for custom IP #3
- `rtl/soc_top.v` - Top-level SoC wrapper

#### [NEW] `tb/` (Testbenches)
- `tb/tb_heartbeat_monitor.v` - Unit testbench
- `tb/tb_reset_sequencer.v` - Unit testbench
- `tb/tb_recovery_policy.v` - Unit testbench
- `tb/tb_soc_top.v` - Full-system testbench

#### [NEW] `fw/` (Firmware / C Application)
- `fw/main.c` - Main application loop
- `fw/console.c` & `fw/console.h` - Command parser
- `fw/drivers/heartbeat.c` & `fw/drivers/heartbeat.h`
- `fw/drivers/reset_seq.c` & `fw/drivers/reset_seq.h`
- `fw/drivers/policy.c` & `fw/drivers/policy.h`
- `fw/drivers/uart.c` & `fw/drivers/uart.h`
- `fw/drivers/vga.c` & `fw/drivers/vga.h`
- `fw/drivers/timer.c` & `fw/drivers/timer.h`

#### [NEW] `Makefile`
- A top-level Makefile containing targets for:
  - Compiling the C firmware to a `.hex`/`.mem` file.
  - Running unit tests for the custom IPs.
  - Running the top-level system simulation.

## Verification Plan

### Automated Tests
Once the placeholder testbenches are set up, I will run the simulator to ensure the build system compiles the empty Verilog modules and firmware successfully.

### Manual Verification
You will be able to run `make` (or specific targets like `make sim`) to verify the toolchain integrates correctly on your machine.
