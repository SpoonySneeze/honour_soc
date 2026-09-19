#!/bin/csh -f

# ============================================================
# AXI-lite UART IP Core - VCS + Verdi Simulation Script
#
# Usage:
#   ./run.csh compile      Compile UART RTL + testbench (VCS)
#   ./run.csh run          Run simulation
#   ./run.csh verdi        Open Verdi with waveform
#   ./run.csh all          Compile + run
#   ./run.csh clean        Remove all build files
# ============================================================

# ------------------------------------------------------------
# Project directories
# ------------------------------------------------------------

set PROJECT_ROOT = `pwd`

set RTL_DIR   = "$PROJECT_ROOT/src/rtl"
set INC_DIR   = "$PROJECT_ROOT/src/include"
set TB_DIR    = "$PROJECT_ROOT/bench/verilog"
set BUILD_DIR = "$PROJECT_ROOT/sim/vcs"
set LOG_DIR   = "$BUILD_DIR/log"

# ------------------------------------------------------------
# Top module name
# ------------------------------------------------------------
set TOP = "tb_axi_uart"

# ------------------------------------------------------------
# RTL source files (in dependency order)
# ------------------------------------------------------------
set RTL_FILES = ( \
    "$RTL_DIR/uart_parity_bit_compute.v" \
    "$RTL_DIR/uart_transmitter.v" \
    "$RTL_DIR/uart_receiver.v" \
    "$RTL_DIR/uart_controller.v" \
    "$RTL_DIR/axi_internal_fifo.v" \
    "$RTL_DIR/axi_uart_top.v" \
)

set TB_FILE = "$TB_DIR/tb_axi_uart.v"

# ------------------------------------------------------------
# Create build directories if they do not exist
# ------------------------------------------------------------

if ( ! -d "$BUILD_DIR" ) mkdir -p "$BUILD_DIR"
if ( ! -d "$LOG_DIR" )   mkdir -p "$LOG_DIR"

# ============================================================
# COMPILE
# ============================================================

if ( "$1" == "compile" || "$1" == "all" ) then

    echo ""
    echo "=============================================="
    echo " Compiling AXI-lite UART RTL with VCS"
    echo "=============================================="
    echo ""

    rm -rf "$BUILD_DIR/csrc"
    rm -rf "$BUILD_DIR/simv.daidir"
    rm -rf "$BUILD_DIR/DVEfiles"
    rm -f  "$BUILD_DIR/simv"

vcs \
    -full64 \
    -sverilog \
    -debug_access+all \
    -debug_region+cell \
    -kdb \
    -timescale=1ns/1ps \
    +incdir+"$INC_DIR" \
    +incdir+"$RTL_DIR" \
    -top "$TOP" \
    -o "$BUILD_DIR/simv" \
    $RTL_FILES \
    "$TB_FILE" \
    -l "$LOG_DIR/compile.log"

    if ( $status != 0 ) then
        echo ""
        echo "ERROR: VCS compilation failed."
        echo "Check: $LOG_DIR/compile.log"
        echo ""
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Compilation successful"
    echo "=============================================="
    echo ""

endif

# ============================================================
# RUN SIMULATION
# ============================================================

if ( "$1" == "run" || "$1" == "all" ) then

    if ( ! -e "$BUILD_DIR/simv" ) then
        echo ""
        echo "ERROR: simv does not exist. Run: ./run.csh compile"
        echo ""
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Running AXI-lite UART simulation"
    echo "=============================================="
    echo ""

    cd "$BUILD_DIR"

    ./simv \
        +vcs+fsdbon \
        -l "$LOG_DIR/sim.log"

    if ( $status != 0 ) then
        echo ""
        echo "ERROR: Simulation failed. Check: $LOG_DIR/sim.log"
        echo ""
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Simulation finished"
    echo "=============================================="
    echo ""

    cd "$PROJECT_ROOT"

    if ( -e "$BUILD_DIR/wave.fsdb" ) then
        echo "FSDB waveform: $BUILD_DIR/wave.fsdb"
    else
        echo "WARNING: wave.fsdb was not generated."
    endif

    echo ""

endif

# ============================================================
# VERDI
# ============================================================

if ( "$1" == "verdi" ) then

    if ( ! -d "$BUILD_DIR/simv.daidir" ) then
        echo "ERROR: Run ./run.csh compile first"
        exit 1
    endif
    if ( ! -e "$BUILD_DIR/wave.fsdb" ) then
        echo "ERROR: Run ./run.csh run first"
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Launching Verdi"
    echo "=============================================="
    echo ""

    # Use wave.rc if present (for signal grouping)
    set WAVE_RC = "$PROJECT_ROOT/waves/uart_wave.rc"

    if ( -e "$WAVE_RC" ) then
        verdi \
            -dbdir "$BUILD_DIR/simv.daidir" \
            -ssf   "$BUILD_DIR/wave.fsdb" \
            -sswr  "$WAVE_RC" \
            &
    else
        verdi \
            -dbdir "$BUILD_DIR/simv.daidir" \
            -ssf   "$BUILD_DIR/wave.fsdb" \
            &
    endif

endif

# ============================================================
# CLEAN
# ============================================================

if ( "$1" == "clean" ) then

    echo ""
    echo "=============================================="
    echo " Cleaning VCS build"
    echo "=============================================="
    echo ""

    rm -rf "$BUILD_DIR"
    rm -f  "$PROJECT_ROOT/ucli.key"
    rm -f  "$PROJECT_ROOT/novas.conf"
    rm -f  "$PROJECT_ROOT/novas.rc"
    rm -rf "$PROJECT_ROOT/csrc"
    rm -rf "$PROJECT_ROOT/verdiLog"

    echo "Clean complete."
    echo ""

endif

# ============================================================
# HELP / no argument
# ============================================================

if ( "$1" == "" || \
     ( "$1" != "compile" && \
       "$1" != "run"     && \
       "$1" != "verdi"   && \
       "$1" != "all"     && \
       "$1" != "clean" ) ) then

    echo ""
    echo "AXI-lite UART IP Core - VCS + Verdi"
    echo ""
    echo "Usage:"
    echo "  ./run.csh compile   Compile RTL + testbench with VCS"
    echo "  ./run.csh run       Run simulation"
    echo "  ./run.csh verdi     Open Verdi with waveform"
    echo "  ./run.csh all       Compile + simulate"
    echo "  ./run.csh clean     Remove all build files"
    echo ""

endif
