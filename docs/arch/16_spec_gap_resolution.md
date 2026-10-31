# Honour SoC — Specification Gap and Architectural Resolution Report

**Document ID:** HRSOC-GAP-001  
**Target Document:** `docs/arch/16_spec_gap_resolution.md`  
**RTL Baseline:** `main` (commit `adac55b` / `3d82bfa`)  
**Scope:** Rigorous, evidence-based audit of all open specification gaps (Part A: 10 items) and test plan contradictions (Part B: 10 items) against synthesizable RTL, testbenches, and existing documentation.

---

## PART A: SPECIFICATION GAPS

### A1. SOC-005 (TP-GAP-02): In-Flight AXI Transaction Reset Behavior

#### Question
What happens to an AXI transaction in flight when `rst_n` is asserted for 10 cycles? Does it complete or get discarded? Do valid/ready/state registers reset, and can any channel hang after release?

#### Answer
The transaction is immediately aborted and discarded; all AXI valid/ready handshake signals, internal FIFOs, channel tracking counters, and state machines synchronously clear to idle, and no channel hangs after reset release.

#### Evidence
- **`rtl/soc_top.v:300`**: Synchronous reset inversion:
  ```verilog
  wire rst = ~rst_n;
  ```
- **`rtl/interconnect/axi_register_wr.v:501-505, 592-596` & `axi_register_rd.v:200-204, 418-422`**:
  ```verilog
  always @(posedge clk) begin
      if (rst) begin
          s_axi_awready_reg <= 1'b0; m_axi_awvalid_reg <= 1'b0;
          s_axi_wready_reg  <= 1'b0; m_axi_wvalid_reg  <= 1'b0;
          m_axi_bready_reg  <= 1'b0; s_axi_bvalid_reg  <= 1'b0;
      end
  ```
- **`rtl/interconnect/axi_crossbar_wr.v:328-333, 497-504` & `axi_crossbar_rd.v:438-444`**:
  ```verilog
  always @(posedge clk) begin
      if (rst) begin
          trans_count_reg <= 0;
          w_select_valid_reg <= 1'b0;
      end
  ```
- **Custom IP Wrappers (e.g., `rtl/custom_ips/axi_heartbeat_monitor.v:89-98`)**:
  ```verilog
  always @(posedge clk) begin
      if (!rst_n) begin
          state <= ST_IDLE;
          s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_bvalid <= 1'b0;
          s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0; reg_en <= 1'b0; reg_we <= 1'b0;
      end
  ```

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-GAP-02`: Define expected result as clean transaction discard with zero post-reset bus hangs, and document that the master must timeout and not await completion for in-flight requests interrupted by `rst_n`.

---

### A2. SOC-009 (TP-ERR-04 / TP-MEM-01): DCCM ECC Architecture and Core Error Handling

#### Question
Is DCCM ECC enabled in the VeeR EL2 configuration used here? Do ECC bits exist, are single-bit errors corrected, what does the core do on double-bit errors, and what are the relevant CSRs?

#### Answer
7-bit SECDED ECC is physically implemented at the DCCM memory array (4 banks of $4096 \times 39$), but top-level core error export pins are left unconnected at `soc_top.v`, restricting error handling exclusively to core-internal exception traps.

#### Evidence
- **`rtl/soc_top.v:1807-1827`**:
  ```verilog
          .dccm_ecc_single_error   (),
          .dccm_ecc_double_error   (),
          .dccm_write_readback_error()
      );
      // VeeR EL2 DCCM SRAM (4 Banks x 4096 x 39 bits = 64 KB with ECC)
      wire [3:0][38:0] dccm_bank_fdout;
      for (genvar b = 0; b < 4; b = b + 1) begin : gen_dccm_banks
          assign el2_mem_export.dccm_bank_dout[b] = dccm_bank_fdout[b][31:0];
          assign el2_mem_export.dccm_bank_ecc[b]  = dccm_bank_fdout[b][38:32];
          ram_4096x39 u_dccm_bank (...);
  ```
- **`Makefile:31` & `rtl/core/`**:
  ```makefile
  RV_ROOT ?= $(CURDIR)/rtl/core/Cores-VeeR-EL2
  ```
  Directory `rtl/core/Cores-VeeR-EL2` is an uncommitted submodule stub in this repository clone. Per VeeR EL2 PRM, SECDED Hamming $(39, 32)$ hardware corrects 1-bit errors silently, while double-bit uncorrectable faults trigger a precise Load/Store Access Fault exception (`mcause = 5` or `7`) with fault address logged in `mtval` and syndrome in `mdeau`/`mdseac`.

#### Confidence
**Proven by RTL** for memory width ($39$ bits = $32$ data + $7$ ECC) and unconnected top-level error ports; **Inferred from VeeR EL2 Specification** for core-internal CSR traps.

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-ERR-04`: Note that `dccm_ecc_*_error` signals cannot be observed at chip boundaries or PIC interrupt lines; verification must inspect internal core CSRs via GPR/DCCM readback or backdoor simulator force.

---

### A2b. Resolution of Open Question OQ-07 (DCCM ECC Verification)

#### Question
Can Open Question OQ-07 in `docs/arch/09_open_questions.md` now be closed?

#### Answer
Yes, OQ-07 (and the matching audit entry OQ-11 in `13_consistency_audit.md`) can be closed regarding memory structure and top-level connectivity, while noting that ECC interrupt generation is intentionally absent at the SoC level.

#### Evidence
- **`rtl/soc_top.v:1808-1809`**: `.dccm_ecc_single_error ()` and `.dccm_ecc_double_error ()` are explicit open terminations.
- **`docs/arch/09_open_questions.md`**: Lists DCCM ECC trap behavior as requiring RTL confirmation.

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Mark OQ-07 in `docs/arch/09_open_questions.md` as [RESOLVED IN RTL]: Document that 7-bit ECC hardware exists in `ram_4096x39`, single-bit correction is internal to VeeR LSU, double-bit faults trigger internal RISC-V synchronous exceptions, and no external IRQ is asserted.

---

### A3. XBR-003 (TP-DEC-05): Peripheral Access Past Valid Register Range

#### Question
For an address inside a peripheral's 256-byte window but past its last valid register (e.g., `0x0002_0320` for heartbeat monitor), what does each wrapper return?

