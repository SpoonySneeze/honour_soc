@echo off
echo "Compiling VeeR Core (SystemVerilog)..."
xvlog -sv -i rtl\core\Cores-VeeR-EL2\design\include -i rtl\core\Cores-VeeR-EL2\snapshots\default rtl\core\Cores-VeeR-EL2\design\lib\el2_assert.sv rtl\core\Cores-VeeR-EL2\design\el2_mubi_pkg.sv rtl\core\Cores-VeeR-EL2\design\el2_veer_wrapper.sv rtl\core\Cores-VeeR-EL2\design\el2_veer_lockstep.sv rtl\core\Cores-VeeR-EL2\design\el2_mem.sv rtl\core\Cores-VeeR-EL2\design\el2_pic_ctrl.sv rtl\core\Cores-VeeR-EL2\design\el2_veer.sv rtl\core\Cores-VeeR-EL2\design\el2_dma_ctrl.sv rtl\core\Cores-VeeR-EL2\design\el2_pmp.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_aln_ctl.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_compress_ctl.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_ifc_ctl.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_bp_ctl.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_ic_mem.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_mem_ctl.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu_iccm_mem.sv rtl\core\Cores-VeeR-EL2\design\ifu\el2_ifu.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec_decode_ctl.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec_gpr_ctl.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec_ib_ctl.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec_pmp_ctl.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec_tlu_ctl.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec_trigger.sv rtl\core\Cores-VeeR-EL2\design\dec\el2_dec.sv rtl\core\Cores-VeeR-EL2\design\exu\el2_exu_alu_ctl.sv rtl\core\Cores-VeeR-EL2\design\exu\el2_exu_mul_ctl.sv rtl\core\Cores-VeeR-EL2\design\exu\el2_exu_div_ctl.sv rtl\core\Cores-VeeR-EL2\design\exu\el2_exu.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_clkdomain.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_addrcheck.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_lsc_ctl.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_stbuf.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_bus_buffer.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_bus_intf.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_ecc.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_dccm_mem.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_dccm_ctl.sv rtl\core\Cores-VeeR-EL2\design\lsu\el2_lsu_trigger.sv rtl\core\Cores-VeeR-EL2\design\dbg\el2_dbg.sv rtl\core\Cores-VeeR-EL2\design\dmi\dmi_mux.v rtl\core\Cores-VeeR-EL2\design\dmi\dmi_wrapper.v rtl\core\Cores-VeeR-EL2\design\dmi\dmi_jtag_to_core_sync.v rtl\core\Cores-VeeR-EL2\design\dmi\rvjtag_tap.v rtl\core\Cores-VeeR-EL2\design\lib\el2_lib.sv rtl\core\Cores-VeeR-EL2\design\lib\el2_mem_if.sv rtl\core\Cores-VeeR-EL2\design\lib\el2_prim_generic_buf.sv rtl\core\Cores-VeeR-EL2\design\lib\el2_prim_buf.sv rtl\core\Cores-VeeR-EL2\design\lib\ahb_to_axi4.sv rtl\core\Cores-VeeR-EL2\design\lib\axi4_to_ahb.sv
if %errorlevel% neq 0 exit /b %errorlevel%

echo "Compiling SoC and Testbench..."
xvlog -i rtl\ips\axi-lite_uart-ipcore-develop\src\include rtl\interconnect\arbiter.v rtl\interconnect\axi_crossbar.v rtl\interconnect\axi_crossbar_addr.v rtl\interconnect\axi_crossbar_rd.v rtl\interconnect\axi_crossbar_wr.v rtl\interconnect\axi_crossbar_wrap_2x1.v rtl\interconnect\axi_interconnect.v rtl\interconnect\axi_interconnect_2x7.v rtl\interconnect\axi_interconnect_wrap_2x7.v rtl\interconnect\axi_interconnect_wrap_3x8.v rtl\interconnect\axi_register_rd.v rtl\interconnect\axi_register_wr.v rtl\interconnect\priority_encoder.v rtl\custom_ips\axi4_to_wb_bridge.v rtl\custom_ips\axi_heartbeat_monitor.v rtl\custom_ips\axi_recovery_policy.v rtl\custom_ips\axi_reset_sequencer.v rtl\custom_ips\axi_rom.v rtl\custom_ips\axi_vga_controller.v rtl\custom_ips\heartbeat_monitor.v rtl\custom_ips\recovery_policy.v rtl\custom_ips\reset_sequencer.v rtl\custom_ips\vga_controller.v rtl\ips\axi-lite_uart-ipcore-develop\src\rtl\axi_internal_fifo.v rtl\ips\axi-lite_uart-ipcore-develop\src\rtl\axi_uart_top.v rtl\ips\axi-lite_uart-ipcore-develop\src\rtl\uart_controller.v rtl\ips\axi-lite_uart-ipcore-develop\src\rtl\uart_parity_bit_compute.v rtl\ips\axi-lite_uart-ipcore-develop\src\rtl\uart_receiver.v rtl\ips\axi-lite_uart-ipcore-develop\src\rtl\uart_transmitter.v rtl\soc_top.v tb\tb_soc_top.v
if %errorlevel% neq 0 exit /b %errorlevel%

echo "Elaborating design..."
xelab -debug typical -top tb_soc_top -snapshot tb_soc_top_snap
if %errorlevel% neq 0 exit /b %errorlevel%

echo "Running simulation..."

if "%1"=="1" (
    echo open_vcd waves.vcd > dump.tcl
    echo log_vcd -recursive * >> dump.tcl
    echo run all >> dump.tcl
    echo close_vcd >> dump.tcl
    echo quit >> dump.tcl
    echo "Running simulation with VCD waveform dumping..."
    xsim tb_soc_top_snap -tclbatch dump.tcl
) else (
    echo "Running simulation (No Waveforms)..."
    xsim tb_soc_top_snap -R
)

