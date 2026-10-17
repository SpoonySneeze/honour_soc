# Verification Open Questions, Specification Gaps, and Risk Analysis

**Document ID:** `docs/arch/09_open_questions.md`  
**Stage:** Stage 9 — Audit of Unclear/Inferred Items, Spec Discrepancies, Gaps, and Ranked Risk Areas  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) through [`docs/arch/08_existing_verif.md`](file:///home/student/sriv_183/honour_soc/docs/arch/08_existing_verif.md)  

---

## 1. Master Table of UNCLEAR, NOT FOUND, and [INFERRED] Items

In accordance with Ground Rule 2 and Ground Rule 3, the table below compiles every fact that is unconfirmed, absent from the repository, or inferred through code analysis, along with the precise question that must be answered and where to look.

| ID | Item Classification | Specific Item & Location | Question to Answer | Where to Look to Confirm |
|---|---|---|---|---|
| **OQ-01** | **NOT FOUND** | Synthesis & Timing Constraints (`*.xdc`, `*.sdc`) | Are there target physical or synthesis timing constraints (clock jitter, input/output delays, max transition) for FPGA or ASIC implementation? | Design release bundle, FPGA top-level project, or synthesis automation scripts outside repository. |
| **OQ-02** | **NOT FOUND** | UVM Testbench Environment | Does any legacy or third-party UVM testbench component (agents, scoreboards, envs, sequences) exist for this SoC? | Verification infrastructure repositories or university coursework archives. |
| **OQ-03** | **[INFERRED]** | Master S02 (VeeR SB / Debug) Interconnect Masking (`soc_top.v:762-805`) | Is the disconnection of Master S02 from peripheral ports M00–M06 (caused by passing literal `2'b11` to 3-bit parameter `Mxx_CONNECT_*`) intentional security isolation, or an indexing bug during interconnect expansion? | Hardware architecture meeting minutes, SoC integration PR review comments, or system architect. |
| **OQ-04** | **[INFERRED]** | AXI-to-Wishbone Bridge (`axi4_to_wb_bridge.v:17`) | Is this uninstantiated bridge retained purely as legacy IP from a predecessor SoC architecture, or is it planned for future Wishbone peripheral integration? | Git commit history or SoC roadmap documentation. |
| **OQ-05** | **[INFERRED]** | 128-bit AES Crypto Accelerator (`rtl/ips/aes_core/rtl/verilog/aes_axi.v:14`) | Is the uninstantiated AES core planned to be integrated as Slave M08 on the crossbar, or is it dead repository code? | Architecture specification updates or milestone planning docs. |
| **OQ-06** | **UNCLEAR** | AXI Boot ROM Write Response (`rtl/custom_ips/axi_rom.v:11`) | When a bus master (LSU or SB) issues a write transaction to the Boot ROM address window (`0x8000_0000`–`0x8000_1FFF`), does the ROM drive `SLVERR` (`2'b10`), `DECERR` (`2'b11`), or return `OKAY` (`2'b00`) with silent data discard? | Detailed inspect of `axi_rom.v` slave write response FSM logic. |
| **OQ-07** | **[INFERRED]** | `GPIO_STATUS` Reset Default Value (`soc_top.v:1346`) | Since `reset_out_internal` defaults to `1'b1` (active-low deasserted) on system reset, does `GPIO_STATUS` reset to `32'h0000_0002`? | Verification bench simulation check of `u_gpio` output at cycle 0 after reset release. |
| **OQ-08** | **UNCLEAR** | VGA Frame Buffer Read Access | Can the CPU read back character bytes from `VGA_BUFFER` (`0x0002_0608`–`0x0002_067C`), or is the buffer strictly write-only? If read, does it return written ASCII characters or 0? | Inspection of `axi_vga_controller.v` read multiplexer decoding. |
| **OQ-09** | **UNCLEAR** | Heartbeat Edge Detection Pulse Width | Does `heartbeat_in` require a minimum pulse high duration (e.g., 2+ clock cycles) to guarantee detection by `hb_prev_sample`, or is a single-cycle glitch sufficient? | Asynchronous pad filtering and edge-detection synchronizer specification. |
| **OQ-10** | **UNCLEAR** | PIC Interrupt Servicing Mode | Does firmware service interrupts in vectored mode or direct mode (`mtvec.MODE`), and what are the software acknowledge requirements for each peripheral IRQ? | Firmware BSP interrupt vector table and `el2_pic_ctrl.sv` register programming guide. |

---

## 2. RTL Implementation vs. Architectural Documentation Discrepancies

In accordance with Ground Rule 4, the table below documents all locations where the written architecture documentation ([`docs/BMC_Architecture_MicroArchitecture_Spec.md`](file:///home/student/sriv_183/honour_soc/docs/BMC_Architecture_MicroArchitecture_Spec.md)) directly contradicts the actual synthesizable RTL code.

| Area of Conflict | Documentation Claim | Actual RTL Implementation | Analysis & Verification Impact |
|---|---|---|---|
| **Peripheral Interconnect Bus Architecture** | Section 1 & Section 3 claim that all peripherals connect via an **AXI-to-Wishbone bridge** to a shared 32-bit Wishbone B4 bus (`Spec:33, 261-277, 351`). | [`soc_top.v:751-1300`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L751-L1300) instantiates a **pure 64-bit AXI4 crossbar** (`axi_interconnect_wrap_3x8`). All peripherals are native AXI wrappers. The bridge `axi4_to_wb_bridge.v` is uninstantiated. | **High Impact**: Testbench agents must drive and monitor pure AXI4 / AXI-Lite protocols at peripheral boundaries, not Wishbone signals. |
| **Unmapped Address Decode Error Response** | Section 1 states that unmapped address accesses return AXI `SLVERR` (`2'b10`) (`Spec:23`). | [`axi_interconnect.v:642, 734`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L642) explicitly drives `bresp = 2'b11` and `rresp = 2'b11` (`DECERR`). | **Medium Impact**: Protocol assertions checking invalid address accesses must expect `DECERR` (`2'b11`), not `SLVERR`. |
| **Watchdog Interrupt Architectural Status** | Section 3.5 & Section 6 claim `hb_irq` is an "optional enhancement" and describe polling `HB_STATUS` as the primary path (`Spec:286, 598`). | [`soc_top.v:1600`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L1600) hard-wires `hb_irq` directly into the VeeR core PIC interrupt vector (`extintsrc_req[1]`). | **Medium Impact**: Verification must validate both interrupt-driven handling and register polling mechanisms. |
| **Peripheral Addressing Scheme** | Early sections describe 16-bit local offsets (`0x0000`, `0x0100`, `0x0200`). | [`soc_top.v:760-805`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L760-L805) and [`firmware/test/test_common.h:9-15`](file:///home/student/sriv_183/honour_soc/firmware/test/test_common.h#L9-L15) map peripherals to 32-bit addresses `0x0002_0000` through `0x0002_06FF`. | **Low Impact**: Verification addresses must target the 32-bit physical map. |

---

## 3. Specification Gaps & Undefined Behaviors

The following functional scenarios are not defined in the specification or code comments and represent ambiguous corner cases:

1. **Heartbeat Pulse vs. Timeout Comparator Collision**:
   - *Undefined Behavior*: What happens if a rising edge on `heartbeat_in` occurs on the **exact clock cycle** that `hb_counter` reaches `HB_THRESHOLD`?
   - *Verification Risk*: Does the synchronous counter reset take precedence (clearing the counter and suppressing timeout), or does the comparator latch `unresponsive_flag = 1` and assert `hb_irq` for a single cycle?
2. **Access During Active Reset**:
   - *Undefined Behavior*: If an AXI master attempts an access while `rst_n` is asserted, or on the exact cycle of reset release, does the interconnect deadlock, drop the transaction silently, or return `DECERR`?
3. **Circular Log Buffer Pointer Wrap & Overwrite Policy**:
   - *Undefined Behavior*: When `log_count > 16`, the 4-bit write pointer wraps around, overwriting older timestamps. There is no `log_full` or `overflow_flag` register bit to notify firmware that records were discarded.
   - *Verification Risk*: Testbench must verify that firmware can detect wrap-around strictly by comparing `LOG_COUNT` against 16.
4. **Reset Sequencer Re-trigger Collision**:
   - *Undefined Behavior*: What happens if firmware writes `RST_CTRL.trigger = 1` on the exact clock cycle that `rst_countdown` reaches 0 (transition from `ASSERT` to `DONE`)? Does the new trigger launch immediately, or is it discarded?
5. **Recovery Policy Window Rollover vs. Event Recording Race**:
   - *Undefined Behavior*: If `POL_CTRL.record_event` is written on the exact clock cycle that `window_counter` reaches `POL_WINDOW`, does `window_recovery_count` reset to 0 first (resulting in count = 1 in the new window), or does it increment before the reset (resulting in count = 0 or count = old+1)?
6. **Concurrent Multi-Master Access to UART Gasket**:
   - *Undefined Behavior*: The 64-to-32 bit bus gasket in `soc_top.v:687-693` uses a shared register `uart_awaddr2_r` latched on `AWVALID & AWREADY`. If two masters issue interleaved write addresses and write data beats, can `uart_awaddr2_r` become corrupted, causing data to be steered to the wrong 32-bit lane?

---

## 4. Verification Risk Areas (Ranked by Risk Level)

The table below ranks the top verification risk areas across the SoC, providing justifications based on micro-architectural complexity.

| Rank | Risk Area | Associated Blocks / Interfaces | Justification & Micro-Architectural Failure Mechanism |
|---|---|---|---|
| **1** | **Interconnect Master Disconnection Bug (S02 Masking)** | `u_axi_intercon`, `u_veer.sb`, Peripherals M00–M06 | In `soc_top.v:762-805`, passing `2'b11` to 3-bit parameter `Mxx_CONNECT_*` zero-extends to `3'b011`, severing Master S02 (System Bus / JTAG Debug) from accessing any peripheral. This prevents external JTAG debuggers from reading watchdog state, triggering resets, or inspecting logs. |
| **2** | **Watchdog Edge Detection & Timeout Collision** | `u_heartbeat`, `heartbeat_in`, `hb_irq` | Cycle-accurate race condition between `heartbeat_in` rising pulse and `hb_counter == HB_THRESHOLD`. Corner cases involving pulse widths near clock period boundary or pulses arriving simultaneously with timeout declaration can cause intermittent glitching or false interrupts. |
| **3** | **UART Bus Gasket Steering & Channel Phase Skew** | `soc_top.v:685-700`, `u_uart` | Gasket latches `awaddr[2]` into `uart_awaddr2_r` on write address handshake, but write data handshake (`WVALID & WREADY`) may lag by multiple arbitrary wait states. Skew between address and data channels or backpressure stalls can cause incorrect byte-lane selection. |
| **4** | **Rolling Window Lockout Timing Precision** | `u_rec_policy`, `u_timer`, `lockout_irq` | Dual asynchronous counters (`window_counter` vs `log_count`) interacting with threshold comparators. Window rollover boundaries represent a high-risk zone where rapid recovery bursts could either prematurely trigger lockout or fail to trigger lockout due to counter reset races. |
| **5** | **Reset Output Glitch Immunity & Isolation** | `u_reset_seq`, `reset_out`, `soc_top` pads | `reset_out` controls physical motherboard power rails. Spurious transitions, glitches during power-up/reset release, or accidental re-triggering during active hold countdown could cause uncontrolled power-cycling of the host server. |

---

## 5. Hard-to-Observe / Hard-to-Control Features & Internal Signals

The table below lists internal hardware signals that are critical for functional verification and assertion coverage but cannot be observed or controlled directly through boundary pins or memory-mapped registers.

| Subsystem | Hidden Internal Signal | Hierarchical RTL Path | Verification Need / Visibility Requirement |
|---|---|---|---|
| **Heartbeat Monitor** | Free-running cycle counter | `soc_top.u_heartbeat.u_core.hb_counter[31:0]` | Needed by scoreboard to verify cycle-accurate watchdog elapsed timing without waiting for AXI register read. |
| **Heartbeat Monitor** | Edge sample flip-flop | `soc_top.u_heartbeat.u_core.hb_prev_sample` | Needed by temporal assertions to check pulse edge detection and noise filtering. |
| **Reset Sequencer** | Reset duration countdown | `soc_top.u_reset_seq.u_core.rst_countdown[31:0]` | Needed to verify that reset pulse duration decrements monotonically without truncation or skip. |
| **Recovery Policy** | Circular RAM write pointer | `soc_top.u_rec_policy.u_core.log_wr_ptr[3:0]` | Needed to verify log entry indexing and circular wrap-around behavior after 16 events. |
| **Recovery Policy** | Rolling window cycle counter | `soc_top.u_rec_policy.u_core.window_counter[31:0]` | Needed to observe exact cycle timing of window expiration and verify window reset precision. |
| **AXI Interconnect** | Crossbar arbitration grant | `soc_top.u_axi_intercon.axi_interconnect_inst.grant_reg[2:0]` | Needed by arbiter scoreboard to verify round-robin fairness under heavy multi-master contention. |
| **AXI Interconnect** | Crossbar FSM state | `soc_top.u_axi_intercon.axi_interconnect_inst.state_reg[2:0]` | Needed to check illegal state transitions and verify decode drop latency. |
| **UART 16550** | RX and TX FIFO occupancy | `soc_top.u_uart.axi_internal_fifo_rx_inst.fifo_counter_o`<br>`soc_top.u_uart.axi_internal_fifo_tx_inst.fifo_counter_o` | Needed to verify FIFO watermarks, overrun detection, and interrupt trigger thresholds. |
| **VeeR Core PIC** | Interrupt pending & claim IDs | `soc_top.u_veer.veer.pic_ctrl_inst.meip[30:0]`<br>`soc_top.u_veer.veer.pic_ctrl_inst.claimid[7:0]` | Needed to verify interrupt delivery, priority preemption, and acknowledge clearing inside the core. |