#### Answer
All seven peripheral wrappers return `rresp = 2'b00` (`OKAY`) and `bresp = 2'b00` (`OKAY`); out-of-range reads return zero (`64'd0`) on five IPs or alias the single status register on Timer and GPIO, and writes are silently dropped.

#### Evidence
- **`rtl/custom_ips/heartbeat_monitor.v:85-93` & `axi_heartbeat_monitor.v:134,148`**:
  ```verilog
  always @(*) begin
      reg_rdata = 32'd0;
      case (reg_addr)
          ADDR_HB_CTRL: ...
          default: reg_rdata = 32'd0;
      endcase
  end
  // axi_heartbeat_monitor.v:
  s_axi_bresp <= 2'b00; s_axi_rresp <= 2'b00; s_axi_rdata <= {reg_rdata, reg_rdata};
  ```
- **`rtl/custom_ips/axi_gpio.v:104-106, 122` & `axi_timer.v:104-106, 122`**:
  ```verilog
  assign s_axi_rresp = 2'b00; // OKAY
  assign s_axi_rdata = {gpio_status_word, gpio_status_word}; // Unconditional alias
  ```
- **`rtl/custom_ips/vga_controller.v:143-145`**:
  ```verilog
  default: begin
      if (reg_addr >= 8'h08 && reg_addr <= 8'h7F) reg_rdata = dashboard_buffer[(reg_addr - 8'h08) >> 2];
      else reg_rdata = 32'd0;
  end
  ```
- **`rtl/ips/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v:304-309`**:
  ```verilog
  default: begin
      axi_arready_d = 1'b1; axi_rdata_d = 32'd0; axi_rresp_d = 2'b0; axi_rvalid_d = 1'b1;
  end
  ```

#### Complete Peripheral Unmapped-Offset Response Table

| Peripheral | Address Range | Valid Decoded Offsets | Read Response (`rresp`) | Read Data (`rdata[63:0]`) | Write Response (`bresp`) | Write Action |
|---|---|---|---|---|---|---|
| **UART 16550** (`u_uart`) | `0x0002_0000–0x00FF` | `0x00–0x1C` | `2'b00` (`OKAY`) | `64'd0` | `2'b00` (`OKAY`) | Silently dropped |
| **System Timer** (`u_timer`) | `0x0002_0100–0x01FF` | `0x00` | `2'b00` (`OKAY`) | `{timer_ctr, timer_ctr}` (aliased) | `2'b00` (`OKAY`) | Silently dropped |
| **GPIO Status** (`u_gpio`) | `0x0002_0200–0x02FF` | `0x00` | `2'b00` (`OKAY`) | `{gpio_stat, gpio_stat}` (aliased) | `2'b00` (`OKAY`) | Silently dropped |
| **Heartbeat Monitor** (`u_heartbeat`) | `0x0002_0300–0x03FF` | `0x00–0x0C` | `2'b00` (`OKAY`) | `64'd0` | `2'b00` (`OKAY`) | Silently dropped |
| **Reset Sequencer** (`u_reset_seq`) | `0x0002_0400–0x04FF` | `0x00–0x08` | `2'b00` (`OKAY`) | `64'd0` | `2'b00` (`OKAY`) | Silently dropped |
| **Recovery Policy** (`u_rec_policy`) | `0x0002_0500–0x05FF` | `0x00–0x1C` | `2'b00` (`OKAY`) | `64'd0` | `2'b00` (`OKAY`) | Silently dropped |
| **VGA Controller** (`u_vga`) | `0x0002_0600–0x06FF` | `0x00–0x7C` | `2'b00` (`OKAY`) | `64'd0` (for offset $\ge 0x80$) | `2'b00` (`OKAY`) | Silently dropped |

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-DEC-05`: State clearly that accesses to undefined offsets within valid peripheral apertures do NOT return `DECERR` or `SLVERR`; they return `OKAY` with zero data or alias data.

---

### A4. XBR-004 (TP-DEC-03, OQ-03): JTAG/System Bus Master S02 Peripheral Access Block

#### Question
Is JTAG/system-bus master S02 blocked from peripherals M00..M06? Is the block implemented, and what response does S02 receive?

#### Answer
Yes, the block is physically implemented in hardware via Verilog parameter zero-extension; any read or write access from Master S02 to peripherals M00..M06 fails address decode in the crossbar and returns `DECERR` (`2'b11`).

#### Evidence
- **`rtl/soc_top.v:762-805`**: Peripherals M00–M06 are instantiated with 2-bit literals:
  ```verilog
  .M00_CONNECT_READ  (2'b11),
  .M00_CONNECT_WRITE (2'b11),
  ```
- **`rtl/interconnect/axi_interconnect_wrap_3x8.v:54-55`**: Defines parameter width as 3 bits:
  ```verilog
  parameter M00_CONNECT_READ = 3'b111,
  parameter M00_CONNECT_WRITE = 3'b111,
  ```
  In Verilog-2001 (IEEE 1364-2001 §4.1.14), passing `2'b11` to a 3-bit parameter zero-extends the literal to `3'b011`. Master 0 (IFU) = bit 0 = 1; Master 1 (LSU) = bit 1 = 1; Master 2 (SB/S02) = bit 2 = 0.
- **`rtl/interconnect/axi_crossbar_addr.v:340, 362-367`**:
  ```verilog
  if (... && (M_CONNECT & (1 << (S+i*S_COUNT))) && ...) begin
      match = 1'b1;
  end ...
  if (match) begin ... end
  else begin
      m_axi_avalid_next = 1'b0;
      m_decerr_next     = 1'b1;  // Returns DECERR (2'b11) to Master S02
      state_next        = STATE_DECODE;
  end
  ```

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-DEC-03` and `docs/arch/09_open_questions.md` OQ-03: Confirm that S02 peripheral isolation is structurally enforced by crossbar decode and returns `DECERR` (`2'b11`).

---

### A5. XBR-007 (TP-ERR-01, OQ-06): Boot ROM Write Response and Dropping

#### Question
What does a write to Boot ROM (`0x8000_0000`) return (`OKAY`, `SLVERR`, or `DECERR`), is the write dropped, and how many cycles does the response take?

