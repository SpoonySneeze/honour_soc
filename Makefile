# ============================================================================
# Master Makefile for BMC SoC Integration & Verification (Synopsys VCS & Verdi)
# ============================================================================
# Supports:
#   1. Cross-compilation of RISC-V Bare-Metal C/ASM Firmware
#   2. Full SoC + VeeR EL2 Core Simulation with Synopsys VCS & Verdi FSDB dumping
#   3. Peripheral Subsystem Integration Simulation (tb_soc_top)
#   4. Standalone Hardware IP Unit Testbenches (Heartbeat, Reset, Policy, AXI)
#   5. Waveform inspection with Synopsys Verdi
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Environment & Toolchain Configuration
# ----------------------------------------------------------------------------
VCS_HOME             ?= /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME           ?= /home/student/snps_tools_target/verdi/U-2023.03-SP1
SNPSLMD_LICENSE_FILE ?= 27021@14.139.1.126
export VCS_HOME VERDI_HOME SNPSLMD_LICENSE_FILE
export PATH          := $(HOME)/.local/bin:$(VCS_HOME)/bin:$(VERDI_HOME)/bin:$(PATH)

CROSS_COMPILE ?= riscv64-unknown-elf-
CC             = $(CROSS_COMPILE)gcc
OBJCOPY        = $(CROSS_COMPILE)objcopy
OBJDUMP        = $(CROSS_COMPILE)objdump

CFLAGS  = -march=rv32imc_zicsr -mabi=ilp32 -mcmodel=medany -Wall -O2 -ffreestanding -nostdlib -Ifirmware/test -Ifirmware
LDFLAGS = -T firmware/link.ld -nostartfiles -Wl,--no-relax
TEST   ?= main

# VeeR Core Root Path
RV_ROOT ?= $(CURDIR)/rtl/core/Cores-VeeR-EL2
export RV_ROOT

# Simulator & Debug Flags
VCS       = vcs
VCS_FLAGS = -full64 -sverilog +v2k -notice -debug_access+all -kdb -timescale=1ns/1ps +define+SIMULATION=1 +define+GTLSIM=1
VERDI     = verdi

# Build directories & outputs
BUILD_DIR = build

# Include paths for VeeR Core, snapshots, and UART
INC_DIRS = +incdir+$(RV_ROOT)/design/lib \
           +incdir+$(RV_ROOT)/design/include \
           +incdir+$(RV_ROOT)/snapshots/default \
           +incdir+rtl/ips/axi-lite_uart-ipcore-develop/src/include

# Core package and define headers required prior to module compilation
VEER_DEFINES = $(RV_ROOT)/snapshots/default/common_defines.vh \
               $(RV_ROOT)/design/include/el2_def.sv \
               $(RV_ROOT)/snapshots/default/el2_pdef.vh

