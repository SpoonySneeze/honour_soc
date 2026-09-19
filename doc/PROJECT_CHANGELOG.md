# Project Changelog — All Work Done
**Repository:** `honour_soc`  
**Last Updated:** September 19, 2026  

---

## Commit History Summary

| Commit | Description |
|---|---|
| `6bcee85` | Option B: AXI 2×7 Interconnect integration + full verification |
| `8d483d2` | UART IP ingestion + Verdi RC files for all FSDBs |

---

## Phase 1 — AXI Interconnect Integration (Option B)
**Commit:** `6bcee85`  
**Doc:** `doc/AXI_Interconnect_2x7_OptionB_Report.md`

### What was done
- Replaced the Wishbone crossbar (`wb_interconnect.v`) entirely with a full **AXI4 Interconnect (2 Masters × 7 Slaves)**
- Used `scripts/axi_interconnect.py` to auto-generate `rtl/interconnect/axi_interconnect_wrap_2x7.v`
- Wired 2 CPU masters and 7 peripheral slave bridges into `rtl/soc_top.v`

### AXI Interconnect Architecture

| Port | Direction | Width | Description |
|---|---|---|---|
| S00 (Master 0) | Input | 64-bit | VeeR LSU (Load/Store Unit) |
| S01 (Master 1) | Input | 64-bit | VeeR SB (System Bus) |
| M00 (Slave 0) | Output | 32-bit | UART @ `0x0002_0000` |
| M01 (Slave 1) | Output | 32-bit | Timer @ `0x0002_0100` |
| M02 (Slave 2) | Output | 32-bit | GPIO @ `0x0002_0200` |
| M03 (Slave 3) | Output | 32-bit | Heartbeat Monitor @ `0x0002_0300` |
| M04 (Slave 4) | Output | 32-bit | Reset Sequencer @ `0x0002_0400` |
| M05 (Slave 5) | Output | 32-bit | Recovery Policy @ `0x0002_0500` |
| M06 (Slave 6) | Output | 32-bit | VGA Controller @ `0x0002_0600` |

### Files Changed / Created
- `rtl/interconnect/axi_interconnect_wrap_2x7.v` — generated wrapper
- `rtl/interconnect/axi_interconnect_2x7.v` — top-level 2x7 module
- `rtl/interconnect/axi_interconnect.v` — bug fix: `M_ADDR_WIDTH < 1` check
- `rtl/soc_top.v` — full rewire: removed Wishbone, added 2 masters + 7 bridges
- `tb/tb_axi_interconnect.v` — comprehensive verification testbench (18 assertions)
- `tb/tb_soc_top.v` — full SoC system test (17 assertions)

### Verification Results
| Testbench | Tests | Result |
|---|---|---|
| `tb_axi_interconnect.v` | 18/18 | ✅ ALL PASS |
| `tb_soc_top.v` | 17/17 | ✅ ALL PASS |
| `make sim_all` | 5 suites | ✅ ALL PASS |
| `make compile_top` | Elaboration | ✅ 0 errors |

---

## Phase 2 — UART IP Ingestion + Verdi RC Files
**Commit:** `8d483d2`  
**Doc:** `doc/UART_IP_Ingestion_and_Verdi_RC_Report.md`

### What was done
- Imported the AXI-Lite UART IP core into the repository
- Verified with native testbench — all tests pass
- Created Verdi `.rc` session files for all FSDB waveform dumps
- Added FSDB dump support to SoC testbenches via `+fsdb` plusarg
- Updated `Makefile` so `make waves_axi` / `make waves_soc` auto-open Verdi with grouped signals

### UART IP Details
- **Location:** `rtl/ips/axi-lite_uart-ipcore-develop/` (stand-alone, NOT in `soc_top.v`)
- **Module:** `axi_uart_top`
- **Interface:** 32-bit AXI4-Lite slave + independent UART serial clock domain
- **Features:** 16-deep TX/RX FIFOs, configurable baud rate (DLAB), parity, stop bits, RX interrupt

