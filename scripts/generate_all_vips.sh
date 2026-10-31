#!/usr/bin/env bash
# ============================================================================
# Generate All Individual UVM VIPs for Honour SoC
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${SOC_ROOT}"

echo "[INFO] Generating individual UVM VIPs from docs/interfaces CSVs..."
python3 scripts/uvm_full_tb_generator.py clk_rst   docs/interfaces/clk_rst_interface.csv
python3 scripts/uvm_full_tb_generator.py uart      docs/interfaces/uart_interface.csv
python3 scripts/uvm_full_tb_generator.py gpio      docs/interfaces/gpio_interface.csv
python3 scripts/uvm_full_tb_generator.py vga       docs/interfaces/vga_interface.csv
python3 scripts/uvm_full_tb_generator.py heartbeat docs/interfaces/heartbeat_interface.csv
python3 scripts/uvm_full_tb_generator.py reset_seq docs/interfaces/reset_seq_interface.csv

echo "[INFO] All 6 individual VIP directories successfully generated:"
echo "  - clk_rst_uvm_tb/"
echo "  - uart_uvm_tb/"
echo "  - gpio_uvm_tb/"
echo "  - vga_uvm_tb/"
echo "  - heartbeat_uvm_tb/"
echo "  - reset_seq_uvm_tb/"
echo "[INFO] Wrapped by top-level testbench in soc_top_uvm_tb/"
