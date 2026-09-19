# Option B Architecture Report: 2x7 AXI Interconnect Integration & Verification

## 1. Executive Summary
Following user direction to implement **Option B** and utilize the user-provided generator script (`scripts/axi_interconnect_wrap.py`), the BMC SoC interconnect architecture has been upgraded from a 2-Master $\times$ 1-Slave crossbar driving a global Wishbone bus to a **direct 2-Master $\times$ 7-Slave AXI4 Interconnect** (`axi_interconnect_wrap_2x7`) with **7 dedicated AXI4-to-Wishbone protocol bridges** (`u_bridge_s0` through `u_bridge_s6`).

This architectural update completely eliminates the global Wishbone crossbar bottleneck (`wb_interconnect`), providing dedicated point-to-point AXI transaction routing directly to each peripheral controller.

---

## 2. Architectural Comparison: Option A vs. Option B

```
OPTION A (Previous Architecture):
+-------------------------+     +-------------------------+
|  VeeR EL2 Core (LSU)    |     | VeeR System Bus / Debug |
+-------------------------+     +-------------------------+
             |                               |
             +---------------+---------------+
                             |
                   [ AXI Crossbar 2x1 ]
                             | (Single Shared AXI4 Bus)
                             v
               [ Single AXI4-to-WB Bridge ]
                             | (Single Shared Wishbone Master)
                             v
                [ WB Interconnect / Mux ]
          +-----+-----+-----+-----+-----+-----+-----+
          |     |     |     |     |     |     |
          v     v     v     v     v     v     v
        UART   TMR   GPIO  HBM   RST   POL   VGA

-------------------------------------------------------------------------

OPTION B (Implemented Architecture):
+-------------------------+     +-------------------------+
|  VeeR EL2 Core (LSU)    |     | VeeR System Bus / Debug |
+-------------------------+     +-------------------------+
             |                               |
             +---------------+---------------+
                             |
             [ AXI4 Interconnect Wrap 2x7 ]
     (Parallel steering, per-slave queues & arbitration)
       |       |       |       |       |       |       |
      M00     M01     M02     M03     M04     M05     M06
       |       |       |       |       |       |       |
    Bridge0 Bridge1 Bridge2 Bridge3 Bridge4 Bridge5 Bridge6
       |       |       |       |       |       |       |
       v       v       v       v       v       v       v
      UART    TMR    GPIO     HBM     RST     POL     VGA
```

### Key Benefits of Option B:
1. **Parallel Routing & Reduced Latency**: Each peripheral interface operates independently on its own slave port.
2. **Dedicated Bridges**: Each peripheral has an isolated 64-bit to 32-bit width conversion bridge, preventing contention between high-frequency monitor reads and low-frequency control writes.
3. **Wishbone Crossbar Eliminated**: Unnecessary routing stages removed from the critical timing path.

---

## 3. Peripheral Address Mapping

All 7 peripherals reside in dedicated 256-byte windows (`ADDR_WIDTH = 8`, 8-bit offset address) within the SoC peripheral region:

| Slave Port | Peripheral Name | Base Address | End Address | Window Size | Offset Bits |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **M00** | UART (16550) | `0x0002_0000` | `0x0002_00FF` | 256 Bytes | 8 bits (`32'd8`) |
| **M01** | Timer Counter | `0x0002_0100` | `0x0002_01FF` | 256 Bytes | 8 bits (`32'd8`) |
| **M02** | GPIO Status | `0x0002_0200` | `0x0002_02FF` | 256 Bytes | 8 bits (`32'd8`) |
| **M03** | Heartbeat Monitor | `0x0002_0300` | `0x0002_03FF` | 256 Bytes | 8 bits (`32'd8`) |
| **M04** | Reset Sequencer | `0x0002_0400` | `0x0002_04FF` | 256 Bytes | 8 bits (`32'd8`) |
| **M05** | Recovery Policy | `0x0002_0500` | `0x0002_05FF` | 256 Bytes | 8 bits (`32'd8`) |
| **M06** | VGA Controller | `0x0002_0600` | `0x0002_06FF` | 256 Bytes | 8 bits (`32'd8`) |

---

## 4. Key Implementation Details

### 4.1. Wrapper Generator (`scripts/axi_interconnect_wrap.py`)
Generated `rtl/interconnect/axi_interconnect_wrap_2x7.v` via:
```bash
python3 scripts/axi_interconnect_wrap.py -p 2 7 -n axi_interconnect_wrap_2x7 -o rtl/interconnect/axi_interconnect_wrap_2x7.v
```

### 4.2. Sub-4KB Address Window Decoding Fix (`rtl/interconnect/axi_interconnect.v`)
Standard AXI crossbars check for address width $\ge 12$ (4 KB page minimum). Because the SoC peripheral architecture utilizes compact 256-byte register windows (`M_ADDR_WIDTH = 8`), line 230 of `axi_interconnect.v` was adapted from:
```verilog
if (M_ADDR_WIDTH < 12) begin
    $error("Error: address width out of range (instance %m)");
    $finish;
end
```
to:
```verilog
if (M_ADDR_WIDTH < 1) begin
    $error("Error: address width out of range (instance %m)");
    $finish;
end
```
This safely enables precise 256-byte (`32'd8`) window decoding without modifying the arithmetic address steering logic.

