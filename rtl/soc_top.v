// ============================================================================
// BMC SoC — Top-Level Integration & Authoritative Register Map
// ============================================================================
// Instantiates and interconnects:
//   - VeeR EL2 RISC-V Core (RV32IMC / Zba / Zbb / Zbc / Zbs)
//   - AXI4-Lite to Wishbone B4 Bus Bridge (u_axi2wb)
//   - Wishbone B4 1-to-7 Address Decoder & Interconnect (u_wb_intercon)
//   - Standard Subsystem Peripherals: UART, Timer, GPIO
//   - Custom BMC Hardware IPs:
//       1. Heartbeat Monitor (autonomous timeout detection)
//       2. Power/Reset Sequencer (hardware-timed active-low pulse)
//       3. Recovery Policy & Circular Event Log (crash-loop lockout)
//       4. VGA Status Dashboard Controller (640x480 @ 60Hz text engine)
//
// ============================================================================
// SYSTEM MEMORY MAP (32-bit Address Space)
// ============================================================================
//   Address Range              Size     Target / Peripheral         Bus Interface
//   --------------------------------------------------------------------------
//   0x0000_0000 – 0x0000_FFFF  64 KB    ICCM (Instruction Memory)   VeeR TCM (Core)
//   0x0001_0000 – 0x0001_FFFF  64 KB    DCCM (Data Memory)          VeeR TCM (Core)
//   0x0002_0000 – 0x0002_00FF  256 B    Slave 0: UART               Wishbone B4
//   0x0002_0100 – 0x0002_01FF  256 B    Slave 1: Timer              Wishbone B4
//   0x0002_0200 – 0x0002_02FF  256 B    Slave 2: GPIO               Wishbone B4
//   0x0002_0300 – 0x0002_03FF  256 B    Slave 3: Heartbeat Monitor  Wishbone B4
//   0x0002_0400 – 0x0002_04FF  256 B    Slave 4: Reset Sequencer    Wishbone B4
//   0x0002_0500 – 0x0002_05FF  256 B    Slave 5: Recovery Policy    Wishbone B4
//   0x0002_0600 – 0x0002_06FF  256 B    Slave 6: VGA Controller     Wishbone B4
//
// ============================================================================
// PERIPHERAL REGISTER MAP DETAILS
// ============================================================================
// All registers are 32-bit word-aligned.
// Access types:
//   R/W = Read / Write
//   RO  = Read Only (writes ignored)
//   WO  = Write Only (reads return 0)
//
// ----------------------------------------------------------------------------
// SLAVE 0: UART PERIPHERAL (Base: 0x0002_0000, Size: 256 B)
// ----------------------------------------------------------------------------
// Stubbed in soc_top with immediate 1-cycle acknowledge. Standard 16550 layout:
//   Address      Offset  Register   Type  Reset       Description
//   0x0002_0000  0x00    UART_RBR   RO    0x00000000  Receiver Buffer Register
//   0x0002_0000  0x00    UART_THR   WO    0x00000000  Transmitter Holding Reg
//   0x0002_0004  0x04    UART_IER   R/W   0x00000000  Interrupt Enable Register
//   0x0002_0008  0x08    UART_IIR   RO    0x00000001  Interrupt Ident Register
//   0x0002_0008  0x08    UART_FCR   WO    0x00000000  FIFO Control Register
//   0x0002_000C  0x0C    UART_LCR   R/W   0x00000000  Line Control Register
//   0x0002_0010  0x10    UART_MCR   R/W   0x00000000  Modem Control Register
//   0x0002_0014  0x14    UART_LSR   RO    0x00000060  Line Status Register
//   0x0002_0018  0x18    UART_MSR   RO    0x00000000  Modem Status Register
//   0x0002_001C  0x1C    UART_SCR   R/W   0x00000000  Scratchpad Register
//
// ----------------------------------------------------------------------------
// SLAVE 1: TIMER PERIPHERAL (Base: 0x0002_0100, Size: 256 B)
// ----------------------------------------------------------------------------
// Free-running 32-bit hardware cycle counter, increments every clock cycle.
//   Address      Offset  Register   Type  Reset       Description
//   0x0002_0100  0x00    TMR_CTR    RO    0x00000000  [31:0] System uptime ticks
//
// ----------------------------------------------------------------------------
// SLAVE 2: GPIO PERIPHERAL (Base: 0x0002_0200, Size: 256 B)
// ----------------------------------------------------------------------------
// Direct status of external input/output pins.
//   Address      Offset  Register   Type  Reset       Description
//   0x0002_0200  0x00    GPIO_STAT  RO    0x00000000  Pin status:
//                                                     [0]    heartbeat_in live pin
//                                                     [1]    reset_out pin level
//                                                     [31:2] Reserved (0)
//
// ----------------------------------------------------------------------------
// SLAVE 3: HEARTBEAT MONITOR — Custom IP #1 (Base: 0x0002_0300, Size: 256 B)
// ----------------------------------------------------------------------------
// Monitors incoming periodic pulse from main system. Times out if edge is missing.
//   Address      Offset  Register      Type  Reset       Description
//   0x0002_0300  0x00    HB_CTRL       R/W   0x00000000  Control Register:
//                                                        [0]    enable (1=active)
//                                                        [1]    clear_flag (1=clear
//                                                               unresponsive state;
//                                                               self-clearing, reads 0)
//                                                        [31:2] Reserved (0)
//   0x0002_0304  0x04    HB_THRESHOLD  R/W   0x00000000  [31:0] Max cycles between
//                                                        consecutive rising edges
//   0x0002_0308  0x08    HB_STATUS     RO    0x00000000  Status Register:
//                                                        [0]    unresponsive (sticky,
//                                                               set when timed out)
//                                                        [1]    heartbeat_in live pin
//                                                        [31:2] Reserved (0)
//   0x0002_030C  0x0C    HB_ELAPSED    RO    0x00000000  [31:0] Live cycle count
//                                                        since last rising edge
//
// ----------------------------------------------------------------------------
// SLAVE 4: POWER/RESET SEQUENCER — Custom IP #2 (Base: 0x0002_0400, Size: 256 B)
// ----------------------------------------------------------------------------
// Generates autonomous, precisely timed active-low reset pulse to target system.
//   Address      Offset  Register        Type  Reset       Description
//   0x0002_0400  0x00    RST_CTRL        WO    0x00000000  Trigger Register:
//                                                          [0]    trigger (1=start
//                                                                 reset pulse;
//                                                                 self-clearing, reads 0)
//                                                          [31:1] Reserved (0)
//   0x0002_0404  0x04    RST_HOLD_CYCLES R/W   0x00000064  [31:0] Cycles to hold
//                                                          reset_out LOW (default 100)
//   0x0002_0408  0x08    RST_STATUS      RO    0x00000000  Status Register:
//                                                          [0]    in_progress (1=active)
//                                                          [1]    complete (1=done,
//                                                                 sticky until next trig)
//                                                          [31:2] Reserved (0)
//
// ----------------------------------------------------------------------------
// SLAVE 5: RECOVERY POLICY & EVENT LOG — Custom IP #3 (Base: 0x0002_0500, Size: 256 B)
// ----------------------------------------------------------------------------
// Circular event log (16 entries) + fixed-window crash-loop lockout policy.
//   Address      Offset  Register       Type  Reset       Description
//   0x0002_0500  0x00    POL_CTRL       WO    0x00000000  Policy Control:
//                                                         [0]    record_event (1=log
//                                                                staged timestamp;
//                                                                self-clearing, reads 0)
//                                                         [1]    clear_lockout (1=clear
//                                                                lockout & window count;
//                                                                self-clearing, reads 0)
//                                                         [31:2] Reserved (0)
//   0x0002_0504  0x04    POL_WINDOW     R/W   0x00000000  [31:0] Rolling evaluation
//                                                         window size in clock cycles
//   0x0002_0508  0x08    POL_THRESHOLD  R/W   0x00000003  Threshold Register:
//                                                         [7:0]  Max recoveries allowed
//                                                                per window before lockout
//                                                         [31:8] Reserved (0)
//   0x0002_050C  0x0C    POL_STATUS     RO    0x00000000  Policy Status:
//                                                         [0]    lockout_flag (1=locked)
//                                                         [7:1]  Reserved (0)
//                                                         [15:8] window_recovery_count
//                                                         [31:16] Reserved (0)
//   0x0002_0510  0x10    POL_EVENT_TS   WO    0x00000000  [31:0] Staged timestamp,
//                                                         written before POL_CTRL[0]
//   0x0002_0514  0x14    LOG_READ_IDX   R/W   0x00000000  [3:0] Read pointer (0–15)
//                                                         into circular log buffer
//   0x0002_0518  0x18    LOG_READ_DATA  RO    0x00000000  [31:0] Stored timestamp
//                                                         at LOG_READ_IDX
//   0x0002_051C  0x1C    LOG_COUNT      RO    0x00000000  [31:0] Lifetime total
//                                                         events logged (saturating)
//
// ----------------------------------------------------------------------------
// SLAVE 6: VGA CONTROLLER — Custom IP #4 (Base: 0x0002_0600, Size: 256 B)
// ----------------------------------------------------------------------------
// Hardware-accelerated text video engine (640x480 @ 60Hz, 3 rows x 40 columns).
//   Address      Offset  Register       Type  Reset       Description
//   0x0002_0600  0x00    VGA_CTRL       R/W   0x00000000  Display Control:
//                                                         [0]    enable (1=active, 0=off)
//                                                         [31:1] Reserved (0)
//   0x0002_0604  0x04    VGA_STATUS     RO    0x00000000  Display Status:
//                                                         [0]    refresh_flag (1=frame
//                                                                rendering; auto-clears)
//                                                         [31:1] Reserved (0)
//   0x0002_0608  0x08–   VGA_BUFFER     WO    0x20202020  Dashboard Text Character Buffer
//     to         0x7C    [0:29]                           30 words x 4 bytes = 120 chars.
//   0x0002_067C                                           Word index = (offset - 0x08) >> 2.
//                                                         Byte packing: MSB first (big-endian).
// ============================================================================

