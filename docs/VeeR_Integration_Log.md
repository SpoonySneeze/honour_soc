# VeeR EL2 SoC Integration Log

This document details the step-by-step process of integrating the Western Digital / CHIPS Alliance VeeR EL2 core into the custom System-on-Chip (SoC).

## 1. Architectural Transition (Wishbone to AXI4)
The original SoC utilized a Wishbone B4 interconnect. The VeeR EL2 core exclusively utilizes AXI4 master interfaces for memory and peripheral access. 
- **AXI Wrappers**: Created AXI4-Lite wrappers for all legacy Wishbone custom IPs (`heartbeat_monitor`, `reset_sequencer`, `recovery_policy`, `vga_controller`).
- **Interconnect Generation**: Utilized the repository's Python scripts to generate a 3x8 AXI4 Interconnect (`axi_interconnect_wrap_3x8.v`) to replace the old 2x7 Wishbone crossbar.

## 2. Interrupt Upgrades
Per architectural requirements, the custom IPs were upgraded to be entirely interrupt-driven, eliminating the need for firmware to waste CPU cycles polling status registers.
- **Heartbeat Monitor**: Already supported a native `hb_irq` for freeze detection.
- **VGA Controller**: Modified the core RTL to expose a `vblank_irq`. This interrupt pulses high at the exact start of the vertical blanking period, allowing firmware to synchronize framebuffer writes without tearing.
- **Recovery Policy**: Modified the core RTL to expose a `lockout_irq`. This fires instantly when the system breaches the maximum allowable recoveries per window, alerting the firmware of a crash-loop.

## 3. External Boot ROM Creation
By default, the VeeR core expects to boot from an internal SRAM (ICCM). To support external boot firmware, an AXI ROM was required.
- **`axi_rom.v`**: Created a lightweight, 8KB AXI4 ROM peripheral.
- **Memory Map**: Mapped to base address `0x8000_0000`.
- **Initialization**: Automatically loads machine code from `firmware.hex` during synthesis/simulation.

## 4. Top-Level Integration (`soc_top.v`)
The `soc_top.v` module was completely rewritten to fuse the VeeR core with the peripheral subsystem.
- **Master Ports**: 
  - Master 0 (`ifu_axi`): Instruction Fetch Unit (Reads instructions from ROM).
  - Master 1 (`lsu_axi`): Load/Store Unit (Reads/Writes data and peripheral registers).
  - Master 2 (`sb_axi`): JTAG System Bus (Allows external debugger to read/write memory without halting the core).
- **Slave Ports**:
  - Slave 0: UART (`0x0002_0000`)
  - Slave 1: Timer (`0x0002_0100`)
  - Slave 2: GPIO (`0x0002_0200`)
  - Slave 3: Heartbeat Monitor (`0x0002_0300`)
  - Slave 4: Reset Sequencer (`0x0002_0400`)
  - Slave 5: Recovery Policy (`0x0002_0500`)
  - Slave 6: VGA Controller (`0x0002_0600`)
  - Slave 7: External Boot ROM (`0x8000_0000`)
- **Interrupt Vectoring**: Wired `uart_irq`, `hb_irq`, `vblank_irq`, and `lockout_irq` directly into VeeR's external interrupt request vector (`extintsrc_req`).

## 5. Tooling and Simulation
Because the VeeR core utilizes advanced SystemVerilog constructs (like the `inside` keyword) that open-source tools like Icarus Verilog do not fully support, the compilation strategy was adjusted for Windows environments lacking Synopsys VCS.
- **Vivado Integration**: Created `run_xsim.bat`, a Windows batch script that automatically parses the VeeR file-list (`flist`) and compiles the entire SoC using Xilinx Vivado Simulator (`xvlog`, `xelab`, `xsim`).
- **Next Steps**: A RISC-V GCC toolchain is required to compile a C/Assembly program into `firmware.hex`. Once the firmware is compiled, `run_xsim.bat` can be executed to observe the VeeR core booting and interacting with the custom IPs in the waveform viewer.