#### Answer
A write to Boot ROM returns `bresp = 2'b00` (`OKAY`), the write payload is completely ignored (dropped), and `bvalid` asserts exactly 1 clock cycle after the write data handshake.

#### Evidence
- **`rtl/custom_ips/axi_rom.v:111-129`**:
  ```verilog
  assign s_axi_awready = 1'b1;
  assign s_axi_wready  = 1'b1;

  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          s_axi_bvalid <= 1'b0; s_axi_bresp <= 2'b00; s_axi_bid <= 0;
      end else begin
          if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
              s_axi_bvalid <= 1'b1;
              s_axi_bresp  <= 2'b00; // OKAY
              s_axi_bid    <= s_axi_awid;
          end else if (s_axi_bvalid && s_axi_bready) begin
              s_axi_bvalid <= 1'b0;
          end
      end
  end
  ```
- **`docs/IP_SPEC_AXI_ROM.md:18`**:
  > "Safe Write Sink: While the memory is non-volatile/read-only, write transactions (`AW`, `W`) complete gracefully with `bresp = OKAY` (`2'b00`) rather than creating bus faults or hanging the processor during rogue store instructions."

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-ERR-01` and resolve OQ-06 in `docs/arch/09_open_questions.md`: Document that ROM writes return `OKAY` (`2'b00`) with 1-cycle latency and silent payload discard.

---

### A6. HBM-05 (TP-GAP-01): Heartbeat Rising Edge vs. Timeout Collision

#### Question
In `heartbeat_monitor.v`, does `hb_rising_edge` win over the timeout compare? What is the compare operator (`>=` or `==`), and how many cycles after reaching threshold do `unresponsive_flag` and `hb_irq` appear?

#### Answer
The rising edge strictly wins; the compare operator is `>=`; `unresponsive_flag` and `hb_irq` assert exactly 1 clock cycle after `hb_counter >= hb_threshold_reg` evaluates to true.

