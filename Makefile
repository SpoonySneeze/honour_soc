# ============================================================================
# BMC SoC — Top-Level Makefile
# ============================================================================
# Targets:
#   sim_hbm    — Run Heartbeat Monitor unit test
#   sim_rst    — Run Reset Sequencer unit test
#   sim_pol    — Run Recovery Policy unit test
#   sim_soc    — Run full SoC system integration test
#   sim_all    — Run all tests sequentially
#   waves_*    — Open GTKWave for any test's VCD output
#   clean      — Remove all generated files
# ============================================================================

# Toolchain
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

# Directories
RTL_DIR    = rtl
CUSTOM_DIR = $(RTL_DIR)/custom
TB_DIR     = tb
BUILD_DIR  = build

# Source files — Custom IPs
SRC_HBM = $(CUSTOM_DIR)/heartbeat_monitor.v
SRC_RST = $(CUSTOM_DIR)/reset_sequencer.v
SRC_POL = $(CUSTOM_DIR)/recovery_policy.v
SRC_VGA = $(CUSTOM_DIR)/vga_controller.v
SRC_BRG = $(CUSTOM_DIR)/axi4_to_wb_bridge.v
SRC_WBI = $(CUSTOM_DIR)/wb_interconnect.v

# All custom RTL
SRC_ALL_CUSTOM = $(SRC_HBM) $(SRC_RST) $(SRC_POL) $(SRC_VGA) $(SRC_BRG) $(SRC_WBI)

# Testbenches
TB_HBM = $(TB_DIR)/tb_heartbeat_monitor.v
TB_RST = $(TB_DIR)/tb_reset_sequencer.v
TB_POL = $(TB_DIR)/tb_recovery_policy.v
TB_SOC = $(TB_DIR)/tb_soc_top.v

# Build outputs
OUT_HBM = $(BUILD_DIR)/tb_hbm
OUT_RST = $(BUILD_DIR)/tb_rst
OUT_POL = $(BUILD_DIR)/tb_pol
OUT_SOC = $(BUILD_DIR)/tb_soc

# VCD waveform outputs
VCD_HBM = tb_heartbeat_monitor.vcd
VCD_RST = tb_reset_sequencer.vcd
VCD_POL = tb_recovery_policy.vcd
VCD_SOC = tb_soc_top.vcd

# ============================================================================
# Default target
# ============================================================================
.PHONY: all sim_all sim_hbm sim_rst sim_pol sim_soc waves_hbm waves_rst waves_pol waves_soc clean help

all: sim_all

help:
	@echo "BMC SoC Build System"
	@echo "===================="
	@echo ""
	@echo "Simulation targets:"
	@echo "  sim_hbm    - Heartbeat Monitor unit test"
	@echo "  sim_rst    - Reset Sequencer unit test"
	@echo "  sim_pol    - Recovery Policy unit test"
	@echo "  sim_soc    - Full SoC system integration test"
	@echo "  sim_all    - Run all tests"
	@echo ""
	@echo "Waveform targets:"
	@echo "  waves_hbm  - Open GTKWave for Heartbeat Monitor"
	@echo "  waves_rst  - Open GTKWave for Reset Sequencer"
	@echo "  waves_pol  - Open GTKWave for Recovery Policy"
	@echo "  waves_soc  - Open GTKWave for SoC system test"
	@echo ""
	@echo "Other:"
	@echo "  clean      - Remove all build artifacts"
	@echo "  help       - Show this message"

# ============================================================================
# Create build directory
# ============================================================================
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# ============================================================================
# Unit Test: Heartbeat Monitor
# ============================================================================
$(OUT_HBM): $(SRC_HBM) $(TB_HBM) | $(BUILD_DIR)
	$(IVERILOG) -o $@ $(TB_HBM) $(SRC_HBM)

sim_hbm: $(OUT_HBM)
	@echo ""
	@echo "=============================="
	@echo " Heartbeat Monitor Unit Test"
	@echo "=============================="
	$(VVP) $(OUT_HBM)

# ============================================================================
# Unit Test: Reset Sequencer
# ============================================================================
$(OUT_RST): $(SRC_RST) $(TB_RST) | $(BUILD_DIR)
	$(IVERILOG) -o $@ $(TB_RST) $(SRC_RST)

sim_rst: $(OUT_RST)
	@echo ""
	@echo "=============================="
	@echo " Reset Sequencer Unit Test"
	@echo "=============================="
	$(VVP) $(OUT_RST)

# ============================================================================
# Unit Test: Recovery Policy
# ============================================================================
$(OUT_POL): $(SRC_POL) $(TB_POL) | $(BUILD_DIR)
	$(IVERILOG) -o $@ $(TB_POL) $(SRC_POL)

sim_pol: $(OUT_POL)
	@echo ""
	@echo "=============================="
	@echo " Recovery Policy Unit Test"
	@echo "=============================="
	$(VVP) $(OUT_POL)

# ============================================================================
# System Integration Test
# ============================================================================
$(OUT_SOC): $(SRC_ALL_CUSTOM) $(TB_SOC) | $(BUILD_DIR)
	$(IVERILOG) -o $@ $(TB_SOC) $(SRC_BRG) $(SRC_WBI) $(SRC_HBM) $(SRC_RST) $(SRC_POL)

sim_soc: $(OUT_SOC)
	@echo ""
	@echo "=============================="
	@echo " SoC System Integration Test"
	@echo "=============================="
	$(VVP) $(OUT_SOC)

# ============================================================================
# Run All Tests
# ============================================================================
sim_all: sim_hbm sim_rst sim_pol sim_soc
	@echo ""
	@echo "=============================="
	@echo " All tests completed."
	@echo "=============================="

# ============================================================================
# Waveform Viewing
# ============================================================================
waves_hbm: sim_hbm
	$(GTKWAVE) $(VCD_HBM) &

waves_rst: sim_rst
	$(GTKWAVE) $(VCD_RST) &

waves_pol: sim_pol
	$(GTKWAVE) $(VCD_POL) &

waves_soc: sim_soc
	$(GTKWAVE) $(VCD_SOC) &

# ============================================================================
# Clean
# ============================================================================
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(VCD_HBM) $(VCD_RST) $(VCD_POL) $(VCD_SOC)
	rm -f *.vcd
