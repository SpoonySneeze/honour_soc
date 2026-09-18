#!/bin/csh -f

# ============================================================
# AES Core - VCS + Verdi Simulation Script
# Usage:
#   ./run.csh compile          Compile original RTL testbench
#   ./run.csh compile_axi      Compile AXI master testbench
#   ./run.csh run              Run simulation (original TB)
#   ./run.csh run_axi          Run simulation (AXI master TB)
#   ./run.csh verdi            Open Verdi (original TB waves)
#   ./run.csh verdi_axi        Open Verdi (AXI master TB waves)
#   ./run.csh all              Compile + run (original TB)
#   ./run.csh all_axi          Compile + run (AXI master TB)
#   ./run.csh clean            Remove build files
# ============================================================

# ------------------------------------------------------------
# Project directories
# ------------------------------------------------------------

set PROJECT_ROOT = `pwd`

set RTL_DIR   = "$PROJECT_ROOT/rtl/verilog"
set TB_DIR    = "$PROJECT_ROOT/bench/verilog"
set BUILD_DIR = "$PROJECT_ROOT/sim/vcs"
set LOG_DIR   = "$BUILD_DIR/log"

# Build directories for AXI simulation
set BUILD_AXI = "$PROJECT_ROOT/sim/vcs_axi"
set LOG_AXI   = "$BUILD_AXI/log"

# ------------------------------------------------------------
# Top module names
# ------------------------------------------------------------
set TOP     = "test"
set TOP_AXI = "tb_axi_master"

# ------------------------------------------------------------
# Original RTL source files
# ------------------------------------------------------------
set RTL_FILES = ( \
    "$RTL_DIR/timescale.v" \
    "$RTL_DIR/aes_rcon.v" \
    "$RTL_DIR/aes_sbox.v" \
    "$RTL_DIR/aes_inv_sbox.v" \
    "$RTL_DIR/aes_key_expand_128.v" \
    "$RTL_DIR/aes_cipher_top.v" \
    "$RTL_DIR/aes_inv_cipher_top.v" \
)

# AXI wrapper RTL source files (AES IP + AXI wrapper stack)
set RTL_AXI_FILES = ( \
    "$RTL_DIR/timescale.v" \
    "$RTL_DIR/aes_rcon.v" \
    "$RTL_DIR/aes_sbox.v" \
    "$RTL_DIR/aes_inv_sbox.v" \
    "$RTL_DIR/aes_key_expand_128.v" \
    "$RTL_DIR/aes_cipher_top.v" \
    "$RTL_DIR/aes_inv_cipher_top.v" \
    "$RTL_DIR/aes_csr_regs.v" \
    "$RTL_DIR/aes_axi_slave.v" \
    "$RTL_DIR/aes_control_fsm.v" \
    "$RTL_DIR/aes_axi.v" \
)

set TB_FILE     = "$TB_DIR/test_bench_top.v"
set TB_AXI_FILE = "$TB_DIR/tb_axi_master.v"

# ------------------------------------------------------------
# Create directories
# ------------------------------------------------------------

if ( ! -d "$BUILD_DIR" ) mkdir -p "$BUILD_DIR"
if ( ! -d "$LOG_DIR" )   mkdir -p "$LOG_DIR"

# ============================================================
# COMPILE (original testbench)
# ============================================================

if ( "$1" == "compile" || "$1" == "all" ) then

    echo ""
    echo "=============================================="
    echo " Compiling AES RTL with VCS (original TB)"
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
    echo " Compilation successful (original TB)"
    echo "=============================================="
    echo ""

endif

# ============================================================
# COMPILE AXI testbench
# ============================================================

if ( "$1" == "compile_axi" || "$1" == "all_axi" ) then

    echo ""
    echo "=============================================="
    echo " Compiling AES AXI RTL with VCS (AXI master TB)"
    echo "=============================================="
    echo ""

    if ( ! -d "$BUILD_AXI" ) mkdir -p "$BUILD_AXI"
    if ( ! -d "$LOG_AXI" )   mkdir -p "$LOG_AXI"

    rm -rf "$BUILD_AXI/csrc"
    rm -rf "$BUILD_AXI/simv.daidir"
    rm -rf "$BUILD_AXI/DVEfiles"
    rm -f  "$BUILD_AXI/simv"

vcs \
    -full64 \
    -sverilog \
    -debug_access+all \
    -debug_region+cell \
    -kdb \
    -timescale=1ns/1ps \
    +incdir+"$RTL_DIR" \
    -top "$TOP_AXI" \
    -o "$BUILD_AXI/simv" \
    $RTL_AXI_FILES \
    "$TB_AXI_FILE" \
    -l "$LOG_AXI/compile.log"

    if ( $status != 0 ) then
        echo ""
        echo "ERROR: VCS compilation failed."
        echo "Check: $LOG_AXI/compile.log"
        echo ""
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Compilation successful (AXI master TB)"
    echo "=============================================="
    echo ""

