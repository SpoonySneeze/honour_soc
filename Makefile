# ============================================================================
# BMC SoC — Top-Level Makefile (Synopsys VCS & Verdi Toolchain)
# ============================================================================
# Targets:
#   sim_axi     — Run AXI4 Interconnect unit & arbitration test
#   sim_soc     — Run full SoC system integration test (Interconnect + IPs)
#   sim_hbm     — Run Heartbeat Monitor unit test
#   sim_rst     — Run Reset Sequencer unit test
#   sim_pol     — Run Recovery Policy unit test
#   sim_all     — Run all verification tests sequentially
#   compile_top — Compile soc_top.v to verify RTL elaboration (0 errors)
#   waves_axi   — Open Verdi for AXI interconnect waveforms
#   waves_soc   — Open Verdi for SoC system test waveforms
#   clean       — Remove all build artifacts and simulation dumps
# ============================================================================

# Toolchain (Synopsys 64-bit VCS and Verdi)
VCS       = vcs
VCS_FLAGS = -full64 -sverilog +v2k -timescale=1ns/1ps -kdb -debug_access+all -notice
VERDI     = verdi

# Directories
RTL_DIR      = rtl
INTERCON_DIR = $(RTL_DIR)/interconnect
CUSTOM_DIR   = $(RTL_DIR)/custom_ips
TB_DIR       = tb
BUILD_DIR    = build

