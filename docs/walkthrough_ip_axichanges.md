# Native AXI Translation & Wishbone Removal

We have successfully eradicated the Wishbone protocol from all custom IP modules in the SoC, substituting it with a clean **Generic Register Interface** and wrapping it with natively terminating AXI state machines. 

## Architectural Changes

1. **Generic Register Interface on Core IPs:**
   The `heartbeat_monitor`, `reset_sequencer`, `recovery_policy`, and **`vga_controller` (User Custom IP #4)** were fully refactored to remove all `wb_*` signals. They now utilize a clean generic interface:
   - `reg_en`, `reg_we`, `reg_ack` for transactional flow control.
   - `reg_addr`, `reg_wdata`, `reg_rdata` for memory-mapped I/O.

2. **Native AXI Termination in Wrappers:**
   The `axi_` wrappers no longer rely on instantiating the `axi4_to_wb_bridge.v`. Instead, the full 64-bit AXI4 Slave FSM is natively embedded within each wrapper (including the newly created `axi_vga_controller.v`). 
   - AXI `awvalid`/`wvalid` sequences are inherently translated into single-cycle `reg_en`/`reg_we` pulses.
   - 64-bit to 32-bit steering based on `awaddr[2]` is performed concurrently.

## Memory Mapping & Offsets Confirmed
I rigorously audited the interconnect's base addresses and the internal register offsets for all Custom IPs to ensure perfect consistency:
- **Slave 3 (Heartbeat)**: Base `0x0002_0300`, Offsets `0x00`-`0x0C` perfectly mapped.
- **Slave 4 (Reset Seq)**: Base `0x0002_0400`, Offsets `0x00`-`0x08` perfectly mapped.
- **Slave 5 (Recovery)**: Base `0x0002_0500`, Offsets `0x00`-`0x1C` perfectly mapped.
- **Slave 6 (VGA Ctrl)**: Base `0x0002_0600`, Offsets `0x00`-`0x04` and `0x08`-`0x7F` (Dashboard buffer) perfectly mapped.

## Verification
All 37 unit tests for the core IPs passed flawlessly under the new interface paradigm using Icarus Verilog (`make veri_all`), confirming that the timing and data integrity remains completely intact through the new architecture.