endif

# ============================================================
# RUN SIMULATION (original testbench)
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
    echo " Running AES simulation (original TB)"
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
    echo " Simulation finished (original TB)"
    echo "=============================================="
    echo ""

    cd "$PROJECT_ROOT"

    if ( -e "$BUILD_DIR/wave.fsdb" ) then
        echo "FSDB: $BUILD_DIR/wave.fsdb"
    else
        echo "WARNING: wave.fsdb was not generated."
    endif

    echo ""

endif

# ============================================================
# RUN SIMULATION (AXI master testbench)
# ============================================================

if ( "$1" == "run_axi" || "$1" == "all_axi" ) then

    if ( ! -e "$BUILD_AXI/simv" ) then
        echo ""
        echo "ERROR: simv does not exist. Run: ./run.csh compile_axi"
        echo ""
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Running AES AXI simulation (AXI master TB)"
    echo "=============================================="
    echo ""

    cd "$BUILD_AXI"

    ./simv \
        +vcs+fsdbon \
        -l "$LOG_AXI/sim.log"

    if ( $status != 0 ) then
        echo ""
        echo "ERROR: Simulation failed. Check: $LOG_AXI/sim.log"
        echo ""
        exit 1
    endif

    echo ""
    echo "=============================================="
    echo " AXI Simulation finished"
    echo "=============================================="
    echo ""

    cd "$PROJECT_ROOT"

    if ( -e "$BUILD_AXI/wave.fsdb" ) then
        echo "FSDB: $BUILD_AXI/wave.fsdb"
    else
        echo "WARNING: wave.fsdb was not generated."
    endif

    echo ""

endif

# ============================================================
# VERDI (original TB)
# ============================================================

if ( "$1" == "verdi" ) then

    if ( ! -d "$BUILD_DIR/simv.daidir" ) then
        echo "ERROR: Run ./run.csh compile first"; exit 1
    endif
    if ( ! -e "$BUILD_DIR/wave.fsdb" ) then
        echo "ERROR: Run ./run.csh run first"; exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Launching Verdi (original TB)"
    echo "=============================================="
    echo ""

    verdi \
        -dbdir "$BUILD_DIR/simv.daidir" \
        -ssf "$BUILD_DIR/wave.fsdb" \
        &

endif

# ============================================================
# VERDI (AXI master TB)
# ============================================================

if ( "$1" == "verdi_axi" ) then

    if ( ! -d "$BUILD_AXI/simv.daidir" ) then
        echo "ERROR: Run ./run.csh compile_axi first"; exit 1
    endif
    if ( ! -e "$BUILD_AXI/wave.fsdb" ) then
        echo "ERROR: Run ./run.csh run_axi first"; exit 1
    endif

    echo ""
    echo "=============================================="
    echo " Launching Verdi (AXI master TB)"
    echo "=============================================="
    echo ""

    # wave.rc lives in waves/ so it survives clean
    set WAVE_RC = "$PROJECT_ROOT/waves/axi_wave.rc"

    if ( -e "$WAVE_RC" ) then
        verdi \
            -dbdir "$BUILD_AXI/simv.daidir" \
            -ssf   "$BUILD_AXI/wave.fsdb" \
            -sswr  "$WAVE_RC" \
            &
    else
        echo "WARNING: $WAVE_RC not found, opening without signal groups."
        verdi \
            -dbdir "$BUILD_AXI/simv.daidir" \
            -ssf   "$BUILD_AXI/wave.fsdb" \
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
    rm -rf "$BUILD_AXI"

    echo "Clean complete."
    echo ""

endif

# ============================================================
# HELP
# ============================================================

if ( "$1" == "" || \
     ( "$1" != "compile"     && \
       "$1" != "compile_axi" && \
       "$1" != "run"         && \
       "$1" != "run_axi"     && \
       "$1" != "verdi"       && \
       "$1" != "verdi_axi"   && \
       "$1" != "all"         && \
       "$1" != "all_axi"     && \
       "$1" != "clean" ) ) then

    echo ""
    echo "AES Core VCS + Verdi"
    echo ""
    echo "Usage:"
    echo "  ./run.csh compile      Compile original RTL testbench"
    echo "  ./run.csh compile_axi  Compile AXI master testbench"
    echo "  ./run.csh run          Run simulation (original TB)"
    echo "  ./run.csh run_axi      Run simulation (AXI master TB)"
    echo "  ./run.csh verdi        Open Verdi (original TB)"
    echo "  ./run.csh verdi_axi    Open Verdi (AXI master TB)"
    echo "  ./run.csh all          Compile + simulate (original TB)"
    echo "  ./run.csh all_axi      Compile + simulate (AXI master TB)"
    echo "  ./run.csh clean        Remove all build files"
    echo ""

endif