#### Evidence
- **`rtl/custom_ips/heartbeat_monitor.v:39, 110-119`**:
  ```verilog
  assign hb_irq = hb_unresponsive_flag;
  ...
  ST_COUNTING: begin
      if (!hb_enable) begin
          hb_state <= ST_DISABLED;
      end else if (hb_rising_edge) begin
          hb_counter <= 32'd0;
      end else if (hb_counter >= hb_threshold_reg && hb_threshold_reg != 32'd0) begin
          hb_unresponsive_flag <= 1'b1;
          hb_state <= ST_UNRESPONSIVE;
      end else begin
          hb_counter <= hb_counter + 32'd1;
      end
  end
  ```
  `hb_rising_edge` is evaluated prior to the threshold comparison in the `if-else` chain, resetting `hb_counter` to 0 and preventing flag assertion. `hb_irq` is continuous assignment of `hb_unresponsive_flag`, which updates on the clock edge immediately following threshold match (1-cycle latency).

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-GAP-01` and `docs/arch/09_open_questions.md` Spec Gap 1: State that edge takes precedence over timeout, compare uses `>=`, and IRQ appears 1 cycle post-threshold.

---

### A7. RST-06 (TP-GAP-04): Reset Sequencer Trigger at ASSERT to DEASSERT Boundary

#### Question
What happens if `RST_CTRL.trigger` is written on the exact cycle `rst_countdown == 0`? Is the trigger ignored or accepted? What is the FSM transition table?

#### Answer
The trigger is completely ignored (discarded); the FSM only evaluates `trigger_req` while in `ST_IDLE`, and `trigger_req` is a 1-cycle unbuffered strobe that expires while the FSM transitions to `ST_DEASSERT`.

#### Evidence
- **`rtl/custom_ips/reset_sequencer.v:47-52, 76-101`**:
  ```verilog
  // trigger_req generation:
  trigger_req <= 1'b0;
  if (reg_en && reg_we && !reg_ack && reg_addr == ADDR_RST_CTRL)
      trigger_req <= reg_wdata[0];

  // FSM trigger evaluation:
  if (trigger_req && rst_state == ST_IDLE) begin
      rst_state <= ST_ASSERT; ...
  end else begin
      case (rst_state)
          ST_ASSERT: if (rst_countdown == 32'd0) rst_state <= ST_DEASSERT;
          ST_DEASSERT: begin reset_out <= 1'b1; in_progress <= 1'b0; complete <= 1'b1; rst_state <= ST_IDLE; end
      endcase
  end
  ```

#### Reset Sequencer FSM Transition Table

| State Name | State Encoding | Stimulus / Condition | Next State | Outputs & Side Effects |
|---|---|---|---|---|
| `ST_IDLE` | `2'b00` | `trigger_req == 1` | `ST_ASSERT` (`2'b01`) | **Trigger Accepted:** `reset_out <= 0`, `in_progress <= 1`, `complete <= 0`, `rst_countdown <= rst_hold_cycles_reg` |
| `ST_IDLE` | `2'b00` | `trigger_req == 0` | `ST_IDLE` (`2'b00`) | Idle: `reset_out <= 1`, `in_progress <= 0`, `complete <= 0` |
| `ST_ASSERT` | `2'b01` | `rst_countdown > 0` | `ST_ASSERT` (`2'b01`) | Active hold: `rst_countdown <= rst_countdown - 1`, `reset_out <= 0`. **Trigger ignored.** |
| `ST_ASSERT` | `2'b01` | `rst_countdown == 0` | `ST_DEASSERT` (`2'b10`) | Hold complete: FSM moves to deassert. **Trigger ignored.** |
| `ST_DEASSERT` | `2'b10` | Any (1 cycle duration) | `ST_IDLE` (`2'b00`) | Deassert: `reset_out <= 1`, `in_progress <= 0`, `complete <= 1`. **Trigger ignored.** |

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-GAP-04` and `docs/arch/09_open_questions.md` Spec Gap 4: Document that reset re-triggers during active hold or at the deassert boundary are ignored.

---

### A8. POL-04 (TP-CTRL-06): Recovery Policy Window Expiry vs. Event Recording Race

#### Question
If `record_event` arrives in the same cycle the window counter expires, which wins: count reset or increment? In the case of threshold 3, window 100, events at cycles 1, 2, and 100, does lockout assert?

#### Answer
The increment wins over the window reset; with 2 prior events, the 3rd event at cycle 100 increments the count to 3, satisfying the threshold ($3 \ge 3$) and asserting `lockout_flag`.

#### Evidence
- **`rtl/custom_ips/recovery_policy.v:166-196`**:
  ```verilog
  if (policy_window_reg != 32'd0) begin
      if (window_counter >= policy_window_reg) begin
          window_counter        <= 32'd0;
          window_recovery_count <= 8'd0;  // First assignment
      end else window_counter <= window_counter + 32'd1;
  end
  if (record_event_req) begin
      ...
      window_recovery_count <= window_recovery_count + 8'd1; // Supersedes 8'd0
      if ((window_recovery_count + 8'd1) >= policy_threshold_reg && policy_threshold_reg != 8'd0) begin
          lockout_flag <= 1'b1; // Lockout asserts!
      end
  end
  ```
  In Verilog procedural execution, subsequent non-blocking assignments to the same register in a single `always` block take precedence. The threshold comparison evaluates $(2 + 1) \ge 3$, which is true, setting `lockout_flag <= 1'b1`.

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-CTRL-06`: State that event recording takes procedural priority over window rollover, and lockout asserts if the incremented count meets threshold.

---

### A9. POL-09 (TP-GAP-05): Window Recovery Count on Single Rollover Event

#### Question
When one event is written exactly when `window_counter == POL_WINDOW`, what is `window_recovery_count` afterwards (0 or 1)?

#### Answer
`window_recovery_count` becomes `1` (assuming pre-event count was 0; otherwise $C+1$).

#### Evidence
- **`rtl/custom_ips/recovery_policy.v:169, 188`**:
  Procedural order executes `window_recovery_count <= window_recovery_count + 8'd1` after `window_recovery_count <= 8'd0`. Because the right-hand side samples the pre-edge value ($0$), $0 + 1 = 1$ is assigned to `window_recovery_count`.

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-GAP-05`: Define expected `window_recovery_count` post-rollover event as 1.

---

### A10. PER-03 (TP-GAP-06): UART 64-to-32 Bit Bus Gasket Multi-Master Write Hazard

#### Question
In `soc_top.v`, does the UART gasket latch `uart_awaddr2_r` across masters, can data go to the wrong lane if two masters write simultaneously, and does the interconnect serialize them?

#### Answer
The address-bit latch `uart_awaddr2_r` is a single shared flip-flop, but the AXI crossbar strictly serializes write transactions per slave with single-issue burst locking, preventing multi-master lane corruption under standard single-beat AXI-Lite traffic.

#### Evidence
- **`rtl/soc_top.v:687-695`**:
  ```verilog
  reg uart_awaddr2_r;
  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) uart_awaddr2_r <= 1'b0;
      else if (m00_axi_awvalid & m00_axi_awready)
          uart_awaddr2_r <= m00_axi_awaddr[2];
  end
  wire [31:0] uart_wdata_32 = uart_awaddr2_r ? m00_axi_wdata[63:32] : m00_axi_wdata[31:0];
  ```
- **`rtl/interconnect/axi_crossbar_wr.v:515-546`**:
  ```verilog
  arbiter #(.PORTS(S_COUNT), .ARB_TYPE_ROUND_ROBIN(1), .ARB_BLOCK(1), .ARB_BLOCK_ACK(1))
  a_arb_inst (...);
  assign a_request[m] = int_axi_awvalid[m*M_COUNT+n] && !a_grant[m] && !trans_limit && !w_select_valid_next;
  ```
  The arbiter blocks subsequent address grants (`!w_select_valid_next`) until the in-flight write data beat has completed (`wlast`), guaranteeing that Master B cannot overwrite `uart_awaddr2_r` while Master A's data is pending.

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-GAP-06`: Confirm that crossbar slave arbitration eliminates concurrent write hazards at the UART gasket, but add an SVA asserting `uart_awaddr2_r` does not toggle between `AWVALID & AWREADY` and `WVALID & WREADY`.

---

## PART B: POINTS TO CONFIRM (CONTRADICTIONS IN THE PLAN)

### B1. RST_STATUS Bit Layout Verification

#### Question
Confirm whether bit 0 = `in_progress` and bit 1 = `complete` in `reset_sequencer.v`, versus `TP-RST-03` claiming bit 0 is `complete`.

#### Answer
Bit 0 is `in_progress` and bit 1 is `complete`; the statement in `TP-RST-03` claiming bit 0 is complete was an error in the draft plan.

#### Evidence
- **`rtl/custom_ips/reset_sequencer.v:31-32, 61-63`**:
  ```verilog
  reg in_progress;
  reg complete;
  ...
  ADDR_RST_STATUS: reg_rdata = {30'd0, complete, in_progress};
  ```
- **`docs/arch/04_address_map.md:143`**:
  `ADDR_RST_STATUS (0x08): [0] in_progress, [1] complete`

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Align `TP-RST-03` in `docs/arch/14_testplan.md`: Update pass criterion to check `RST_STATUS[1] == 1` and `RST_STATUS[0] == 0`.

---

### B2. LOG_COUNT Saturation vs. Pointer Wrap

#### Question
Confirm whether `LOG_COUNT` saturates at `0xFFFFFFFF` or 16, and whether only the log pointer wraps at 16.

#### Answer
`LOG_COUNT` increments monotonically up to `32'hFFFF_FFFF` (`0xFFFFFFFF`); only the internal 4-bit write pointer `log_wr_ptr` wraps modulo 16.

#### Evidence
- **`rtl/custom_ips/recovery_policy.v:180-185`**:
  ```verilog
  // Advance write pointer (wraps at 16)
  log_wr_ptr <= log_wr_ptr + 4'd1;

  // Increment total log count (saturating)
  if (log_count != 32'hFFFF_FFFF)
      log_count <= log_count + 32'd1;
  ```
- **`tb/tb_recovery_policy.v:305-306`**:
  ```verilog
  axi_read(ADDR_LOG_COUNT, read_data);
  check(32'd18, read_data, "LOG_COUNT after 18 events");
  ```

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Align `TP-REG-04` and `TP-GAP-03` in `docs/arch/14_testplan.md`: Correct claims that `LOG_COUNT` clamps at 16, stating that `LOG_COUNT > 16` is firmware's mechanism to detect circular buffer overwrites.

---

### B3. Reset-Value Exclusion List & Complete Peripheral Register Map

#### Question
Which registers genuinely cannot be reset-checked by `uvm_reg_hw_reset_seq`, and what are the actual reset values of every register across all 7 peripherals?

#### Answer
Registers that cannot be front-door checked are write-only registers (`UART_THR`, `UART_FCR`, `POL_CTRL`, `POL_EVENT_TS`, `RST_CTRL`), live incrementing counters (`TMR_CTR`), and dynamic pin inputs (`GPIO_STAT[0]`); `docs/arch/14_testplan.md` §4.3 conflated reset exclusions with bit-bash exclusions.

#### Genuine RAL Reset-Check Exclusion List
1. `RST_CTRL` (`0x0002_0400`): Write-only; writing bit 0 fires external system power reset.
2. `UART_THR` (`0x0002_0000`): Write-only; reading offset 0x00 accesses `UART_RBR`.
3. `UART_FCR` (`0x0002_0008`): Write-only; reading offset 0x08 accesses `UART_IIR`.
4. `POL_CTRL` (`0x0002_0500`): Write-only; read returns 0.
5. `POL_EVENT_TS` (`0x0002_0510`): Write-only staging register; read returns 0.
6. `TMR_CTR` (`0x0002_0100`): Free-running real-time counter; non-zero by time AXI transaction arrives.
7. `GPIO_STAT` (`0x0002_0200`): Dynamic pin tracking on bit 0; reset value is `0x0000_0002`.

#### Complete Reset Values for All 7 Peripherals

| Peripheral | Register Name | Physical Address | Access | Reset Value (Hex) | RTL Source Citation |
|---|---|---|---|---|---|
| **UART 16550** | `UART_RBR` / `UART_THR` | `0x0002_0000` | RO / WO | `0x00` (RBR) / WO | `axi_uart_top.v:347` |
| | `UART_IER` | `0x0002_0004` | RW | `0x00` | `axi_uart_top.v:347` |
| | `UART_IIR` / `UART_FCR` | `0x0002_0008` | RO / WO | `0x01` (IIR) / WO | `axi_uart_top.v:347` |
| | `UART_LCR` | `0x0002_000C` | RW | `0x00` | `axi_uart_top.v:347` |
| | `UART_MCR` | `0x0002_0010` | RW | `0x00` | `axi_uart_top.v:347` |
| | `UART_LSR` | `0x0002_0014` | RO | `0x60` (TEMT \| THRE) | `axi_uart_top.v:347` |
| | `UART_MSR` | `0x0002_0018` | RO | `0x00` | `axi_uart_top.v:347` |
| | `UART_SCR` | `0x0002_001C` | RW | `0x00` | `axi_uart_top.v:347` |
| **System Timer** | `TMR_CTR` | `0x0002_0100` | RO | `0x0000_0000` (dynamic) | `axi_timer.v:56` |
| **GPIO** | `GPIO_STAT` | `0x0002_0200` | RO | `0x0000_0002` (bit 1=1) | `soc_top.v:1346` / `axi_gpio.v:53` |
| **Heartbeat Monitor** | `HB_CTRL` | `0x0002_0300` | WO / RO | `0x0000_0000` | `heartbeat_monitor.v:61, 87` |
| | `HB_THRESHOLD` | `0x0002_0304` | RW | `0x0000_0000` | `heartbeat_monitor.v:63` |
| | `HB_STATUS` | `0x0002_0308` | RO | `0x0000_0000` | `heartbeat_monitor.v:89` |
| | `HB_ELAPSED` | `0x0002_030C` | RO | `0x0000_0000` | `heartbeat_monitor.v:101` |
| **Reset Sequencer** | `RST_CTRL` | `0x0002_0400` | WO | `0x0000_0000` | `reset_sequencer.v:45` |
| | `RST_HOLD_CYCLES` | `0x0002_0404` | RW | `0x0000_0064` (100d) | `reset_sequencer.v:44` |
| | `RST_STATUS` | `0x0002_0408` | RO | `0x0000_0000` | `reset_sequencer.v:62, 72` |
| **Recovery Policy** | `POL_CTRL` | `0x0002_0500` | WO | `0x0000_0000` | `recovery_policy.v:131` |
| | `POL_WINDOW` | `0x0002_0504` | RW | `0x0000_0000` | `recovery_policy.v:105` |
| | `POL_THRESHOLD` | `0x0002_0508` | RW | `0x0000_0000` | `recovery_policy.v:106` |
| | `POL_STATUS` | `0x0002_050C` | RO | `0x0000_0000` | `recovery_policy.v:134` |
| | `POL_EVENT_TS` | `0x0002_0510` | WO | `0x0000_0000` | `recovery_policy.v:135` |
| | `LOG_READ_IDX` | `0x0002_0514` | RW | `0x0000_0000` | `recovery_policy.v:108` |
| | `LOG_READ_DATA` | `0x0002_0518` | RO | `0x0000_0000` | `recovery_policy.v:137, 161` |
| | `LOG_COUNT` | `0x0002_051C` | RO | `0x0000_0000` | `recovery_policy.v:157` |
| **VGA Controller** | `VGA_CTRL` | `0x0002_0600` | RW | `0x0000_0000` | `vga_controller.v:114` |
| | `VGA_STATUS` | `0x0002_0604` | RO | `0x0000_0000` | `vga_controller.v:115` |
| | `VGA_BUFFER[0..29]`| `0x0002_0608–7C`| RW | `0x2020_2020` (spaces) | `vga_controller.v:117` |

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` §4.3 and §19: Differentiate `uvm_reg_hw_reset_seq` exclusions from `uvm_reg_bit_bash_seq` exclusions.

---

### B4. Response of Each Peripheral to Writes on Read-Only Registers

#### Question
What does each peripheral return when a write is attempted to a read-only register (OKAY, SLVERR, or silently ignored)?

#### Answer
All peripherals return `bresp = 2'b00` (`OKAY`) and silently discard the write payload, except for `UART_IIR` at offset `0x08` where writing activates `UART_FCR` (FIFO Control Register).

#### Read-Only Register Write Response Table

| Register | Address | Wrapper Module | Response (`bresp`) | Functional Hardware Behavior on Write |
|---|---|---|---|---|
| `HB_STATUS` | `0x0002_0308` | `axi_heartbeat_monitor.v` | `2'b00` (`OKAY`) | Silently ignored (`case` address unmapped for writes) |
| `HB_ELAPSED` | `0x0002_030C` | `axi_heartbeat_monitor.v` | `2'b00` (`OKAY`) | Silently ignored (counter continues unmodified) |
| `GPIO_STAT` | `0x0002_0200` | `axi_gpio.v` | `2'b00` (`OKAY`) | Silently ignored (no write register in IP) |
| `TMR_CTR` | `0x0002_0100` | `axi_timer.v` | `2'b00` (`OKAY`) | Silently ignored (tick counter continues) |
| `RST_STATUS` | `0x0002_0408` | `axi_reset_sequencer.v` | `2'b00` (`OKAY`) | Silently ignored (`case` address unmapped for writes) |
| `UART_LSR` | `0x0002_0014` | `axi_uart_top.v` | `2'b00` (`OKAY`) | Silently ignored |
| `UART_IIR` | `0x0002_0008` | `axi_uart_top.v` | `2'b00` (`OKAY`) | **Side-effect write to UART_FCR** (FIFO control/reset) |
| `UART_MSR` | `0x0002_0018` | `axi_uart_top.v` | `2'b00` (`OKAY`) | Silently ignored |
| `POL_STATUS` | `0x0002_050C` | `axi_recovery_policy.v` | `2'b00` (`OKAY`) | Silently ignored |
| `LOG_READ_DATA`| `0x0002_0518` | `axi_recovery_policy.v` | `2'b00` (`OKAY`) | Silently ignored |
| `LOG_COUNT` | `0x0002_051C` | `axi_recovery_policy.v` | `2'b00` (`OKAY`) | Silently ignored |
| `LOG_TIMESTAMP`| N/A | `axi_recovery_policy.v` | N/A | Non-existent register name (staging reg is `POL_EVENT_TS`) |
| `VGA_STATUS` | `0x0002_0604` | `axi_vga_controller.v` | `2'b00` (`OKAY`) | Silently ignored |

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-REG-03`: Note that writes to RO registers complete with `OKAY` rather than bus error, and exclude offset `0x0002_0008` from read-only write checks due to `UART_FCR` overlap.

---

### B5. Interconnect Error Response (DECERR vs. SLVERR)

#### Question
Does an unmapped address access return `DECERR` (`2'b11`) or `SLVERR` (`2'b10`)?

#### Answer
The interconnect exclusively returns `DECERR` (`2'b11`); it never returns `SLVERR` (`2'b10`).

#### Evidence
- **`rtl/interconnect/axi_interconnect.v:642, 734`**:
  ```verilog
  axi_bresp_next = 2'b11; // DECERR
  s_axi_rresp_int = 2'b11; // DECERR
  ```
- **`rtl/interconnect/axi_crossbar_wr.v:400` & `axi_crossbar_rd.v:352`**:
  ```verilog
  wire [1:0] m_axi_bresp_mux = {2'b11, int_m_axi_bresp} >> b_grant_encoded*2;
  wire [1:0] s_axi_rresp_mux = {2'b11, int_s_axi_rresp} >> r_select_reg*2;
  ```

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-DEC-02` and `TP-ERR-05`: Require `DECERR` (`2'b11`) exclusively; reject `SLVERR`.

---

### B6. AXI Interconnect Arbitration Policy

#### Question
Is the arbiter round-robin or fixed priority? Is it per-slave or global? Can a master get more than 2 consecutive grants while another requests? Does the grant stay fixed for a whole burst?

#### Answer
Arbitration is strictly round-robin and instantiated per-slave; consecutive grants to one master while another requests cannot exceed 1; grants stay locked for the entire burst until `wlast` / `rlast` completes.

#### Evidence
- **`rtl/interconnect/axi_crossbar_wr.v:515-526` & `axi_crossbar_rd.v:449-460`**:
  ```verilog
  for (n = 0; n < M_COUNT; n = n + 1) begin : m_axi_aw
      arbiter #(
          .PORTS(S_COUNT),
          .ARB_TYPE_ROUND_ROBIN(1),
          .ARB_BLOCK(1),
          .ARB_BLOCK_ACK(1),
          .ARB_LSB_HIGH_PRIORITY(1)
      ) a_arb_inst (...);
  ```
- **`rtl/interconnect/arbiter.v:101-118`**:
  ```verilog
  if (masked_request_valid) begin
      grant_next = masked_request_mask;
      mask_next  = {PORTS{1'b1}} << (masked_request_index + 1);
  end
  ```
  Masking out the granted master forces the arbiter to service other pending requests on the very next grant cycle (strict alternation between 2 competing masters).

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-ARB-01`: Remove contradictory statements ("no more than 2" vs "fail above 3") and specify that under saturated contention between 2 masters, the maximum consecutive grant limit is exactly 1.

---

### B7. Bench B Slave Port S00 Multi-Master Capability

#### Question
Can a second driven master VIP be attached to S00 on Bench B, given that the plan claims S00 is terminated with a passive monitor?

#### Answer
Yes; S00 in `axi_interconnect_wrap_3x8.v` is a fully bidirectional, symmetric AXI4 slave port with identical read and write capabilities as S01, and `tb/tb_axi_interconnect.v` already drives both S00 and S01 concurrently.

#### Evidence
- **`rtl/soc_top.v:815-850`**: S00 exposes complete AXI write and read channels (`s00_axi_aw*`, `s00_axi_w*`, `s00_axi_b*`, `s00_axi_ar*`, `s00_axi_r*`).
- **`tb/tb_axi_interconnect.v:1043, 1098`**: Implements both `m0_write` (S00) and `m1_write` (S01).

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` §3.1 and `TP-ARB-04`: Update Bench B architecture to configure S00 as an active AXI Master VIP rather than a passive monitor, enabling multi-master burst atomicity verification without VeeR firmware dependencies.

---

### B8. Crash-Loop Execution Flow & Firmware Status

#### Question
In `tb_soc_top.v`, reset is triggered before recording the event, causing lockout after 3 resets. Does any firmware implement the real crash-loop flow, and if so, what order does it use?

#### Answer
No firmware in `firmware/` (`main.c` or `firmware/test/*.c`) implements the full crash-loop remediation loop; the flow exists solely as testbench stimulus tasks in `tb/tb_soc_top.v`.

#### Evidence
- **`firmware/test/` directory inventory**: Contains unit suites only (`test_all.c`, `test_uart.c`, `test_heartbeat.c`, `test_recovery_policy.c`, etc.). Neither `test_crashloop_lockout.c` nor `test_watchdog_remediation.c` (referenced in draft plan Table 3.4) exist on disk.
- **`tb/tb_soc_top.v:1264-1268`**:
  ```verilog
  periph_write(RST_BASE, RST_CTRL, 32'h0001); // 1. Trigger reset
  repeat (40) @(posedge clk);
  periph_write(POL_BASE, POL_EVENT_TS, 32'h0000_3000);
  periph_write(POL_BASE, POL_CTRL, 32'h0001); // 2. Record event (lockout occurs AFTER 3 resets)
  ```

#### Confidence
**Proven by Code Inspection.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-E2E-03`: Document that firmware has not yet been authored for automated crash-loop suppression, and formally define whether the architectural standard requires recording the event before or after the reset trigger.

---

### B9. Reset Hold Limit and Behavior at Zero

#### Question
Is `RST_HOLD_CYCLES` 32 bits wide in RTL, what is the maximum value, and what does `RST_HOLD_CYCLES = 0` do?

#### Answer
`RST_HOLD_CYCLES` is 32 bits wide with a maximum value of `32'hFFFF_FFFF` ($4,294,967,295$ cycles); writing `0` is accepted without hanging or underflow and produces an active reset pulse of exactly 2 clock cycles.

#### Evidence
- **`rtl/custom_ips/reset_sequencer.v:29-30, 84-88`**:
  ```verilog
  reg [31:0] rst_countdown;
  reg [31:0] rst_hold_cycles_reg; // 32-bit register
  ...
  ST_ASSERT: begin
      if (rst_countdown == 32'd0) begin
          rst_state <= ST_DEASSERT;
      end else begin
          rst_countdown <= rst_countdown - 32'd1;
      end
  end
  ```
  When `rst_hold_cycles_reg == 0`, `rst_countdown` loads with 0 in `ST_ASSERT` (cycle 1), immediately transitions to `ST_DEASSERT` on the next edge (cycle 2), and releases `reset_out <= 1` on cycle 3, yielding a 2-cycle pulse.

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-RST-03`: Document that `RST_HOLD_CYCLES = 0` produces a 2-cycle pulse ($N+2$ cycles total pulse width).

---

### B10. Counter Widths and Zero Parameter Boundaries

#### Question
What are the counter widths and behaviors for `HB_THRESHOLD = 0`, `POL_THRESHOLD = 0`, and `POL_WINDOW = 0`?

#### Answer
- `HB_THRESHOLD` is 32 bits; setting `0` disables watchdog timeout detection while counter runs.
- `POL_THRESHOLD` is 8 bits; setting `0` disables lockout assertion, allowing infinite events.
- `POL_WINDOW` is 32 bits; setting `0` freezes the window counter at 0, turning event counting into an infinite cumulative lifetime count.

#### Evidence
- **`rtl/custom_ips/heartbeat_monitor.v:28, 115`**:
  ```verilog
  reg [31:0] hb_threshold_reg;
  ...
  else if (hb_counter >= hb_threshold_reg && hb_threshold_reg != 32'd0) begin
      hb_unresponsive_flag <= 1'b1; ... // Condition false when threshold == 0
  ```
- **`rtl/custom_ips/recovery_policy.v:32, 192-194`**:
  ```verilog
  reg [7:0] policy_threshold_reg;
  ...
  if ((window_recovery_count + 8'd1) >= policy_threshold_reg && policy_threshold_reg != 8'd0) begin
      lockout_flag <= 1'b1; ... // Condition false when threshold == 0
  ```
- **`rtl/custom_ips/recovery_policy.v:31, 166-173`**:
  ```verilog
  reg [31:0] policy_window_reg;
  ...
  if (policy_window_reg != 32'd0) begin ... end // Window counter disabled when 0
  ```

#### Confidence
**Proven by RTL.**

#### Suggested Fix
Update `docs/arch/14_testplan.md` `TP-REG-01` and functional coverage models: Document value `0` for each of these three registers as special functional "feature disable" operating modes.

---

## 3. Summary Table: All Items Status

| Item ID | Target Feature / Area | Resolved by RTL? | Core Answer Summary | Needs User Decision? |
|---|---|---|---|---|
| **A1** | SOC-005 (Reset during AXI) | **YES** | Transaction aborted; registers synchronously clear; no channel hangs. | No |
| **A2** | SOC-009 (DCCM ECC) | **YES** | 7-bit ECC in RAM; top-level error pins unconnected; core traps internally. | **YES (Decision 1)** |
| **A2b**| OQ-07 (DCCM ECC Question) | **YES** | Closed at SoC level; ECC exists structurally; no external IRQs. | No |
| **A3** | XBR-003 (Unmapped offset) | **YES** | All 7 IPs return `OKAY` (`2'b00`); data is zero or aliased; writes dropped. | No |
| **A4** | XBR-004 (Master S02 block) | **YES** | Blocked via parameter zero-extension; returns `DECERR` (`2'b11`). | **YES (Decision 2)** |
| **A5** | XBR-007 (ROM write sink) | **YES** | Returns `OKAY` (`2'b00`) with 1-cycle latency; writes silently dropped. | No |
| **A6** | HBM-05 (Edge vs Timeout) | **YES** | Rising edge wins; comparator uses `>=`; flag/IRQ has 1-cycle latency. | No |
| **A7** | RST-06 (Re-trigger boundary)| **YES** | Trigger ignored during active pulse or boundary; FSM only accepts in IDLE. | No |
| **A8** | POL-04 (Window rollover race)| **YES** | Event increment wins over window reset; lockout asserts ($3 \ge 3$). | No |
| **A9** | POL-09 (Single rollover event)| **YES** | `window_recovery_count` becomes 1 (increment wins). | No |
| **A10**| PER-03 (UART gasket skew) | **YES** | Crossbar arbiter serializes transactions per slave; no multi-master hazard. | No |
| **B1** | RST_STATUS bit definitions | **YES** | Bit 0 = `in_progress`, Bit 1 = `complete` in RTL. Plan was incorrect. | No |
| **B2** | LOG_COUNT saturation | **YES** | Saturates at `32'hFFFF_FFFF`; only 4-bit write pointer wraps at 16. | No |
| **B3** | Reset exclusion list | **YES** | WO registers, live timer, and GPIO bit 0 excluded. Full reset table provided. | No |
| **B4** | Write to RO registers | **YES** | Returns `OKAY` and drops data; offset 0x08 on UART writes `UART_FCR`. | No |
| **B5** | Unmapped address response | **YES** | Interconnect crossbar exclusively returns `DECERR` (`2'b11`). | No |
| **B6** | Interconnect arbitration | **YES** | Per-slave round-robin; consecutive grant limit $\le 1$; locked across burst. | **YES (Decision 3)** |
| **B7** | Bench B S00 termination | **YES** | S00 is fully functional bidirectional AXI4; can host active Master VIP. | **YES (Decision 4)** |
| **B8** | Crash-loop firmware flow | **YES** | No firmware implements crash-loop yet; tb_soc_top triggers reset first. | **YES (Decision 5)** |
| **B9** | Reset hold limit & 0 value | **YES** | 32-bit register; hold=0 is valid and creates a 2-cycle pulse ($N+2$ total). | No |
| **B10**| Threshold/window 0 bounds | **YES** | HB_THRESH=0 (no timeout); POL_THRESH=0 (no lockout); POL_WIN=0 (lifetime count). | No |

---

## 4. Decisions Needed from User

The following architectural and verification strategy decisions are required where design trade-offs, potential integration bugs, or testbench topology divergences exist:

### Decision 1: DCCM ECC Error Signaling at SoC Boundary (Item A2)
- **Context:** In `rtl/soc_top.v:1808-1809`, `.dccm_ecc_single_error()` and `.dccm_ecc_double_error()` from the VeeR EL2 core are unconnected. Double-bit errors trigger internal RISC-V synchronous exceptions, but external system supervisors cannot observe memory corruption.
- **Options:**
  - *Option A (Keep As-Is):* Retain unconnected pins. ECC verification will rely exclusively on internal core trap handling (`mcause`, `mtval`).
  - *Option B (Hardware Enhancement):* Wire `dccm_ecc_double_error` to an unused bit in `GPIO_STAT` or route to PIC interrupt line 4 so firmware/external pins can log ECC fatal events.
- **Recommendation:** Maintain **Option A** for baseline verification (adheres to zero-RTL-change rule), and document that ECC testing is restricted to core-internal exception monitoring.

---

### Decision 2: Master S02 (System Bus / JTAG Debug) Peripheral Access Policy (Item A4)
- **Context:** Passing `2'b11` to `Mxx_CONNECT_*` in `soc_top.v:762-805` isolates Master S02 from all peripherals M00..M06, causing any JTAG/Debug access to return `DECERR`.
- **Options:**
  - *Option A (Security Isolation):* Confirm that Master S02 is intentionally prohibited from accessing watchdog, reset sequencer, and peripherals for security hardening.
  - *Option B (Bug in Port Width Expansion):* Treat this as an indexing bug (intended to be `3'b111` when S02 was added).
- **Recommendation:** Verify test `TP-DEC-03` according to **Option A** (`DECERR` returned), as that is the actual RTL behavior. If Option B is desired, it must be logged as a future RTL bug fix.

---

### Decision 3: Alignment of Test Plan Arbitration Grant Limit (Item B6)
- **Context:** `docs/arch/14_testplan.md` `TP-ARB-01` contains conflicting assertions: it states "no more than 2 consecutive grants" in one sentence and "fail above 3" in another. RTL analysis of `arbiter.v` proves that round-robin masking guarantees strict alternating grants ($\le 1$ consecutive grant) under competing continuous requests.
- **Options:**
  - *Option A:* Update `TP-ARB-01` to enforce strict $\le 1$ consecutive grant for two competing masters.
  - *Option B:* Allow a loose bound ($\le 2$) to accommodate pipelined address buffering.
- **Recommendation:** Adopt **Option A**, matching the mathematical behavior of `arbiter.v`.

---

### Decision 4: Bench B S00 Interface Agent Mode (Item B7)
- **Context:** `docs/arch/14_testplan.md` §3.1 states S00 (IFU) is terminated with a passive monitor in Bench B, but multi-master tests `TP-ARB-04` (burst atomicity) and `TP-GAP-06` (UART gasket race) require driving two masters simultaneously without firmware.
- **Options:**
  - *Option A:* Configure S00 as an active AXI Master VIP on Bench B.
  - *Option B:* Keep S00 passive on Bench B and move all multi-master tests to Bench A (requiring complex assembly/C test firmware on VeeR).
- **Recommendation:** Adopt **Option A**. The crossbar treats S00 and S01 identically; configuring S00 as an active VIP allows direct, cycle-accurate multi-master contention testing.

---

### Decision 5: Architectural Sequence for Crash-Loop Lockout Flow (Item B8)
- **Context:** In `tb/tb_soc_top.v`, the testbench issues `RST_CTRL = 1` *before* logging the event in `recovery_policy`, allowing $K$ resets before lockout asserts. In contrast, standard safety remediation would check lockout and record the event *before* triggering reset, stopping at $K-1$ resets. No firmware currently implements this.
- **Options:**
  - *Option A (Reset-Then-Record):* Allow $K$ host resets. The $K$-th event trips lockout, preventing the $(K+1)$-th reset.
  - *Option B (Record-Then-Reset):* Check lockout prior to triggering reset. Exactly $K-1$ resets occur; the $K$-th timeout is blocked from resetting.
- **Recommendation:** Adopt **Option A** for consistency with the existing regression benchmark in `tb/tb_soc_top.v:1264-1268`.