### UART Register Map
| Offset | Name | Mode | Description |
|---|---|---|---|
| `0x00` | THR | WO (DLAB=0) | Transmit Holding Register |
| `0x00` | RBR | RO (DLAB=0) | Receiver Buffer Register |
| `0x04` | IER | WO | Interrupt Enable Register |
| `0x08` | BAUD_DIV | WO (DLAB=1) | Baud Rate Divisor |
| `0x0C` | LCR | WO | Line Control Register |
| `0x14` | LSR | RO | Line Status Register |

### UART Testbench Results (`./run.csh all`)
| Test | Description | Result |
|---|---|---|
| Test 1 | LSR reset state (THRE=1, TEMT=1, DR=0) | ✅ PASS |
| Test 2 | LCR write (write-only register) | ✅ PASS |
| Test 3 | IER write + interrupt signal check | ✅ PASS |
| Test 4 | DLAB mode — baud divisor write | ✅ PASS |
| Test 5 | TX path — write THR, check LSR THRE/TEMT | ✅ PASS |
| Test 6 | Single byte loopback (TX→RX, `0x55`) | ✅ PASS |
| Test 7 | LSR DATA_READY and interrupt signal | ✅ PASS |
| Test 8 | Multi-byte loopback (`0xDEADBEEF`) | ✅ PASS |

### Verdi `.rc` Files Created
| File | Used By | Signal Groups |
|---|---|---|
| `rtl/ips/axi-lite_uart-ipcore-develop/waves/uart_wave.rc` | `./run.csh verdi` | 13 groups (CLK, AXI AW/W/B/AR/R, FSM, CSR, UART serial, TX/RX FIFOs, TX/RX cores) |
| `waves/axi_interconnect_wave.rc` | `make waves_axi` | 10 groups (CLK, M0 LSU, M1 SB, S0–S6) |
| `waves/soc_top_wave.rc` | `make waves_soc` | 7 groups (CLK, AXI master, external, HB Mon, Reset Seq, Recovery Policy, UART/VGA) |

### Files Changed
- `rtl/ips/axi-lite_uart-ipcore-develop/` — full IP added (clean, no build artifacts)
- `rtl/ips/axi-lite_uart-ipcore-develop/waves/uart_wave.rc` — UART Verdi RC
- `waves/axi_interconnect_wave.rc` — AXI interconnect Verdi RC
- `waves/soc_top_wave.rc` — SoC top Verdi RC
- `tb/tb_axi_interconnect.v` — added `+fsdb` FSDB dump
- `tb/tb_soc_top.v` — added `+fsdb` FSDB dump
- `Makefile` — FSDB variables, `+fsdb` in sim targets, Verdi `-sswr` in waves targets

### Post-change Regression
| Test | Result |
|---|---|
| `make sim_all` | ✅ ALL PASS |
| `make compile_top` | ✅ 0 errors |
| `aes_core` | ✅ Untouched (verified) |

---

## Repository Structure (Current)

```
honour_soc/
├── doc/
│   ├── AXI_Interconnect_2x7_OptionB_Report.md   ← Phase 1 detailed report
│   ├── UART_IP_Ingestion_and_Verdi_RC_Report.md  ← Phase 2 detailed report
│   └── PROJECT_CHANGELOG.md                      ← This file (master overview)
├── rtl/
│   ├── soc_top.v                                 ← AXI 2x7, no Wishbone
│   ├── interconnect/                             ← AXI crossbar + 2x7 wrapper
│   └── ips/
│       ├── aes_core/                             ← UNTOUCHED
│       └── axi-lite_uart-ipcore-develop/         ← New UART IP (stand-alone)
├── waves/
│   ├── axi_interconnect_wave.rc                  ← Verdi RC for AXI tb
│   └── soc_top_wave.rc                           ← Verdi RC for SoC tb
├── tb/                                           ← All testbenches
└── Makefile                                      ← Updated with FSDB + Verdi
```

---

## Constraints Always Respected
- `rtl/ips/aes_core/` — **NEVER modified** (confirmed in every commit)
- UART IP — **NOT integrated** into `soc_top.v` (as explicitly requested)
- Every change — **documented in `doc/`** and **committed to git**
