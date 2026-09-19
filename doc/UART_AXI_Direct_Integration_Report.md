# UART IP Direct AXI Integration Report

**Date:** September 19, 2026  
**Commit:** (see git log)  
**Feature:** Direct AXI4-Lite integration of `axi_uart_top` into `soc_top.v`  
**Status:** ✅ COMPLETE — 0 errors, full regression PASS

---

## 1. What Changed

### Old Architecture (Stub → Wishbone)
```
AXI Interconnect [M00, 64-bit]
        ↓
u_bridge_s0 (AXI 64→32 + AXI→Wishbone)
        ↓
wbs0_* Wishbone signals
        ↓
UART STUB (wbs0_dat_i = 0, wbs0_ack = stb & cyc)
        ↓
uart_tx = 1'b1  (idle, no real UART)
```

### New Architecture (Direct AXI)
```
AXI Interconnect [M00, 64-bit]
        ↓
64→32 bit data steering (addr[2] selects word)
        ↓
axi_uart_top (u_uart) — real 32-bit AXI4-Lite UART
        ↓
uart_tx / uart_rx (real serial I/O)
        ↓
uart_irq → interrupt (for future PIC connection)
```

---

## 2. Data Width Adaptation (64→32 bit)

The AXI interconnect runs at 64-bit; `axi_uart_top` is a 32-bit AXI4-Lite slave. A minimal inline adapter handles the mismatch:

| Signal | From | To | Adaptation |
|---|---|---|---|
| `wdata` | `m00_axi_wdata[63:0]` | `axi_uart_top.axi_wdata_i[31:0]` | `addr[2]=0` → `[31:0]`, `addr[2]=1` → `[63:32]` |
| `wstrb` | `m00_axi_wstrb[7:0]` | `axi_uart_top.axi_wstrb_i[3:0]` | Same steering as wdata |
| `rdata` | `axi_uart_top.axi_rdata_o[31:0]` | `m00_axi_rdata[63:0]` | Replicated: `{rdata_32, rdata_32}` |
| `rlast` | N/A | `m00_axi_rlast` | `= m00_axi_rvalid` (AXI-Lite single beat) |
| `awid/arid` | `m00_axi_awid[7:0]` | `axi_uart_top.axi_awid_i[11:0]` | Zero-extended: `{4'b0, m00_axi_awid}` |
| `bid/rid` | `axi_uart_top.axi_bid_o[11:0]` | `m00_axi_bid[7:0]` | `[7:0]` lower bits |

---

## 3. UART Register Map (Active in SoC)

Base address: `0x0002_0000`

| SoC Address | Offset | Reg | Mode | Description |
|---|---|---|---|---|
| `0x0002_0000` | `0x00` | THR | WO (DLAB=0) | Transmit data byte |
| `0x0002_0000` | `0x00` | RBR | RO (DLAB=0) | Receive data byte |
| `0x0002_0004` | `0x04` | IER | WO | Interrupt Enable (`bit[0]` = RX IRQ) |
| `0x0002_0008` | `0x08` | BAUD_DIV | WO (DLAB=1) | Baud rate clock divisor |
| `0x0002_000C` | `0x0C` | LCR | WO | Line Control (stop bits, parity, DLAB) |
| `0x0002_0014` | `0x14` | LSR | RO | Line Status (`[0]` DR, `[5]` THRE, `[6]` TEMT) |

---

## 4. Files Changed

| File | Change |
|---|---|
| `rtl/soc_top.v` | Removed `u_bridge_s0` + `wbs0_*` stub; added `u_uart` (axi_uart_top); added data steering logic |
| `Makefile` | Added `SRC_UART`, `VCS_UART_INC`, included UART RTL in all relevant compile targets |

---

## 5. Regression Results

| Test Suite | Tests | Result |
|---|---|---|
| `sim_hbm` | 9/9 | ✅ PASS |
| `sim_rst` | 12/12 | ✅ PASS |
| `sim_pol` | 16/16 | ✅ PASS |
| `sim_axi` | 18/18 | ✅ PASS |
| `sim_soc` | 17/17 | ✅ PASS |
| `compile_top` | Elaboration | ✅ 0 errors |
