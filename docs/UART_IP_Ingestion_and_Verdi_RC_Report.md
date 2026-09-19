# Replace Wishbone with Generic Register Interface

The goal is to completely eradicate the Wishbone standard from the custom IPs and the top-level SoC, replacing it with a clean, proprietary Generic Register Interface on the core IPs, while using Native AXI Wrappers to terminate the AXI protocol natively (without any standalone bridging modules).

## User Review Required
> [!IMPORTANT]
> This plan will permanently remove the Wishbone protocol (`cyc`, `stb`, `we`, etc.) from your custom IPs and replace them with a proprietary, simple, generic register interface. 

> [!WARNING]
> Since we are removing the standalone `axi4_to_wb_bridge.v` for your custom IPs, the wrapper modules (`axi_heartbeat_monitor.v`, etc.) will be upgraded to contain the AXI protocol state machine natively.

## Proposed Changes

### 1. Define the Generic Register Interface
The new interface on the raw IPs (`heartbeat_monitor.v`, `reset_sequencer.v`, `recovery_policy.v`) will completely drop Wishbone terms and instead use a very clean, generic SRAM-like interface:
- `reg_en`: Chip select / transaction enable
- `reg_we`: Write enable
- `reg_addr`: 8-bit register offset
- `reg_wdata`: 32-bit write data
- `reg_rdata`: 32-bit read data
- `reg_ack`: Transaction acknowledge (typically tied to `reg_en` or delayed by 1 cycle)

### 2. Rewrite Core IPs
---
#### [MODIFY] [heartbeat_monitor.v](file:///e:/Projects/honours_project/rtl/custom_ips/heartbeat_monitor.v)
- Strip out all `wb_*` ports.
- Add the new `reg_*` ports.
- Rename internal FSM conditions from `wb_stb_i & wb_cyc_i` to `reg_en`.

#### [MODIFY] [reset_sequencer.v](file:///e:/Projects/honours_project/rtl/custom_ips/reset_sequencer.v)
- Strip out all `wb_*` ports.
- Add the new `reg_*` ports.
- Update internal register write logic to use the new `reg_*` handshake.

#### [MODIFY] [recovery_policy.v](file:///e:/Projects/honours_project/rtl/custom_ips/recovery_policy.v)
- Strip out all `wb_*` ports.
- Add the new `reg_*` ports.
- Update internal memory map logic to use the new `reg_*` handshake.

### 3. Rewrite AXI Wrappers (No Bridges)
---
#### [MODIFY] [axi_heartbeat_monitor.v](file:///e:/Projects/honours_project/rtl/custom_ips/axi_heartbeat_monitor.v)
- Completely remove the internal `axi4_to_wb_bridge.v` instance.
- Implement the AXI4 64-bit slave state machine directly in this file.
- The state machine will translate AXI `awvalid`/`wvalid`/`arvalid` into `reg_en`/`reg_we` pulses to drive the core IP.

#### [MODIFY] [axi_reset_sequencer.v](file:///e:/Projects/honours_project/rtl/custom_ips/axi_reset_sequencer.v)
- Completely remove the internal `axi4_to_wb_bridge.v` instance.
- Natively implement the AXI4 protocol and drive the `reg_*` generic interface of the core reset sequencer.

#### [MODIFY] [axi_recovery_policy.v](file:///e:/Projects/honours_project/rtl/custom_ips/axi_recovery_policy.v)
- Completely remove the internal `axi4_to_wb_bridge.v` instance.
- Natively implement the AXI4 protocol and drive the `reg_*` generic interface of the core recovery policy.

### 4. Top-Level Integration
---
#### [MODIFY] [soc_top.v](file:///e:/Projects/honours_project/rtl/soc_top.v)
- No changes required to the `soc_top.v` instances of Slaves 3, 4, 5, as they are already wired directly to the `m0X_axi_*` ports.

#### [MODIFY] [tb_soc_top.v](file:///e:/Projects/honours_project/tb/tb_soc_top.v)
- No changes required, as it currently interfaces with the AXI wrappers.

## Verification Plan

### Automated Tests
- Run `wsl bash -c "make veri_hbm"` to verify the AXI wrappers function correctly using Icarus Verilog.
- Run `wsl bash -c "make veri_rst"`
- Run `wsl bash -c "make veri_pol"`
- Check that all 37 unit tests across the 3 IPs still pass under the new native AXI FSMs.
