# SoC Verification Test Plan (Revised Draft)

**Document ID:** `docs/arch/12_test_plan_draft.md`  
**Stage:** Stage 12 — SoC-Level UVM Test Plan, Testbench Architecture, Traceability, and Execution Roadmap  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Synthesized from analysis in [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) through [`docs/arch/11_agent_interfaces.md`](file:///home/student/sriv_183/honour_soc/docs/arch/11_agent_interfaces.md), corrected and expanded in accordance with [`docs/arch/13_consistency_audit.md`](file:///home/student/sriv_183/honour_soc/docs/arch/13_consistency_audit.md) and Task 14 resolutions.

---

## 1. Scope & Verification Strategy

### 1.1 Scope
This test plan defines the complete verification scope for the Honour SoC, encompassing the VeeR EL2 RISC-V core integration, the 64-bit AXI4 crossbar interconnect, memory sub-systems (Boot ROM, DCCM), legacy peripherals (16550 UART, Timer, GPIO, VGA), and dedicated BMC custom security IPs (`heartbeat_monitor`, `reset_sequencer`, `recovery_policy`).

Following architectural resolutions from the consistency audit and RTL deep-dives:
- **Interconnect Slave Mapping**: Verified as M00=UART, M01=Timer, M02=GPIO, M03=Heartbeat, M04=Reset Sequencer, M05=Recovery Policy, M06=VGA, M07=Boot ROM.
- **Lockout Mechanism**: Verified as **firmware-enforced**. Hardware contains no interlock blocking `reset_sequencer` when `recovery_policy.lockout_flag` is asserted. Test plan explicitly validates this architectural boundary.
- **Single Synchronous Clock**: Verified that the VGA controller operates entirely on `clk` (100 MHz) with a synchronous 1-in-4 clock enable (`pixel_clk_en`); asynchronous CDC test requirements are eliminated.
- **Memory Subsystems**: Verified that the core boots from Boot ROM (`0x8000_0000`) and executes with 64KB DCCM (`0xF004_0000`); ICCM is confirmed tied off.

Verification is executed across two distinct environments:
1. **Full-SoC System Level**: Employs the complete top-level netlist (`soc_top.v`) with compiled firmware running on the VeeR core. Validates end-to-end system control flows, interrupt dispatch, cold boot, and real-time BMC remediation behavior.
2. **Subsystem Core-Stubbed Level**: Replaces `u_veer` with an active AXI4 Master VIP driving Master S01 (LSU). Enables rapid, high-coverage directed stimulus for register models, bus stress testing, illegal address fault injection, and arbitration boundary testing without firmware compile overhead.

### 1.2 Verification Exit Criteria
Sign-off requires achieving all of the following quantified milestones:
- **Functional Coverage**: 100% coverage of all defined covergroups across the 44 features cataloged in [`docs/arch/10_features.md`](file:///home/student/sriv_183/honour_soc/docs/arch/10_features.md) and tracked in the traceability matrix.
- **Code Coverage**: 100% statement, 95%+ branch, and 90%+ condition coverage on all custom IPs (`heartbeat_monitor.v`, `reset_sequencer.v`, `recovery_policy.v`, `axi_interconnect.v`, and peripheral wrappers).
- **Assertion Coverage**: 100% pass rate on all SystemVerilog Assertions (SVA) with zero failures or unexpected vacuous triggers.
- **Regression Robustness**: 100% test pass rate across a **500-seed randomized regression suite restricted to the high-speed core-stubbed subsystem testbench** (full-SoC firmware runs targeted directed regression suites).
- **Open Questions Resolution**: Resolution and closure of all open architecture questions documented in [`docs/arch/09_open_questions.md`](file:///home/student/sriv_183/honour_soc/docs/arch/09_open_questions.md).

---

## 2. UVM Testbench Architecture Summary

```
                      +-------------------------------------------------------------+
                      |                      uvm_test_top                           |
                      |                                                             |
                      |  +-------------------------------------------------------+  |
                      |  |                   soc_virtual_sequencer               |  |
                      |  +-------------------------------------------------------+  |
                      |       |             |             |                         |
                      |  +----+----+   +----+----+   +----+----+                    |
                      |  | Clk/Rst |   |   HB    |   |  UART   |                    |
                      |  |  Agent  |   |  Agent  |   |  Agent  |                    |
                      |  +---------+   +---------+   +---------+                    |
                      |       |             |             |                         |
                      |  +-------------------------------------------------------+  |
                      |  |                   soc_env_top                         |  |
                      |  |                                                       |  |
                      |  |  +-------------------+        +--------------------+  |  |
                      |  |  |  soc_scoreboard   |        |  uvm_reg_predictor |  |  |
                      |  |  +-------------------+        +--------------------+  |  |
                      |  |            ^                            ^             |  |
                      |  |            |                            |             |  |
                      |  |  +---------+---------+        +---------+----------+  |  |
                      |  |  | Rst_Out Passive   |        | PIC IRQ Passive    |  |  |
                      |  |  | Monitor           |        | Monitor            |  |  |
                      |  |  +-------------------+        +--------------------+  |  |
                      |  |            |                            |             |  |
                      |  |  +---------+---------+        +---------+----------+  |  |
                      |  |  | VGA Passive       |        | AXI Slave Monitors |  |  |
                      |  |  | Monitor           |        | (M00..M07)         |  |  |
                      |  |  +-------------------+        +--------------------+  |  |
                      |  +-------------------------------------------------------+  |
                      +-------------------------------------------------------------+
                                                     |
                                   [ Boundary Pins & Hierarchical Binds ]
                                                     |
                      +-------------------------------------------------------------+
                      |                         soc_top                             |
                      |                                                             |
                      |   [ VeeR Core ] <---> [ 3x8 AXI Crossbar ] <---> [ IPs ]    |
                      +-------------------------------------------------------------+
```

### 2.1 Component Architecture & Register Test Exclusions
- **Agents**:
  - `clk_rst_agent` (Active): Drives 100 MHz clock and asserts/deasserts `rst_n`.
  - `heartbeat_agent` (Active): Generates pulse trains, jitter, and glitch bursts on `heartbeat_in`.
  - `uart_agent` (Active): Bidirectional serial agent on `uart_rx` and `uart_tx`.
  - `reset_out_monitor` (Passive): Samples `reset_out` pad, measures pulse width, and verifies glitch freedom.
  - `vga_monitor` (Passive): Samples `vga_hsync`, `vga_vsync`, and `vga_rgb[11:0]`; reconstructs character buffer text.
  - `pic_irq_monitor` (Passive): Taps `extintsrc_req[31:0]` inside `soc_top.v:1600`.
- **Register Model Exclusions for `uvm_reg_hw_reset_seq`**:
  - `TMR_CTR` (Slave M01): Excluded because monotonic hardware clock counter increments immediately after reset release.
  - `GPIO_STAT` (Slave M02): Excluded because register reflects dynamic external pin inputs (`heartbeat_in`, `reset_out_internal`).
  - `HB_ELAPSED` (Slave M03): Excluded from static readback if watchdog is actively running.
  - `UART_RBR` (Slave M00): Excluded because read access pops character from internal RX FIFO.
- **Register Model Exclusions for `uvm_reg_bit_bash_seq`**:
  - `RST_CTRL` (Slave M04, offset `0x00`): Excluded because writing bit 0 launches physical host reset pulse with hardware side effects.
  - `HB_CTRL` (Slave M03, offset `0x00`): Excluded because writing bit 0 mutates watchdog FSM state; bit 1 is a self-clearing command.
  - `POL_CTRL` (Slave M05, offset `0x00`): Excluded because bit 0 commits failure records to circular RAM; bit 1 clears lockout.
  - `UART_FCR` (Slave M00, offset `0x08`): Excluded because bits 1 and 2 reset internal FIFOs.
  - `UART_THR` (Slave M00, offset `0x00`): Excluded because writing launches transmission serializer.
  - `UART_LCR` (Slave M00, offset `0x0C`): Excluded because bit 7 modifies DLAB mode, dynamically remapping offsets `0x00` and `0x04`.
  - All Read-Only registers (`TMR_CTR`, `GPIO_STAT`, `HB_STATUS`, `HB_ELAPSED`, `RST_STATUS`, `POL_STATUS`, `LOG_READ_DATA`, `LOG_COUNT`, `UART_LSR`, `UART_MSR`, `UART_IIR`, `VGA_STATUS`).

---

## 3. SoC Verification Test Plan Table

| Test ID | Category | Feature ID(s) | Path / Interface | Scenario Description | Stimulus Idea | Checking Method | Coverage Item | Proposed Test Name | Priority & Notes |
|---|---|---|---|---|---|---|---|---|---|
| **TP-RST-01** | Reset & Boot | `SOC-RST-001`<br>`SOC-CLK-001` | S00, Boot ROM, `rst_n` | Power-on cold reset deassertion and first instruction fetch from `0x8000_0000`. | Assert `rst_n` low for 100 cycles, deassert synchronously. | SVA / protocol monitor checks first read address on S00 (`ifu_axi_araddr`) is exactly `0x8000_0000`. | `cg_boot_vector` | `soc_cold_boot_test` | **HIGH** |
| **TP-RST-02** | Reset & Boot | `SOC-RST-002`<br>`SOC-RST-006` | `reset_out` pad, `u_veer` | Verify `reset_out` defaults to 1 and core is NOT reset when `reset_out` asserts. | Trigger host reset; observe internal core execution uninterrupted. | SVA checks `reset_out` glitch-free high at power-up; monitor checks CPU PC advances. | `cg_reset_out_state` | `soc_rst_isolation_test` | **HIGH** |
| **TP-RST-03** | Reset & Boot | `SOC-RST-003`<br>`SOC-RST-004`<br>`SOC-RST-005` | M04, `reset_out` pad | Reset Sequencer pulse duration accuracy. | Program `RST_HOLD_CYCLES` = 50, 100, 1000; write `RST_CTRL.trigger=1`. | `reset_out_monitor` measures low cycle duration; checks `RST_STATUS.complete` sets to 1. | `cg_rst_duration_bins` | `soc_rst_seq_duration_test` | **HIGH** |
| **TP-RST-04** | Reset & Boot | `SOC-RST-007` | M02, `reset_out` | Host `reset_out` GPIO loopback readback. | Trigger reset sequencer; read `GPIO_STAT[1]` before, during, and after pulse. | Compare register read data against physical `reset_out` state. | `cg_gpio_status_read` | `soc_rst_gpio_loopback_test` | **LOW** |
| **TP-DEC-01** | Address Decode | `SOC-DEC-001`<br>`SOC-DEC-002`<br>`SOC-DEC-003`<br>`SOC-DEC-005` | S01, Crossbar M00–M07 | Comprehensive address decode check across all valid memory and peripheral windows. | Sweep read/write accesses across boundary base addresses and limits of all 8 slaves. | Bus scoreboard checks correct slave selected without hang. | `cg_address_decode_map` | `soc_addr_decode_sweep_test` | **HIGH** |
| **TP-DEC-02** | Address Decode | `SOC-DEC-004`<br>`SOC-ERR-002` | S01, Crossbar | Access to unmapped address holes returns AXI `DECERR`. | Inject reads and writes to unmapped regions (e.g. `0x0001_0000`, `0x0002_0700`, `0x8001_0000`). | Protocol monitor verifies `rresp == 2'b11` and `bresp == 2'b11`. | `cg_unmapped_decerr` | `soc_unmapped_decerr_test` | **HIGH** |
| **TP-DEC-03** | Address Decode | `SOC-DEC-006` | S02 (System Bus / JTAG), M00–M06 | Master S02 interconnect masking verification (Configurable Knob). | Drive transactions from S02 to peripheral addresses `0x0002_0000`–`0x0002_0600`. | Controlled by TB knob `cfg_expect_s02_decerr`: if 1, expects `DECERR` (`2'b11`); if 0 (patched RTL), expects `OKAY` (`2'b00`). | `cg_s02_masked_access` | `soc_s02_intercon_mask_test` | **HIGH**<br>*(Configurable via OQ-03)* |
| **TP-DEC-04** | Address Decode | `SOC-DEC-007` | S02, M07 (Boot ROM) | Master S02 access to Boot ROM. | Drive reads from S02 to `0x8000_0000`–`0x8000_0100`. | Bus scoreboard checks valid data return with `rresp == 2'b00` (`OKAY`). | `cg_s02_rom_read` | `soc_s02_rom_access_test` | **MEDIUM** |
| **TP-DEC-05** | Address Decode | `SOC-DEC-003` | S01, M00–M06 | In-window undecoded offset accesses returning `OKAY`. | Inject reads and writes to offsets `0x20`–`0xFC` within each 256-byte peripheral window. | Protocol monitor verifies `rresp == 2'b00` (`OKAY`) with 0 data, and `bresp == 2'b00` (`OKAY`) with write ignored. | `cg_inwindow_undecoded_okay` | `soc_inwindow_undecoded_test` | **MEDIUM** |
| **TP-REG-01** | Register Access | `SOC-REG-001`<br>`SOC-REG-003`<br>`SOC-REG-004`<br>`SOC-REG-006`<br>`SOC-REG-007`<br>`SOC-REG-008` | M00–M06 | Standard register read/write, reset default, and bitmask walk across custom IPs. | UVM RAL built-in sequences (`uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq`) with defined exclusions. | UVM register model predictor compares RTL readback against mirror. | `cg_reg_field_coverage` | `soc_reg_hw_reset_bash_test` | **HIGH** |
| **TP-REG-02** | Register Access | `SOC-REG-002` | M03, `hb_irq` | Write-1-to-clear (W1C) verification on `HB_CTRL.clear_flag`. | Trigger timeout; verify `unresponsive_flag=1` and `hb_irq=1`; write 1 to `HB_CTRL[1]`; verify flag=0 and `hb_irq=0`. | Monitor checks register clears and interrupt line deasserts within 1 cycle. | `cg_w1c_clearing` | `soc_hb_w1c_clear_test` | **HIGH** |
| **TP-REG-03** | Register Access | `SOC-REG-009` | M00–M06 | Read-only register enforcement. | Attempt writes with `0xFFFF_FFFF` to read-only counters and status registers (`TMR_CTR`, `GPIO_STAT`, `HB_STATUS`, `RST_STATUS`, `POL_STATUS`). | Read back registers; verify values did not mutate. | `cg_ro_write_discard` | `soc_ro_reg_protection_test` | **MEDIUM** |
| **TP-REG-04** | Register Access | `SOC-REG-010` | M05 | Event log indexed readback via `LOG_READ_IDX` and `LOG_READ_DATA`. | Log 5 failure events; program index 0 through 4 into `LOG_READ_IDX` and read `LOG_READ_DATA`. | Direct comparison of read timestamps against recorded event times. | `cg_log_indexed_read` | `soc_pol_log_readout_test` | **MEDIUM** |
| **TP-REG-05** | Register Access | `SOC-REG-011` | M06 | VGA character buffer memory-mapped read and write access. | Write ASCII string into `VGA_BASE + 0x08` through `0x7C`; read back words. | Scoreboard compares readback against written character words. | `cg_vga_buffer_access` | `soc_vga_buffer_rw_test` | **LOW** |
| **TP-REG-06** | Register Access | `SOC-REG-005` | M05 | `POL_CTRL.clear_lockout` register mechanics and state clearing. | Force `lockout_flag=1`; write 1 to `POL_CTRL[1]`; verify `lockout_flag` clears to 0 and `window_recovery_count` resets to 0. | Register model checks status clear within 1 cycle. | `cg_clear_lockout_reg` | `soc_pol_clear_lockout_test` | **HIGH** |
| **TP-DAT-01** | Data Path | `SOC-DAT-002` | S01, DCCM | DCCM byte and half-word enable precision (`wstrb`). | Write byte patterns `0xAA`, `0x55` at odd and even offsets; verify adjacent bytes uncorrupted. | Memory model verifies byte-lane strobe fidelity. | `cg_wstrb_byte_lanes` | `soc_dccm_byte_strobe_test` | **HIGH** |
| **TP-DAT-02** | Data Path | `SOC-DAT-003` | M00 (UART), S01 | UART 64-to-32 bit bus gasket steering based on address bit `[2]`. | Alternate write/read transactions targeting odd and even word offsets of UART. | SVA checks data steering across `uart_awaddr2_r` without byte corruption. | `cg_uart_gasket_steering` | `soc_uart_gasket_lane_test` | **HIGH** |
| **TP-DAT-03** | Data Path | `SOC-DAT-004`<br>`SOC-DAT-005` | `uart_rx`, `uart_tx` pads, M00 | UART character loopback and FIFO buffering under baud rate variations. | Transmit 64 ASCII bytes into `uart_rx`; read back via `RBR`; transmit via `THR`. | Scoreboard compares transmitted characters byte-for-byte. | `cg_uart_fifo_depth` | `soc_uart_loopback_test` | **MEDIUM** |
| **TP-DAT-04** | Data Path | `SOC-DAT-006` | M06, VGA pads | VGA display character rendering and 12-bit RGB raster output. | Write test string into buffer; observe `vga_rgb[11:0]` stream during active display. | Scoreboard matches RGB color codes (`12'h0F0` text, `12'h001` background) to buffer characters. | `cg_vga_raster_rgb` | `soc_vga_raster_test` | **LOW** |
| **TP-DAT-05** | Data Path | `SOC-DAT-001` | S00, M07 (Boot ROM) | 64-bit instruction burst fetching from Boot ROM to VeeR IFU. | Trigger dense instruction fetch loops; monitor multi-beat AXI read burst transactions. | SVA checks `m07_axi_rdata[63:0]` transfer without width truncation or beat drops. | `cg_rom_burst_fetch` | `soc_rom_burst_fetch_test` | **HIGH** |
| **TP-DAT-06** | Data Path | `SOC-DAT-007` | M00–M06, Crossbar | AXI slave backpressure handling and stall tolerance. | Inject random slave stalls by deasserting `awready`, `wready`, and `arready` dynamically. | Scoreboard verifies zero transaction drop or bus deadlock under backpressure. | `cg_slave_backpressure` | `soc_axi_backpressure_test` | **HIGH** |
| **TP-CTRL-01** | Control Path | `SOC-CTRL-001`<br>`SOC-CTRL-002` | `heartbeat_in`, M03 | Heartbeat edge detection and counter reset. | Drive `heartbeat_in` pulse trains with varying pulse widths and intervals. | SVA verifies `hb_counter` resets to 0 on every rising edge. | `cg_hb_pulse_interval` | `soc_hb_pulse_detect_test` | **HIGH**<br>*(Depends on OQ-09)* |
| **TP-CTRL-02** | Control Path | `SOC-CTRL-003` | `heartbeat_in`, `hb_irq`, M03 | Heartbeat timeout expiration and IRQ assertion. | Stop `heartbeat_in` pulses; allow `hb_counter` to exceed `HB_THRESHOLD`. | Monitor verifies `unresponsive_flag` sets and `hb_irq` asserts on exact cycle. | `cg_hb_timeout_detect` | `soc_hb_timeout_irq_test` | **HIGH** |
| **TP-CTRL-03** | Control Path | `SOC-CTRL-006` | M04 | Reset Sequencer trigger rejection during active countdown. | Trigger reset; while `rst_state != IDLE`, issue second trigger write. | SVA verifies secondary trigger is ignored; countdown continues uninterrupted. | `cg_rst_retrigger_reject` | `soc_rst_retrigger_reject_test` | **HIGH** |
| **TP-CTRL-04** | Control Path | `SOC-CTRL-007`<br>`SOC-CTRL-008`<br>`SOC-CTRL-009` | M05, `lockout_irq` | Crash-loop lockout trigger upon exceeding threshold within rolling window. | Pulse `POL_CTRL.record_event` rapidly $N$ times ($N \ge \text{POL\_THRESHOLD}$). | Monitor verifies `lockout_flag` sets and `lockout_irq` single-cycle pulse asserts. | `cg_lockout_trigger` | `soc_crash_loop_lockout_test` | **HIGH** |
| **TP-CTRL-05** | Control Path | `SOC-CTRL-010` | M05 | Rolling window counter expiration and recovery count decay. | Record 2 events; wait until `window_counter >= POL_WINDOW`; inject 1 event. | Check `window_recovery_count` reset to 0 at window boundary, preventing premature lockout. | `cg_window_rollover` | `soc_window_expiration_test` | **HIGH** |
| **TP-CTRL-06** | Control Path | `SOC-CTRL-010` | M05 | Lockout persistence across rolling window boundaries. | Drive system into lockout (`lockout_flag=1`); allow `window_counter` to reach `POL_WINDOW` and roll over. | Scoreboard verifies `lockout_flag` remains 1; lockout is sticky and unaffected by window reset. | `cg_lockout_window_persistence` | `soc_lockout_persistence_test` | **HIGH** |
| **TP-CTRL-07** | Control Path | `SOC-CTRL-004` | M03 | Heartbeat monitor disable & flush behavior. | While counting, write `HB_CTRL.enable=0`. | SVA verifies FSM enters `ST_DISABLED`, `hb_counter` flushes to 0, and flags clear. | `cg_hb_disable_flush` | `soc_hb_disable_flush_test` | **MEDIUM** |
| **TP-CTRL-08** | Control Path | `SOC-CTRL-005` | M04 | Reset Sequencer 3-state FSM state transitions. | Trigger reset; track state through `ST_IDLE (00) -> ST_ASSERT (01) -> ST_DEASSERT (10) -> ST_IDLE (00)`. | SVA verifies exact state sequence and complete flag assertion in `ST_DEASSERT`. | `cg_rst_fsm_states` | `soc_rst_fsm_transitions_test` | **HIGH** |
| **TP-ARB-01** | Arbitration | `SOC-ARB-001` | S00, S01, Crossbar | Multi-master simultaneous contention for Boot ROM and DCCM. | Generate concurrent continuous reads from S00 and writes from S01 to same slave. | Scoreboard checks round-robin grant alternation and zero deadlocks. | `cg_arbiter_fairness` | `soc_multimaster_contention_test` | **HIGH** |
| **TP-ARB-02** | Arbitration | `SOC-ARB-003` | S01, Crossbar | Address and Data channel phase skew and backpressure stalls. | Inject delays between `AWVALID` and `WVALID` handshakes (0 to 20 cycles). | SVA checks transaction completion without data loss or lane corruption. | `cg_channel_skew_delay` | `soc_axi_phase_skew_test` | **HIGH** |
| **TP-ARB-03** | Arbitration | `SOC-ARB-002` | Crossbar M00–M07 | Concurrent non-conflicting read and write channels across multiple slaves. | Issue simultaneous read to ROM (M07) and write to Timer (M01) from separate masters. | Scoreboard checks transactions execute concurrently without mutual blocking. | `cg_full_duplex_throughput` | `soc_crossbar_concurrent_rw_test` | **MEDIUM** |
| **TP-ARB-04** | Arbitration | `SOC-ARB-004` | S00, S01, Crossbar | Crossbar burst atomicity across multi-beat bursts. | Master S00 executes 8-beat burst to ROM; Master S01 injects write requests during burst. | SVA verifies arbiter locks grant until `RLAST` asserts, preventing burst interleaving. | `cg_burst_atomicity` | `soc_burst_atomicity_test` | **HIGH** |
| **TP-IRQ-01** | Interrupts | `SOC-IRQ-001` through `SOC-IRQ-004` | PIC, `extintsrc_req` | Complete interrupt generation and PIC vector dispatch for all 4 peripherals. | Trigger conditions for UART, Watchdog, VGA, and Lockout interrupts sequentially. | Monitor checks corresponding bit in `extintsrc_req` asserts with exact cycle latency. | `cg_pic_irq_delivery` | `soc_peripheral_irq_map_test` | **HIGH**<br>*(Depends on OQ-10)* |
| **TP-IRQ-02** | Interrupts | `SOC-IRQ-005` | PIC, `u_veer` | PIC interrupt arbitration and priority preemption inside core. | Assert multiple peripheral interrupts simultaneously; verify PIC preemption order. | Monitor checks core takes trap and services highest priority interrupt first. | `cg_pic_priority_preempt` | `soc_pic_preemption_test` | **HIGH** |
| **TP-ERR-01** | Error & Recovery | `SOC-ERR-003` | S01, M07 (Boot ROM) | Boot ROM write transaction handling. | Drive write transaction to ROM address window `0x8000_0000`. | Monitor checks write response completion without crossbar hang (OQ-06). | `cg_rom_write_response` | `soc_rom_write_reject_test` | **MEDIUM**<br>*(Depends on OQ-06)* |
| **TP-ERR-02** | Error & Recovery | `SOC-ERR-004` | M05 | Circular event log RAM wrap-around after 16 failure records. | Inject 20 consecutive `record_event` pulses; read out all 16 entries via `LOG_READ_IDX`. | Verify slots 0–3 contain timestamps from events 16–19 (circular wrap). | `cg_log_wrap_around` | `soc_log_circular_wrap_test` | **HIGH** |
| **TP-ERR-03** | Error & Recovery | `SOC-ERR-005` | Full SoC Top | Firmware-enforced lockout suppression verification. | Place SoC in lockout (`lockout_flag=1`); execute firmware reset routine; verify firmware refrains from writing `RST_CTRL.trigger`. | Monitor confirms `reset_out` remains high; confirms firmware enforces policy. | `cg_firmware_lockout_check` | `soc_firmware_lockout_test` | **HIGH** |
| **TP-ERR-04** | Error & Recovery | `SOC-ERR-005` | S01, M04, M05 | Core-stubbed verification that `RST_CTRL.trigger` fires `reset_out` even when `lockout_flag=1`. | Assert `lockout_flag=1`; from Master VIP (S01), issue write to `RST_CTRL.trigger=1`. | Passive monitor observes `reset_out` asserts low, proving hardware lacks lockout interlock. | `cg_hw_lockout_isolation` | `soc_stubbed_lockout_trigger_test` | **HIGH** |
| **TP-ERR-05** | Error & Recovery | `SOC-ERR-001`<br>`SOC-ERR-002` | S01, Crossbar | Out-of-bounds MMIO read and write precise `DECERR` handling. | Drive out-of-bounds reads and writes to unmapped crossbar holes. | Protocol monitor verifies `rresp == 2'b11` and `bresp == 2'b11`; bus continues operating normally. | `cg_out_of_bounds_decerr` | `soc_mmio_out_of_bounds_test` | **HIGH** |
| **TP-CLK-01** | Clock & Reset | `SOC-CLK-003` | `clk`, `u_vga` | Synchronous video clock enable operation (`pixel_clk_en`). | Run video display engine continuously; verify beam counters advance every 4 system clock cycles. | SVA checks `pixel_clk_en` 1-in-4 cadence and synchronous scan timing. | `cg_pixel_clk_cadence` | `soc_vga_sync_clock_test` | **MEDIUM** |
| **TP-CLK-02** | Clock & Reset | `SOC-CLK-001`<br>`SOC-CLK-002` | `rst_n`, `u_veer`, Peripherals | System synchronous reset deassertion and core warm reset sequence. | Toggle `rst_n` with asynchronous assertion and synchronous deassertion. | SVA verifies all IP registers reach valid reset states without meta-stability. | `cg_sync_reset_release` | `soc_sync_reset_release_test` | **HIGH** |
| **TP-CLK-03** | Clock & Reset | `SOC-CLK-004` | `jtag_tck`, `clk`, JTAG TAP | JTAG clock domain crossing double-flop synchronizer verification. | Inject asynchronous JTAG scan chains across wide clock frequency ratios (5 MHz to 25 MHz). | SVA checks DMI request/response handshake across `dmi_jtag_to_core_sync` for zero data drops. | `cg_jtag_cdc_synchronizer` | `soc_jtag_cdc_stress_test` | **MEDIUM** |
| **TP-MEM-01** | Memory & ECC | `SOC-DEC-001`<br>`SOC-DAT-002` | `u_veer`, DCCM | DCCM SECDED ECC single-bit correction and double-bit detection. | Inject single-bit error into `dccm_bank_fdout[38:0]`; read word; then inject double-bit error. | Core corrects single-bit error without trap; double-bit error triggers ECC NMI/fault. | `cg_dccm_ecc_faults` | `soc_dccm_ecc_test` | **HIGH** |
| **TP-GAP-01** | Spec Gap | `SOC-CTRL-001`<br>`SOC-CTRL-003` | `heartbeat_in`, M03 | Spec Gap 1: Heartbeat rising edge simultaneous with `hb_counter == HB_THRESHOLD`. | Inject `heartbeat_in` rising pulse on the exact clock cycle `hb_counter == HB_THRESHOLD`. | SVA checks whether edge reset takes precedence (clearing counter) or timeout flag latches. | `cg_hb_threshold_race` | `soc_gap_hb_threshold_race_test` | **HIGH** |
| **TP-GAP-02** | Spec Gap | `SOC-CLK-001` | S01, Crossbar, `rst_n` | Spec Gap 2: AXI access attempt during active `rst_n=0` or cycle of release. | Master VIP drives AXI read/write request while `rst_n=0` and during transition $0 \to 1$. | Protocol monitor verifies crossbar does not deadlock or hang; rejects or buffers cleanly. | `cg_access_during_reset` | `soc_gap_access_during_reset_test` | **HIGH** |
| **TP-GAP-03** | Spec Gap | `SOC-ERR-004`<br>`SOC-REG-010` | M05 | Spec Gap 3: Circular log buffer pointer wrap without `log_full` indicator. | Commit 32 events ($2\times$ buffer capacity); inspect `LOG_COUNT` vs `LOG_READ_IDX`. | Scoreboard checks software can reliably detect wrap-around strictly via `LOG_COUNT > 16`. | `cg_log_wrap_detection` | `soc_gap_log_wrap_policy_test` | **MEDIUM** |
| **TP-GAP-04** | Spec Gap | `SOC-CTRL-006` | M04 | Spec Gap 4: Reset Sequencer re-trigger collision at `ASSERT -> DEASSERT` transition. | Issue second write to `RST_CTRL.trigger=1` on exact clock cycle `rst_countdown == 0`. | SVA checks whether trigger is discarded or launches a second back-to-back reset pulse. | `cg_rst_retrigger_race` | `soc_gap_rst_retrigger_race_test` | **HIGH** |
| **TP-GAP-05** | Spec Gap | `SOC-CTRL-007`<br>`SOC-CTRL-010` | M05 | Spec Gap 5: Recovery policy window rollover vs event recording race. | Write `POL_CTRL.record_event=1` on the exact clock cycle `window_counter == POL_WINDOW`. | Scoreboard verifies whether event count increments in old window or new window. | `cg_window_event_race` | `soc_gap_window_race_test` | **HIGH** |
| **TP-GAP-06** | Spec Gap | `SOC-DAT-003`<br>`SOC-ARB-003` | S00, S01, M00 (UART) | Spec Gap 6: Concurrent multi-master access to UART gasket with address/data skew. | Two masters issue interleaved write addresses (`AW`) and write data (`W`) beats to UART. | SVA verifies `uart_awaddr2_r` is not corrupted, ensuring data reaches correct 32-bit lane. | `cg_uart_gasket_race` | `soc_gap_uart_gasket_race_test` | **HIGH** |
| **TP-E2E-01** | End-to-End | `SOC-E2E-001` | VeeR, ROM, Peripherals | Full system cold boot running C firmware suite (`test_all.c`). | Power up SoC; VeeR core boots from ROM, initializes peripherals, outputs UART banner. | UART monitor verifies PASS string received from firmware. | `cg_firmware_e2e_pass` | `soc_firmware_boot_all_test` | **HIGH** |
| **TP-E2E-02** | End-to-End | `SOC-E2E-003` | Full SoC Top | Watchdog failure remediation sequence (Host hang -> IRQ -> Event logged -> Reset fired). | Heartbeat agent stops pulses; firmware ISR catches IRQ, logs event, triggers reset. | Passive monitor checks `reset_out` pulse matches programmed duration. | `cg_watchdog_e2e_recovery`| `soc_watchdog_remediation_test`| **HIGH** |
| **TP-E2E-03** | End-to-End | `SOC-E2E-004`<br>`SOC-E2E-005` | Full SoC Top | Crash-loop lockout trigger and administrator unlock sequence. | Induce repeated watchdog timeouts; verify firmware enters lockout state; issue unlock command; verify resume. | Monitor checks lockout IRQ assertion and subsequent deassertion upon clear. | `cg_crash_loop_e2e_lifecycle`| `soc_crash_loop_lifecycle_test`| **HIGH** |
| **TP-E2E-04** | End-to-End | `SOC-E2E-002` | Full SoC Top | Normal steady-state operation without watchdog timeouts. | Stream valid periodic heartbeat pulses continuously for 1,000,000 cycles while servicing console commands. | Monitor checks `hb_irq` never asserts and `reset_out` remains high throughout test. | `cg_steady_state_healthy` | `soc_steady_state_health_test` | **HIGH** |
| **TP-E2E-05** | End-to-End | `SOC-E2E-006` | Full SoC Top | Simultaneous multi-peripheral activity under heavy CPU and bus load. | Execute concurrent UART RX/TX transfers + VGA raster scanning + Timer reading + Heartbeat monitoring. | System scoreboard verifies no bus deadlocks, data corruption, or missed events. | `cg_simultaneous_stress` | `soc_concurrent_multiblock_test` | **MEDIUM** |

---

## 4. Recommended Implementation Order

Testbench development is organized into 5 dependency-ordered phases:

```
  Phase 1: Bus Subsystem & Register Model Bring-Up (Core-Stubbed VIP)
     |
     v
  Phase 2: Custom IP Directed Logic, SVA Checkers & Spec Gaps
     |
     v
  Phase 3: Multi-Master Interconnect Stress, Arbitration & Gasket Skew
     |
     v
  Phase 4: Full SoC Firmware Integration & Interrupt Routing (VeeR + Peripherals)
     |
     v
  Phase 5: End-to-End Remediation Scenarios & Subsystem Regression (500 Seeds)
```

1. **Phase 1: Bus Subsystem & Register Model Bring-Up (Core-Stubbed VIP)**:
   - Deploy `uvm_reg_model` for all custom IPs using the Core-Stubbed AXI Master VIP.
   - Run `TP-REG-01`, `TP-DEC-01`, `TP-DEC-02`, and `TP-DEC-05` to validate address mapping, in-window undecoded space, and decode error responses.
2. **Phase 2: Custom IP Directed Logic, SVA Checkers & Spec Gaps**:
   - Bind SVA monitors into `heartbeat_monitor`, `reset_sequencer`, and `recovery_policy`.
   - Run `TP-CTRL-01` through `TP-CTRL-08`, `TP-RST-03`, `TP-ERR-02`, `TP-ERR-04`, and Spec Gap tests `TP-GAP-01` through `TP-GAP-05`.
3. **Phase 3: Multi-Master Interconnect Stress & Arbitration**:
   - Instantiate multi-master VIPs (S00, S01, S02) with randomized backpressure, channel phase skew, and burst testing.
   - Run `TP-ARB-01` through `TP-ARB-04`, `TP-DEC-03`, `TP-DAT-02`, `TP-DAT-05`, `TP-DAT-06`, and `TP-GAP-06`.
4. **Phase 4: Full SoC Firmware Integration & Interrupt Routing**:
   - Enable full `soc_top.v` with VeeR core executing compiled C firmware.
   - Run `TP-RST-01`, `TP-IRQ-01`, `TP-IRQ-02`, `TP-MEM-01`, and `TP-E2E-01` to verify core interrupt dispatch and boot flow.
5. **Phase 5: End-to-End BMC Remediation Scenarios & Regression**:
   - Run complex end-to-end scenarios (`TP-E2E-02`, `TP-E2E-03`, `TP-E2E-04`, `TP-E2E-05`, `TP-RST-02`, `TP-ERR-03`) simulating server crashes, crash loops, and operator triage.
   - Execute the **500-seed randomized regression on the core-stubbed subsystem testbench** to close 100% functional and code coverage.

---

## 5. Feature-to-Test Traceability Matrix

The table below maps every verifiable functional feature from [`docs/arch/10_features.md`](file:///home/student/sriv_183/honour_soc/docs/arch/10_features.md) to one or more test cases defined in this test plan.

| Feature ID | Feature Description Summary | Associated Test Case ID(s) | Verification Method |
|---|---|---|---|
| **SOC-RST-001** | Core boots out of reset from Boot ROM `0x8000_0000` | `TP-RST-01` | SVA / Bus Monitor on S00 AR channel |
| **SOC-RST-002** | Reset sequencer powers up in `IDLE` with `reset_out=1` | `TP-RST-02` | Passive Monitor on `reset_out` pad |
| **SOC-RST-003** | Reset sequencer triggers host reset pulse on `RST_CTRL.trigger=1` | `TP-RST-03` | Passive Monitor on `reset_out` pad |
| **SOC-RST-004** | Reset pulse duration matches `RST_HOLD_CYCLES` | `TP-RST-03` | Passive Monitor cycle timing check |
| **SOC-RST-005** | Reset sequencer sets `RST_STATUS.complete` upon completion | `TP-RST-03` | Register readback via Scoreboard |
| **SOC-RST-006** | `reset_out` assertion does NOT reset VeeR core or peripherals | `TP-RST-02` | Core PC progress monitor & peripheral check |
| **SOC-RST-007** | Host `reset_out` state is readable via `GPIO_STAT[1]` | `TP-RST-04` | Register readback comparison |
| **SOC-DEC-001** | Address decode routing to DCCM (`0xF004_0000`–`0xF004_FFFF`) | `TP-DEC-01`, `TP-MEM-01` | Bus Scoreboard & Memory Model |
| **SOC-DEC-002** | Address decode routing to Boot ROM (`0x8000_0000`–`0x8000_1FFF`) | `TP-DEC-01`, `TP-DAT-05` | Bus Scoreboard |
| **SOC-DEC-003** | Address decode routing to peripheral slaves M00–M06 | `TP-DEC-01`, `TP-DEC-05` | Bus Scoreboard |
| **SOC-DEC-004** | Access to unmapped address space returns AXI `DECERR` | `TP-DEC-02`, `TP-ERR-05` | Protocol Monitor |
| **SOC-DEC-005** | Master S00 and S01 have full access to M00–M06 | `TP-DEC-01`, `TP-ARB-01` | Bus Scoreboard |
| **SOC-DEC-006** | Master S02 access to M00–M06 is blocked / receives `DECERR` | `TP-DEC-03` | Configurable Protocol Monitor |
| **SOC-DEC-007** | Master S02 retains connectivity to M07 (Boot ROM) | `TP-DEC-04` | Bus Scoreboard |
| **SOC-REG-001** | Heartbeat Monitor register read/write access | `TP-REG-01` | UVM Register Model |
| **SOC-REG-002** | `HB_CTRL.clear_flag` clears `unresponsive_flag` & `hb_irq` | `TP-REG-02` | Scoreboard & IRQ Monitor |
| **SOC-REG-003** | Reset Sequencer register read/write access | `TP-REG-01`, `TP-RST-03` | UVM Register Model |
| **SOC-REG-004** | Recovery Policy register read/write access | `TP-REG-01`, `TP-CTRL-04` | UVM Register Model |
| **SOC-REG-005** | `POL_CTRL.clear_lockout` clears `lockout_flag` | `TP-REG-06`, `TP-E2E-03` | UVM Register Model |
| **SOC-REG-006** | System Timer register read access (`TMR_CTR`) | `TP-REG-01` | UVM Register Model |
| **SOC-REG-007** | GPIO pin status register read access (`GPIO_STAT`) | `TP-REG-01`, `TP-RST-04` | UVM Register Model |
| **SOC-REG-008** | UART 16550 standard register set access | `TP-REG-01`, `TP-DAT-03` | UVM Register Model |
| **SOC-REG-009** | Read-only register write protection enforcement | `TP-REG-03` | UVM Register Model |
| **SOC-REG-010** | Event log indexed readback (`LOG_READ_IDX` / `DATA`) | `TP-REG-04`, `TP-GAP-03` | Scoreboard comparison |
| **SOC-REG-011** | VGA character buffer memory-mapped read/write access | `TP-REG-05`, `TP-DAT-04` | Scoreboard comparison |
| **SOC-DAT-001** | 64-bit instruction burst fetching from Boot ROM | `TP-DAT-05` | SVA / Protocol Monitor |
| **SOC-DAT-002** | 64-bit load/store access to DCCM with byte enables | `TP-DAT-01`, `TP-MEM-01` | Memory Model |
| **SOC-DAT-003** | UART 64-to-32 bit bus gasket steering based on `addr[2]` | `TP-DAT-02`, `TP-GAP-06` | SVA on `uart_awaddr2_r` |
| **SOC-DAT-004** | UART TX FIFO buffering and serialization on `uart_tx` | `TP-DAT-03` | Scoreboard byte comparison |
| **SOC-DAT-005** | UART RX FIFO deserialization from `uart_rx` into `RBR` | `TP-DAT-03` | Scoreboard byte comparison |
| **SOC-DAT-006** | VGA character buffer rendering to 12-bit RGB raster | `TP-DAT-04` | Video Frame Scoreboard |
| **SOC-DAT-007** | AXI backpressure stall handling on custom IP slaves | `TP-DAT-06` | Protocol Monitor |
| **SOC-CTRL-001** | Heartbeat edge detection on `heartbeat_in` | `TP-CTRL-01`, `TP-GAP-01` | SVA on `hb_prev_sample` |
| **SOC-CTRL-002** | Heartbeat edge resets `hb_counter` to 0 | `TP-CTRL-01` | SVA on `hb_counter` |
| **SOC-CTRL-003** | Watchdog timeout sets `unresponsive_flag` & `hb_irq` | `TP-CTRL-02`, `TP-GAP-01` | Scoreboard & IRQ Monitor |
| **SOC-CTRL-004** | Heartbeat monitor disable & flush behavior | `TP-CTRL-07` | SVA on FSM states |
| **SOC-CTRL-005** | Reset Sequencer FSM transitions (`IDLE->ASSERT->DEASSERT->IDLE`) | `TP-CTRL-08`, `TP-RST-03` | SVA on `rst_state` |
| **SOC-CTRL-006** | Reset Sequencer re-trigger rejection during active pulse | `TP-CTRL-03`, `TP-GAP-04` | SVA on FSM trigger |
| **SOC-CTRL-007** | Recovery Policy commits staged timestamp into RAM | `TP-CTRL-04`, `TP-GAP-05` | Scoreboard shadow RAM check |
| **SOC-CTRL-008** | Recovery Policy increments `window_recovery_count` | `TP-CTRL-04` | Register readback |
| **SOC-CTRL-009** | Recovery Policy asserts `lockout_flag` and single-cycle `lockout_irq` | `TP-CTRL-04`, `TP-IRQ-01` | IRQ Monitor & Status check |
| **SOC-CTRL-010** | Rolling window counter resets recovery count at expiration | `TP-CTRL-05`, `TP-CTRL-06`, `TP-GAP-05` | SVA on `window_counter` |
| **SOC-ARB-001** | Fair round-robin arbitration between S00 and S01 | `TP-ARB-01` | Arbiter Scoreboard |
| **SOC-ARB-002** | Concurrent non-conflicting read and write channels | `TP-ARB-03` | Protocol Scoreboard |
| **SOC-ARB-003** | Interleaved write address and data handshake acceptance | `TP-ARB-02`, `TP-GAP-06` | SVA on AXI handshakes |
| **SOC-ARB-004** | Crossbar holds grant active across multi-beat bursts | `TP-ARB-04` | SVA on burst atomicity |
| **SOC-IRQ-001** | `uart_irq` directly drives VeeR PIC line 0 | `TP-IRQ-01` | PIC IRQ Monitor |
| **SOC-IRQ-002** | `hb_irq` directly drives VeeR PIC line 1 | `TP-IRQ-01`, `TP-CTRL-02` | PIC IRQ Monitor |
| **SOC-IRQ-003** | `vblank_irq` directly drives VeeR PIC line 2 | `TP-IRQ-01` | PIC IRQ Monitor |
| **SOC-IRQ-004** | `lockout_irq` single-cycle pulse directly drives PIC line 3 | `TP-IRQ-01`, `TP-CTRL-04` | PIC IRQ Monitor |
| **SOC-IRQ-005** | PIC interrupt arbitration and priority preemption | `TP-IRQ-02` | Core trap monitor |
| **SOC-ERR-001** | Out-of-bounds MMIO read returns `DECERR` | `TP-ERR-05`, `TP-DEC-02` | Protocol Monitor |
| **SOC-ERR-002** | Out-of-bounds MMIO write returns `DECERR` and drops data | `TP-DEC-02`, `TP-ERR-05` | Protocol Monitor |
| **SOC-ERR-003** | Boot ROM write transaction handling | `TP-ERR-01` | Protocol Monitor |
| **SOC-ERR-004** | Circular event log RAM clean wrap-around after 16 events | `TP-ERR-02`, `TP-GAP-03` | Log Scoreboard |
| **SOC-ERR-005** | Firmware-enforced lockout suppression verification | `TP-ERR-03`, `TP-ERR-04` | Firmware Monitor & Scoreboard |
| **SOC-CLK-001** | Synchronous reset release to legal register defaults | `TP-RST-01`, `TP-CLK-02`, `TP-GAP-02` | SVA on register reset |
| **SOC-CLK-002** | VeeR core synchronous reset release sequence | `TP-CLK-02` | SVA on core reset lines |
| **SOC-CLK-003** | Synchronous video clock enable cadence (`pixel_clk_en`) | `TP-CLK-01` | SVA on clock divider |
| **SOC-CLK-004** | JTAG clock domain crossing synchronizer verification | `TP-CLK-03` | CDC SVA Checker |
| **SOC-E2E-001** | Cold Boot to Firmware Loop executing bare-metal C test | `TP-E2E-01` | UART Console Monitor |
| **SOC-E2E-002** | Normal steady-state operation without watchdog timeouts | `TP-E2E-04` | System Scoreboard |
| **SOC-E2E-003** | Watchdog timeout & reset recovery sequence | `TP-E2E-02` | End-to-End System Scoreboard |
| **SOC-E2E-004** | Crash-loop lockout containment | `TP-E2E-03` | End-to-End System Scoreboard |
| **SOC-E2E-005** | Lockout override & operational resumption | `TP-E2E-03` | End-to-End System Scoreboard |
| **SOC-E2E-006** | Simultaneous multi-peripheral activity under heavy load | `TP-E2E-05` | System Stress Scoreboard |
