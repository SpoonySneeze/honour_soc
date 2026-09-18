# VeeR-EL2: VCS & Verdi Simulation Guide

This guide walks you through setting up and running simulations for the **Cores-VeeR-EL2** project from scratch on a Linux machine that already has Synopsys **VCS** and **Verdi** installed.

> [!IMPORTANT]
> This guide assumes that the `vcs` and `verdi` executables, as well as the RISC-V GCC toolchain (`riscv64-unknown-elf-gcc`), are already in your system's `$PATH`.

## 1. Clone the Repository

Since the `Cores-VeeR-EL2` repository uses submodules (like `picolibc` for firmware), you must clone it recursively. If you have already cloned it, you must initialize the submodules.

```bash
# Clone the repository recursively
git clone --recursive https://github.com/chipsalliance/Cores-VeeR-EL2.git
cd Cores-VeeR-EL2

# If already cloned, initialize submodules like this:
git submodule update --init --recursive
```

## 2. Environment Setup

The build system requires the `RV_ROOT` environment variable to point to the root directory of the VeeR-EL2 repository.

```bash
# Set RV_ROOT to the current directory
export RV_ROOT=$(pwd)
```

## 3. Running Simulations in VCS

The included `tools/Makefile` has native support for Synopsys VCS. 

To compile and run a test program (e.g., `csr_access` or `hello_world`) using VCS, run the following command:

```bash
make -f tools/Makefile vcs TEST=csr_access
```

### Common Flags
- `USER_MODE=1`: Configures the core hardware with User Mode support enabled (required by some tests like `csr_access`).
- `debug=1`: Passes debug flags (`-debug_access+all -kdb`) to the compiler and enables waveform dumping during simulation.

**Example: Running a test with User Mode and Waveform Dumping enabled**
```bash
make -f tools/Makefile vcs TEST=csr_access USER_MODE=1 debug=1
```

## 4. Viewing Waveforms in Verdi

When you compile the simulation with `debug=1`, VCS uses the `-kdb` flag to generate a Knowledge Database, making it extremely easy to load the design into Verdi.

After the simulation finishes, it will generate an `inter.fsdb` (or `simv.vdb` / `sim.fsdb`) waveform file and a `simv.daidir` database in the current directory.

You can launch Verdi to view the results:

```bash
# Launch Verdi and load the VCS Knowledge Database and Waveforms
verdi -ssf inter.fsdb
```
*(Note: If the waveform file is named differently in your VCS environment, such as `novas.fsdb`, replace `inter.fsdb` with that filename).*

> [!TIP]
> If you want to open Verdi interactively *during* the simulation (to single-step through the Verilog code), you can run the generated binary manually with the GUI flag:
> `./simv -gui`
