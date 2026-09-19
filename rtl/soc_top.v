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

    // ---- AXI4 Interconnect Master Output (M00 → Bridge) ----
    wire [8:0]  m_axi_awid;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awlock;
    wire [3:0]  m_axi_awcache;
    wire [2:0]  m_axi_awprot;
    wire [3:0]  m_axi_awqos;
    wire [3:0]  m_axi_awregion;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [63:0] m_axi_wdata;
    wire [7:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [8:0]  m_axi_bid;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [8:0]  m_axi_arid;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arlock;
    wire [3:0]  m_axi_arcache;
    wire [2:0]  m_axi_arprot;
    wire [3:0]  m_axi_arqos;
    wire [3:0]  m_axi_arregion;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [8:0]  m_axi_rid;
    wire [63:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // ---- Wishbone master bus (bridge → interconnect) ----
    wire [31:0] wbm_adr;
    wire [31:0] wbm_dat_m2s;   // Master to slave (write data)
    wire [31:0] wbm_dat_s2m;   // Slave to master (read data)
    wire        wbm_we;
    wire [3:0]  wbm_sel;
    wire        wbm_stb;
    wire        wbm_cyc;
    wire        wbm_ack;
    wire        wbm_err;

    // ---- Wishbone slave interfaces (interconnect → peripherals) ----
    // Slave 0: UART
    wire [7:0]  wbs0_adr;
    wire [31:0] wbs0_dat_o, wbs0_dat_i;
    wire        wbs0_we, wbs0_stb, wbs0_cyc, wbs0_ack;
    wire [3:0]  wbs0_sel;
    // Slave 1: Timer
    wire [7:0]  wbs1_adr;
    wire [31:0] wbs1_dat_o, wbs1_dat_i;
    wire        wbs1_we, wbs1_stb, wbs1_cyc, wbs1_ack;
    wire [3:0]  wbs1_sel;
    // Slave 2: GPIO
    wire [7:0]  wbs2_adr;
    wire [31:0] wbs2_dat_o, wbs2_dat_i;
    wire        wbs2_we, wbs2_stb, wbs2_cyc, wbs2_ack;
    wire [3:0]  wbs2_sel;
    // Slave 3: Heartbeat Monitor
    wire [7:0]  wbs3_adr;
    wire [31:0] wbs3_dat_o, wbs3_dat_i;
    wire        wbs3_we, wbs3_stb, wbs3_cyc, wbs3_ack;
    wire [3:0]  wbs3_sel;
    // Slave 4: Reset Sequencer
    wire [7:0]  wbs4_adr;
    wire [31:0] wbs4_dat_o, wbs4_dat_i;
    wire        wbs4_we, wbs4_stb, wbs4_cyc, wbs4_ack;
    wire [3:0]  wbs4_sel;
    // Slave 5: Recovery Policy
    wire [7:0]  wbs5_adr;
    wire [31:0] wbs5_dat_o, wbs5_dat_i;
    wire        wbs5_we, wbs5_stb, wbs5_cyc, wbs5_ack;
    wire [3:0]  wbs5_sel;
    // Slave 6: VGA Controller
    wire [7:0]  wbs6_adr;
    wire [31:0] wbs6_dat_o, wbs6_dat_i;
    wire        wbs6_we, wbs6_stb, wbs6_cyc, wbs6_ack;
    wire [3:0]  wbs6_sel;

    // ---- Point-to-point inter-IP signals ----
    wire        hb_irq;            // Heartbeat Monitor → PIC
    wire        reset_out_internal; // Reset Sequencer → GPIO output

    // ========================================================================
    // VeeR EL2 Core Instance (Placeholder / Interface Hook)
    // ========================================================================
    // In full SoC integration, u_veer connects to lsu_axi_* and sb_axi_*.
    // Tying off master request signals when core is uninstantiated:
    assign lsu_axi_awid    = 8'h0;
    assign lsu_axi_awaddr  = 32'h0;
    assign lsu_axi_awlen   = 8'h0;
    assign lsu_axi_awsize  = 3'h2;
    assign lsu_axi_awburst = 2'h1;
    assign lsu_axi_awlock  = 1'b0;
    assign lsu_axi_awcache = 4'h0;
    assign lsu_axi_awprot  = 3'h0;
    assign lsu_axi_awqos   = 4'h0;
    assign lsu_axi_awvalid = 1'b0;
    assign lsu_axi_wdata   = 64'h0;
    assign lsu_axi_wstrb   = 8'h0;
    assign lsu_axi_wlast   = 1'b0;
    assign lsu_axi_wvalid  = 1'b0;
    assign lsu_axi_bready  = 1'b0;
    assign lsu_axi_arid    = 8'h0;
    assign lsu_axi_araddr  = 32'h0;
    assign lsu_axi_arlen   = 8'h0;
    assign lsu_axi_arsize  = 3'h2;
    assign lsu_axi_arburst = 2'h1;
    assign lsu_axi_arlock  = 1'b0;
    assign lsu_axi_arcache = 4'h0;
    assign lsu_axi_arprot  = 3'h0;
    assign lsu_axi_arqos   = 4'h0;
    assign lsu_axi_arvalid = 1'b0;
    assign lsu_axi_rready  = 1'b0;

    assign sb_axi_awid     = 8'h0;
    assign sb_axi_awaddr   = 32'h0;
    assign sb_axi_awlen    = 8'h0;
    assign sb_axi_awsize   = 3'h2;
    assign sb_axi_awburst  = 2'h1;
    assign sb_axi_awlock   = 1'b0;
    assign sb_axi_awcache  = 4'h0;
    assign sb_axi_awprot   = 3'h0;
    assign sb_axi_awqos    = 4'h0;
    assign sb_axi_awvalid  = 1'b0;
    assign sb_axi_wdata    = 64'h0;
    assign sb_axi_wstrb    = 8'h0;
    assign sb_axi_wlast    = 1'b0;
    assign sb_axi_wvalid   = 1'b0;
    assign sb_axi_bready   = 1'b0;
    assign sb_axi_arid     = 8'h0;
    assign sb_axi_araddr   = 32'h0;
    assign sb_axi_arlen    = 8'h0;
    assign sb_axi_arsize   = 3'h2;
    assign sb_axi_arburst  = 2'h1;
    assign sb_axi_arlock   = 1'b0;
    assign sb_axi_arcache  = 4'h0;
    assign sb_axi_arprot   = 3'h0;
    assign sb_axi_arqos    = 4'h0;
    assign sb_axi_arvalid  = 1'b0;
    assign sb_axi_rready   = 1'b0;

    // ========================================================================
    // AXI4 Interconnect (2 Masters x 1 Slave)
    // ========================================================================
    axi_interconnect #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (32),
        .S_ID_WIDTH (8),
        .M_ID_WIDTH (9)
    ) u_axi_intercon (
        .clk             (clk),
        .rst_n           (rst_n),

        // Master 0 Interface (S00) — VeeR LSU
        .s00_axi_awid    (lsu_axi_awid),
        .s00_axi_awaddr  (lsu_axi_awaddr),
        .s00_axi_awlen   (lsu_axi_awlen),
        .s00_axi_awsize  (lsu_axi_awsize),
        .s00_axi_awburst (lsu_axi_awburst),
        .s00_axi_awlock  (lsu_axi_awlock),
        .s00_axi_awcache (lsu_axi_awcache),
        .s00_axi_awprot  (lsu_axi_awprot),
        .s00_axi_awqos   (lsu_axi_awqos),
        .s00_axi_awvalid (lsu_axi_awvalid),
        .s00_axi_awready (lsu_axi_awready),
        .s00_axi_wdata   (lsu_axi_wdata),
        .s00_axi_wstrb   (lsu_axi_wstrb),
        .s00_axi_wlast   (lsu_axi_wlast),
        .s00_axi_wvalid  (lsu_axi_wvalid),
        .s00_axi_wready  (lsu_axi_wready),
        .s00_axi_bid     (lsu_axi_bid),
        .s00_axi_bresp   (lsu_axi_bresp),
        .s00_axi_bvalid  (lsu_axi_bvalid),
        .s00_axi_bready  (lsu_axi_bready),
        .s00_axi_arid    (lsu_axi_arid),
        .s00_axi_araddr  (lsu_axi_araddr),
        .s00_axi_arlen   (lsu_axi_arlen),
        .s00_axi_arsize  (lsu_axi_arsize),
        .s00_axi_arburst (lsu_axi_arburst),
        .s00_axi_arlock  (lsu_axi_arlock),
        .s00_axi_arcache (lsu_axi_arcache),
        .s00_axi_arprot  (lsu_axi_arprot),
        .s00_axi_arqos   (lsu_axi_arqos),
        .s00_axi_arvalid (lsu_axi_arvalid),
        .s00_axi_arready (lsu_axi_arready),
        .s00_axi_rid     (lsu_axi_rid),
        .s00_axi_rdata   (lsu_axi_rdata),
        .s00_axi_rresp   (lsu_axi_rresp),
        .s00_axi_rlast   (lsu_axi_rlast),
        .s00_axi_rvalid  (lsu_axi_rvalid),
        .s00_axi_rready  (lsu_axi_rready),

        // Master 1 Interface (S01) — VeeR SB / Debug
        .s01_axi_awid    (sb_axi_awid),
        .s01_axi_awaddr  (sb_axi_awaddr),
        .s01_axi_awlen   (sb_axi_awlen),
        .s01_axi_awsize  (sb_axi_awsize),
        .s01_axi_awburst (sb_axi_awburst),
        .s01_axi_awlock  (sb_axi_awlock),
        .s01_axi_awcache (sb_axi_awcache),
        .s01_axi_awprot  (sb_axi_awprot),
        .s01_axi_awqos   (sb_axi_awqos),
        .s01_axi_awvalid (sb_axi_awvalid),
        .s01_axi_awready (sb_axi_awready),
        .s01_axi_wdata   (sb_axi_wdata),
        .s01_axi_wstrb   (sb_axi_wstrb),
        .s01_axi_wlast   (sb_axi_wlast),
        .s01_axi_wvalid  (sb_axi_wvalid),
        .s01_axi_wready  (sb_axi_wready),
        .s01_axi_bid     (sb_axi_bid),
        .s01_axi_bresp   (sb_axi_bresp),
        .s01_axi_bvalid  (sb_axi_bvalid),
        .s01_axi_bready  (sb_axi_bready),
        .s01_axi_arid    (sb_axi_arid),
        .s01_axi_araddr  (sb_axi_araddr),
        .s01_axi_arlen   (sb_axi_arlen),
        .s01_axi_arsize  (sb_axi_arsize),
        .s01_axi_arburst (sb_axi_arburst),
        .s01_axi_arlock  (sb_axi_arlock),
        .s01_axi_arcache (sb_axi_arcache),
        .s01_axi_arprot  (sb_axi_arprot),
        .s01_axi_arqos   (sb_axi_arqos),
        .s01_axi_arvalid (sb_axi_arvalid),
        .s01_axi_arready (sb_axi_arready),
        .s01_axi_rid     (sb_axi_rid),
        .s01_axi_rdata   (sb_axi_rdata),
        .s01_axi_rresp   (sb_axi_rresp),
        .s01_axi_rlast   (sb_axi_rlast),
        .s01_axi_rvalid  (sb_axi_rvalid),
        .s01_axi_rready  (sb_axi_rready),

        // Slave 0 Interface (M00) — to AXI-to-WB Bridge
        .m00_axi_awid    (m_axi_awid),
        .m00_axi_awaddr  (m_axi_awaddr),
        .m00_axi_awlen   (m_axi_awlen),
        .m00_axi_awsize  (m_axi_awsize),
        .m00_axi_awburst (m_axi_awburst),
        .m00_axi_awlock  (m_axi_awlock),
        .m00_axi_awcache (m_axi_awcache),
        .m00_axi_awprot  (m_axi_awprot),
        .m00_axi_awqos   (m_axi_awqos),
        .m00_axi_awregion(m_axi_awregion),
        .m00_axi_awvalid (m_axi_awvalid),
        .m00_axi_awready (m_axi_awready),
        .m00_axi_wdata   (m_axi_wdata),
        .m00_axi_wstrb   (m_axi_wstrb),
        .m00_axi_wlast   (m_axi_wlast),
        .m00_axi_wvalid  (m_axi_wvalid),
        .m00_axi_wready  (m_axi_wready),
        .m00_axi_bid     (m_axi_bid),
        .m00_axi_bresp   (m_axi_bresp),
        .m00_axi_bvalid  (m_axi_bvalid),
        .m00_axi_bready  (m_axi_bready),
        .m00_axi_arid    (m_axi_arid),
        .m00_axi_araddr  (m_axi_araddr),
        .m00_axi_arlen   (m_axi_arlen),
        .m00_axi_arsize  (m_axi_arsize),
        .m00_axi_arburst (m_axi_arburst),
        .m00_axi_arlock  (m_axi_arlock),
        .m00_axi_arcache (m_axi_arcache),
        .m00_axi_arprot  (m_axi_arprot),
        .m00_axi_arqos   (m_axi_arqos),
        .m00_axi_arregion(m_axi_arregion),
        .m00_axi_arvalid (m_axi_arvalid),
        .m00_axi_arready (m_axi_arready),
        .m00_axi_rid     (m_axi_rid),
        .m00_axi_rdata   (m_axi_rdata),
        .m00_axi_rresp   (m_axi_rresp),
        .m00_axi_rlast   (m_axi_rlast),
        .m00_axi_rvalid  (m_axi_rvalid),
        .m00_axi_rready  (m_axi_rready)
    );

    // ========================================================================
    // AXI4 to Wishbone Bridge
    // ========================================================================
    axi4_to_wb_bridge #(
        .AXI_ADDR_WIDTH (32),
        .AXI_DATA_WIDTH (64),
        .AXI_ID_WIDTH   (9),
        .WB_ADDR_WIDTH  (32),
        .WB_DATA_WIDTH  (32)
    ) u_axi2wb (
        .clk            (clk),
        .rst_n          (rst_n),

        // AXI4 slave interface (driven by interconnect M00)
        .s_axi_awid     (m_axi_awid),
        .s_axi_awaddr   (m_axi_awaddr),
        .s_axi_awlen    (m_axi_awlen),
        .s_axi_awsize   (m_axi_awsize),
        .s_axi_awburst  (m_axi_awburst),
        .s_axi_awprot   (m_axi_awprot),
        .s_axi_awvalid  (m_axi_awvalid),
        .s_axi_awready  (m_axi_awready),
        .s_axi_wdata    (m_axi_wdata),
        .s_axi_wstrb    (m_axi_wstrb),
        .s_axi_wlast    (m_axi_wlast),
        .s_axi_wvalid   (m_axi_wvalid),
        .s_axi_wready   (m_axi_wready),
        .s_axi_bid      (m_axi_bid),
        .s_axi_bresp    (m_axi_bresp),
        .s_axi_bvalid   (m_axi_bvalid),
        .s_axi_bready   (m_axi_bready),
        .s_axi_arid     (m_axi_arid),
        .s_axi_araddr   (m_axi_araddr),
        .s_axi_arlen    (m_axi_arlen),
        .s_axi_arsize   (m_axi_arsize),
        .s_axi_arburst  (m_axi_arburst),
        .s_axi_arprot   (m_axi_arprot),
        .s_axi_arvalid  (m_axi_arvalid),
        .s_axi_arready  (m_axi_arready),
        .s_axi_rid      (m_axi_rid),
        .s_axi_rdata    (m_axi_rdata),
        .s_axi_rresp    (m_axi_rresp),
        .s_axi_rlast    (m_axi_rlast),
        .s_axi_rvalid   (m_axi_rvalid),
        .s_axi_rready   (m_axi_rready),

        // Wishbone master (to interconnect)
        .wb_adr_o       (wbm_adr),
        .wb_dat_o       (wbm_dat_m2s),
        .wb_dat_i       (wbm_dat_s2m),
        .wb_we_o        (wbm_we),
        .wb_sel_o       (wbm_sel),
        .wb_stb_o       (wbm_stb),
        .wb_cyc_o       (wbm_cyc),
        .wb_ack_i       (wbm_ack),
        .wb_err_i       (wbm_err)
    );

    // ========================================================================
    // Wishbone Interconnect (1 master → 7 slaves)
    // ========================================================================
    wb_interconnect u_wb_intercon (
        // Master side
        .wbm_adr_i      (wbm_adr),
        .wbm_dat_i      (wbm_dat_m2s),
        .wbm_dat_o      (wbm_dat_s2m),
        .wbm_we_i       (wbm_we),
        .wbm_sel_i      (wbm_sel),
        .wbm_stb_i      (wbm_stb),
        .wbm_cyc_i      (wbm_cyc),
        .wbm_ack_o      (wbm_ack),
        .wbm_err_o      (wbm_err),

        // Slave 0: UART
        .wbs0_adr_o     (wbs0_adr),
        .wbs0_dat_o     (wbs0_dat_o),
        .wbs0_dat_i     (wbs0_dat_i),
        .wbs0_we_o      (wbs0_we),
        .wbs0_sel_o     (wbs0_sel),
        .wbs0_stb_o     (wbs0_stb),
        .wbs0_cyc_o     (wbs0_cyc),
        .wbs0_ack_i     (wbs0_ack),

        // Slave 1: Timer
        .wbs1_adr_o     (wbs1_adr),
        .wbs1_dat_o     (wbs1_dat_o),
        .wbs1_dat_i     (wbs1_dat_i),
        .wbs1_we_o      (wbs1_we),
        .wbs1_sel_o     (wbs1_sel),
        .wbs1_stb_o     (wbs1_stb),
        .wbs1_cyc_o     (wbs1_cyc),
        .wbs1_ack_i     (wbs1_ack),

        // Slave 2: GPIO
        .wbs2_adr_o     (wbs2_adr),
        .wbs2_dat_o     (wbs2_dat_o),
        .wbs2_dat_i     (wbs2_dat_i),
        .wbs2_we_o      (wbs2_we),
        .wbs2_sel_o     (wbs2_sel),
        .wbs2_stb_o     (wbs2_stb),
        .wbs2_cyc_o     (wbs2_cyc),
        .wbs2_ack_i     (wbs2_ack),

        // Slave 3: Heartbeat Monitor
        .wbs3_adr_o     (wbs3_adr),
        .wbs3_dat_o     (wbs3_dat_o),
        .wbs3_dat_i     (wbs3_dat_i),
        .wbs3_we_o      (wbs3_we),
        .wbs3_sel_o     (wbs3_sel),
        .wbs3_stb_o     (wbs3_stb),
        .wbs3_cyc_o     (wbs3_cyc),
        .wbs3_ack_i     (wbs3_ack),

        // Slave 4: Reset Sequencer
        .wbs4_adr_o     (wbs4_adr),
        .wbs4_dat_o     (wbs4_dat_o),
        .wbs4_dat_i     (wbs4_dat_i),
        .wbs4_we_o      (wbs4_we),
        .wbs4_sel_o     (wbs4_sel),
        .wbs4_stb_o     (wbs4_stb),
        .wbs4_cyc_o     (wbs4_cyc),
        .wbs4_ack_i     (wbs4_ack),

        // Slave 5: Recovery Policy
        .wbs5_adr_o     (wbs5_adr),
        .wbs5_dat_o     (wbs5_dat_o),
        .wbs5_dat_i     (wbs5_dat_i),
        .wbs5_we_o      (wbs5_we),
        .wbs5_sel_o     (wbs5_sel),
        .wbs5_stb_o     (wbs5_stb),
        .wbs5_cyc_o     (wbs5_cyc),
        .wbs5_ack_i     (wbs5_ack),

        // Slave 6: VGA Controller
        .wbs6_adr_o     (wbs6_adr),
        .wbs6_dat_o     (wbs6_dat_o),
        .wbs6_dat_i     (wbs6_dat_i),
        .wbs6_we_o      (wbs6_we),
        .wbs6_sel_o     (wbs6_sel),
        .wbs6_stb_o     (wbs6_stb),
        .wbs6_cyc_o     (wbs6_cyc),
        .wbs6_ack_i     (wbs6_ack)
    );

    // ========================================================================
    // Slave 0: UART Peripheral (Pre-built)
    // ========================================================================
    // Base Address: 0x0002_0000 | Offset Range: 0x00 - 0xFF
    // Standard 16550 registers (when full IP is attached):
    //   0x00: RBR (RO) / THR (WO), 0x04: IER (RW), 0x08: IIR (RO) / FCR (WO),
    //   0x0C: LCR (RW), 0x10: MCR (RW), 0x14: LSR (RO), 0x18: MSR (RO), 0x1C: SCR (RW)
    // Currently stubbed with default read response (0x0) and 1-cycle ACK.
    assign wbs0_dat_i = 32'd0;
    assign wbs0_ack   = wbs0_stb & wbs0_cyc;

    // UART TX/RX external connections
    // assign uart_tx = uart_core_tx;
    assign uart_tx = 1'b1;  // Idle high (stub)

    // ========================================================================
    // Slave 1: Timer Peripheral (Pre-built)
    // ========================================================================
    // Base Address: 0x0002_0100 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (TMR_CTR, RO): [31:0] timer_counter (free-running 32-bit tick counter)
    // Used by firmware for event timestamps and system uptime measurement.
    reg [31:0] timer_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timer_counter <= 32'd0;
        else
            timer_counter <= timer_counter + 32'd1;
    end

    // Timer stub: reads return counter value
    assign wbs1_dat_i = timer_counter;
    assign wbs1_ack   = wbs1_stb & wbs1_cyc;

    // ========================================================================
    // Slave 2: GPIO Peripheral (Pre-built)
    // ========================================================================
    // Base Address: 0x0002_0200 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (GPIO_STAT, RO):
    //     Bit [0]: heartbeat_in live pin level
    //     Bit [1]: reset_out_internal (current reset drive level)
    //     Bits [31:2]: Reserved (0)
    assign wbs2_dat_i = {30'd0, reset_out_internal, heartbeat_in};
    assign wbs2_ack   = wbs2_stb & wbs2_cyc;

    // ========================================================================
    // Slave 3: Heartbeat Monitor (Custom IP #1)
    // ========================================================================
    // Base Address: 0x0002_0300 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (HB_CTRL, R/W):       [0] enable, [1] clear_flag (self-clearing)
    //   0x04 (HB_THRESHOLD, R/W):  [31:0] max cycles before timeout
    //   0x08 (HB_STATUS, RO):      [0] unresponsive (sticky), [1] heartbeat_in live
    //   0x0C (HB_ELAPSED, RO):     [31:0] cycles since last heartbeat rising edge
    heartbeat_monitor u_heartbeat (
        .wb_clk_i     (clk),
        .wb_rst_i     (rst),
        .wb_adr_i     (wbs3_adr),
        .wb_dat_i     (wbs3_dat_o),    // Interconnect dat_o → slave dat_i
        .wb_dat_o     (wbs3_dat_i),    // Slave dat_o → interconnect dat_i
        .wb_we_i      (wbs3_we),
        .wb_sel_i     (wbs3_sel),
        .wb_stb_i     (wbs3_stb),
        .wb_cyc_i     (wbs3_cyc),
        .wb_ack_o     (wbs3_ack),
        .heartbeat_in (heartbeat_in),  // Direct wire from external pad
        .hb_irq       (hb_irq)
    );

    // ========================================================================
    // Slave 4: Power/Reset Sequencer (Custom IP #2)
    // ========================================================================
    // Base Address: 0x0002_0400 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (RST_CTRL, WO):        [0] trigger (self-clearing)
    //   0x04 (RST_HOLD_CYCLES, R/W):[31:0] reset pulse duration in clock cycles
    //   0x08 (RST_STATUS, RO):      [0] in_progress, [1] complete (sticky)
    reset_sequencer u_reset_seq (
        .wb_clk_i     (clk),
        .wb_rst_i     (rst),
        .wb_adr_i     (wbs4_adr),
        .wb_dat_i     (wbs4_dat_o),
        .wb_dat_o     (wbs4_dat_i),
        .wb_we_i      (wbs4_we),
        .wb_sel_i     (wbs4_sel),
        .wb_stb_i     (wbs4_stb),
        .wb_cyc_i     (wbs4_cyc),
        .wb_ack_o     (wbs4_ack),
        .reset_out    (reset_out_internal)
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
    recovery_policy u_rec_policy (
        .wb_clk_i     (clk),
        .wb_rst_i     (rst),
        .wb_adr_i     (wbs5_adr),
        .wb_dat_i     (wbs5_dat_o),
        .wb_dat_o     (wbs5_dat_i),
        .wb_we_i      (wbs5_we),
        .wb_sel_i     (wbs5_sel),
        .wb_stb_i     (wbs5_stb),
        .wb_cyc_i     (wbs5_cyc),
        .wb_ack_o     (wbs5_ack)
    );

    // ========================================================================
    // Slave 6: VGA Controller (Custom IP #4, Optional)
    // ========================================================================
    // Base Address: 0x0002_0600 | Offset Range: 0x00 - 0xFF
    // Registers:
    //   0x00 (VGA_CTRL, R/W):   [0] enable (1=active, 0=off)
    //   0x04 (VGA_STATUS, RO):  [0] refresh_flag (cleared at start of frame)
    //   0x08-0x7C (VGA_BUFFER, WO): 30 words x 4 bytes = 120 ASCII chars (3 rows x 40 cols)
    vga_controller u_vga (
        .wb_clk_i     (clk),
        .wb_rst_i     (rst),
        .wb_adr_i     (wbs6_adr),
        .wb_dat_i     (wbs6_dat_o),
        .wb_dat_o     (wbs6_dat_i),
        .wb_we_i      (wbs6_we),
        .wb_sel_i     (wbs6_sel),
        .wb_stb_i     (wbs6_stb),
        .wb_cyc_i     (wbs6_cyc),
        .wb_ack_o     (wbs6_ack),
        .vga_hsync    (vga_hsync),
        .vga_vsync    (vga_vsync),
        .vga_rgb      (vga_rgb)
    );

    // ========================================================================
    // JTAG Stub (directly connected to VeeR core when instantiated)
    // ========================================================================
    assign jtag_tdo = 1'b0;  // Stub — replaced by core connection

endmodule