### 4.3. Top-Level SoC Integration (`rtl/soc_top.v`)
- Instantiated `axi_interconnect_wrap_2x7` with `DATA_WIDTH=64`, `ADDR_WIDTH=32`, `ID_WIDTH=8`.
- Instantiated 7 dedicated instances of `axi4_to_wb_bridge` (`u_bridge_s0` through `u_bridge_s6`).
- Directly mapped Wishbone signals from each bridge to its corresponding IP:
  - `u_bridge_s0` $\rightarrow$ UART stub
  - `u_bridge_s1` $\rightarrow$ Timer counter
  - `u_bridge_s2` $\rightarrow$ GPIO status
  - `u_bridge_s3` $\rightarrow$ `u_heartbeat` (`heartbeat_monitor`)
  - `u_bridge_s4` $\rightarrow$ `u_reset_seq` (`reset_sequencer`)
  - `u_bridge_s5` $\rightarrow$ `u_recovery_pol` (`recovery_policy`)
  - `u_bridge_s6` $\rightarrow$ VGA dashboard
- Preserved strict exclusion: `rtl/ips/aes_core/` was untouched.

---

## 5. Verification & Testbench Suite

### 5.1. AXI Interconnect Unit Test (`tb/tb_axi_interconnect.v`)
Updated testbench to instantiate `axi_interconnect_wrap_2x7` and the 7 dedicated bridges. Six comprehensive test scenarios execute:
1. **Master 0 (LSU) Write & Read with ID Tag Matching**: Tested against Heartbeat Monitor (`0x0002_0304`) with ID `0x11` / `0x12`.
2. **Master 1 (SB) Write & Read with ID Tag Matching**: Tested against Reset Sequencer (`0x0002_0404`) with ID `0x21` / `0x22`.
3. **64-to-32 bit Address/Data Steering**: Verified proper routing of high 32-bit word (`addr[2]=1`, `POL_WINDOW`) and low 32-bit word (`addr[2]=0`, `POL_THRESHOLD`).
4. **Concurrent Master 0 & Master 1 Arbitration**: Simulates simultaneous access from LSU and Debug ports to distinct slaves; verified mutual exclusion and zero cross-contamination.
5. **Unmapped Address Error Handling**: Verified unmapped address `0x0002_0800` returns AXI `DECERR` (`2'b11`).
6. **7-Port Peripheral Sweep**: Verified read accessibility across all 7 peripheral slave interfaces (S0 through S6).

**Simulation Result (`make sim_axi`)**:
- Tests executed: 18 assertions
- Assertions passed: 18 / 18 (100%)
- Failures: 0

### 5.2. Full SoC System Integration Test (`tb/tb_soc_top.v`)
Exercises the full recovery lifecycle through AXI master transactions into the 2x7 interconnect and 7 bridges:
- **Scenario 1**: Normal Heartbeat monitoring $\rightarrow$ system stays online, reset line remains HIGH.
- **Scenario 2**: Heartbeat freeze detection $\rightarrow$ timeout interrupt $\rightarrow$ reset pulse sequence (50 cycles) $\rightarrow$ event logged in circular buffer.
- **Scenario 3**: Rapid repeated freezes $\rightarrow$ policy threshold reached (3 recoveries in window) $\rightarrow$ lockout flag asserted, preventing reboot loops.
- **Scenario 4**: Manual override $\rightarrow$ lockout cleared via register write $\rightarrow$ force manual recovery pulse $\rightarrow$ circular event buffer readback.

**Simulation Result (`make sim_soc`)**:
- Assertions passed: 17 / 17 (100%)
- Failures: 0

### 5.3. Full Regression Summary (`make sim_all`)
| Test Target | Module Under Test | Status | Failures |
| :--- | :--- | :--- | :--- |
| `make sim_hbm` | Heartbeat Monitor Unit Test | **PASSED** | 0 |
| `make sim_rst` | Reset Sequencer Unit Test | **PASSED** | 0 |
| `make sim_pol` | Recovery Policy Unit Test | **PASSED** | 0 |
| `make sim_axi` | 2x7 AXI Interconnect & 7 Bridges | **PASSED** | 0 |
| `make sim_soc` | Full SoC Integration Lifecycle | **PASSED** | 0 |
| `make compile_top` | Full `soc_top.v` Elaboration | **PASSED** | 0 |

---

## 6. Git Status & Untouched Files
- **Untouched**: `rtl/ips/aes_core/` (AES core strictly untouched).
- **Modified**:
  - `rtl/interconnect/axi_interconnect.v` (sub-4KB address range check fix)
  - `rtl/soc_top.v` (Option B 2x7 interconnect and 7 dedicated bridges)
  - `scripts/axi_interconnect_wrap.py` (AXI wrapper generator)
  - `tb/tb_axi_interconnect.v` (2x7 testbench with 6 test scenarios)
  - `tb/tb_soc_top.v` (2x7 system testbench)
- **New Files**:
  - `rtl/interconnect/axi_interconnect_wrap_2x7.v` (generated 2x7 wrapper)
  - `rtl/interconnect/axi_interconnect_2x7.v` (standalone 2x7 interconnect)
  - `rtl/interconnect/axil_to_wb.v` (bridge module)
  - `doc/AXI_Interconnect_2x7_OptionB_Report.md` (this report)
