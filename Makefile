# ============================================================================
# Master Makefile for BMC SoC Integration
# ============================================================================
# This Makefile mimics the workflow of the VeeR tools/Makefile, but is
# entirely adapted to build and simulate the FULL SoC top-level with all
# custom IPs and the external AXI ROM.
#
# Available commands:
#   make sim_xsim TEST=firmware  - Cross-compiles C/ASM firmware and simulates in Vivado XSIM
#   make clean                   - Cleans up logs, firmware build files, and simulator data
# ============================================================================

# ----------------------------------------------------------------------------
# 1. RISC-V Toolchain Configuration
# ----------------------------------------------------------------------------
CROSS_COMPILE ?= riscv64-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump

# We use 32-bit RISC-V with Integer, Multiply, and Compressed Instructions
CFLAGS  = -march=rv32imc -mabi=ilp32 -mcmodel=medany -Wall -O2 -ffreestanding -nostdlib
LDFLAGS = -T firmware/link.ld -nostartfiles -Wl,--no-relax

# Target test program (defaults to 'firmware/main.c')
TEST ?= main
DEBUG ?= 0

# ----------------------------------------------------------------------------
# 2. Firmware Compilation Rules
# ----------------------------------------------------------------------------
.PHONY: build_firmware
build_firmware: program.hex program.dump

# Compile the .elf from C and Assembly source files
program.elf: firmware/start.S firmware/$(TEST).c
	@echo "================================================================"
	@echo " [FIRMWARE] Compiling $(TEST).c ..."
	@echo "================================================================"
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

# Generate the verilog hex memory initialization file
program.hex: program.elf
	@echo " [FIRMWARE] Generating program.hex for AXI ROM..."
	$(OBJCOPY) -O verilog $< $@
	# Rename to firmware.hex because axi_rom.v specifically loads "firmware.hex"
	cp program.hex firmware.hex

# Generate disassembly for debugging
program.dump: program.elf
	@echo " [FIRMWARE] Generating program.dump (disassembly)..."
	$(OBJDUMP) -D $< > $@

# ----------------------------------------------------------------------------
# 3. Simulation Targets (Vivado XSIM Native on Windows/WSL)
# ----------------------------------------------------------------------------
.PHONY: sim_xsim
sim_xsim: build_firmware
	@echo "================================================================"
	@echo " [SIMULATION] Launching Vivado XSIM for Full SoC..."
	@echo "================================================================"
	@# Check if we are running in WSL or native Windows. 
	@# If WSL, we invoke cmd.exe to run the batch script.
	@if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then \
		cmd.exe /c run_xsim.bat $(DEBUG); \
	else \
		./run_xsim.bat $(DEBUG); \
	fi

# ----------------------------------------------------------------------------
# 4. Cleanup
# ----------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo "Cleaning firmware binaries and simulator logs..."
	rm -f program.elf program.hex firmware.hex program.dump
	rm -rf xsim.dir *.log *.pb *.jou *.wdb waves.vcd dump.tcl
