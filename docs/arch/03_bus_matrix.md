# Interconnect Architecture & Master-Slave Bus Matrix

**Document ID:** `docs/arch/03_bus_matrix.md`  
**Stage:** Stage 3 — Bus Protocols, Interconnect Engines, Connectivity Matrix, and Protocol Analysis  
**Target:** Honour SoC Verification Architecture & UVM Planning  
**Prior Reference:** Analyzed in accordance with [`docs/arch/01_inventory.md`](file:///home/student/sriv_183/honour_soc/docs/arch/01_inventory.md) and [`docs/arch/02_blocks.md`](file:///home/student/sriv_183/honour_soc/docs/arch/02_blocks.md)  

---

## 1. Bus Protocols, Interconnect Modules, and Decoders

### 1.1 Bus Protocols Present in Design
1. **AXI4 (Full Specification, `AMBA AXI Protocol v2.0 / AXI4`)**:
   - The primary system backbone protocol operating at 64-bit data width (`DATA_WIDTH = 64`) and 32-bit address width (`ADDR_WIDTH = 32`).
   - Supports 5 independent, concurrent channels: Write Address (`AW`), Write Data (`W`), Write Response (`B`), Read Address (`AR`), and Read Data (`R`).
   - Supports out-of-order transaction completion and thread tagging via 8-bit transaction IDs (`ID_WIDTH = 8`).
   - Implemented between the VeeR EL2 core masters (IFU, LSU, SB), the central crossbar (`u_axi_intercon`), and all peripheral IP wrappers.
2. **AXI4-Lite**:
   - Simplified single-beat subset of AXI4 (burst length fixed to 1, no burst types, no caching).
   - Used natively at the slave interface of the ingested 16550 UART core (`axi_uart_top.v:28-115`).
   - Integrated into the 64-bit crossbar via a dedicated 64-to-32 bit address steering and data replication gasket in [`rtl/soc_top.v:685-700`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L685-L700).
3. **Wishbone B4 (Pipelined / Classic)**:
   - Present on disk in [`rtl/custom_ips/axi4_to_wb_bridge.v:17-45`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi4_to_wb_bridge.v#L17-L45) and referenced extensively throughout [`docs/BMC_Architecture_MicroArchitecture_Spec.md:261-277`](file:///home/student/sriv_183/honour_soc/docs/BMC_Architecture_MicroArchitecture_Spec.md#L261-L277).
   - **RTL Reality**: **Uninstantiated** in [`rtl/soc_top.v`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L751-L1578). All custom IPs connect directly to the 64-bit AXI4 crossbar through native AXI wrappers.

### 1.2 Interconnect, Bridge, Decoder, and Arbiter File Inventory

| Sub-System Component | Module Name | Source File | Key Role & Implementation Summary |
|---|---|---|---|
| **Interconnect Top Wrapper** | `axi_interconnect_wrap_3x8` | [`rtl/interconnect/axi_interconnect_wrap_3x8.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect_wrap_3x8.v#L34) | Instantiates the 3x8 crossbar core and binds system parameter overrides (base addresses, address masks, connection bits, and ID forwarding). |
| **Crossbar Matrix Engine** | `axi_interconnect` | [`rtl/interconnect/axi_interconnect.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L34) | Core routing matrix containing master/slave channel multiplexers, transaction state machines (`STATE_IDLE`, `STATE_DECODE`, `STATE_WRITE`, `STATE_READ`, `STATE_DROP`), and admission control. |
| **Address Decoder** | `axi_interconnect` (inlined logic) | [`rtl/interconnect/axi_interconnect.v:611-647`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L611-L647) | Iterates over target regions (`M_ADDR_WIDTH`, `M_BASE_ADDR_INT`, `M_SECURE`), checks master connection bitmask (`M_CONNECT_READ`/`M_CONNECT_WRITE`), and selects target slave port. |
| **Arbiter Sub-Module** | `arbiter` | [`rtl/interconnect/arbiter.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/arbiter.v#L34) | Parameterized request arbiter supporting both round-robin and fixed-priority schemes; resolves conflicting concurrent master requests. |
| **Priority Encoders** | `priority_encoder` | [`rtl/interconnect/priority_encoder.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/priority_encoder.v#L34) | Dual priority encoders (base and masked) calculating grant index for round-robin arbitration. |
| **Pipeline Registers (Skid Buffers)** | `axi_register_rd`, `axi_register_wr` | [`rtl/interconnect/axi_register_rd.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_register_rd.v#L34)<br>[`rtl/interconnect/axi_register_wr.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_register_wr.v#L34) | Internal pipeline registers decoupling timing paths across crossbar interfaces. |
| **UART 64-to-32 Bit Bus Gasket** | Inlined glue logic in `soc_top` | [`rtl/soc_top.v:685-700`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L685-L700) | Latches `awaddr[2]` on address handshake to steer write data/strobes to upper/lower 32-bit lanes; replicates 32-bit UART read data across both 32-bit lanes of 64-bit read bus. |
| **AXI4-to-Wishbone Bridge (Legacy)** | `axi4_to_wb_bridge` | [`rtl/custom_ips/axi4_to_wb_bridge.v:17`](file:///home/student/sriv_183/honour_soc/rtl/custom_ips/axi4_to_wb_bridge.v#L17) | Standalone protocol bridge converting 64-bit AXI4 to 32-bit Wishbone B4 with address steering and error mapping; uninstantiated in active SoC top-level. |

---

## 2. Bus Masters and Bus Slaves

### 2.1 Bus Masters

| Master Port ID | Master Name | Originating Block | Data Bus Width | ID Width | Supported Transaction Types | Role in SoC | Source Citation |
|---|---|---|---|---|---|---|---|
| **S00** | `VeeR_IFU` | Instruction Fetch Unit (`u_veer`) | 64-bit | 8-bit | Read Bursts (`AR`, `R`) | Fetches instructions from 8KB Boot ROM (`u_rom`) or external memory space. Write channels are tied off or unused. | `rtl/soc_top.v:814-850, 1605-1644` |
| **S01** | `VeeR_LSU` | Load/Store Unit (`u_veer`) | 64-bit | 8-bit | Read & Write Single-beat and Bursts | Issues data read and write transactions to memory and memory-mapped peripheral registers. | `rtl/soc_top.v:853-895, 1646-1685` |
| **S02** | `VeeR_SB` | System Bus / Debug (`u_veer`) | 64-bit | 8-bit | Read & Write Single-beat and Bursts | Services external JTAG debug master requests (DMI) and direct system bus transfers. | `rtl/soc_top.v:897-939, 1687-1726` |

### 2.2 Bus Slaves

| Slave Port ID | Slave Name | Target Block | Address Range | Window Size | Native Data Width | Supported Access | Source Citation |
|---|---|---|---|---|---|---|---|
| **M00** | `UART` | `u_uart` (`axi_uart_top`) | `0x0002_0000`–`0x0002_00FF` | 256 B | 32-bit (AXI-Lite) | Read / Write | `rtl/soc_top.v:705-739, 760-764` |
| **M01** | `TIMER` | `u_timer` (`axi_timer`) | `0x0002_0100`–`0x0002_01FF` | 256 B | 64-bit (AXI4) | Read (Write ignored) | `rtl/soc_top.v:1303-1341, 767-771` |
| **M02** | `GPIO` | `u_gpio` (`axi_gpio`) | `0x0002_0200`–`0x0002_02FF` | 256 B | 64-bit (AXI4) | Read (Write ignored) | `rtl/soc_top.v:1346-1386, 774-778` |
| **M03** | `HEARTBEAT` | `u_heartbeat` (`axi_heartbeat_monitor`) | `0x0002_0300`–`0x0002_03FF` | 256 B | 64-bit (AXI4) | Read / Write | `rtl/soc_top.v:1391-1430, 781-785` |
| **M04** | `RESET_SEQ` | `u_reset_seq` (`axi_reset_sequencer`) | `0x0002_0400`–`0x0002_04FF` | 256 B | 64-bit (AXI4) | Read / Write | `rtl/soc_top.v:1437-1472, 788-792` |
| **M05** | `REC_POL` | `u_rec_policy` (`axi_recovery_policy`) | `0x0002_0500`–`0x0002_05FF` | 256 B | 64-bit (AXI4) | Read / Write | `rtl/soc_top.v:1490-1525, 795-799` |
| **M06** | `VGA` | `u_vga` (`axi_vga_controller`) | `0x0002_0600`–`0x0002_06FF` | 256 B | 64-bit (AXI4) | Read / Write | `rtl/soc_top.v:1535-1578, 802-806` |
| **M07** | `BOOT_ROM` | `u_rom` (`axi_rom`) | `0x8000_0000`–`0x8000_1FFF` | 8 KB | 64-bit (AXI4) | Read Only | `rtl/soc_top.v:1856-1888, 808-809` |

---

## 3. Master-by-Slave Connectivity Matrix

The connectivity matrix below details the exact interconnect access rights between every bus master and every bus slave, determined by parameter instantiation values in [`rtl/soc_top.v:759-809`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L759-L809) and decode matching logic in [`rtl/interconnect/axi_interconnect.v:615-623`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L615-L623).

| Master Interface | M00: UART (`0x0002_0000`) | M01: TIMER (`0x0002_0100`) | M02: GPIO (`0x0002_0200`) | M03: HEARTBEAT (`0x0002_0300`) | M04: RESET_SEQ (`0x0002_0400`) | M05: REC_POL (`0x0002_0500`) | M06: VGA (`0x0002_0600`) | M07: BOOT_ROM (`0x8000_0000`) |
|---|---|---|---|---|---|---|---|---|
| **S00: VeeR IFU** (Instruction Fetch) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **RESTRICTED**<br>(Read allowed by crossbar mask `bit 0=1`; Write restricted by core IFU role) | **CONNECTED**<br>(Full instruction burst read capability; Primary boot target) |
| **S01: VeeR LSU** (Load/Store Unit) | **CONNECTED**<br>(Read/Write enabled via mask `bit 1=1`) | **CONNECTED**<br>(Read enabled; Writes ignored by timer hardware) | **CONNECTED**<br>(Read enabled; Writes ignored by GPIO hardware) | **CONNECTED**<br>(Read/Write enabled via mask `bit 1=1`) | **CONNECTED**<br>(Read/Write enabled via mask `bit 1=1`) | **CONNECTED**<br>(Read/Write enabled via mask `bit 1=1`) | **CONNECTED**<br>(Read/Write enabled via mask `bit 1=1`) | **RESTRICTED**<br>(Read connected; Writes return error or are discarded) |
| **S02: VeeR SB** (Debug / System Bus) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M00_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M01_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M02_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M03_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M04_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M05_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **NOT CONNECTED**<br>(Blocked by crossbar mask: `M06_CONNECT_*` parameter passed `2'b11`, zero-extended to `3'b011`; bit 2 is 0) | **CONNECTED**<br>(Default parameter `M07_CONNECT_* = 3'b111` applies; Read enabled for debug inspection) |

### 3.1 Detailed Analysis of Decode & Masking Constraints

1. **Parameter Width Mismatch on Ports M00–M06**:
   - In [`rtl/interconnect/axi_interconnect_wrap_3x8.v:54-91`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect_wrap_3x8.v#L54-L91), parameters `Mxx_CONNECT_READ` and `Mxx_CONNECT_WRITE` are declared with width `3` (defaulting to `3'b111`).
   - In [`rtl/soc_top.v:762-805`](file:///home/student/sriv_183/honour_soc/rtl/soc_top.v#L762-L805), `soc_top` instantiates the wrapper passing `.Mxx_CONNECT_READ(2'b11)` and `.Mxx_CONNECT_WRITE(2'b11)`.
   - **RTL Evaluation**: Under IEEE 1364-2001 rules, passing `2'b11` to a 3-bit parameter zero-extends the literal to `3'b011`.
   - **Functional Result**: 
     - `bit 0` (S00 = IFU) is `1` (Connected).
     - `bit 1` (S01 = LSU) is `1` (Connected).
     - `bit 2` (S02 = SB / JTAG Debug) is `0` (**Disconnected / Blocked**).
   - If an external JTAG debugger issues an access through VeeR SB to any peripheral in range `0x0002_0000`–`0x0002_06FF`, the interconnect decode logic evaluates line 617 as false and returns an AXI `DECERR` (`2'b11`).
2. **Port M07 (Boot ROM) Default Connectivity**:
   - `soc_top.v:808-809` specifies `.M07_BASE_ADDR(32'h8000_0000)` and `.M07_ADDR_WIDTH(32'd13)` but **omits** `M07_CONNECT_READ` and `M07_CONNECT_WRITE`.
   - Therefore, M07 inherits the default `3'b111` from `axi_interconnect_wrap_3x8.v:89-90`. S00 (IFU), S01 (LSU), and S02 (SB) are all connected to M07.

---

## 4. Arbitration, Unmapped Address Handling, and Protocol Behaviors

### 4.1 Arbitration Scheme
- **Mechanism**: The crossbar instantiates an independent arbiter core [`arbiter.v:34`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/arbiter.v#L34) for master admission control.
- **Priority Resolution**: Employs **Round-Robin arbitration** (`ARB_TYPE_ROUND_ROBIN = 1` in default wrapper configuration).
- **Masking Logic**: Two instances of `priority_encoder` are used:
  1. `priority_encoder_inst`: Computes unmasked priority from request vector (`arbiter.v:70-79`).
  2. `priority_encoder_masked`: Computes priority from masked vector (`request & mask_reg`), preserving fairness across consecutive cycles (`arbiter.v:87-96`).
- **Locking & Preemption**: An active burst retains master grant until completion; ungranted requests wait in `STATE_IDLE` (`axi_interconnect.v:567-610`).

### 4.2 Handling of Unmapped Addresses and Access Violations
When a bus transaction requests an address outside configured slave windows, or requests an interface with a disabled connection mask bit:
1. **Decode Evaluation**: The decoder in `STATE_DECODE` fails to assert `match = 1'b1` ([`rtl/interconnect/axi_interconnect.v:614-623`](file:///home/student/sriv_183/honour_soc/rtl/interconnect/axi_interconnect.v#L614-L623)).
2. **Write Channel Fallback (`STATE_WRITE_DROP`)**:
   - The interconnect immediately asserts `s_axi_wready = 1'b1` to absorb write data and avoid bus hanging (`axi_interconnect.v:643, 690`).
   - Upon receiving `wlast`, it drives `bvalid = 1'b1` and returns completion code `bresp = 2'b11` (`DECERR`) (`axi_interconnect.v:642, 696`).
3. **Read Channel Fallback (`STATE_READ_DROP`)**:
   - The interconnect enters `STATE_READ_DROP`, drives `rdata = 64'd0`, asserts `rvalid = 1'b1`, and sets `rresp = 2'b11` (`DECERR`) (`axi_interconnect.v:730-737`).
   - It maintains `rlast` assertion aligned with the requested `arlen` to satisfy burst completion rules.
4. **Documentation Discrepancy**:
   - [`docs/BMC_Architecture_MicroArchitecture_Spec.md:23`](file:///home/student/sriv_183/honour_soc/docs/BMC_Architecture_MicroArchitecture_Spec.md#L23) claims unmapped addresses return `SLVERR` (`2'b10`).
   - **RTL Reality**: The interconnect RTL explicitly drives `2'b11` (`DECERR`) on lines 642 and 734.

### 4.3 Wait States, Backpressure, and Handshakes
- All transactions follow standard AXI4 two-way `VALID` / `READY` handshakes:
  - Addresses are latched only on `AWVALID & AWREADY` or `ARVALID & ARREADY`.
  - Data transfer occurs strictly on `WVALID & WREADY` or `RVALID & RREADY`.
- **Wait States**: Slaves that require multiple cycles (e.g., UART with internal FIFO, or crossbar arbitration latency) withhold `READY` until ready to sample or drive. The crossbar preserves requests without dropped cycles.

### 4.4 Data Width Conversion & Byte Steering
- **System Crossbar Width**: Pure 64-bit data path.
- **UART Width Conversion**:
  - In `soc_top.v:687-696`, `uart_awaddr2_r` captures `awaddr[2]`:
    - `awaddr[2] == 0`: Lower 32 bits `wdata[31:0]` and strobes `wstrb[3:0]` are routed to UART.
    - `awaddr[2] == 1`: Upper 32 bits `wdata[63:32]` and strobes `wstrb[7:4]` are routed to UART.
  - Read path replicates 32-bit UART data to both halves: `m00_axi_rdata = {uart_rdata_32, uart_rdata_32}` (`soc_top.v:698`).
- **All Custom IPs**: Natively support 64-bit AXI data interfaces, receiving 64-bit data directly with 8-bit write strobes (`wstrb[7:0]`).

---

## 5. Supported vs. Unsupported AXI Protocol Features

The table below catalogs which standard AMBA AXI4 protocol features are actively supported by the hardware versus those that are unsupported or ignored.

| AXI4 Protocol Feature | Implementation Status | Behavioral Details & Limitations | Source Citation |
|---|---|---|---|
| **Burst Length (`AxLEN`)** | **Supported** | Crossbar supports bursts up to 256 beats (`AxLEN[7:0]`). Boot ROM (`axi_rom`) natively supports multi-beat instruction read bursts. | `axi_interconnect.v:390`<br>`soc_top.v:1861` |
| **Burst Type (`AxBURST`)** | **Partially Supported** | `INCR` (2'b01) supported for memory/ROM bursts. `FIXED` (2'b00) and `WRAP` (2'b10) are passed through crossbar but custom peripheral IPs treat accesses as single-beat registers. | `axi_interconnect.v:392` |
| **Burst Size (`AxSIZE`)** | **Supported** | Supports byte (1B), halfword (2B), word (4B), and doubleword (8B) transfers via `AxSIZE[2:0]`. | `axi_interconnect.v:391` |
| **Byte Write Strobes (`WSTRB`)** | **Supported** | Full 8-bit strobe support (`wstrb[7:0]`). Peripherals utilize strobes to qualify valid byte lane writes. | `axi_interconnect.v:401`<br>`soc_top.v:696, 1403` |
| **Out-of-Order / Thread IDs** | **Supported** | 8-bit ID tracking (`ID_WIDTH = 8`). Crossbar routes `bid` and `rid` matching original `awid` and `arid`. `FORWARD_ID = 1` enabled. | `soc_top.v:755-756`<br>`axi_interconnect.v:352-358` |
| **Error Responses (`RESP`)** | **Supported** | Interconnect drives `DECERR` (`2'b11`) on decode failure or access restriction. Custom IPs drive `OKAY` (`2'b00`) on valid access. | `axi_interconnect.v:642, 734` |
| **Exclusive Access (`AxLOCK`)** | **Unsupported** | `AxLOCK` signals are accepted by crossbar ports but exclusive reservation monitors (atomic load-linked / store-conditional) are not implemented in the peripheral slaves. | `soc_top.v:819, 858` |
| **Quality of Service (`AxQOS`)** | **Unsupported** | `AxQOS` signals are routed through crossbar registers but are not evaluated by arbitration priority encoders. | `soc_top.v:822, 861` |
| **User Signals (`AxUSER`, etc.)** | **Unsupported** | Disabled at top wrapper level (`AWUSER_ENABLE = 0`, `WUSER_ENABLE = 0`, etc.). Tied to 0. | `axi_interconnect_wrap_3x8.v:40-49` |
| **TrustZone / Secure (`AxPROT`)** | **Ignored in Wrapper** | Crossbar supports `M_SECURE` filtering, but `soc_top.v` ties `.Mxx_SECURE(1'b0)` for all slaves, disabling security-based blocking. | `soc_top.v:764, 771, 778, 785` |
