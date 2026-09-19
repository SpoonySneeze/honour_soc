# BMC SoC Makefile Guide

This repository includes a unified Makefile designed to support both **Synopsys VCS** (for full ASIC/SoC verification) and **Icarus Verilog** (for quick, open-source RTL unit testing).

## Default Behavior
By default, the Makefile uses **Synopsys VCS**. 
If you simply run:
`ash
make
`
It will execute the ll target, which defaults to sim_all, compiling and running all unit tests and system integration tests using VCS.

---

## 1. Synopsys VCS Targets

### Running Simulations
- make sim_all - Runs all unit tests and full SoC simulations sequentially.
- make sim_soc - Runs the full System-on-Chip integration test (Interconnect + Custom IPs).
- make sim_axi - Runs the standalone AXI4 Interconnect arbitration test.
- make sim_hbm - Runs the Heartbeat Monitor unit test.
- make sim_rst - Runs the Reset Sequencer unit test.
- make sim_pol - Runs the Recovery Policy unit test.
- make compile_top - Compiles and elaborates the top-level soc_top.v strictly to check for syntax/structural errors (without running a simulation).

### Waveform Viewing (Verdi)
The VCS testbenches automatically dump .fsdb waveform files. You can open these in Synopsys Verdi:
- make waves_soc - Opens the SoC integration test waveforms in Verdi.
- make waves_axi - Opens the standalone AXI interconnect waveforms in Verdi.

---

## 2. Icarus Verilog Targets

If you do not have a VCS license available, or want to quickly test the Custom IPs using the open-source **Icarus Verilog** (iverilog), you can explicitly invoke the eri_* targets.

### Running Simulations
You can run all Icarus Verilog tests at once using:
`ash
make iverilog veri_all
`
*(Note: The iverilog keyword is an optional flag target that simply echoes your intent; eri_all triggers the actual builds).*

- make veri_all - Runs all Icarus Verilog unit tests sequentially.
- make veri_hbm - Runs the Heartbeat Monitor unit test via Icarus.
- make veri_rst - Runs the Reset Sequencer unit test via Icarus.
- make veri_pol - Runs the Recovery Policy unit test via Icarus.

---

## 3. Utilities

- make clean - Deletes the uild/ directory, compiled binaries (simv), logs, and all waveform files (.fsdb, .vcd). Run this before committing to version control or to force a completely fresh compile.
- make help - Displays a quick reference guide directly in your terminal.
