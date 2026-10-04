@echo off
rem ============================================================================
rem Clean script for Windows CMD / PowerShell
rem Removes build artifacts, simulation snapshots, logs, and waveforms
rem ============================================================================

echo Cleaning simulation artifacts, logs, and compiled binaries...

if exist build rmdir /s /q build
if exist obj_dir rmdir /s /q obj_dir
if exist .Xil rmdir /s /q .Xil
if exist xsim.dir rmdir /s /q xsim.dir

del /f /q program.elf program.hex firmware.hex program.dump 2>nul
del /f /q *.log *.pb *.jou *.wdb dump.tcl *.str flist*.tmp 2>nul
del /f /q *.vcd waves.vcd *.fsdb *.vpd ucli.key vc_hdrs.h 2>nul

echo Clean completed.