module soc_top (
    input  wire        clk,
    input  wire        rst_n,

    // ---- External Signals ----
    // Heartbeat from simulated main system
    input  wire        heartbeat_in,
    // Reset command to simulated main system
    output wire        reset_out,

    // UART
    input  wire        uart_rx,
    output wire        uart_tx,

    // JTAG Debug (directly to VeeR core)
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,

    // VGA (optional)
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [11:0] vga_rgb
);

    // ========================================================================
    // Peripheral Base Address Parameters
    // ========================================================================
    localparam [31:0] BASE_UART           = 32'h0002_0000;
    localparam [31:0] BASE_TIMER          = 32'h0002_0100;
    localparam [31:0] BASE_GPIO           = 32'h0002_0200;
    localparam [31:0] BASE_HB_MON         = 32'h0002_0300;
    localparam [31:0] BASE_RESET_SEQ      = 32'h0002_0400;
    localparam [31:0] BASE_REC_POL        = 32'h0002_0500;
    localparam [31:0] BASE_VGA            = 32'h0002_0600;

    // ========================================================================
    // Register Offset Definitions (wb_adr_i[7:0])
    // ========================================================================
    // Slave 0: UART Offsets (Standard 16550)
    localparam [7:0]  OFF_UART_RBR        = 8'h00; // Receiver Buffer Reg (RO)
    localparam [7:0]  OFF_UART_THR        = 8'h00; // Transmitter Holding Reg (WO)
    localparam [7:0]  OFF_UART_IER        = 8'h04; // Interrupt Enable Reg (R/W)
    localparam [7:0]  OFF_UART_IIR        = 8'h08; // Interrupt Ident Reg (RO)
    localparam [7:0]  OFF_UART_FCR        = 8'h08; // FIFO Control Reg (WO)
    localparam [7:0]  OFF_UART_LCR        = 8'h0C; // Line Control Reg (R/W)
    localparam [7:0]  OFF_UART_MCR        = 8'h10; // Modem Control Reg (R/W)
    localparam [7:0]  OFF_UART_LSR        = 8'h14; // Line Status Reg (RO)
    localparam [7:0]  OFF_UART_MSR        = 8'h18; // Modem Status Reg (RO)
    localparam [7:0]  OFF_UART_SCR        = 8'h1C; // Scratchpad Reg (R/W)

    // Slave 1: Timer Offset
    localparam [7:0]  OFF_TMR_CTR         = 8'h00; // 32-bit Tick Counter (RO)

    // Slave 2: GPIO Offset
    localparam [7:0]  OFF_GPIO_STAT       = 8'h00; // Pin Status Reg (RO)

    // Slave 3: Heartbeat Monitor Offsets
    localparam [7:0]  OFF_HB_CTRL         = 8'h00; // Control: [0] enable, [1] clear_flag
    localparam [7:0]  OFF_HB_THRESHOLD    = 8'h04; // Max cycles between pulse edges (R/W)
    localparam [7:0]  OFF_HB_STATUS       = 8'h08; // Status: [0] unresponsive, [1] live pin (RO)
    localparam [7:0]  OFF_HB_ELAPSED      = 8'h0C; // Cycles since last pulse edge (RO)

    // Slave 4: Power/Reset Sequencer Offsets
    localparam [7:0]  OFF_RST_CTRL        = 8'h00; // Trigger: [0] trigger (WO)
    localparam [7:0]  OFF_RST_HOLD_CYCLES = 8'h04; // Hold duration in cycles (R/W)
    localparam [7:0]  OFF_RST_STATUS      = 8'h08; // Status: [0] in_prog, [1] complete (RO)

    // Slave 5: Recovery Policy & Event Log Offsets
    localparam [7:0]  OFF_POL_CTRL        = 8'h00; // Control: [0] record, [1] clear_lockout (WO)
    localparam [7:0]  OFF_POL_WINDOW      = 8'h04; // Rolling window size in cycles (R/W)
    localparam [7:0]  OFF_POL_THRESHOLD   = 8'h08; // Max recoveries per window (R/W)
    localparam [7:0]  OFF_POL_STATUS      = 8'h0C; // Status: [0] lockout, [15:8] win_count (RO)
    localparam [7:0]  OFF_POL_EVENT_TS    = 8'h10; // Staged timestamp (WO)
    localparam [7:0]  OFF_LOG_READ_IDX    = 8'h14; // Log buffer read pointer [3:0] (R/W)
    localparam [7:0]  OFF_LOG_READ_DATA   = 8'h18; // Timestamp at LOG_READ_IDX (RO)
    localparam [7:0]  OFF_LOG_COUNT       = 8'h1C; // Total lifetime logged events (RO)

    // Slave 6: VGA Controller Offsets
    localparam [7:0]  OFF_VGA_CTRL        = 8'h00; // Control: [0] enable (R/W)
    localparam [7:0]  OFF_VGA_STATUS      = 8'h04; // Status: [0] refresh_flag (RO)
    localparam [7:0]  OFF_VGA_BUF_START   = 8'h08; // Start of 120-char text buffer (WO)
    localparam [7:0]  OFF_VGA_BUF_END     = 8'h7C; // End of 120-char text buffer (WO)

    // ========================================================================
    // Full 32-bit Memory-Mapped CPU Register Addresses (BASE + OFFSET)
    // ========================================================================
    // UART
    localparam [31:0] ADDR_UART_RBR        = BASE_UART      + OFF_UART_RBR;
    localparam [31:0] ADDR_UART_THR        = BASE_UART      + OFF_UART_THR;
    localparam [31:0] ADDR_UART_IER        = BASE_UART      + OFF_UART_IER;
    localparam [31:0] ADDR_UART_IIR        = BASE_UART      + OFF_UART_IIR;
    localparam [31:0] ADDR_UART_FCR        = BASE_UART      + OFF_UART_FCR;
    localparam [31:0] ADDR_UART_LCR        = BASE_UART      + OFF_UART_LCR;
    localparam [31:0] ADDR_UART_MCR        = BASE_UART      + OFF_UART_MCR;
    localparam [31:0] ADDR_UART_LSR        = BASE_UART      + OFF_UART_LSR;
    localparam [31:0] ADDR_UART_MSR        = BASE_UART      + OFF_UART_MSR;
    localparam [31:0] ADDR_UART_SCR        = BASE_UART      + OFF_UART_SCR;

    // Timer
    localparam [31:0] ADDR_TMR_CTR         = BASE_TIMER     + OFF_TMR_CTR;

    // GPIO
    localparam [31:0] ADDR_GPIO_STAT       = BASE_GPIO      + OFF_GPIO_STAT;

    // Heartbeat Monitor
    localparam [31:0] ADDR_HB_CTRL         = BASE_HB_MON    + OFF_HB_CTRL;
    localparam [31:0] ADDR_HB_THRESHOLD    = BASE_HB_MON    + OFF_HB_THRESHOLD;
    localparam [31:0] ADDR_HB_STATUS       = BASE_HB_MON    + OFF_HB_STATUS;
    localparam [31:0] ADDR_HB_ELAPSED      = BASE_HB_MON    + OFF_HB_ELAPSED;

    // Power/Reset Sequencer
    localparam [31:0] ADDR_RST_CTRL        = BASE_RESET_SEQ + OFF_RST_CTRL;
    localparam [31:0] ADDR_RST_HOLD_CYCLES = BASE_RESET_SEQ + OFF_RST_HOLD_CYCLES;
    localparam [31:0] ADDR_RST_STATUS      = BASE_RESET_SEQ + OFF_RST_STATUS;

    // Recovery Policy & Event Log
    localparam [31:0] ADDR_POL_CTRL        = BASE_REC_POL   + OFF_POL_CTRL;
    localparam [31:0] ADDR_POL_WINDOW      = BASE_REC_POL   + OFF_POL_WINDOW;
    localparam [31:0] ADDR_POL_THRESHOLD   = BASE_REC_POL   + OFF_POL_THRESHOLD;
    localparam [31:0] ADDR_POL_STATUS      = BASE_REC_POL   + OFF_POL_STATUS;
    localparam [31:0] ADDR_POL_EVENT_TS    = BASE_REC_POL   + OFF_POL_EVENT_TS;
    localparam [31:0] ADDR_LOG_READ_IDX    = BASE_REC_POL   + OFF_LOG_READ_IDX;
    localparam [31:0] ADDR_LOG_READ_DATA   = BASE_REC_POL   + OFF_LOG_READ_DATA;
    localparam [31:0] ADDR_LOG_COUNT       = BASE_REC_POL   + OFF_LOG_COUNT;

    // VGA Controller
    localparam [31:0] ADDR_VGA_CTRL        = BASE_VGA       + OFF_VGA_CTRL;
    localparam [31:0] ADDR_VGA_STATUS      = BASE_VGA       + OFF_VGA_STATUS;
    localparam [31:0] ADDR_VGA_BUF_START   = BASE_VGA       + OFF_VGA_BUF_START;
    localparam [31:0] ADDR_VGA_BUF_END     = BASE_VGA       + OFF_VGA_BUF_END;

    // ========================================================================
    // Internal Signals
    // ========================================================================

    // Active-high reset derived from active-low rst_n
    wire rst = ~rst_n;

    // ---- AXI4 Master 0: VeeR Load/Store Unit (LSU) ----
    wire [7:0]  lsu_axi_awid;
    wire [31:0] lsu_axi_awaddr;
    wire [7:0]  lsu_axi_awlen;
    wire [2:0]  lsu_axi_awsize;
    wire [1:0]  lsu_axi_awburst;
    wire        lsu_axi_awlock;
    wire [3:0]  lsu_axi_awcache;
    wire [2:0]  lsu_axi_awprot;
    wire [3:0]  lsu_axi_awqos;
    wire        lsu_axi_awvalid;
    wire        lsu_axi_awready;
    wire [63:0] lsu_axi_wdata;
    wire [7:0]  lsu_axi_wstrb;
    wire        lsu_axi_wlast;
    wire        lsu_axi_wvalid;
    wire        lsu_axi_wready;
    wire [7:0]  lsu_axi_bid;
    wire [1:0]  lsu_axi_bresp;
    wire        lsu_axi_bvalid;
    wire        lsu_axi_bready;
    wire [7:0]  lsu_axi_arid;
    wire [31:0] lsu_axi_araddr;
    wire [7:0]  lsu_axi_arlen;
    wire [2:0]  lsu_axi_arsize;
    wire [1:0]  lsu_axi_arburst;
    wire        lsu_axi_arlock;
    wire [3:0]  lsu_axi_arcache;
    wire [2:0]  lsu_axi_arprot;
    wire [3:0]  lsu_axi_arqos;
    wire        lsu_axi_arvalid;
    wire        lsu_axi_arready;
    wire [7:0]  lsu_axi_rid;
    wire [63:0] lsu_axi_rdata;
    wire [1:0]  lsu_axi_rresp;
    wire        lsu_axi_rlast;
    wire        lsu_axi_rvalid;
    wire        lsu_axi_rready;

    // ---- AXI4 Master 1: VeeR System Bus / Debug (SB) ----
    wire [7:0]  sb_axi_awid;
    wire [31:0] sb_axi_awaddr;
    wire [7:0]  sb_axi_awlen;
    wire [2:0]  sb_axi_awsize;
    wire [1:0]  sb_axi_awburst;
    wire        sb_axi_awlock;
    wire [3:0]  sb_axi_awcache;
    wire [2:0]  sb_axi_awprot;
    wire [3:0]  sb_axi_awqos;
    wire        sb_axi_awvalid;
    wire        sb_axi_awready;
    wire [63:0] sb_axi_wdata;
    wire [7:0]  sb_axi_wstrb;
    wire        sb_axi_wlast;
    wire        sb_axi_wvalid;
    wire        sb_axi_wready;
    wire [7:0]  sb_axi_bid;
    wire [1:0]  sb_axi_bresp;
    wire        sb_axi_bvalid;
    wire        sb_axi_bready;
    wire [7:0]  sb_axi_arid;
    wire [31:0] sb_axi_araddr;
    wire [7:0]  sb_axi_arlen;
    wire [2:0]  sb_axi_arsize;
    wire [1:0]  sb_axi_arburst;
    wire        sb_axi_arlock;
    wire [3:0]  sb_axi_arcache;
    wire [2:0]  sb_axi_arprot;
    wire [3:0]  sb_axi_arqos;
    wire        sb_axi_arvalid;
    wire        sb_axi_arready;
    wire [7:0]  sb_axi_rid;
    wire [63:0] sb_axi_rdata;
    wire [1:0]  sb_axi_rresp;
    wire        sb_axi_rlast;
    wire        sb_axi_rvalid;
    wire        sb_axi_rready;

    // ---- AXI4 Interconnect Master Outputs (7 Dedicated Slave Ports) ----
    // Slave 0: UART
    wire [7:0]  m00_axi_awid;
    wire [31:0] m00_axi_awaddr;
    wire [7:0]  m00_axi_awlen;
    wire [2:0]  m00_axi_awsize;
    wire [1:0]  m00_axi_awburst;
    wire [2:0]  m00_axi_awprot;
    wire        m00_axi_awvalid;
    wire        m00_axi_awready;
    wire [63:0] m00_axi_wdata;
    wire [7:0]  m00_axi_wstrb;
    wire        m00_axi_wlast;
    wire        m00_axi_wvalid;
    wire        m00_axi_wready;
    wire [7:0]  m00_axi_bid;
    wire [1:0]  m00_axi_bresp;
    wire        m00_axi_bvalid;
    wire        m00_axi_bready;
    wire [7:0]  m00_axi_arid;
    wire [31:0] m00_axi_araddr;
    wire [7:0]  m00_axi_arlen;
    wire [2:0]  m00_axi_arsize;
    wire [1:0]  m00_axi_arburst;
    wire [2:0]  m00_axi_arprot;
    wire        m00_axi_arvalid;
    wire        m00_axi_arready;
    wire [7:0]  m00_axi_rid;
    wire [63:0] m00_axi_rdata;
    wire [1:0]  m00_axi_rresp;
    wire        m00_axi_rlast;
    wire        m00_axi_rvalid;
    wire        m00_axi_rready;

    // Slave 1: Timer
    wire [7:0]  m01_axi_awid;
    wire [31:0] m01_axi_awaddr;
    wire [7:0]  m01_axi_awlen;
    wire [2:0]  m01_axi_awsize;
    wire [1:0]  m01_axi_awburst;
    wire [2:0]  m01_axi_awprot;
    wire        m01_axi_awvalid;
    wire        m01_axi_awready;
    wire [63:0] m01_axi_wdata;
    wire [7:0]  m01_axi_wstrb;
    wire        m01_axi_wlast;
    wire        m01_axi_wvalid;
    wire        m01_axi_wready;
    wire [7:0]  m01_axi_bid;
    wire [1:0]  m01_axi_bresp;
    wire        m01_axi_bvalid;
    wire        m01_axi_bready;
    wire [7:0]  m01_axi_arid;
    wire [31:0] m01_axi_araddr;
    wire [7:0]  m01_axi_arlen;
    wire [2:0]  m01_axi_arsize;
    wire [1:0]  m01_axi_arburst;
    wire [2:0]  m01_axi_arprot;
    wire        m01_axi_arvalid;
    wire        m01_axi_arready;
    wire [7:0]  m01_axi_rid;
    wire [63:0] m01_axi_rdata;
    wire [1:0]  m01_axi_rresp;
    wire        m01_axi_rlast;
    wire        m01_axi_rvalid;
    wire        m01_axi_rready;

    // Slave 2: GPIO
    wire [7:0]  m02_axi_awid;
    wire [31:0] m02_axi_awaddr;
    wire [7:0]  m02_axi_awlen;
    wire [2:0]  m02_axi_awsize;
    wire [1:0]  m02_axi_awburst;
    wire [2:0]  m02_axi_awprot;
    wire        m02_axi_awvalid;
    wire        m02_axi_awready;
    wire [63:0] m02_axi_wdata;
    wire [7:0]  m02_axi_wstrb;
    wire        m02_axi_wlast;
    wire        m02_axi_wvalid;
    wire        m02_axi_wready;
    wire [7:0]  m02_axi_bid;
    wire [1:0]  m02_axi_bresp;
    wire        m02_axi_bvalid;
    wire        m02_axi_bready;
    wire [7:0]  m02_axi_arid;
    wire [31:0] m02_axi_araddr;
    wire [7:0]  m02_axi_arlen;
    wire [2:0]  m02_axi_arsize;
    wire [1:0]  m02_axi_arburst;
    wire [2:0]  m02_axi_arprot;
    wire        m02_axi_arvalid;
    wire        m02_axi_arready;
    wire [7:0]  m02_axi_rid;
    wire [63:0] m02_axi_rdata;
    wire [1:0]  m02_axi_rresp;
    wire        m02_axi_rlast;
    wire        m02_axi_rvalid;
    wire        m02_axi_rready;

    // Slave 3: Heartbeat Monitor
    wire [7:0]  m03_axi_awid;
    wire [31:0] m03_axi_awaddr;
    wire [7:0]  m03_axi_awlen;
    wire [2:0]  m03_axi_awsize;
    wire [1:0]  m03_axi_awburst;
    wire [2:0]  m03_axi_awprot;
    wire        m03_axi_awvalid;
    wire        m03_axi_awready;
    wire [63:0] m03_axi_wdata;
    wire [7:0]  m03_axi_wstrb;
    wire        m03_axi_wlast;
    wire        m03_axi_wvalid;
    wire        m03_axi_wready;
    wire [7:0]  m03_axi_bid;
    wire [1:0]  m03_axi_bresp;
    wire        m03_axi_bvalid;
    wire        m03_axi_bready;
    wire [7:0]  m03_axi_arid;
    wire [31:0] m03_axi_araddr;
    wire [7:0]  m03_axi_arlen;
    wire [2:0]  m03_axi_arsize;
    wire [1:0]  m03_axi_arburst;
    wire [2:0]  m03_axi_arprot;
    wire        m03_axi_arvalid;
    wire        m03_axi_arready;
    wire [7:0]  m03_axi_rid;
    wire [63:0] m03_axi_rdata;
    wire [1:0]  m03_axi_rresp;
    wire        m03_axi_rlast;
    wire        m03_axi_rvalid;
    wire        m03_axi_rready;

    // Slave 4: Reset Sequencer
    wire [7:0]  m04_axi_awid;
    wire [31:0] m04_axi_awaddr;
    wire [7:0]  m04_axi_awlen;
    wire [2:0]  m04_axi_awsize;
    wire [1:0]  m04_axi_awburst;
    wire [2:0]  m04_axi_awprot;
    wire        m04_axi_awvalid;
    wire        m04_axi_awready;
    wire [63:0] m04_axi_wdata;
    wire [7:0]  m04_axi_wstrb;
    wire        m04_axi_wlast;
    wire        m04_axi_wvalid;
    wire        m04_axi_wready;
    wire [7:0]  m04_axi_bid;
    wire [1:0]  m04_axi_bresp;
    wire        m04_axi_bvalid;
    wire        m04_axi_bready;
    wire [7:0]  m04_axi_arid;
    wire [31:0] m04_axi_araddr;
    wire [7:0]  m04_axi_arlen;
    wire [2:0]  m04_axi_arsize;
    wire [1:0]  m04_axi_arburst;
    wire [2:0]  m04_axi_arprot;
    wire        m04_axi_arvalid;
    wire        m04_axi_arready;
    wire [7:0]  m04_axi_rid;
    wire [63:0] m04_axi_rdata;
    wire [1:0]  m04_axi_rresp;
    wire        m04_axi_rlast;
    wire        m04_axi_rvalid;
    wire        m04_axi_rready;

    // Slave 5: Recovery Policy
    wire [7:0]  m05_axi_awid;
    wire [31:0] m05_axi_awaddr;
    wire [7:0]  m05_axi_awlen;
    wire [2:0]  m05_axi_awsize;
    wire [1:0]  m05_axi_awburst;
    wire [2:0]  m05_axi_awprot;
    wire        m05_axi_awvalid;
    wire        m05_axi_awready;
    wire [63:0] m05_axi_wdata;
    wire [7:0]  m05_axi_wstrb;
    wire        m05_axi_wlast;
    wire        m05_axi_wvalid;
    wire        m05_axi_wready;
    wire [7:0]  m05_axi_bid;
    wire [1:0]  m05_axi_bresp;
    wire        m05_axi_bvalid;
    wire        m05_axi_bready;
    wire [7:0]  m05_axi_arid;
    wire [31:0] m05_axi_araddr;
    wire [7:0]  m05_axi_arlen;
    wire [2:0]  m05_axi_arsize;
    wire [1:0]  m05_axi_arburst;
    wire [2:0]  m05_axi_arprot;
    wire        m05_axi_arvalid;
    wire        m05_axi_arready;
    wire [7:0]  m05_axi_rid;
    wire [63:0] m05_axi_rdata;
    wire [1:0]  m05_axi_rresp;
    wire        m05_axi_rlast;
    wire        m05_axi_rvalid;
    wire        m05_axi_rready;

    // Slave 6: VGA Controller
    wire [7:0]  m06_axi_awid;
    wire [31:0] m06_axi_awaddr;
    wire [7:0]  m06_axi_awlen;
    wire [2:0]  m06_axi_awsize;
    wire [1:0]  m06_axi_awburst;
    wire [2:0]  m06_axi_awprot;
    wire        m06_axi_awvalid;
    wire        m06_axi_awready;
    wire [63:0] m06_axi_wdata;
    wire [7:0]  m06_axi_wstrb;
    wire        m06_axi_wlast;
    wire        m06_axi_wvalid;
    wire        m06_axi_wready;
    wire [7:0]  m06_axi_bid;
    wire [1:0]  m06_axi_bresp;
    wire        m06_axi_bvalid;
    wire        m06_axi_bready;
    wire [7:0]  m06_axi_arid;
    wire [31:0] m06_axi_araddr;
    wire [7:0]  m06_axi_arlen;
    wire [2:0]  m06_axi_arsize;
    wire [1:0]  m06_axi_arburst;
    wire [2:0]  m06_axi_arprot;
    wire        m06_axi_arvalid;
    wire        m06_axi_arready;
    wire [7:0]  m06_axi_rid;
    wire [63:0] m06_axi_rdata;
    wire [1:0]  m06_axi_rresp;
    wire        m06_axi_rlast;
    wire        m06_axi_rvalid;
    wire        m06_axi_rready;

    wire [7:0]  m07_axi_awid;
    wire [31:0] m07_axi_awaddr;
    wire [7:0]  m07_axi_awlen;
    wire [2:0]  m07_axi_awsize;
    wire [1:0]  m07_axi_awburst;
    wire [2:0]  m07_axi_awprot;
    wire        m07_axi_awvalid;
    wire        m07_axi_awready;
    wire [63:0] m07_axi_wdata;
    wire [7:0]  m07_axi_wstrb;
    wire        m07_axi_wlast;
    wire        m07_axi_wvalid;
    wire        m07_axi_wready;
    wire [7:0]  m07_axi_bid;
    wire [1:0]  m07_axi_bresp;
    wire        m07_axi_bvalid;
    wire        m07_axi_bready;
    wire [7:0]  m07_axi_arid;
    wire [31:0] m07_axi_araddr;
    wire [7:0]  m07_axi_arlen;
    wire [2:0]  m07_axi_arsize;
    wire [1:0]  m07_axi_arburst;
    wire [2:0]  m07_axi_arprot;
    wire        m07_axi_arvalid;
    wire        m07_axi_arready;
    wire [7:0]  m07_axi_rid;
    wire [63:0] m07_axi_rdata;
    wire [1:0]  m07_axi_rresp;
    wire        m07_axi_rlast;
    wire        m07_axi_rvalid;
    wire        m07_axi_rready;    wire [7:0]  ifu_axi_awid;
    wire [31:0] ifu_axi_awaddr;
    wire [7:0]  ifu_axi_awlen;
    wire [2:0]  ifu_axi_awsize;
    wire [1:0]  ifu_axi_awburst;
    wire [2:0]  ifu_axi_awprot;
    wire        ifu_axi_awvalid;
    wire        ifu_axi_awready;
    wire [63:0] ifu_axi_wdata;
    wire [7:0]  ifu_axi_wstrb;
    wire        ifu_axi_wlast;
    wire        ifu_axi_wvalid;
    wire        ifu_axi_wready;
    wire [7:0]  ifu_axi_bid;
    wire [1:0]  ifu_axi_bresp;
    wire        ifu_axi_bvalid;
    wire        ifu_axi_bready;
    wire [7:0]  ifu_axi_arid;
    wire [31:0] ifu_axi_araddr;
    wire [7:0]  ifu_axi_arlen;
    wire [2:0]  ifu_axi_arsize;
    wire [1:0]  ifu_axi_arburst;
    wire [2:0]  ifu_axi_arprot;
    wire        ifu_axi_arvalid;
    wire        ifu_axi_arready;
    wire [7:0]  ifu_axi_rid;
    wire [63:0] ifu_axi_rdata;
    wire [1:0]  ifu_axi_rresp;
    wire        ifu_axi_rlast;
    wire        ifu_axi_rvalid;
    wire        ifu_axi_rready;

    // ---- Pure AXI4 SoC Architecture — No Wishbone interfaces ----
    

    // ---- Point-to-point inter-IP signals ----
    wire        hb_irq;            // Heartbeat Monitor → PIC
    wire        reset_out_internal; // Reset Sequencer → GPIO output
    wire        uart_irq;          // UART RX interrupt
    wire        lockout_irq;
    wire        vblank_irq;

    // ---- UART direct-AXI data-width steering (64-bit bus → 32-bit UART) ----
    // The AXI interconnect operates at 64-bit; axi_uart_top is 32-bit AXI-Lite.
    // addr[2]=0 → lower 32 bits, addr[2]=1 → upper 32 bits (same as bridge).
    reg         uart_awaddr2_r;   // latch awaddr[2] when AW handshake fires
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_awaddr2_r <= 1'b0;
        else if (m00_axi_awvalid & m00_axi_awready)
            uart_awaddr2_r <= m00_axi_awaddr[2];
    end

    wire [31:0] uart_wdata_32  = uart_awaddr2_r ? m00_axi_wdata[63:32] : m00_axi_wdata[31:0];
    wire [3:0]  uart_wstrb_4   = uart_awaddr2_r ? m00_axi_wstrb[7:4]   : m00_axi_wstrb[3:0];
    wire [31:0] uart_rdata_32;   // driven by axi_uart_top
    assign      m00_axi_rdata  = {uart_rdata_32, uart_rdata_32}; // replicated to both halves
    assign      m00_axi_rlast  = m00_axi_rvalid; // AXI-Lite: always single beat

    
    // ========================================================================
    // UART Controller Instance
    // ========================================================================
    axi_uart_top u_uart (
        .fixed_clk_i      (clk),
        .axi_aclk_i       (clk),
        .axi_aresetn_i    (rst_n),
        
        .axi_awid_i       (m00_axi_awid),
        .axi_awaddr_i     (m00_axi_awaddr),
        .axi_awvalid_i    (m00_axi_awvalid),
        .axi_awready_o    (m00_axi_awready),
        
        .axi_wdata_i      (uart_wdata_32),
        .axi_wstrb_i      (uart_wstrb_4),
        .axi_wvalid_i     (m00_axi_wvalid),
        .axi_wready_o     (m00_axi_wready),
        
        .axi_bid_o        (m00_axi_bid),
        .axi_bresp_o      (m00_axi_bresp),
        .axi_bvalid_o     (m00_axi_bvalid),
        .axi_bready_i     (m00_axi_bready),
        
        .axi_arid_i       (m00_axi_arid),
        .axi_araddr_i     (m00_axi_araddr),
        .axi_arvalid_i    (m00_axi_arvalid),
        .axi_arready_o    (m00_axi_arready),
        
        .axi_rid_o        (m00_axi_rid),
        .axi_rdata_o      (uart_rdata_32),
        .axi_rresp_o      (m00_axi_rresp),
        .axi_rvalid_o     (m00_axi_rvalid),
        .axi_rready_i     (m00_axi_rready),
        
        .uart_rx_i        (uart_rx),
        .uart_tx_o        (uart_tx),
        .read_interrupt_o (uart_irq)
    );

    // ========================================================================
    // VeeR EL2 Core Instance (Placeholder / Interface Hook)
    // ========================================================================
    // In full SoC integration, u_veer connects to lsu_axi_* and sb_axi_*.
    // Tying off master request signals when core is uninstantiated:

    // ========================================================================
    // AXI4 Interconnect (2 Masters x 7 Slaves)
    // Generated using scripts/axi_interconnect_wrap.py
    // ========================================================================
    axi_interconnect_wrap_3x8 #(
        .DATA_WIDTH        (64),
        .ADDR_WIDTH        (32),
        .STRB_WIDTH        (8),
        .ID_WIDTH          (8),
        .FORWARD_ID        (1),
        .M_REGIONS         (1),

        // Slave 0: UART (0x0002_0000 - 0x0002_00FF, 256 B = 8-bit offset)
        .M00_BASE_ADDR     (BASE_UART),
        .M00_ADDR_WIDTH    (32'd8),
        .M00_CONNECT_READ  (2'b11),
        .M00_CONNECT_WRITE (2'b11),
        .M00_SECURE        (1'b0),

        // Slave 1: Timer (0x0002_0100 - 0x0002_01FF, 256 B = 8-bit offset)
        .M01_BASE_ADDR     (BASE_TIMER),
        .M01_ADDR_WIDTH    (32'd8),
        .M01_CONNECT_READ  (2'b11),
        .M01_CONNECT_WRITE (2'b11),
        .M01_SECURE        (1'b0),

        // Slave 2: GPIO (0x0002_0200 - 0x0002_02FF, 256 B = 8-bit offset)
        .M02_BASE_ADDR     (BASE_GPIO),
        .M02_ADDR_WIDTH    (32'd8),
        .M02_CONNECT_READ  (2'b11),
        .M02_CONNECT_WRITE (2'b11),
        .M02_SECURE        (1'b0),

        // Slave 3: Heartbeat Monitor (0x0002_0300 - 0x0002_03FF, 256 B = 8-bit offset)
        .M03_BASE_ADDR     (BASE_HB_MON),
        .M03_ADDR_WIDTH    (32'd8),
        .M03_CONNECT_READ  (2'b11),
        .M03_CONNECT_WRITE (2'b11),
        .M03_SECURE        (1'b0),

        // Slave 4: Reset Sequencer (0x0002_0400 - 0x0002_04FF, 256 B = 8-bit offset)
        .M04_BASE_ADDR     (BASE_RESET_SEQ),
        .M04_ADDR_WIDTH    (32'd8),
        .M04_CONNECT_READ  (2'b11),
        .M04_CONNECT_WRITE (2'b11),
        .M04_SECURE        (1'b0),

        // Slave 5: Recovery Policy (0x0002_0500 - 0x0002_05FF, 256 B = 8-bit offset)
        .M05_BASE_ADDR     (BASE_REC_POL),
        .M05_ADDR_WIDTH    (32'd8),
        .M05_CONNECT_READ  (2'b11),
        .M05_CONNECT_WRITE (2'b11),
        .M05_SECURE        (1'b0),

        // Slave 6: VGA Dashboard (0x0002_0600 - 0x0002_06FF, 256 B = 8-bit offset)
        .M06_BASE_ADDR     (BASE_VGA),
        .M06_ADDR_WIDTH    (32'd8),
        .M06_CONNECT_READ  (2'b11),
        .M06_CONNECT_WRITE (2'b11),
        .M06_SECURE        (1'b0)
    ,
        .M07_BASE_ADDR     (32'h8000_0000),
        .M07_ADDR_WIDTH    (32'd13)
    ) u_axi_intercon (
        .clk             (clk),
        .rst             (rst),

        .s00_axi_awid (ifu_axi_awid),
        .s00_axi_awaddr (ifu_axi_awaddr),
        .s00_axi_awlen (ifu_axi_awlen),
        .s00_axi_awsize (ifu_axi_awsize),
        .s00_axi_awburst (ifu_axi_awburst),
        .s00_axi_awlock (ifu_axi_awlock),
        .s00_axi_awcache (ifu_axi_awcache),
        .s00_axi_awprot (ifu_axi_awprot),
        .s00_axi_awqos (ifu_axi_awqos),
        .s00_axi_awvalid (ifu_axi_awvalid),
        .s00_axi_awready (ifu_axi_awready),
        .s00_axi_wdata (ifu_axi_wdata),
        .s00_axi_wstrb (ifu_axi_wstrb),
        .s00_axi_wlast (ifu_axi_wlast),
        .s00_axi_wvalid (ifu_axi_wvalid),
        .s00_axi_wready (ifu_axi_wready),
        .s00_axi_bid (ifu_axi_bid),
        .s00_axi_bresp (ifu_axi_bresp),
        .s00_axi_bvalid (ifu_axi_bvalid),
        .s00_axi_bready (ifu_axi_bready),
        .s00_axi_arid (ifu_axi_arid),
        .s00_axi_araddr (ifu_axi_araddr),
        .s00_axi_arlen (ifu_axi_arlen),
        .s00_axi_arsize (ifu_axi_arsize),
        .s00_axi_arburst (ifu_axi_arburst),
        .s00_axi_arlock (ifu_axi_arlock),
        .s00_axi_arcache (ifu_axi_arcache),
        .s00_axi_arprot (ifu_axi_arprot),
        .s00_axi_arqos (ifu_axi_arqos),
        .s00_axi_arvalid (ifu_axi_arvalid),
        .s00_axi_arready (ifu_axi_arready),
        .s00_axi_rid (ifu_axi_rid),
        .s00_axi_rdata (ifu_axi_rdata),
        .s00_axi_rresp (ifu_axi_rresp),
        .s00_axi_rlast (ifu_axi_rlast),
        .s00_axi_rvalid (ifu_axi_rvalid),
        .s00_axi_rready (ifu_axi_rready),

        // Master 0 Interface (S00) — VeeR LSU
        .s01_axi_awid    (lsu_axi_awid),
        .s01_axi_awaddr  (lsu_axi_awaddr),
        .s01_axi_awlen   (lsu_axi_awlen),
        .s01_axi_awsize  (lsu_axi_awsize),
        .s01_axi_awburst (lsu_axi_awburst),
        .s01_axi_awlock  (lsu_axi_awlock),
        .s01_axi_awcache (lsu_axi_awcache),
        .s01_axi_awprot  (lsu_axi_awprot),
        .s01_axi_awqos   (lsu_axi_awqos),
        .s01_axi_awuser  (1'b0),
        .s01_axi_awvalid (lsu_axi_awvalid),
        .s01_axi_awready (lsu_axi_awready),
        .s01_axi_wdata   (lsu_axi_wdata),
        .s01_axi_wstrb   (lsu_axi_wstrb),
        .s01_axi_wlast   (lsu_axi_wlast),
        .s01_axi_wuser   (1'b0),
        .s01_axi_wvalid  (lsu_axi_wvalid),
        .s01_axi_wready  (lsu_axi_wready),
        .s01_axi_bid     (lsu_axi_bid),
        .s01_axi_bresp   (lsu_axi_bresp),
        .s01_axi_buser   (),
        .s01_axi_bvalid  (lsu_axi_bvalid),
        .s01_axi_bready  (lsu_axi_bready),
        .s01_axi_arid    (lsu_axi_arid),
        .s01_axi_araddr  (lsu_axi_araddr),
        .s01_axi_arlen   (lsu_axi_arlen),
        .s01_axi_arsize  (lsu_axi_arsize),
        .s01_axi_arburst (lsu_axi_arburst),
        .s01_axi_arlock  (lsu_axi_arlock),
        .s01_axi_arcache (lsu_axi_arcache),
        .s01_axi_arprot  (lsu_axi_arprot),
        .s01_axi_arqos   (lsu_axi_arqos),
        .s01_axi_aruser  (1'b0),
        .s01_axi_arvalid (lsu_axi_arvalid),
        .s01_axi_arready (lsu_axi_arready),
        .s01_axi_rid     (lsu_axi_rid),
        .s01_axi_rdata   (lsu_axi_rdata),
        .s01_axi_rresp   (lsu_axi_rresp),
        .s01_axi_rlast   (lsu_axi_rlast),
        .s01_axi_ruser   (),
        .s01_axi_rvalid  (lsu_axi_rvalid),
        .s01_axi_rready  (lsu_axi_rready),

        // Master 1 Interface (S01) — VeeR SB / Debug
        .s02_axi_awid    (sb_axi_awid),
        .s02_axi_awaddr  (sb_axi_awaddr),
        .s02_axi_awlen   (sb_axi_awlen),
        .s02_axi_awsize  (sb_axi_awsize),
        .s02_axi_awburst (sb_axi_awburst),
        .s02_axi_awlock  (sb_axi_awlock),
        .s02_axi_awcache (sb_axi_awcache),
        .s02_axi_awprot  (sb_axi_awprot),
        .s02_axi_awqos   (sb_axi_awqos),
        .s02_axi_awuser  (1'b0),
        .s02_axi_awvalid (sb_axi_awvalid),
        .s02_axi_awready (sb_axi_awready),
        .s02_axi_wdata   (sb_axi_wdata),
        .s02_axi_wstrb   (sb_axi_wstrb),
        .s02_axi_wlast   (sb_axi_wlast),
        .s02_axi_wuser   (1'b0),
        .s02_axi_wvalid  (sb_axi_wvalid),
        .s02_axi_wready  (sb_axi_wready),
        .s02_axi_bid     (sb_axi_bid),
        .s02_axi_bresp   (sb_axi_bresp),
        .s02_axi_buser   (),
        .s02_axi_bvalid  (sb_axi_bvalid),
        .s02_axi_bready  (sb_axi_bready),
        .s02_axi_arid    (sb_axi_arid),
        .s02_axi_araddr  (sb_axi_araddr),
        .s02_axi_arlen   (sb_axi_arlen),
        .s02_axi_arsize  (sb_axi_arsize),
        .s02_axi_arburst (sb_axi_arburst),
        .s02_axi_arlock  (sb_axi_arlock),
        .s02_axi_arcache (sb_axi_arcache),
        .s02_axi_arprot  (sb_axi_arprot),
        .s02_axi_arqos   (sb_axi_arqos),
        .s02_axi_aruser  (1'b0),
        .s02_axi_arvalid (sb_axi_arvalid),
        .s02_axi_arready (sb_axi_arready),
        .s02_axi_rid     (sb_axi_rid),
        .s02_axi_rdata   (sb_axi_rdata),
        .s02_axi_rresp   (sb_axi_rresp),
        .s02_axi_rlast   (sb_axi_rlast),
        .s02_axi_ruser   (),
        .s02_axi_rvalid  (sb_axi_rvalid),
        .s02_axi_rready  (sb_axi_rready),

        // Slave 0 Interface (M00) — UART
        .m00_axi_awid    (m00_axi_awid),
        .m00_axi_awaddr  (m00_axi_awaddr),
        .m00_axi_awlen   (m00_axi_awlen),
        .m00_axi_awsize  (m00_axi_awsize),
        .m00_axi_awburst (m00_axi_awburst),
        .m00_axi_awlock  (),
        .m00_axi_awcache (),
        .m00_axi_awprot  (m00_axi_awprot),
        .m00_axi_awqos   (),
        .m00_axi_awregion(),
        .m00_axi_awuser  (),
        .m00_axi_awvalid (m00_axi_awvalid),
        .m00_axi_awready (m00_axi_awready),
        .m00_axi_wdata   (m00_axi_wdata),
        .m00_axi_wstrb   (m00_axi_wstrb),
        .m00_axi_wlast   (m00_axi_wlast),
        .m00_axi_wuser   (),
        .m00_axi_wvalid  (m00_axi_wvalid),
        .m00_axi_wready  (m00_axi_wready),
        .m00_axi_bid     (m00_axi_bid),
        .m00_axi_bresp   (m00_axi_bresp),
        .m00_axi_buser   (1'b0),
        .m00_axi_bvalid  (m00_axi_bvalid),
        .m00_axi_bready  (m00_axi_bready),
        .m00_axi_arid    (m00_axi_arid),
        .m00_axi_araddr  (m00_axi_araddr),
        .m00_axi_arlen   (m00_axi_arlen),
        .m00_axi_arsize  (m00_axi_arsize),
        .m00_axi_arburst (m00_axi_arburst),
        .m00_axi_arlock  (),
        .m00_axi_arcache (),
        .m00_axi_arprot  (m00_axi_arprot),
        .m00_axi_arqos   (),
        .m00_axi_arregion(),
        .m00_axi_aruser  (),
        .m00_axi_arvalid (m00_axi_arvalid),
        .m00_axi_arready (m00_axi_arready),
        .m00_axi_rid     (m00_axi_rid),
        .m00_axi_rdata   (m00_axi_rdata),
        .m00_axi_rresp   (m00_axi_rresp),
        .m00_axi_rlast   (m00_axi_rlast),
        .m00_axi_ruser   (1'b0),
        .m00_axi_rvalid  (m00_axi_rvalid),
        .m00_axi_rready  (m00_axi_rready),

        // Slave 1 Interface (M01) — Timer
        .m01_axi_awid    (m01_axi_awid),
        .m01_axi_awaddr  (m01_axi_awaddr),
        .m01_axi_awlen   (m01_axi_awlen),
        .m01_axi_awsize  (m01_axi_awsize),
        .m01_axi_awburst (m01_axi_awburst),
        .m01_axi_awlock  (),
        .m01_axi_awcache (),
        .m01_axi_awprot  (m01_axi_awprot),
        .m01_axi_awqos   (),
        .m01_axi_awregion(),
        .m01_axi_awuser  (),
        .m01_axi_awvalid (m01_axi_awvalid),
        .m01_axi_awready (m01_axi_awready),
        .m01_axi_wdata   (m01_axi_wdata),
        .m01_axi_wstrb   (m01_axi_wstrb),
        .m01_axi_wlast   (m01_axi_wlast),
        .m01_axi_wuser   (),
        .m01_axi_wvalid  (m01_axi_wvalid),
        .m01_axi_wready  (m01_axi_wready),
        .m01_axi_bid     (m01_axi_bid),
        .m01_axi_bresp   (m01_axi_bresp),
        .m01_axi_buser   (1'b0),
        .m01_axi_bvalid  (m01_axi_bvalid),
        .m01_axi_bready  (m01_axi_bready),
        .m01_axi_arid    (m01_axi_arid),
        .m01_axi_araddr  (m01_axi_araddr),
        .m01_axi_arlen   (m01_axi_arlen),
        .m01_axi_arsize  (m01_axi_arsize),
        .m01_axi_arburst (m01_axi_arburst),
        .m01_axi_arlock  (),
        .m01_axi_arcache (),
        .m01_axi_arprot  (m01_axi_arprot),
        .m01_axi_arqos   (),
        .m01_axi_arregion(),
        .m01_axi_aruser  (),
        .m01_axi_arvalid (m01_axi_arvalid),
        .m01_axi_arready (m01_axi_arready),
        .m01_axi_rid     (m01_axi_rid),
        .m01_axi_rdata   (m01_axi_rdata),
        .m01_axi_rresp   (m01_axi_rresp),
        .m01_axi_rlast   (m01_axi_rlast),
        .m01_axi_ruser   (1'b0),
        .m01_axi_rvalid  (m01_axi_rvalid),
        .m01_axi_rready  (m01_axi_rready),

        // Slave 2 Interface (M02) — GPIO
        .m02_axi_awid    (m02_axi_awid),
        .m02_axi_awaddr  (m02_axi_awaddr),
        .m02_axi_awlen   (m02_axi_awlen),
        .m02_axi_awsize  (m02_axi_awsize),
        .m02_axi_awburst (m02_axi_awburst),
        .m02_axi_awlock  (),
        .m02_axi_awcache (),
        .m02_axi_awprot  (m02_axi_awprot),
        .m02_axi_awqos   (),
        .m02_axi_awregion(),
        .m02_axi_awuser  (),
        .m02_axi_awvalid (m02_axi_awvalid),
        .m02_axi_awready (m02_axi_awready),
        .m02_axi_wdata   (m02_axi_wdata),
        .m02_axi_wstrb   (m02_axi_wstrb),
        .m02_axi_wlast   (m02_axi_wlast),
        .m02_axi_wuser   (),
        .m02_axi_wvalid  (m02_axi_wvalid),
        .m02_axi_wready  (m02_axi_wready),
        .m02_axi_bid     (m02_axi_bid),
        .m02_axi_bresp   (m02_axi_bresp),
        .m02_axi_buser   (1'b0),
        .m02_axi_bvalid  (m02_axi_bvalid),
        .m02_axi_bready  (m02_axi_bready),
        .m02_axi_arid    (m02_axi_arid),
        .m02_axi_araddr  (m02_axi_araddr),
        .m02_axi_arlen   (m02_axi_arlen),
        .m02_axi_arsize  (m02_axi_arsize),
        .m02_axi_arburst (m02_axi_arburst),
        .m02_axi_arlock  (),
        .m02_axi_arcache (),
        .m02_axi_arprot  (m02_axi_arprot),
        .m02_axi_arqos   (),
        .m02_axi_arregion(),
        .m02_axi_aruser  (),
        .m02_axi_arvalid (m02_axi_arvalid),
        .m02_axi_arready (m02_axi_arready),
        .m02_axi_rid     (m02_axi_rid),
        .m02_axi_rdata   (m02_axi_rdata),
        .m02_axi_rresp   (m02_axi_rresp),
        .m02_axi_rlast   (m02_axi_rlast),
        .m02_axi_ruser   (1'b0),
        .m02_axi_rvalid  (m02_axi_rvalid),
        .m02_axi_rready  (m02_axi_rready),

        // Slave 3 Interface (M03) — Heartbeat Monitor
        .m03_axi_awid    (m03_axi_awid),
        .m03_axi_awaddr  (m03_axi_awaddr),
        .m03_axi_awlen   (m03_axi_awlen),
        .m03_axi_awsize  (m03_axi_awsize),
        .m03_axi_awburst (m03_axi_awburst),
        .m03_axi_awlock  (),
        .m03_axi_awcache (),
        .m03_axi_awprot  (m03_axi_awprot),
        .m03_axi_awqos   (),
        .m03_axi_awregion(),
        .m03_axi_awuser  (),
        .m03_axi_awvalid (m03_axi_awvalid),
        .m03_axi_awready (m03_axi_awready),
        .m03_axi_wdata   (m03_axi_wdata),
        .m03_axi_wstrb   (m03_axi_wstrb),
        .m03_axi_wlast   (m03_axi_wlast),
        .m03_axi_wuser   (),
        .m03_axi_wvalid  (m03_axi_wvalid),
        .m03_axi_wready  (m03_axi_wready),
        .m03_axi_bid     (m03_axi_bid),
        .m03_axi_bresp   (m03_axi_bresp),
        .m03_axi_buser   (1'b0),
        .m03_axi_bvalid  (m03_axi_bvalid),
        .m03_axi_bready  (m03_axi_bready),
        .m03_axi_arid    (m03_axi_arid),
        .m03_axi_araddr  (m03_axi_araddr),
        .m03_axi_arlen   (m03_axi_arlen),
        .m03_axi_arsize  (m03_axi_arsize),
        .m03_axi_arburst (m03_axi_arburst),
        .m03_axi_arlock  (),
        .m03_axi_arcache (),
        .m03_axi_arprot  (m03_axi_arprot),
        .m03_axi_arqos   (),
        .m03_axi_arregion(),
        .m03_axi_aruser  (),
        .m03_axi_arvalid (m03_axi_arvalid),
        .m03_axi_arready (m03_axi_arready),
        .m03_axi_rid     (m03_axi_rid),
        .m03_axi_rdata   (m03_axi_rdata),
        .m03_axi_rresp   (m03_axi_rresp),
        .m03_axi_rlast   (m03_axi_rlast),
        .m03_axi_ruser   (1'b0),
        .m03_axi_rvalid  (m03_axi_rvalid),
        .m03_axi_rready  (m03_axi_rready),

        // Slave 4 Interface (M04) — Reset Sequencer
        .m04_axi_awid    (m04_axi_awid),
        .m04_axi_awaddr  (m04_axi_awaddr),
        .m04_axi_awlen   (m04_axi_awlen),
        .m04_axi_awsize  (m04_axi_awsize),
        .m04_axi_awburst (m04_axi_awburst),
        .m04_axi_awlock  (),
        .m04_axi_awcache (),
        .m04_axi_awprot  (m04_axi_awprot),
        .m04_axi_awqos   (),
        .m04_axi_awregion(),
        .m04_axi_awuser  (),
        .m04_axi_awvalid (m04_axi_awvalid),
        .m04_axi_awready (m04_axi_awready),
        .m04_axi_wdata   (m04_axi_wdata),
        .m04_axi_wstrb   (m04_axi_wstrb),
        .m04_axi_wlast   (m04_axi_wlast),
        .m04_axi_wuser   (),
        .m04_axi_wvalid  (m04_axi_wvalid),
        .m04_axi_wready  (m04_axi_wready),
        .m04_axi_bid     (m04_axi_bid),
        .m04_axi_bresp   (m04_axi_bresp),
        .m04_axi_buser   (1'b0),
        .m04_axi_bvalid  (m04_axi_bvalid),
        .m04_axi_bready  (m04_axi_bready),
        .m04_axi_arid    (m04_axi_arid),
        .m04_axi_araddr  (m04_axi_araddr),
        .m04_axi_arlen   (m04_axi_arlen),
        .m04_axi_arsize  (m04_axi_arsize),
        .m04_axi_arburst (m04_axi_arburst),
        .m04_axi_arlock  (),
        .m04_axi_arcache (),
        .m04_axi_arprot  (m04_axi_arprot),
        .m04_axi_arqos   (),
        .m04_axi_arregion(),
        .m04_axi_aruser  (),
        .m04_axi_arvalid (m04_axi_arvalid),
        .m04_axi_arready (m04_axi_arready),
        .m04_axi_rid     (m04_axi_rid),
        .m04_axi_rdata   (m04_axi_rdata),
        .m04_axi_rresp   (m04_axi_rresp),
        .m04_axi_rlast   (m04_axi_rlast),
        .m04_axi_ruser   (1'b0),
        .m04_axi_rvalid  (m04_axi_rvalid),
        .m04_axi_rready  (m04_axi_rready),

        // Slave 5 Interface (M05) — Recovery Policy
        .m05_axi_awid    (m05_axi_awid),
        .m05_axi_awaddr  (m05_axi_awaddr),
        .m05_axi_awlen   (m05_axi_awlen),
        .m05_axi_awsize  (m05_axi_awsize),
        .m05_axi_awburst (m05_axi_awburst),
        .m05_axi_awlock  (),
        .m05_axi_awcache (),
        .m05_axi_awprot  (m05_axi_awprot),
        .m05_axi_awqos   (),
        .m05_axi_awregion(),
        .m05_axi_awuser  (),
        .m05_axi_awvalid (m05_axi_awvalid),
        .m05_axi_awready (m05_axi_awready),
        .m05_axi_wdata   (m05_axi_wdata),
        .m05_axi_wstrb   (m05_axi_wstrb),
        .m05_axi_wlast   (m05_axi_wlast),
        .m05_axi_wuser   (),
        .m05_axi_wvalid  (m05_axi_wvalid),
        .m05_axi_wready  (m05_axi_wready),
        .m05_axi_bid     (m05_axi_bid),
        .m05_axi_bresp   (m05_axi_bresp),
        .m05_axi_buser   (1'b0),
        .m05_axi_bvalid  (m05_axi_bvalid),
        .m05_axi_bready  (m05_axi_bready),
        .m05_axi_arid    (m05_axi_arid),
        .m05_axi_araddr  (m05_axi_araddr),
        .m05_axi_arlen   (m05_axi_arlen),
        .m05_axi_arsize  (m05_axi_arsize),
        .m05_axi_arburst (m05_axi_arburst),
        .m05_axi_arlock  (),
        .m05_axi_arcache (),
        .m05_axi_arprot  (m05_axi_arprot),
        .m05_axi_arqos   (),
        .m05_axi_arregion(),
        .m05_axi_aruser  (),
        .m05_axi_arvalid (m05_axi_arvalid),
        .m05_axi_arready (m05_axi_arready),
        .m05_axi_rid     (m05_axi_rid),
        .m05_axi_rdata   (m05_axi_rdata),
        .m05_axi_rresp   (m05_axi_rresp),
        .m05_axi_rlast   (m05_axi_rlast),
        .m05_axi_ruser   (1'b0),
        .m05_axi_rvalid  (m05_axi_rvalid),
        .m05_axi_rready  (m05_axi_rready),

        // Slave 6 Interface (M06) — VGA Dashboard
        .m06_axi_awid    (m06_axi_awid),
        .m06_axi_awaddr  (m06_axi_awaddr),
        .m06_axi_awlen   (m06_axi_awlen),
        .m06_axi_awsize  (m06_axi_awsize),
        .m06_axi_awburst (m06_axi_awburst),
        .m06_axi_awlock  (),
        .m06_axi_awcache (),
        .m06_axi_awprot  (m06_axi_awprot),
        .m06_axi_awqos   (),
        .m06_axi_awregion(),
        .m06_axi_awuser  (),
        .m06_axi_awvalid (m06_axi_awvalid),
        .m06_axi_awready (m06_axi_awready),
        .m06_axi_wdata   (m06_axi_wdata),
        .m06_axi_wstrb   (m06_axi_wstrb),
        .m06_axi_wlast   (m06_axi_wlast),
        .m06_axi_wuser   (),
        .m06_axi_wvalid  (m06_axi_wvalid),
        .m06_axi_wready  (m06_axi_wready),
        .m06_axi_bid     (m06_axi_bid),
        .m06_axi_bresp   (m06_axi_bresp),
        .m06_axi_buser   (1'b0),
        .m06_axi_bvalid  (m06_axi_bvalid),
        .m06_axi_bready  (m06_axi_bready),
        .m06_axi_arid    (m06_axi_arid),
        .m06_axi_araddr  (m06_axi_araddr),
        .m06_axi_arlen   (m06_axi_arlen),
        .m06_axi_arsize  (m06_axi_arsize),
        .m06_axi_arburst (m06_axi_arburst),
        .m06_axi_arlock  (),
        .m06_axi_arcache (),
        .m06_axi_arprot  (m06_axi_arprot),
        .m06_axi_arqos   (),
        .m06_axi_arregion(),
        .m06_axi_aruser  (),
        .m06_axi_arvalid (m06_axi_arvalid),
        .m06_axi_arready (m06_axi_arready),
        .m06_axi_rid     (m06_axi_rid),
        .m06_axi_rdata   (m06_axi_rdata),
        .m06_axi_rresp   (m06_axi_rresp),
        .m06_axi_rlast   (m06_axi_rlast),
        .m06_axi_ruser   (1'b0),
        .m06_axi_rvalid  (m06_axi_rvalid),
        .m06_axi_rready  (m06_axi_rready)
    ,
        .m07_axi_awid (m07_axi_awid),
        .m07_axi_awaddr (m07_axi_awaddr),
        .m07_axi_awlen (m07_axi_awlen),
        .m07_axi_awsize (m07_axi_awsize),
        .m07_axi_awburst (m07_axi_awburst),
        .m07_axi_awlock (m07_axi_awlock),
        .m07_axi_awcache (m07_axi_awcache),
        .m07_axi_awprot (m07_axi_awprot),
        .m07_axi_awqos (m07_axi_awqos),
        .m07_axi_awvalid (m07_axi_awvalid),
        .m07_axi_awready (m07_axi_awready),
        .m07_axi_wdata (m07_axi_wdata),
        .m07_axi_wstrb (m07_axi_wstrb),
        .m07_axi_wlast (m07_axi_wlast),
        .m07_axi_wvalid (m07_axi_wvalid),
        .m07_axi_wready (m07_axi_wready),
        .m07_axi_bid (m07_axi_bid),
        .m07_axi_bresp (m07_axi_bresp),
        .m07_axi_bvalid (m07_axi_bvalid),
        .m07_axi_bready (m07_axi_bready),
        .m07_axi_arid (m07_axi_arid),
        .m07_axi_araddr (m07_axi_araddr),
        .m07_axi_arlen (m07_axi_arlen),
        .m07_axi_arsize (m07_axi_arsize),
        .m07_axi_arburst (m07_axi_arburst),
        .m07_axi_arlock (m07_axi_arlock),
        .m07_axi_arcache (m07_axi_arcache),
        .m07_axi_arprot (m07_axi_arprot),
        .m07_axi_arqos (m07_axi_arqos),
        .m07_axi_arvalid (m07_axi_arvalid),
        .m07_axi_arready (m07_axi_arready),
        .m07_axi_rid (m07_axi_rid),
        .m07_axi_rdata (m07_axi_rdata),
        .m07_axi_rresp (m07_axi_rresp),
        .m07_axi_rlast (m07_axi_rlast),
        .m07_axi_rvalid (m07_axi_rvalid),
        .m07_axi_rready (m07_axi_rready));

    // ========================================================================
    // Slave 1: 32-bit Free-Running System Timer (Pure AXI4)
    // ========================================================================
    axi_timer #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (32),
        .ID_WIDTH   (8)
    ) u_timer (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awid    (m01_axi_awid),
        .s_axi_awaddr  (m01_axi_awaddr),
        .s_axi_awlen   (m01_axi_awlen),
        .s_axi_awsize  (m01_axi_awsize),
        .s_axi_awburst (m01_axi_awburst),
        .s_axi_awprot  (m01_axi_awprot),
        .s_axi_awvalid (m01_axi_awvalid),
        .s_axi_awready (m01_axi_awready),
        .s_axi_wdata   (m01_axi_wdata),
        .s_axi_wstrb   (m01_axi_wstrb),
        .s_axi_wlast   (m01_axi_wlast),
        .s_axi_wvalid  (m01_axi_wvalid),
        .s_axi_wready  (m01_axi_wready),
        .s_axi_bid     (m01_axi_bid),
        .s_axi_bresp   (m01_axi_bresp),
        .s_axi_bvalid  (m01_axi_bvalid),
        .s_axi_bready  (m01_axi_bready),
        .s_axi_arid    (m01_axi_arid),
        .s_axi_araddr  (m01_axi_araddr),
        .s_axi_arlen   (m01_axi_arlen),
        .s_axi_arsize  (m01_axi_arsize),
        .s_axi_arburst (m01_axi_arburst),
        .s_axi_arprot  (m01_axi_arprot),
        .s_axi_arvalid (m01_axi_arvalid),
        .s_axi_arready (m01_axi_arready),
        .s_axi_rid     (m01_axi_rid),
        .s_axi_rdata   (m01_axi_rdata),
        .s_axi_rresp   (m01_axi_rresp),
        .s_axi_rlast   (m01_axi_rlast),
        .s_axi_rvalid  (m01_axi_rvalid),
        .s_axi_rready  (m01_axi_rready)
    );

    // ========================================================================
    // Slave 2: GPIO Pin Status Register (Pure AXI4)
    // ========================================================================
    axi_gpio #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (32),
        .ID_WIDTH   (8)
    ) u_gpio (
        .clk           (clk),
        .rst_n         (rst_n),
        .heartbeat_in  (heartbeat_in),
        .reset_out     (reset_out_internal),
        .s_axi_awid    (m02_axi_awid),
        .s_axi_awaddr  (m02_axi_awaddr),
        .s_axi_awlen   (m02_axi_awlen),
        .s_axi_awsize  (m02_axi_awsize),
        .s_axi_awburst (m02_axi_awburst),
        .s_axi_awprot  (m02_axi_awprot),
        .s_axi_awvalid (m02_axi_awvalid),
        .s_axi_awready (m02_axi_awready),
        .s_axi_wdata   (m02_axi_wdata),
        .s_axi_wstrb   (m02_axi_wstrb),
        .s_axi_wlast   (m02_axi_wlast),
        .s_axi_wvalid  (m02_axi_wvalid),
        .s_axi_wready  (m02_axi_wready),
        .s_axi_bid     (m02_axi_bid),
        .s_axi_bresp   (m02_axi_bresp),
        .s_axi_bvalid  (m02_axi_bvalid),
        .s_axi_bready  (m02_axi_bready),
        .s_axi_arid    (m02_axi_arid),
        .s_axi_araddr  (m02_axi_araddr),
        .s_axi_arlen   (m02_axi_arlen),
        .s_axi_arsize  (m02_axi_arsize),
        .s_axi_arburst (m02_axi_arburst),
        .s_axi_arprot  (m02_axi_arprot),
        .s_axi_arvalid (m02_axi_arvalid),
        .s_axi_arready (m02_axi_arready),
        .s_axi_rid     (m02_axi_rid),
        .s_axi_rdata   (m02_axi_rdata),
        .s_axi_rresp   (m02_axi_rresp),
        .s_axi_rlast   (m02_axi_rlast),
        .s_axi_rvalid  (m02_axi_rvalid),
        .s_axi_rready  (m02_axi_rready)
    );

    // ========================================================================
    // Slave 3: Heartbeat Monitor (AXI Wrapper)
    // ========================================================================
    axi_heartbeat_monitor u_heartbeat (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awid    (m03_axi_awid),
        .s_axi_awaddr  (m03_axi_awaddr),
        .s_axi_awlen   (m03_axi_awlen),
        .s_axi_awsize  (m03_axi_awsize),
        .s_axi_awburst (m03_axi_awburst),
        .s_axi_awprot  (m03_axi_awprot),
        .s_axi_awvalid (m03_axi_awvalid),
        .s_axi_awready (m03_axi_awready),
        .s_axi_wdata   (m03_axi_wdata),
        .s_axi_wstrb   (m03_axi_wstrb),
        .s_axi_wlast   (m03_axi_wlast),
        .s_axi_wvalid  (m03_axi_wvalid),
        .s_axi_wready  (m03_axi_wready),
        .s_axi_bid     (m03_axi_bid),
        .s_axi_bresp   (m03_axi_bresp),
        .s_axi_bvalid  (m03_axi_bvalid),
        .s_axi_bready  (m03_axi_bready),
        .s_axi_arid    (m03_axi_arid),
        .s_axi_araddr  (m03_axi_araddr),
        .s_axi_arlen   (m03_axi_arlen),
        .s_axi_arsize  (m03_axi_arsize),
        .s_axi_arburst (m03_axi_arburst),
        .s_axi_arprot  (m03_axi_arprot),
        .s_axi_arvalid (m03_axi_arvalid),
        .s_axi_arready (m03_axi_arready),
        .s_axi_rid     (m03_axi_rid),
        .s_axi_rdata   (m03_axi_rdata),
        .s_axi_rresp   (m03_axi_rresp),
        .s_axi_rlast   (m03_axi_rlast),
        .s_axi_rvalid  (m03_axi_rvalid),
        .s_axi_rready  (m03_axi_rready),
        .heartbeat_in  (heartbeat_in),
        .hb_irq        (hb_irq)
    );

    // ========================================================================
    // Slave 4: Power/Reset Sequencer (Custom IP #2)
    // ========================================================================
    // Base Address: 0x0002_0400 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (RST_CTRL, WO):        [0] trigger (self-clearing)
    //   0x04 (RST_HOLD_CYCLES, R/W):[31:0] reset pulse duration in clock cycles
    //   0x08 (RST_STATUS, RO):      [0] in_progress, [1] complete (sticky)
    axi_reset_sequencer u_reset_seq (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awid    (m04_axi_awid),
        .s_axi_awaddr  (m04_axi_awaddr),
        .s_axi_awlen   (m04_axi_awlen),
        .s_axi_awsize  (m04_axi_awsize),
        .s_axi_awburst (m04_axi_awburst),
        .s_axi_awprot  (m04_axi_awprot),
        .s_axi_awvalid (m04_axi_awvalid),
        .s_axi_awready (m04_axi_awready),
        .s_axi_wdata   (m04_axi_wdata),
        .s_axi_wstrb   (m04_axi_wstrb),
        .s_axi_wlast   (m04_axi_wlast),
        .s_axi_wvalid  (m04_axi_wvalid),
        .s_axi_wready  (m04_axi_wready),
        .s_axi_bid     (m04_axi_bid),
        .s_axi_bresp   (m04_axi_bresp),
        .s_axi_bvalid  (m04_axi_bvalid),
        .s_axi_bready  (m04_axi_bready),
        .s_axi_arid    (m04_axi_arid),
        .s_axi_araddr  (m04_axi_araddr),
        .s_axi_arlen   (m04_axi_arlen),
        .s_axi_arsize  (m04_axi_arsize),
        .s_axi_arburst (m04_axi_arburst),
        .s_axi_arprot  (m04_axi_arprot),
        .s_axi_arvalid (m04_axi_arvalid),
        .s_axi_arready (m04_axi_arready),
        .s_axi_rid     (m04_axi_rid),
        .s_axi_rdata   (m04_axi_rdata),
        .s_axi_rresp   (m04_axi_rresp),
        .s_axi_rlast   (m04_axi_rlast),
        .s_axi_rvalid  (m04_axi_rvalid),
        .s_axi_rready  (m04_axi_rready),
        .reset_out     (reset_out_internal)
    );

    // Reset output to external pad
    assign reset_out = reset_out_internal;

    // ========================================================================
    // Slave 5: Recovery Policy & Event Log (Custom IP #3)
    // ========================================================================
    // Base Address: 0x0002_0500 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (POL_CTRL, WO):       [0] record_event, [1] clear_lockout (self-clearing)
    //   0x04 (POL_WINDOW, R/W):    [31:0] rolling window size in clock cycles
    //   0x08 (POL_THRESHOLD, R/W): [7:0] max recoveries per window before lockout
    //   0x0C (POL_STATUS, RO):     [0] lockout_flag, [15:8] window_recovery_count
    //   0x10 (POL_EVENT_TS, WO):   [31:0] staged timestamp written before record_event
    //   0x14 (LOG_READ_IDX, R/W):  [3:0] read index for circular log buffer (0-15)
    //   0x18 (LOG_READ_DATA, RO):  [31:0] timestamp stored at LOG_READ_IDX
    //   0x1C (LOG_COUNT, RO):      [31:0] cumulative recovery events logged
    axi_recovery_policy u_rec_policy (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awid    (m05_axi_awid),
        .s_axi_awaddr  (m05_axi_awaddr),
        .s_axi_awlen   (m05_axi_awlen),
        .s_axi_awsize  (m05_axi_awsize),
        .s_axi_awburst (m05_axi_awburst),
        .s_axi_awprot  (m05_axi_awprot),
        .s_axi_awvalid (m05_axi_awvalid),
        .s_axi_awready (m05_axi_awready),
        .s_axi_wdata   (m05_axi_wdata),
        .s_axi_wstrb   (m05_axi_wstrb),
        .s_axi_wlast   (m05_axi_wlast),
        .s_axi_wvalid  (m05_axi_wvalid),
        .s_axi_wready  (m05_axi_wready),
        .s_axi_bid     (m05_axi_bid),
        .s_axi_bresp   (m05_axi_bresp),
        .s_axi_bvalid  (m05_axi_bvalid),
        .s_axi_bready  (m05_axi_bready),
        .s_axi_arid    (m05_axi_arid),
        .s_axi_araddr  (m05_axi_araddr),
        .s_axi_arlen   (m05_axi_arlen),
        .s_axi_arsize  (m05_axi_arsize),
        .s_axi_arburst (m05_axi_arburst),
        .s_axi_arprot  (m05_axi_arprot),
        .s_axi_arvalid (m05_axi_arvalid),
        .s_axi_arready (m05_axi_arready),
        .s_axi_rid     (m05_axi_rid),
        .s_axi_rdata   (m05_axi_rdata),
        .s_axi_rresp   (m05_axi_rresp),
        .s_axi_rlast   (m05_axi_rlast),
        .s_axi_rvalid  (m05_axi_rvalid),
        .s_axi_rready  (m05_axi_rready),
        .lockout_irq   (lockout_irq)
    );

    // ========================================================================
    // Slave 6: VGA Controller (Custom IP #4, Optional)
    // ========================================================================
    // Base Address: 0x0002_0600 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (VGA_CTRL, R/W):   [0] enable (1=active, 0=off)
    //   0x04 (VGA_STATUS, RO):  [0] refresh_flag (cleared at start of frame)
    //   0x08-0x7C (VGA_BUFFER, WO): 30 words x 4 bytes = 120 ASCII chars (3 rows x 40 cols)
    axi_vga_controller u_vga (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awid    (m06_axi_awid),
        .s_axi_awaddr  (m06_axi_awaddr),
        .s_axi_awlen   (m06_axi_awlen),
        .s_axi_awsize  (m06_axi_awsize),
        .s_axi_awburst (m06_axi_awburst),
        .s_axi_awprot  (m06_axi_awprot),
        .s_axi_awvalid (m06_axi_awvalid),
        .s_axi_awready (m06_axi_awready),
        .s_axi_wdata   (m06_axi_wdata),
        .s_axi_wstrb   (m06_axi_wstrb),
        .s_axi_wlast   (m06_axi_wlast),
        .s_axi_wvalid  (m06_axi_wvalid),
        .s_axi_wready  (m06_axi_wready),
        .s_axi_bid     (m06_axi_bid),
        .s_axi_bresp   (m06_axi_bresp),
        .s_axi_bvalid  (m06_axi_bvalid),
        .s_axi_bready  (m06_axi_bready),
        .s_axi_arid    (m06_axi_arid),
        .s_axi_araddr  (m06_axi_araddr),
        .s_axi_arlen   (m06_axi_arlen),
        .s_axi_arsize  (m06_axi_arsize),
        .s_axi_arburst (m06_axi_arburst),
        .s_axi_arprot  (m06_axi_arprot),
        .s_axi_arvalid (m06_axi_arvalid),
        .s_axi_arready (m06_axi_arready),
        .s_axi_rid     (m06_axi_rid),
        .s_axi_rdata   (m06_axi_rdata),
        .s_axi_rresp   (m06_axi_rresp),
        .s_axi_rlast   (m06_axi_rlast),
        .s_axi_rvalid  (m06_axi_rvalid),
        .s_axi_rready  (m06_axi_rready),
        .vga_hsync     (vga_hsync),
        .vga_vsync     (vga_vsync),
        .vga_rgb       (vga_rgb)
    );

    // ========================================================================
    // JTAG Stub (directly connected to VeeR core when instantiated)
    // ========================================================================

    // ========================================================================
    // VeeR EL2 Core
    // ========================================================================
    el2_mem_if el2_mem_export ();
    el2_mem_if el2_icache_export ();

    wire [31:0] boot_vector = 32'h8000_0000;

    el2_veer_wrapper u_veer (
        .clk               (clk),
        .rst_l             (rst_n),              // Core warm reset
        .dbg_rst_l         (rst_n),              // Debug cold reset
        .rst_vec           (boot_vector[31:1]),  // Boot from 0x8000_0000
        .nmi_int           (1'b0),
        .nmi_vec           (31'h0),
        .jtag_id           (31'h0),
        
        // Memory export interfaces
        .el2_mem_export    (el2_mem_export),
        .el2_icache_export (el2_icache_export),
        
        // Interrupts
        .extintsrc_req     ({27'd0, lockout_irq, vblank_irq, hb_irq, uart_irq}),
        .timer_int         (1'b0),
        .soft_int          (1'b0),
        
        // IFU AXI
        .ifu_axi_awvalid   (ifu_axi_awvalid),
        .ifu_axi_awready   (ifu_axi_awready),
        .ifu_axi_awid      (ifu_axi_awid),
        .ifu_axi_awaddr    (ifu_axi_awaddr),
        .ifu_axi_awregion  (),
        .ifu_axi_awlen     (ifu_axi_awlen),
        .ifu_axi_awsize    (ifu_axi_awsize),
        .ifu_axi_awburst   (ifu_axi_awburst),
        .ifu_axi_awlock    (ifu_axi_awlock),
        .ifu_axi_awcache   (ifu_axi_awcache),
        .ifu_axi_awprot    (ifu_axi_awprot),
        .ifu_axi_awqos     (ifu_axi_awqos),
        .ifu_axi_wvalid    (ifu_axi_wvalid),
        .ifu_axi_wready    (ifu_axi_wready),
        .ifu_axi_wdata     (ifu_axi_wdata),
        .ifu_axi_wstrb     (ifu_axi_wstrb),
        .ifu_axi_wlast     (ifu_axi_wlast),
        .ifu_axi_bvalid    (ifu_axi_bvalid),
        .ifu_axi_bready    (ifu_axi_bready),
        .ifu_axi_bresp     (ifu_axi_bresp),
        .ifu_axi_bid       (ifu_axi_bid),
        .ifu_axi_arvalid   (ifu_axi_arvalid),
        .ifu_axi_arready   (ifu_axi_arready),
        .ifu_axi_arid      (ifu_axi_arid),
        .ifu_axi_araddr    (ifu_axi_araddr),
        .ifu_axi_arregion  (),
        .ifu_axi_arlen     (ifu_axi_arlen),
        .ifu_axi_arsize    (ifu_axi_arsize),
        .ifu_axi_arburst   (ifu_axi_arburst),
        .ifu_axi_arlock    (ifu_axi_arlock),
        .ifu_axi_arcache   (ifu_axi_arcache),
        .ifu_axi_arprot    (ifu_axi_arprot),
        .ifu_axi_arqos     (ifu_axi_arqos),
        .ifu_axi_rvalid    (ifu_axi_rvalid),
        .ifu_axi_rready    (ifu_axi_rready),
        .ifu_axi_rid       (ifu_axi_rid),
        .ifu_axi_rdata     (ifu_axi_rdata),
        .ifu_axi_rresp     (ifu_axi_rresp),
        .ifu_axi_rlast     (ifu_axi_rlast),
        
        // LSU AXI
        .lsu_axi_awvalid   (lsu_axi_awvalid),
        .lsu_axi_awready   (lsu_axi_awready),
        .lsu_axi_awid      (lsu_axi_awid),
        .lsu_axi_awaddr    (lsu_axi_awaddr),
        .lsu_axi_awregion  (),
        .lsu_axi_awlen     (lsu_axi_awlen),
        .lsu_axi_awsize    (lsu_axi_awsize),
        .lsu_axi_awburst   (lsu_axi_awburst),
        .lsu_axi_awlock    (lsu_axi_awlock),
        .lsu_axi_awcache   (lsu_axi_awcache),
        .lsu_axi_awprot    (lsu_axi_awprot),
        .lsu_axi_awqos     (lsu_axi_awqos),
        .lsu_axi_wvalid    (lsu_axi_wvalid),
        .lsu_axi_wready    (lsu_axi_wready),
        .lsu_axi_wdata     (lsu_axi_wdata),
        .lsu_axi_wstrb     (lsu_axi_wstrb),
        .lsu_axi_wlast     (lsu_axi_wlast),
        .lsu_axi_bvalid    (lsu_axi_bvalid),
        .lsu_axi_bready    (lsu_axi_bready),
        .lsu_axi_bresp     (lsu_axi_bresp),
        .lsu_axi_bid       (lsu_axi_bid),
        .lsu_axi_arvalid   (lsu_axi_arvalid),
        .lsu_axi_arready   (lsu_axi_arready),
        .lsu_axi_arid      (lsu_axi_arid),
        .lsu_axi_araddr    (lsu_axi_araddr),
        .lsu_axi_arregion  (),
        .lsu_axi_arlen     (lsu_axi_arlen),
        .lsu_axi_arsize    (lsu_axi_arsize),
        .lsu_axi_arburst   (lsu_axi_arburst),
        .lsu_axi_arlock    (lsu_axi_arlock),
        .lsu_axi_arcache   (lsu_axi_arcache),
        .lsu_axi_arprot    (lsu_axi_arprot),
        .lsu_axi_arqos     (lsu_axi_arqos),
        .lsu_axi_rvalid    (lsu_axi_rvalid),
        .lsu_axi_rready    (lsu_axi_rready),
        .lsu_axi_rid       (lsu_axi_rid),
        .lsu_axi_rdata     (lsu_axi_rdata),
        .lsu_axi_rresp     (lsu_axi_rresp),
        .lsu_axi_rlast     (lsu_axi_rlast),

        // SB AXI
        .sb_axi_awvalid    (sb_axi_awvalid),
        .sb_axi_awready    (sb_axi_awready),
        .sb_axi_awid       (sb_axi_awid),
        .sb_axi_awaddr     (sb_axi_awaddr),
        .sb_axi_awregion   (),
        .sb_axi_awlen      (sb_axi_awlen),
        .sb_axi_awsize     (sb_axi_awsize),
        .sb_axi_awburst    (sb_axi_awburst),
        .sb_axi_awlock     (sb_axi_awlock),
        .sb_axi_awcache    (sb_axi_awcache),
        .sb_axi_awprot     (sb_axi_awprot),
        .sb_axi_awqos      (sb_axi_awqos),
        .sb_axi_wvalid     (sb_axi_wvalid),
        .sb_axi_wready     (sb_axi_wready),
        .sb_axi_wdata      (sb_axi_wdata),
        .sb_axi_wstrb      (sb_axi_wstrb),
        .sb_axi_wlast      (sb_axi_wlast),
        .sb_axi_bvalid     (sb_axi_bvalid),
        .sb_axi_bready     (sb_axi_bready),
        .sb_axi_bresp      (sb_axi_bresp),
        .sb_axi_bid        (sb_axi_bid),
        .sb_axi_arvalid    (sb_axi_arvalid),
        .sb_axi_arready    (sb_axi_arready),
        .sb_axi_arid       (sb_axi_arid),
        .sb_axi_araddr     (sb_axi_araddr),
        .sb_axi_arregion   (),
        .sb_axi_arlen      (sb_axi_arlen),
        .sb_axi_arsize     (sb_axi_arsize),
        .sb_axi_arburst    (sb_axi_arburst),
        .sb_axi_arlock     (sb_axi_arlock),
        .sb_axi_arcache    (sb_axi_arcache),
        .sb_axi_arprot     (sb_axi_arprot),
        .sb_axi_arqos      (sb_axi_arqos),
        .sb_axi_rvalid     (sb_axi_rvalid),
        .sb_axi_rready     (sb_axi_rready),
        .sb_axi_rid        (sb_axi_rid),
        .sb_axi_rdata      (sb_axi_rdata),
        .sb_axi_rresp      (sb_axi_rresp),
        .sb_axi_rlast      (sb_axi_rlast),
        
        // DMA AXI (Tie off slave ports)
        .dma_axi_awvalid   (1'b0),
        .dma_axi_awready   (),
        .dma_axi_awid      (8'd0),
        .dma_axi_awaddr    (32'd0),
        .dma_axi_awsize    (3'd0),
        .dma_axi_awprot    (3'd0),
        .dma_axi_awlen     (8'd0),
        .dma_axi_awburst   (2'd0),
        .dma_axi_wvalid    (1'b0),
        .dma_axi_wready    (),
        .dma_axi_wdata     (64'd0),
        .dma_axi_wstrb     (8'd0),
        .dma_axi_wlast     (1'b0),
        .dma_axi_bvalid    (),
        .dma_axi_bready    (1'b1),
        .dma_axi_bresp     (),
        .dma_axi_bid       (),
        .dma_axi_arvalid   (1'b0),
        .dma_axi_arready   (),
        .dma_axi_arid      (8'd0),
        .dma_axi_araddr    (32'd0),
        .dma_axi_arsize    (3'd0),
        .dma_axi_arprot    (3'd0),
        .dma_axi_arlen     (8'd0),
        .dma_axi_arburst   (2'd0),
        .dma_axi_rvalid    (),
        .dma_axi_rready    (1'b1),
        .dma_axi_rid       (),
        .dma_axi_rdata     (),
        .dma_axi_rresp     (),
        .dma_axi_rlast     (),
        
        // JTAG
        .jtag_tck          (jtag_tck),
        .jtag_tms          (jtag_tms),
        .jtag_tdi          (jtag_tdi),
        .jtag_tdo          (jtag_tdo),
        .jtag_tdoEn        (),
        .jtag_trst_n       (rst_n),
        
        // Trace / Core status
        .trace_rv_i_insn_ip      (),
        .trace_rv_i_address_ip   (),
        .trace_rv_i_valid_ip     (),
        .trace_rv_i_exception_ip (),
        .trace_rv_i_ecause_ip    (),
        .trace_rv_i_interrupt_ip (),
        .trace_rv_i_tval_ip      (),
        .dec_tlu_perfcnt0        (),
        .dec_tlu_perfcnt1        (),
        .dec_tlu_perfcnt2        (),
        .lsu_bus_clk_en          (1'b1),
        .ifu_bus_clk_en          (1'b1),
        .dbg_bus_clk_en          (1'b1),
        .dma_bus_clk_en          (1'b1),
        .core_id                 (28'd0),
        .mpc_debug_halt_req      (1'b0),
        .mpc_debug_halt_ack      (),
        .mpc_debug_run_req       (1'b0),
        .mpc_debug_run_ack       (),
        .mpc_reset_run_req       (1'b1),
        .debug_brkpt_status      (),
        .i_cpu_halt_req          (1'b0),
        .o_cpu_halt_ack          (),
        .o_cpu_halt_status       (),
        .o_debug_mode_status     (),
        .i_cpu_run_req           (1'b0),
        .o_cpu_run_ack           (),
        .scan_mode               (1'b0),
        .mbist_mode              (1'b0),
        .dmi_core_enable         (1'b1),
        .dmi_uncore_enable       (1'b0),
        .dmi_uncore_en           (),
        .dmi_uncore_wr_en        (),
        .dmi_uncore_addr         (),
        .dmi_uncore_wdata        (),
        .dmi_uncore_rdata        (32'd0),
        .dmi_active              (),
        .iccm_ecc_single_error   (),
        .iccm_ecc_double_error   (),
        .dccm_ecc_single_error   (),
        .dccm_ecc_double_error   (),
        .dccm_write_readback_error()
    );

    // ========================================================================
    // VeeR EL2 DCCM SRAM (4 Banks x 4096 x 39 bits = 64 KB with ECC)
    // ========================================================================
    wire [3:0][38:0] dccm_bank_fdout;
    for (genvar b = 0; b < 4; b = b + 1) begin : gen_dccm_banks
        assign el2_mem_export.dccm_bank_dout[b] = dccm_bank_fdout[b][31:0];
        assign el2_mem_export.dccm_bank_ecc[b]  = dccm_bank_fdout[b][38:32];

        ram_4096x39 u_dccm_bank (
            .CLK      (clk),
            .ME       (el2_mem_export.dccm_clken[b]),
            .WE       (el2_mem_export.dccm_wren_bank[b]),
            .ADR      (el2_mem_export.dccm_addr_bank[b]),
            .D        ({el2_mem_export.dccm_wr_ecc_bank[b], el2_mem_export.dccm_wr_data_bank[b]}),
            .Q        (dccm_bank_fdout[b]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );
    end

    // Tie off unused ICCM export interface
    for (genvar b = 0; b < 4; b = b + 1) begin : gen_iccm_tieoff
        assign el2_mem_export.iccm_bank_dout[b] = 32'd0;
        assign el2_mem_export.iccm_bank_ecc[b]  = 7'd0;
    end

    // Tie off unused ICACHE export interface
    assign el2_icache_export.ic_tag_data_raw_packed_pre = '0;
    assign el2_icache_export.wb_packeddout_pre = '0;
    assign el2_icache_export.ic_tag_data_raw_pre = '0;
    assign el2_icache_export.wb_dout_pre_up = '0;

    // ========================================================================
    // Slave 7: External AXI ROM
    // ========================================================================
    axi_rom u_rom (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_arid    (m07_axi_arid),
        .s_axi_araddr  (m07_axi_araddr),
        .s_axi_arlen   (m07_axi_arlen),
        .s_axi_arsize  (m07_axi_arsize),
        .s_axi_arburst (m07_axi_arburst),
        .s_axi_arvalid (m07_axi_arvalid),
        .s_axi_arready (m07_axi_arready),
        .s_axi_rid     (m07_axi_rid),
        .s_axi_rdata   (m07_axi_rdata),
        .s_axi_rresp   (m07_axi_rresp),
        .s_axi_rlast   (m07_axi_rlast),
        .s_axi_rvalid  (m07_axi_rvalid),
        .s_axi_rready  (m07_axi_rready),
        .s_axi_awid    (m07_axi_awid),
        .s_axi_awaddr  (m07_axi_awaddr),
        .s_axi_awlen   (m07_axi_awlen),
        .s_axi_awsize  (m07_axi_awsize),
        .s_axi_awburst (m07_axi_awburst),
        .s_axi_awvalid (m07_axi_awvalid),
        .s_axi_awready (m07_axi_awready),
        .s_axi_wdata   (m07_axi_wdata),
        .s_axi_wstrb   (m07_axi_wstrb),
        .s_axi_wlast   (m07_axi_wlast),
        .s_axi_wvalid  (m07_axi_wvalid),
        .s_axi_wready  (m07_axi_wready),
        .s_axi_bid     (m07_axi_bid),
        .s_axi_bresp   (m07_axi_bresp),
        .s_axi_bvalid  (m07_axi_bvalid),
        .s_axi_bready  (m07_axi_bready)
    );

endmodule
