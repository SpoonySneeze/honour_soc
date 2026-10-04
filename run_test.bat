@echo off
rem ============================================================================
rem Helper script to build any firmware test and run it in Vivado XSIM
rem Usage:
rem   run_test.bat test_timer        (no waveforms)
rem   run_test.bat test_uart 1       (with VCD waveform dumping)
rem ============================================================================

set TEST_TARGET=%1
if "%TEST_TARGET%"=="" set TEST_TARGET=test_uart

rem Prepend test/ if user specified just the test name
if not "%TEST_TARGET:~0,5%"=="test/" if not "%TEST_TARGET%"=="main" set TEST_TARGET=test/%TEST_TARGET%

echo ================================================================
echo  [BUILD] Compiling firmware: %TEST_TARGET%
echo ================================================================
wsl bash -c "rm -f program.elf program.hex firmware.hex && make build_firmware TEST=%TEST_TARGET%"
if %errorlevel% neq 0 (
    echo [ERROR] Firmware cross-compilation failed.
    exit /b %errorlevel%
)

echo ================================================================
echo  [SIM] Launching Vivado XSIM Simulation: %TEST_TARGET%
echo ================================================================
call run_xsim_fw.bat %2