# Full synthesizable RTL files
SOC_RTL = $(wildcard rtl/interconnect/*.v) \
          $(wildcard rtl/custom_ips/*.v) \
          $(wildcard rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/*.v) \
          rtl/soc_top.v

# Waveform files & Verdi RC layouts
FSDB_CORE = soc_core.fsdb
FSDB_SOC  = tb_soc_top.fsdb
FSDB_AXI  = tb_axi_interconnect.fsdb
RC_SOC    = waves/soc_top_wave.rc
RC_AXI    = waves/axi_interconnect_wave.rc

# ----------------------------------------------------------------------------
# 2. Main Phony Targets
# ----------------------------------------------------------------------------
.PHONY: all default help build_firmware snapshot \
        sim_core vcs_core sim_soc sim_axi sim_hbm sim_rst sim_pol sim_all \
        compile_top waves_core waves_soc waves_axi clean xsim \
        test_uart test_timer test_gpio test_heartbeat test_reset_sequencer \
        test_recovery_policy test_vga test_all_ips run_fw_test

default: help

all: sim_all

help:
	@echo "=================================================================="
	@echo " BMC System-on-Chip: Synopsys VCS & Verdi Verification System"
	@echo "=================================================================="
	@echo ""
	@echo " Firmware Targets:"
	@echo "   make build_firmware [TEST=main]  - Cross-compile C firmware to firmware.hex"
	@echo ""
	@echo " Full SoC Simulation (VeeR Core + AXI ROM + All IPs):"
	@echo "   make sim_core                   - Cross-compiles firmware, compiles with VCS,"
	@echo "                                     runs simulation, prints UART output to terminal,"
	@echo "                                     and dumps soc_core.fsdb for Verdi"
	@echo ""
	@echo " Subsystem & Unit Test Targets (VCS):"
	@echo "   make sim_soc                    - Run full peripheral subsystem testbench"
	@echo "   make sim_axi                    - Run AXI4 Interconnect standalone test"
	@echo "   make sim_hbm                    - Run Heartbeat Monitor unit test"
	@echo "   make sim_rst                    - Run Reset Sequencer unit test"
	@echo "   make sim_pol                    - Run Recovery Policy unit test"
	@echo "   make sim_all                    - Run all unit and integration tests"
	@echo "   make compile_top                - Verify RTL syntax & elaboration of soc_top.v"
	@echo ""
	@echo " Waveform Viewing (Verdi):"
	@echo "   make waves_core                 - Open Verdi with full SoC + VeeR execution waves"
	@echo "   make waves_soc                  - Open Verdi with peripheral subsystem waves"
	@echo "   make waves_axi                  - Open Verdi with AXI interconnect waves"
	@echo ""
	@echo " Other:"
	@echo "   make clean                      - Clean all build files, simv, and waveform logs"
	@echo "   make help                       - Display this reference menu"
	@echo "=================================================================="

# ----------------------------------------------------------------------------
# 3. Directories & Snapshot Generation
# ----------------------------------------------------------------------------
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

snapshot: $(RV_ROOT)/snapshots/default/el2_pdef.vh

$(RV_ROOT)/snapshots/default/el2_pdef.vh:
	@echo ">>> Generating VeeR default snapshot..."
	@mkdir -p $(RV_ROOT)/snapshots/default
	@perl $(RV_ROOT)/configs/veer.config -target=default -set build_axi4
	@cp -r snapshots/default/* $(RV_ROOT)/snapshots/default/ 2>/dev/null || true

# ----------------------------------------------------------------------------
# 4. Firmware Compilation
# ----------------------------------------------------------------------------
build_firmware: program.hex program.dump

program.elf: firmware/start.S firmware/$(TEST).c
	@echo "================================================================"
	@echo " [FIRMWARE] Cross-Compiling firmware/$(TEST).c with $(CC)..."
	@echo "================================================================"
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

program.hex: program.elf
	@echo " [FIRMWARE] Generating verilog hex memory initialization file..."
	$(OBJCOPY) --change-addresses -0x80000000 -O verilog $< $@
	cp program.hex firmware.hex

program.dump: program.elf
	@echo " [FIRMWARE] Disassembling to program.dump..."
	$(OBJDUMP) -D $< > $@

# ----------------------------------------------------------------------------
# 5. Full SoC Simulation (VeeR EL2 + AXI ROM + Peripherals)
# ----------------------------------------------------------------------------
$(BUILD_DIR)/simv_soc_core: snapshot build_firmware tb/tb_soc_core.v $(SOC_RTL) | $(BUILD_DIR)
	@echo "================================================================"
	@echo " [VCS] Compiling Full SoC with VeeR EL2 Core..."
	@echo "================================================================"
	$(VCS) $(VCS_FLAGS) $(INC_DIRS) \
		$(VEER_DEFINES) \
		-f $(RV_ROOT)/design/flist \
		$(SOC_RTL) \
		tb/tb_soc_core.v \
		-o $@

sim_core: $(BUILD_DIR)/simv_soc_core
	@echo "================================================================"
	@echo " [SIMULATION] Running Full SoC Core Simulation (VCS)..."
	@echo "================================================================"
	./$(BUILD_DIR)/simv_soc_core +fsdb

vcs_core: sim_core

run_fw_test:
	@rm -f program.elf program.hex firmware.hex
	$(MAKE) build_firmware TEST=$(TEST)
	@echo "================================================================"
	@echo " [SIMULATION] Running SoC Bare-Metal Test: $(TEST)"
	@echo "================================================================"
	./$(BUILD_DIR)/simv_soc_core

test_uart: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_uart

test_timer: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_timer

test_gpio: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_gpio

test_heartbeat: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_heartbeat

test_reset_sequencer: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_reset_sequencer

test_recovery_policy: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_recovery_policy

test_vga: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_vga

test_all_ips: $(BUILD_DIR)/simv_soc_core
	$(MAKE) run_fw_test TEST=test/test_all

# ----------------------------------------------------------------------------
# 6. Peripheral Subsystem Integration Simulation
# ----------------------------------------------------------------------------
$(BUILD_DIR)/simv_soc: $(SOC_RTL) tb/tb_soc_top.v | $(BUILD_DIR)
	@echo "================================================================"
	@echo " [VCS] Compiling Peripheral Subsystem Testbench..."
	@echo "================================================================"
	$(VCS) $(VCS_FLAGS) \
		+incdir+rtl/ips/axi-lite_uart-ipcore-develop/src/include \
		$(wildcard rtl/interconnect/*.v) \
		$(wildcard rtl/custom_ips/*.v) \
		$(wildcard rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/*.v) \
		tb/tb_soc_top.v \
		-o $@

sim_soc: $(BUILD_DIR)/simv_soc
	@echo "================================================================"
	@echo " [SIMULATION] Running Peripheral Subsystem Simulation (VCS)..."
	@echo "================================================================"
	./$(BUILD_DIR)/simv_soc +fsdb

# ----------------------------------------------------------------------------
# 7. Standalone Unit Tests
# ----------------------------------------------------------------------------
# AXI Interconnect Test
$(BUILD_DIR)/simv_axi: $(wildcard rtl/interconnect/*.v) $(wildcard rtl/custom_ips/*.v) tb/tb_axi_interconnect.v | $(BUILD_DIR)
	@echo ">>> Compiling AXI4 Interconnect Testbench..."
	$(VCS) $(VCS_FLAGS) -o $@ $(wildcard rtl/interconnect/*.v) $(wildcard rtl/custom_ips/*.v) tb/tb_axi_interconnect.v

sim_axi: $(BUILD_DIR)/simv_axi
	@echo ">>> Running AXI4 Interconnect Simulation..."
	./$(BUILD_DIR)/simv_axi +fsdb

# Heartbeat Monitor Unit Test
$(BUILD_DIR)/simv_hbm: rtl/custom_ips/heartbeat_monitor.v rtl/custom_ips/axi_heartbeat_monitor.v tb/tb_heartbeat_monitor.v | $(BUILD_DIR)
	@echo ">>> Compiling Heartbeat Monitor Unit Test..."
	$(VCS) $(VCS_FLAGS) -o $@ rtl/custom_ips/heartbeat_monitor.v rtl/custom_ips/axi_heartbeat_monitor.v tb/tb_heartbeat_monitor.v

sim_hbm: $(BUILD_DIR)/simv_hbm
	@echo ">>> Running Heartbeat Monitor Unit Test..."
	./$(BUILD_DIR)/simv_hbm

# Reset Sequencer Unit Test
$(BUILD_DIR)/simv_rst: rtl/custom_ips/reset_sequencer.v rtl/custom_ips/axi_reset_sequencer.v tb/tb_reset_sequencer.v | $(BUILD_DIR)
	@echo ">>> Compiling Reset Sequencer Unit Test..."
	$(VCS) $(VCS_FLAGS) -o $@ rtl/custom_ips/reset_sequencer.v rtl/custom_ips/axi_reset_sequencer.v tb/tb_reset_sequencer.v

sim_rst: $(BUILD_DIR)/simv_rst
	@echo ">>> Running Reset Sequencer Unit Test..."
	./$(BUILD_DIR)/simv_rst

# Recovery Policy Unit Test
$(BUILD_DIR)/simv_pol: rtl/custom_ips/recovery_policy.v rtl/custom_ips/axi_recovery_policy.v tb/tb_recovery_policy.v | $(BUILD_DIR)
	@echo ">>> Compiling Recovery Policy Unit Test..."
	$(VCS) $(VCS_FLAGS) -o $@ rtl/custom_ips/recovery_policy.v rtl/custom_ips/axi_recovery_policy.v tb/tb_recovery_policy.v

sim_pol: $(BUILD_DIR)/simv_pol
	@echo ">>> Running Recovery Policy Unit Test..."
	./$(BUILD_DIR)/simv_pol

# Top-level RTL Syntax & Elaboration Check
compile_top: snapshot | $(BUILD_DIR)
	@echo ">>> Compiling and elaborating full soc_top.v..."
	$(VCS) $(VCS_FLAGS) $(INC_DIRS) \
		$(VEER_DEFINES) \
		-f $(RV_ROOT)/design/flist \
		$(SOC_RTL) \
		-o $(BUILD_DIR)/simv_top_check
	@echo " soc_top.v RTL compilation & elaboration PASSED (0 errors)!"

# Run All Regression Suites
sim_all: sim_hbm sim_rst sim_pol sim_axi sim_soc sim_core
	@echo ""
	@echo "================================================================"
	@echo " ALL SIMULATION TEST SUITES COMPLETED SUCCESSFULLY!"
	@echo "================================================================"

# ----------------------------------------------------------------------------
# 8. Synopsys Verdi Waveform Viewing
# ----------------------------------------------------------------------------
waves_core:
	$(VERDI) -ssf $(FSDB_CORE) -sswr $(RC_SOC) &

waves_soc:
	$(VERDI) -ssf $(FSDB_SOC) -sswr $(RC_SOC) &

waves_axi:
	$(VERDI) -ssf $(FSDB_AXI) -sswr $(RC_AXI) &

# ----------------------------------------------------------------------------
# 9. Vivado XSIM Target (WSL / Windows compatibility)
# ----------------------------------------------------------------------------
DEBUG ?= 0
xsim: build_firmware
	@if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then \
		cmd.exe /c run_xsim.bat $(DEBUG); \
	else \
		./run_xsim.bat $(DEBUG); \
	fi

# ----------------------------------------------------------------------------
# 10. Cleanup
# ----------------------------------------------------------------------------
clean:
	@echo "Cleaning simulation artifacts, logs, and compiled binaries..."
	rm -rf $(BUILD_DIR)
	rm -f program.elf program.hex firmware.hex program.dump
	rm -rf simv* csrc *.daidir ucli.key vc_hdrs.h *.vpd *.fsdb *.vcd
	rm -rf novas.* verdiLog xsim.dir *.log *.pb *.jou *.wdb dump.tcl
	@echo "Clean completed."
