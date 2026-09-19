# ============================================================================
# Master Makefile for BMC SoC Integration
# ============================================================================
# This Makefile mimics the workflow of the VeeR tools/Makefile, but is
# entirely adapted to build and simulate the FULL SoC top-level with all
# custom IPs and the external AXI ROM.
#
# Available commands:
#   make xsim TEST=firmware  - Cross-compiles C/ASM firmware and simulates in Vivado XSIM
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
export RV_ROOT = rtl/core/Cores-VeeR-EL2
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
.PHONY: xsim
xsim: build_firmware
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
# 5. Simulation Targets (Synopsys VCS on Linux)
# ----------------------------------------------------------------------------
VCS = vcs
VCS_FLAGS = -full64 -sverilog -notice -debug_access+all -quiet -timescale=1ns/1ps

# Gather all SoC files
SOC_FILES = $(wildcard rtl/interconnect/*.v) \
            $(wildcard rtl/custom_ips/*.v) \
            $(wildcard rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/*.v) \
            rtl/soc_top.v \
            tb/tb_soc_top.v

INC_DIRS = +incdir+$(RV_ROOT)/design/include \
           +incdir+$(RV_ROOT)/snapshots/default \
           +incdir+rtl/ips/axi-lite_uart-ipcore-develop/src/include

.PHONY: vcs
vcs: build_firmware
	@echo "================================================================"
	@echo " [SIMULATION] Compiling with Synopsys VCS..."
	@echo "================================================================"
	$(VCS) $(VCS_FLAGS) $(INC_DIRS) -f $(RV_ROOT)/design/flist $(SOC_FILES) -o simv
	@echo "================================================================"
	@echo " [SIMULATION] Running VCS..."
	@echo "================================================================"
	@if [ "$(DEBUG)" = "1" ]; then \
		./simv +vcs+dumpvars+waves.vpd; \
	else \
		./simv; \
	fi

# ----------------------------------------------------------------------------
# 6. Cleanup
# ----------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo "Cleaning firmware binaries and simulator logs..."
	rm -f program.elf program.hex firmware.hex program.dump
	rm -rf xsim.dir *.log *.pb *.jou *.wdb waves.vcd waves.vpd dump.tcl simv* csrc *.daidir