# Source files — Interconnect
SRC_ALL_INTERCON = $(wildcard $(INTERCON_DIR)/*.v)

# Source files — Custom IPs
SRC_HBM = $(CUSTOM_DIR)/heartbeat_monitor.v
SRC_RST = $(CUSTOM_DIR)/reset_sequencer.v
SRC_POL = $(CUSTOM_DIR)/recovery_policy.v
SRC_VGA = $(CUSTOM_DIR)/vga_controller.v
SRC_BRG = $(CUSTOM_DIR)/axi4_to_wb_bridge.v
SRC_WBI = $(CUSTOM_DIR)/wb_interconnect.v

# All custom RTL
SRC_ALL_CUSTOM = $(SRC_HBM) $(SRC_RST) $(SRC_POL) $(SRC_VGA) $(SRC_BRG) $(SRC_WBI)

# Top-level SoC RTL
SRC_SOC_TOP = $(RTL_DIR)/soc_top.v

# Testbenches
TB_AXI = $(TB_DIR)/tb_axi_interconnect.v
TB_SOC = $(TB_DIR)/tb_soc_top.v
TB_HBM = $(TB_DIR)/tb_heartbeat_monitor.v
TB_RST = $(TB_DIR)/tb_reset_sequencer.v
TB_POL = $(TB_DIR)/tb_recovery_policy.v

# Build simulation targets
OUT_AXI = $(BUILD_DIR)/simv_axi
OUT_SOC = $(BUILD_DIR)/simv_soc
OUT_HBM = $(BUILD_DIR)/simv_hbm
OUT_RST = $(BUILD_DIR)/simv_rst
OUT_POL = $(BUILD_DIR)/simv_pol
OUT_TOP = $(BUILD_DIR)/simv_top

# Waveform outputs
VCD_AXI  = tb_axi_interconnect.vcd
VCD_SOC  = tb_soc_top.vcd
VCD_HBM  = tb_heartbeat_monitor.vcd
VCD_RST  = tb_reset_sequencer.vcd
VCD_POL  = tb_recovery_policy.vcd

FSDB_AXI = tb_axi_interconnect.fsdb
FSDB_SOC = tb_soc_top.fsdb
RC_AXI   = waves/axi_interconnect_wave.rc
RC_SOC   = waves/soc_top_wave.rc

# ============================================================================
# Default target
# ============================================================================
.PHONY: all sim_all sim_axi sim_soc sim_hbm sim_rst sim_pol compile_top waves_axi waves_soc clean help

all: sim_all

help:
	@echo "================================================================"
	@echo " BMC SoC Build & Verification System (Synopsys VCS)"
	@echo "================================================================"
	@echo ""
	@echo "Simulation targets:"
	@echo "  make sim_axi     - Run AXI4 Interconnect test (arbitration, ID, width)"
	@echo "  make sim_soc     - Full SoC system integration test"
	@echo "  make sim_hbm     - Heartbeat Monitor unit test"
	@echo "  make sim_rst     - Reset Sequencer unit test"
	@echo "  make sim_pol     - Recovery Policy unit test"
	@echo "  make sim_all     - Run all tests sequentially"
	@echo "  make compile_top - Verify soc_top.v compilation & elaboration"
	@echo ""
	@echo "Waveform viewing (Verdi):"
	@echo "  make waves_axi   - Open Verdi with AXI interconnect waveforms"
	@echo "  make waves_soc   - Open Verdi with SoC system test waveforms"
	@echo ""
	@echo "Other:"
	@echo "  make clean       - Remove build artifacts, logs, and waveform files"
	@echo "  make help        - Show this message"
	@echo "================================================================"

# ============================================================================
# Create build directory
# ============================================================================
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# ============================================================================
# Target: AXI4 Interconnect Verification
# ============================================================================
$(OUT_AXI): $(SRC_ALL_INTERCON) $(SRC_ALL_CUSTOM) $(TB_AXI) | $(BUILD_DIR)
	@echo ">>> Compiling AXI4 Interconnect Testbench..."
	$(VCS) $(VCS_FLAGS) -o $@ $(SRC_ALL_INTERCON) $(SRC_ALL_CUSTOM) $(TB_AXI)

sim_axi: $(OUT_AXI)
	@echo ""
	@echo "================================================================"
	@echo " Running AXI4 Interconnect Simulation (VCS)"
	@echo "================================================================"
	./$(OUT_AXI) +fsdb

# ============================================================================
# Target: SoC System Integration Test
# ============================================================================
$(OUT_SOC): $(SRC_ALL_INTERCON) $(SRC_ALL_CUSTOM) $(TB_SOC) | $(BUILD_DIR)
	@echo ">>> Compiling SoC System Integration Testbench..."
	$(VCS) $(VCS_FLAGS) -o $@ $(SRC_ALL_INTERCON) $(SRC_ALL_CUSTOM) $(TB_SOC)

sim_soc: $(OUT_SOC)
	@echo ""
	@echo "================================================================"
	@echo " Running SoC System Integration Simulation (VCS)"
	@echo "================================================================"
	./$(OUT_SOC) +fsdb

# ============================================================================
# Unit Test: Heartbeat Monitor
# ============================================================================
$(OUT_HBM): $(SRC_HBM) $(TB_HBM) | $(BUILD_DIR)
	@echo ">>> Compiling Heartbeat Monitor Unit Test..."
	$(VCS) $(VCS_FLAGS) -o $@ $(SRC_HBM) $(TB_HBM)

sim_hbm: $(OUT_HBM)
	@echo ""
	@echo "================================================================"
	@echo " Running Heartbeat Monitor Unit Test (VCS)"
	@echo "================================================================"
	./$(OUT_HBM)

# ============================================================================
# Unit Test: Reset Sequencer
# ============================================================================
$(OUT_RST): $(SRC_RST) $(TB_RST) | $(BUILD_DIR)
	@echo ">>> Compiling Reset Sequencer Unit Test..."
	$(VCS) $(VCS_FLAGS) -o $@ $(SRC_RST) $(TB_RST)

sim_rst: $(OUT_RST)
	@echo ""
	@echo "================================================================"
	@echo " Running Reset Sequencer Unit Test (VCS)"
	@echo "================================================================"
	./$(OUT_RST)

# ============================================================================
# Unit Test: Recovery Policy
# ============================================================================
$(OUT_POL): $(SRC_POL) $(TB_POL) | $(BUILD_DIR)
	@echo ">>> Compiling Recovery Policy Unit Test..."
	$(VCS) $(VCS_FLAGS) -o $@ $(SRC_POL) $(TB_POL)

sim_pol: $(OUT_POL)
	@echo ""
	@echo "================================================================"
	@echo " Running Recovery Policy Unit Test (VCS)"
	@echo "================================================================"
	./$(OUT_POL)

# ============================================================================
# Target: Top-level RTL Syntax & Elaboration Check
# ============================================================================
$(OUT_TOP): $(SRC_ALL_INTERCON) $(SRC_ALL_CUSTOM) $(SRC_SOC_TOP) | $(BUILD_DIR)
	@echo ">>> Compiling full soc_top.v with AXI interconnect and custom IPs..."
	$(VCS) $(VCS_FLAGS) -o $@ $(SRC_ALL_INTERCON) $(SRC_ALL_CUSTOM) $(SRC_SOC_TOP)

compile_top: $(OUT_TOP)
	@echo ""
	@echo "================================================================"
	@echo " soc_top.v RTL compilation & elaboration PASSED (0 errors)!"
	@echo "================================================================"

# ============================================================================
# Run All Tests
# ============================================================================
sim_all: sim_hbm sim_rst sim_pol sim_axi sim_soc
	@echo ""
	@echo "================================================================"
	@echo " All simulation tests completed successfully!"
	@echo "================================================================"

# ============================================================================
# Waveform Viewing (Verdi)
# ============================================================================
waves_axi: sim_axi
	$(VERDI) -ssf $(FSDB_AXI) -sswr $(RC_AXI) &

waves_soc: sim_soc
	$(VERDI) -ssf $(FSDB_SOC) -sswr $(RC_SOC) &

# ============================================================================
# Clean
# ============================================================================
clean:
	rm -rf $(BUILD_DIR)
	rm -rf simv* csrc *.daidir ucli.key vc_hdrs.h *.vpd *.fsdb *.vcd
	rm -rf novas.* verdiLog
	@echo "Clean completed."
