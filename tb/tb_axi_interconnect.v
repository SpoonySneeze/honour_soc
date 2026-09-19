// ============================================================================
// Testbench — AXI4 Interconnect Verification
// ============================================================================
// Verifies the AXI4 Interconnect (2 Masters x 1 Slave) in the BMC SoC:
//   - Master 0 (S00): VeeR EL2 Load/Store Unit (LSU)
//   - Master 1 (S01): VeeR EL2 System Bus / JTAG Debug (SB)
//   - Slave 0  (M00): AXI4-to-Wishbone Bridge -> Wishbone Interconnect -> Peripherals
//
// Test Coverage:
//   1. Master 0 Single-Beat Write & Read with ID tracking (HB Monitor)
//   2. Master 1 Single-Beat Write & Read with ID tracking (Reset Sequencer)
//   3. 64-bit to 32-bit Address/Data Steering (addr[2] = 0 vs addr[2] = 1)
//   4. Read Data Word Replication across 64-bit lanes
//   5. Simultaneous / Concurrent Master 0 and Master 1 Requests (Arbitration)
//   6. Unmapped Address Error Handling (Wishbone ERR -> AXI SLVERR)
// ============================================================================

`timescale 1ns / 1ps

module tb_axi_interconnect;

    localparam CLK_PERIOD = 10; // 100 MHz clock
    localparam DATA_WIDTH = 64;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = 8;
    localparam S_ID_WIDTH = 8;
    localparam M_ID_WIDTH = 8;

    // Peripheral base addresses
    localparam BASE_HB_MON    = 32'h0002_0300;
    localparam BASE_RESET_SEQ = 32'h0002_0400;
    localparam BASE_REC_POL   = 32'h0002_0500;

    // Registers
    localparam ADDR_HB_CTRL         = BASE_HB_MON    + 8'h00; // addr[2]=0
    localparam ADDR_HB_THRESHOLD    = BASE_HB_MON    + 8'h04; // addr[2]=1
    localparam ADDR_HB_STATUS       = BASE_HB_MON    + 8'h08; // addr[2]=0
    localparam ADDR_RST_CTRL        = BASE_RESET_SEQ + 8'h00; // addr[2]=0
    localparam ADDR_RST_HOLD_CYCLES = BASE_RESET_SEQ + 8'h04; // addr[2]=1
    localparam ADDR_RST_STATUS      = BASE_RESET_SEQ + 8'h08; // addr[2]=0
    localparam ADDR_POL_CTRL        = BASE_REC_POL   + 8'h00; // addr[2]=0
    localparam ADDR_POL_WINDOW      = BASE_REC_POL   + 8'h04; // addr[2]=1
    localparam ADDR_POL_THRESHOLD   = BASE_REC_POL   + 8'h08; // addr[2]=0
    localparam ADDR_POL_STATUS      = BASE_REC_POL   + 8'h0C; // addr[2]=1
    localparam ADDR_UNMAPPED        = 32'h0002_0800;          // Unmapped

    // Clock and Reset
    reg clk;
    reg rst_n;
    wire wb_rst = ~rst_n;

    // ------------------------------------------------------------------------
    // Master 0 (S00) Interface
    // ------------------------------------------------------------------------
    reg  [S_ID_WIDTH-1:0]  s00_axi_awid;
    reg  [ADDR_WIDTH-1:0]  s00_axi_awaddr;
    reg  [7:0]             s00_axi_awlen;
    reg  [2:0]             s00_axi_awsize;
    reg  [1:0]             s00_axi_awburst;
    reg                    s00_axi_awlock;
    reg  [3:0]             s00_axi_awcache;
    reg  [2:0]             s00_axi_awprot;
    reg  [3:0]             s00_axi_awqos;
    reg                    s00_axi_awvalid;
    wire                   s00_axi_awready;
    reg  [DATA_WIDTH-1:0]  s00_axi_wdata;
    reg  [STRB_WIDTH-1:0]  s00_axi_wstrb;
    reg                    s00_axi_wlast;
    reg                    s00_axi_wvalid;
    wire                   s00_axi_wready;
    wire [S_ID_WIDTH-1:0]  s00_axi_bid;
    wire [1:0]             s00_axi_bresp;
    wire                   s00_axi_bvalid;
    reg                    s00_axi_bready;
    reg  [S_ID_WIDTH-1:0]  s00_axi_arid;
    reg  [ADDR_WIDTH-1:0]  s00_axi_araddr;
    reg  [7:0]             s00_axi_arlen;
    reg  [2:0]             s00_axi_arsize;
    reg  [1:0]             s00_axi_arburst;
    reg                    s00_axi_arlock;
    reg  [3:0]             s00_axi_arcache;
    reg  [2:0]             s00_axi_arprot;
    reg  [3:0]             s00_axi_arqos;
    reg                    s00_axi_arvalid;
    wire                   s00_axi_arready;
    wire [S_ID_WIDTH-1:0]  s00_axi_rid;
    wire [DATA_WIDTH-1:0]  s00_axi_rdata;
    wire [1:0]             s00_axi_rresp;
    wire                   s00_axi_rlast;
    wire                   s00_axi_rvalid;
    reg                    s00_axi_rready;

    // ------------------------------------------------------------------------
    // Master 1 (S01) Interface
    // ------------------------------------------------------------------------
    reg  [S_ID_WIDTH-1:0]  s01_axi_awid;
    reg  [ADDR_WIDTH-1:0]  s01_axi_awaddr;
    reg  [7:0]             s01_axi_awlen;
    reg  [2:0]             s01_axi_awsize;
    reg  [1:0]             s01_axi_awburst;
    reg                    s01_axi_awlock;
    reg  [3:0]             s01_axi_awcache;
    reg  [2:0]             s01_axi_awprot;
    reg  [3:0]             s01_axi_awqos;
    reg                    s01_axi_awvalid;
    wire                   s01_axi_awready;
    reg  [DATA_WIDTH-1:0]  s01_axi_wdata;
    reg  [STRB_WIDTH-1:0]  s01_axi_wstrb;
    reg                    s01_axi_wlast;
    reg                    s01_axi_wvalid;
    wire                   s01_axi_wready;
    wire [S_ID_WIDTH-1:0]  s01_axi_bid;
    wire [1:0]             s01_axi_bresp;
    wire                   s01_axi_bvalid;
    reg                    s01_axi_bready;
    reg  [S_ID_WIDTH-1:0]  s01_axi_arid;
    reg  [ADDR_WIDTH-1:0]  s01_axi_araddr;
    reg  [7:0]             s01_axi_arlen;
    reg  [2:0]             s01_axi_arsize;
    reg  [1:0]             s01_axi_arburst;
    reg                    s01_axi_arlock;
    reg  [3:0]             s01_axi_arcache;
    reg  [2:0]             s01_axi_arprot;
    reg  [3:0]             s01_axi_arqos;
    reg                    s01_axi_arvalid;
    wire                   s01_axi_arready;
    wire [S_ID_WIDTH-1:0]  s01_axi_rid;
    wire [DATA_WIDTH-1:0]  s01_axi_rdata;
    wire [1:0]             s01_axi_rresp;
    wire                   s01_axi_rlast;
    wire                   s01_axi_rvalid;
    reg                    s01_axi_rready;

    // ------------------------------------------------------------------------
    // AXI Master Outputs (7 Dedicated Slave Ports from 2x7 Interconnect)
    // ------------------------------------------------------------------------
    // Slave 0: UART
    wire [7:0]  m00_axi_awid, m00_axi_arid, m00_axi_bid, m00_axi_rid;
    wire [31:0] m00_axi_awaddr, m00_axi_araddr;
    wire [7:0]  m00_axi_awlen, m00_axi_arlen;
    wire [2:0]  m00_axi_awsize, m00_axi_arsize;
    wire [1:0]  m00_axi_awburst, m00_axi_arburst;
    wire [2:0]  m00_axi_awprot, m00_axi_arprot;
    wire        m00_axi_awvalid, m00_axi_awready;
    wire [63:0] m00_axi_wdata, m00_axi_rdata;
    wire [7:0]  m00_axi_wstrb;
    wire        m00_axi_wlast, m00_axi_wvalid, m00_axi_wready;
    wire [1:0]  m00_axi_bresp, m00_axi_rresp;
    wire        m00_axi_bvalid, m00_axi_bready;
    wire        m00_axi_rlast, m00_axi_rvalid, m00_axi_rready;

    // Slave 1: Timer
    wire [7:0]  m01_axi_awid, m01_axi_arid, m01_axi_bid, m01_axi_rid;
    wire [31:0] m01_axi_awaddr, m01_axi_araddr;
    wire [7:0]  m01_axi_awlen, m01_axi_arlen;
    wire [2:0]  m01_axi_awsize, m01_axi_arsize;
    wire [1:0]  m01_axi_awburst, m01_axi_arburst;
    wire [2:0]  m01_axi_awprot, m01_axi_arprot;
    wire        m01_axi_awvalid, m01_axi_awready;
    wire [63:0] m01_axi_wdata, m01_axi_rdata;
    wire [7:0]  m01_axi_wstrb;
    wire        m01_axi_wlast, m01_axi_wvalid, m01_axi_wready;
    wire [1:0]  m01_axi_bresp, m01_axi_rresp;
    wire        m01_axi_bvalid, m01_axi_bready;
    wire        m01_axi_rlast, m01_axi_rvalid, m01_axi_rready;

    // Slave 2: GPIO
    wire [7:0]  m02_axi_awid, m02_axi_arid, m02_axi_bid, m02_axi_rid;
    wire [31:0] m02_axi_awaddr, m02_axi_araddr;
    wire [7:0]  m02_axi_awlen, m02_axi_arlen;
    wire [2:0]  m02_axi_awsize, m02_axi_arsize;
    wire [1:0]  m02_axi_awburst, m02_axi_arburst;
    wire [2:0]  m02_axi_awprot, m02_axi_arprot;
    wire        m02_axi_awvalid, m02_axi_awready;
    wire [63:0] m02_axi_wdata, m02_axi_rdata;
    wire [7:0]  m02_axi_wstrb;
    wire        m02_axi_wlast, m02_axi_wvalid, m02_axi_wready;
    wire [1:0]  m02_axi_bresp, m02_axi_rresp;
    wire        m02_axi_bvalid, m02_axi_bready;
    wire        m02_axi_rlast, m02_axi_rvalid, m02_axi_rready;

    // Slave 3: Heartbeat Monitor
    wire [7:0]  m03_axi_awid, m03_axi_arid, m03_axi_bid, m03_axi_rid;
    wire [31:0] m03_axi_awaddr, m03_axi_araddr;
    wire [7:0]  m03_axi_awlen, m03_axi_arlen;
    wire [2:0]  m03_axi_awsize, m03_axi_arsize;
    wire [1:0]  m03_axi_awburst, m03_axi_arburst;
    wire [2:0]  m03_axi_awprot, m03_axi_arprot;
    wire        m03_axi_awvalid, m03_axi_awready;
    wire [63:0] m03_axi_wdata, m03_axi_rdata;
    wire [7:0]  m03_axi_wstrb;
    wire        m03_axi_wlast, m03_axi_wvalid, m03_axi_wready;
    wire [1:0]  m03_axi_bresp, m03_axi_rresp;
    wire        m03_axi_bvalid, m03_axi_bready;
    wire        m03_axi_rlast, m03_axi_rvalid, m03_axi_rready;

    // Slave 4: Reset Sequencer
    wire [7:0]  m04_axi_awid, m04_axi_arid, m04_axi_bid, m04_axi_rid;
    wire [31:0] m04_axi_awaddr, m04_axi_araddr;
    wire [7:0]  m04_axi_awlen, m04_axi_arlen;
    wire [2:0]  m04_axi_awsize, m04_axi_arsize;
    wire [1:0]  m04_axi_awburst, m04_axi_arburst;
    wire [2:0]  m04_axi_awprot, m04_axi_arprot;
    wire        m04_axi_awvalid, m04_axi_awready;
    wire [63:0] m04_axi_wdata, m04_axi_rdata;
    wire [7:0]  m04_axi_wstrb;
    wire        m04_axi_wlast, m04_axi_wvalid, m04_axi_wready;
    wire [1:0]  m04_axi_bresp, m04_axi_rresp;
    wire        m04_axi_bvalid, m04_axi_bready;
    wire        m04_axi_rlast, m04_axi_rvalid, m04_axi_rready;

    // Slave 5: Recovery Policy
    wire [7:0]  m05_axi_awid, m05_axi_arid, m05_axi_bid, m05_axi_rid;
    wire [31:0] m05_axi_awaddr, m05_axi_araddr;
    wire [7:0]  m05_axi_awlen, m05_axi_arlen;
    wire [2:0]  m05_axi_awsize, m05_axi_arsize;
    wire [1:0]  m05_axi_awburst, m05_axi_arburst;
    wire [2:0]  m05_axi_awprot, m05_axi_arprot;
    wire        m05_axi_awvalid, m05_axi_awready;
    wire [63:0] m05_axi_wdata, m05_axi_rdata;
    wire [7:0]  m05_axi_wstrb;
    wire        m05_axi_wlast, m05_axi_wvalid, m05_axi_wready;
    wire [1:0]  m05_axi_bresp, m05_axi_rresp;
    wire        m05_axi_bvalid, m05_axi_bready;
    wire        m05_axi_rlast, m05_axi_rvalid, m05_axi_rready;

    // Slave 6: VGA Controller
    wire [7:0]  m06_axi_awid, m06_axi_arid, m06_axi_bid, m06_axi_rid;
    wire [31:0] m06_axi_awaddr, m06_axi_araddr;
    wire [7:0]  m06_axi_awlen, m06_axi_arlen;
    wire [2:0]  m06_axi_awsize, m06_axi_arsize;
    wire [1:0]  m06_axi_awburst, m06_axi_arburst;
    wire [2:0]  m06_axi_awprot, m06_axi_arprot;
    wire        m06_axi_awvalid, m06_axi_awready;
    wire [63:0] m06_axi_wdata, m06_axi_rdata;
    wire [7:0]  m06_axi_wstrb;
    wire        m06_axi_wlast, m06_axi_wvalid, m06_axi_wready;
    wire [1:0]  m06_axi_bresp, m06_axi_rresp;
    wire        m06_axi_bvalid, m06_axi_bready;
    wire        m06_axi_rlast, m06_axi_rvalid, m06_axi_rready;

    // ------------------------------------------------------------------------
    // Wishbone Interfaces (7 Dedicated Channels from Bridges to Peripherals)
    // ------------------------------------------------------------------------
    wire [7:0]  wbs0_adr, wbs1_adr, wbs2_adr, wbs3_adr, wbs4_adr, wbs5_adr, wbs6_adr;
    wire [31:0] wbs0_dat_o, wbs1_dat_o, wbs2_dat_o, wbs3_dat_o, wbs4_dat_o, wbs5_dat_o, wbs6_dat_o;
    wire [31:0] wbs0_dat_i, wbs1_dat_i, wbs2_dat_i, wbs3_dat_i, wbs4_dat_i, wbs5_dat_i, wbs6_dat_i;
    wire        wbs0_we, wbs1_we, wbs2_we, wbs3_we, wbs4_we, wbs5_we, wbs6_we;
    wire        wbs0_stb, wbs1_stb, wbs2_stb, wbs3_stb, wbs4_stb, wbs5_stb, wbs6_stb;
    wire        wbs0_cyc, wbs1_cyc, wbs2_cyc, wbs3_cyc, wbs4_cyc, wbs5_cyc, wbs6_cyc;
    wire        wbs0_ack, wbs1_ack, wbs2_ack, wbs3_ack, wbs4_ack, wbs5_ack, wbs6_ack;
    wire [3:0]  wbs0_sel, wbs1_sel, wbs2_sel, wbs3_sel, wbs4_sel, wbs5_sel, wbs6_sel;

    wire        hb_irq;
    reg         heartbeat_in;
    wire        reset_out;

    // Test execution bookkeeping
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num = 0;

    // ========================================================================
    // DUT: AXI4 Interconnect (2 Masters x 7 Slaves)
    // ========================================================================
    axi_interconnect_wrap_2x7 #(
        .DATA_WIDTH        (DATA_WIDTH),
        .ADDR_WIDTH        (ADDR_WIDTH),
        .STRB_WIDTH        (STRB_WIDTH),
        .ID_WIDTH          (S_ID_WIDTH),
        .FORWARD_ID        (1),
        .M_REGIONS         (1),

        // Slave 0: UART
        .M00_BASE_ADDR     (32'h0002_0000),
        .M00_ADDR_WIDTH    (32'd8),
        .M00_CONNECT_READ  (2'b11),
        .M00_CONNECT_WRITE (2'b11),
        .M00_SECURE        (1'b0),

        // Slave 1: Timer
        .M01_BASE_ADDR     (32'h0002_0100),
        .M01_ADDR_WIDTH    (32'd8),
        .M01_CONNECT_READ  (2'b11),
        .M01_CONNECT_WRITE (2'b11),
        .M01_SECURE        (1'b0),

        // Slave 2: GPIO
        .M02_BASE_ADDR     (32'h0002_0200),
        .M02_ADDR_WIDTH    (32'd8),
        .M02_CONNECT_READ  (2'b11),
        .M02_CONNECT_WRITE (2'b11),
        .M02_SECURE        (1'b0),

        // Slave 3: Heartbeat Monitor
        .M03_BASE_ADDR     (BASE_HB_MON),
        .M03_ADDR_WIDTH    (32'd8),
        .M03_CONNECT_READ  (2'b11),
        .M03_CONNECT_WRITE (2'b11),
        .M03_SECURE        (1'b0),

        // Slave 4: Reset Sequencer
        .M04_BASE_ADDR     (BASE_RESET_SEQ),
        .M04_ADDR_WIDTH    (32'd8),
        .M04_CONNECT_READ  (2'b11),
        .M04_CONNECT_WRITE (2'b11),
        .M04_SECURE        (1'b0),

        // Slave 5: Recovery Policy
        .M05_BASE_ADDR     (BASE_REC_POL),
        .M05_ADDR_WIDTH    (32'd8),
        .M05_CONNECT_READ  (2'b11),
        .M05_CONNECT_WRITE (2'b11),
        .M05_SECURE        (1'b0),

        // Slave 6: VGA Dashboard
        .M06_BASE_ADDR     (32'h0002_0600),
        .M06_ADDR_WIDTH    (32'd8),
        .M06_CONNECT_READ  (2'b11),
        .M06_CONNECT_WRITE (2'b11),
        .M06_SECURE        (1'b0)
    ) u_intercon (
        .clk             (clk),
        .rst             (wb_rst),

        // Master 0 Interface (S00) — VeeR LSU
        .s00_axi_awid    (s00_axi_awid),
        .s00_axi_awaddr  (s00_axi_awaddr),
        .s00_axi_awlen   (s00_axi_awlen),
        .s00_axi_awsize  (s00_axi_awsize),
        .s00_axi_awburst (s00_axi_awburst),
        .s00_axi_awlock  (s00_axi_awlock),
        .s00_axi_awcache (s00_axi_awcache),
        .s00_axi_awprot  (s00_axi_awprot),
        .s00_axi_awqos   (s00_axi_awqos),
        .s00_axi_awuser  (1'b0),
        .s00_axi_awvalid (s00_axi_awvalid),
        .s00_axi_awready (s00_axi_awready),
        .s00_axi_wdata   (s00_axi_wdata),
        .s00_axi_wstrb   (s00_axi_wstrb),
        .s00_axi_wlast   (s00_axi_wlast),
        .s00_axi_wuser   (1'b0),
        .s00_axi_wvalid  (s00_axi_wvalid),
        .s00_axi_wready  (s00_axi_wready),
        .s00_axi_bid     (s00_axi_bid),
        .s00_axi_bresp   (s00_axi_bresp),
        .s00_axi_buser   (),
        .s00_axi_bvalid  (s00_axi_bvalid),
        .s00_axi_bready  (s00_axi_bready),
        .s00_axi_arid    (s00_axi_arid),
        .s00_axi_araddr  (s00_axi_araddr),
        .s00_axi_arlen   (s00_axi_arlen),
        .s00_axi_arsize  (s00_axi_arsize),
        .s00_axi_arburst (s00_axi_arburst),
        .s00_axi_arlock  (s00_axi_arlock),
        .s00_axi_arcache (s00_axi_arcache),
        .s00_axi_arprot  (s00_axi_arprot),
        .s00_axi_arqos   (s00_axi_arqos),
        .s00_axi_aruser  (1'b0),
        .s00_axi_arvalid (s00_axi_arvalid),
        .s00_axi_arready (s00_axi_arready),
        .s00_axi_rid     (s00_axi_rid),
        .s00_axi_rdata   (s00_axi_rdata),
        .s00_axi_rresp   (s00_axi_rresp),
        .s00_axi_rlast   (s00_axi_rlast),
        .s00_axi_ruser   (),
        .s00_axi_rvalid  (s00_axi_rvalid),
        .s00_axi_rready  (s00_axi_rready),

        // Master 1 Interface (S01) — VeeR SB / Debug
        .s01_axi_awid    (s01_axi_awid),
        .s01_axi_awaddr  (s01_axi_awaddr),
        .s01_axi_awlen   (s01_axi_awlen),
        .s01_axi_awsize  (s01_axi_awsize),
        .s01_axi_awburst (s01_axi_awburst),
        .s01_axi_awlock  (s01_axi_awlock),
        .s01_axi_awcache (s01_axi_awcache),
        .s01_axi_awprot  (s01_axi_awprot),
        .s01_axi_awqos   (s01_axi_awqos),
        .s01_axi_awuser  (1'b0),
        .s01_axi_awvalid (s01_axi_awvalid),
        .s01_axi_awready (s01_axi_awready),
        .s01_axi_wdata   (s01_axi_wdata),
        .s01_axi_wstrb   (s01_axi_wstrb),
        .s01_axi_wlast   (s01_axi_wlast),
        .s01_axi_wuser   (1'b0),
        .s01_axi_wvalid  (s01_axi_wvalid),
        .s01_axi_wready  (s01_axi_wready),
        .s01_axi_bid     (s01_axi_bid),
        .s01_axi_bresp   (s01_axi_bresp),
        .s01_axi_buser   (),
        .s01_axi_bvalid  (s01_axi_bvalid),
        .s01_axi_bready  (s01_axi_bready),
        .s01_axi_arid    (s01_axi_arid),
        .s01_axi_araddr  (s01_axi_araddr),
        .s01_axi_arlen   (s01_axi_arlen),
        .s01_axi_arsize  (s01_axi_arsize),
        .s01_axi_arburst (s01_axi_arburst),
        .s01_axi_arlock  (s01_axi_arlock),
        .s01_axi_arcache (s01_axi_arcache),
        .s01_axi_arprot  (s01_axi_arprot),
        .s01_axi_arqos   (s01_axi_arqos),
        .s01_axi_aruser  (1'b0),
        .s01_axi_arvalid (s01_axi_arvalid),
        .s01_axi_arready (s01_axi_arready),
        .s01_axi_rid     (s01_axi_rid),
        .s01_axi_rdata   (s01_axi_rdata),
        .s01_axi_rresp   (s01_axi_rresp),
        .s01_axi_rlast   (s01_axi_rlast),
        .s01_axi_ruser   (),
        .s01_axi_rvalid  (s01_axi_rvalid),
        .s01_axi_rready  (s01_axi_rready),

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
    );

    // ========================================================================
    // Dedicated 64-to-32 bit AXI-to-Wishbone Bridges (7 Instances)
    // ========================================================================
    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s0 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m00_axi_awid), .s_axi_awaddr(m00_axi_awaddr), .s_axi_awlen(m00_axi_awlen), .s_axi_awsize(m00_axi_awsize),
        .s_axi_awburst(m00_axi_awburst), .s_axi_awprot(m00_axi_awprot), .s_axi_awvalid(m00_axi_awvalid), .s_axi_awready(m00_axi_awready),
        .s_axi_wdata(m00_axi_wdata), .s_axi_wstrb(m00_axi_wstrb), .s_axi_wlast(m00_axi_wlast), .s_axi_wvalid(m00_axi_wvalid), .s_axi_wready(m00_axi_wready),
        .s_axi_bid(m00_axi_bid), .s_axi_bresp(m00_axi_bresp), .s_axi_bvalid(m00_axi_bvalid), .s_axi_bready(m00_axi_bready),
        .s_axi_arid(m00_axi_arid), .s_axi_araddr(m00_axi_araddr), .s_axi_arlen(m00_axi_arlen), .s_axi_arsize(m00_axi_arsize),
        .s_axi_arburst(m00_axi_arburst), .s_axi_arprot(m00_axi_arprot), .s_axi_arvalid(m00_axi_arvalid), .s_axi_arready(m00_axi_arready),
        .s_axi_rid(m00_axi_rid), .s_axi_rdata(m00_axi_rdata), .s_axi_rresp(m00_axi_rresp), .s_axi_rlast(m00_axi_rlast), .s_axi_rvalid(m00_axi_rvalid), .s_axi_rready(m00_axi_rready),
        .wb_adr_o(wbs0_adr), .wb_dat_o(wbs0_dat_o), .wb_dat_i(wbs0_dat_i), .wb_we_o(wbs0_we), .wb_sel_o(wbs0_sel),
        .wb_stb_o(wbs0_stb), .wb_cyc_o(wbs0_cyc), .wb_ack_i(wbs0_ack), .wb_err_i(1'b0)
    );

    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s1 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m01_axi_awid), .s_axi_awaddr(m01_axi_awaddr), .s_axi_awlen(m01_axi_awlen), .s_axi_awsize(m01_axi_awsize),
        .s_axi_awburst(m01_axi_awburst), .s_axi_awprot(m01_axi_awprot), .s_axi_awvalid(m01_axi_awvalid), .s_axi_awready(m01_axi_awready),
        .s_axi_wdata(m01_axi_wdata), .s_axi_wstrb(m01_axi_wstrb), .s_axi_wlast(m01_axi_wlast), .s_axi_wvalid(m01_axi_wvalid), .s_axi_wready(m01_axi_wready),
        .s_axi_bid(m01_axi_bid), .s_axi_bresp(m01_axi_bresp), .s_axi_bvalid(m01_axi_bvalid), .s_axi_bready(m01_axi_bready),
        .s_axi_arid(m01_axi_arid), .s_axi_araddr(m01_axi_araddr), .s_axi_arlen(m01_axi_arlen), .s_axi_arsize(m01_axi_arsize),
        .s_axi_arburst(m01_axi_arburst), .s_axi_arprot(m01_axi_arprot), .s_axi_arvalid(m01_axi_arvalid), .s_axi_arready(m01_axi_arready),
        .s_axi_rid(m01_axi_rid), .s_axi_rdata(m01_axi_rdata), .s_axi_rresp(m01_axi_rresp), .s_axi_rlast(m01_axi_rlast), .s_axi_rvalid(m01_axi_rvalid), .s_axi_rready(m01_axi_rready),
        .wb_adr_o(wbs1_adr), .wb_dat_o(wbs1_dat_o), .wb_dat_i(wbs1_dat_i), .wb_we_o(wbs1_we), .wb_sel_o(wbs1_sel),
        .wb_stb_o(wbs1_stb), .wb_cyc_o(wbs1_cyc), .wb_ack_i(wbs1_ack), .wb_err_i(1'b0)
    );

    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s2 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m02_axi_awid), .s_axi_awaddr(m02_axi_awaddr), .s_axi_awlen(m02_axi_awlen), .s_axi_awsize(m02_axi_awsize),
        .s_axi_awburst(m02_axi_awburst), .s_axi_awprot(m02_axi_awprot), .s_axi_awvalid(m02_axi_awvalid), .s_axi_awready(m02_axi_awready),
        .s_axi_wdata(m02_axi_wdata), .s_axi_wstrb(m02_axi_wstrb), .s_axi_wlast(m02_axi_wlast), .s_axi_wvalid(m02_axi_wvalid), .s_axi_wready(m02_axi_wready),
        .s_axi_bid(m02_axi_bid), .s_axi_bresp(m02_axi_bresp), .s_axi_bvalid(m02_axi_bvalid), .s_axi_bready(m02_axi_bready),
        .s_axi_arid(m02_axi_arid), .s_axi_araddr(m02_axi_araddr), .s_axi_arlen(m02_axi_arlen), .s_axi_arsize(m02_axi_arsize),
        .s_axi_arburst(m02_axi_arburst), .s_axi_arprot(m02_axi_arprot), .s_axi_arvalid(m02_axi_arvalid), .s_axi_arready(m02_axi_arready),
        .s_axi_rid(m02_axi_rid), .s_axi_rdata(m02_axi_rdata), .s_axi_rresp(m02_axi_rresp), .s_axi_rlast(m02_axi_rlast), .s_axi_rvalid(m02_axi_rvalid), .s_axi_rready(m02_axi_rready),
        .wb_adr_o(wbs2_adr), .wb_dat_o(wbs2_dat_o), .wb_dat_i(wbs2_dat_i), .wb_we_o(wbs2_we), .wb_sel_o(wbs2_sel),
        .wb_stb_o(wbs2_stb), .wb_cyc_o(wbs2_cyc), .wb_ack_i(wbs2_ack), .wb_err_i(1'b0)
    );

    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s3 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m03_axi_awid), .s_axi_awaddr(m03_axi_awaddr), .s_axi_awlen(m03_axi_awlen), .s_axi_awsize(m03_axi_awsize),
        .s_axi_awburst(m03_axi_awburst), .s_axi_awprot(m03_axi_awprot), .s_axi_awvalid(m03_axi_awvalid), .s_axi_awready(m03_axi_awready),
        .s_axi_wdata(m03_axi_wdata), .s_axi_wstrb(m03_axi_wstrb), .s_axi_wlast(m03_axi_wlast), .s_axi_wvalid(m03_axi_wvalid), .s_axi_wready(m03_axi_wready),
        .s_axi_bid(m03_axi_bid), .s_axi_bresp(m03_axi_bresp), .s_axi_bvalid(m03_axi_bvalid), .s_axi_bready(m03_axi_bready),
        .s_axi_arid(m03_axi_arid), .s_axi_araddr(m03_axi_araddr), .s_axi_arlen(m03_axi_arlen), .s_axi_arsize(m03_axi_arsize),
        .s_axi_arburst(m03_axi_arburst), .s_axi_arprot(m03_axi_arprot), .s_axi_arvalid(m03_axi_arvalid), .s_axi_arready(m03_axi_arready),
        .s_axi_rid(m03_axi_rid), .s_axi_rdata(m03_axi_rdata), .s_axi_rresp(m03_axi_rresp), .s_axi_rlast(m03_axi_rlast), .s_axi_rvalid(m03_axi_rvalid), .s_axi_rready(m03_axi_rready),
        .wb_adr_o(wbs3_adr), .wb_dat_o(wbs3_dat_o), .wb_dat_i(wbs3_dat_i), .wb_we_o(wbs3_we), .wb_sel_o(wbs3_sel),
        .wb_stb_o(wbs3_stb), .wb_cyc_o(wbs3_cyc), .wb_ack_i(wbs3_ack), .wb_err_i(1'b0)
    );

    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s4 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m04_axi_awid), .s_axi_awaddr(m04_axi_awaddr), .s_axi_awlen(m04_axi_awlen), .s_axi_awsize(m04_axi_awsize),
        .s_axi_awburst(m04_axi_awburst), .s_axi_awprot(m04_axi_awprot), .s_axi_awvalid(m04_axi_awvalid), .s_axi_awready(m04_axi_awready),
        .s_axi_wdata(m04_axi_wdata), .s_axi_wstrb(m04_axi_wstrb), .s_axi_wlast(m04_axi_wlast), .s_axi_wvalid(m04_axi_wvalid), .s_axi_wready(m04_axi_wready),
        .s_axi_bid(m04_axi_bid), .s_axi_bresp(m04_axi_bresp), .s_axi_bvalid(m04_axi_bvalid), .s_axi_bready(m04_axi_bready),
        .s_axi_arid(m04_axi_arid), .s_axi_araddr(m04_axi_araddr), .s_axi_arlen(m04_axi_arlen), .s_axi_arsize(m04_axi_arsize),
        .s_axi_arburst(m04_axi_arburst), .s_axi_arprot(m04_axi_arprot), .s_axi_arvalid(m04_axi_arvalid), .s_axi_arready(m04_axi_arready),
        .s_axi_rid(m04_axi_rid), .s_axi_rdata(m04_axi_rdata), .s_axi_rresp(m04_axi_rresp), .s_axi_rlast(m04_axi_rlast), .s_axi_rvalid(m04_axi_rvalid), .s_axi_rready(m04_axi_rready),
        .wb_adr_o(wbs4_adr), .wb_dat_o(wbs4_dat_o), .wb_dat_i(wbs4_dat_i), .wb_we_o(wbs4_we), .wb_sel_o(wbs4_sel),
        .wb_stb_o(wbs4_stb), .wb_cyc_o(wbs4_cyc), .wb_ack_i(wbs4_ack), .wb_err_i(1'b0)
    );

    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s5 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m05_axi_awid), .s_axi_awaddr(m05_axi_awaddr), .s_axi_awlen(m05_axi_awlen), .s_axi_awsize(m05_axi_awsize),
        .s_axi_awburst(m05_axi_awburst), .s_axi_awprot(m05_axi_awprot), .s_axi_awvalid(m05_axi_awvalid), .s_axi_awready(m05_axi_awready),
        .s_axi_wdata(m05_axi_wdata), .s_axi_wstrb(m05_axi_wstrb), .s_axi_wlast(m05_axi_wlast), .s_axi_wvalid(m05_axi_wvalid), .s_axi_wready(m05_axi_wready),
        .s_axi_bid(m05_axi_bid), .s_axi_bresp(m05_axi_bresp), .s_axi_bvalid(m05_axi_bvalid), .s_axi_bready(m05_axi_bready),
        .s_axi_arid(m05_axi_arid), .s_axi_araddr(m05_axi_araddr), .s_axi_arlen(m05_axi_arlen), .s_axi_arsize(m05_axi_arsize),
        .s_axi_arburst(m05_axi_arburst), .s_axi_arprot(m05_axi_arprot), .s_axi_arvalid(m05_axi_arvalid), .s_axi_arready(m05_axi_arready),
        .s_axi_rid(m05_axi_rid), .s_axi_rdata(m05_axi_rdata), .s_axi_rresp(m05_axi_rresp), .s_axi_rlast(m05_axi_rlast), .s_axi_rvalid(m05_axi_rvalid), .s_axi_rready(m05_axi_rready),
        .wb_adr_o(wbs5_adr), .wb_dat_o(wbs5_dat_o), .wb_dat_i(wbs5_dat_i), .wb_we_o(wbs5_we), .wb_sel_o(wbs5_sel),
        .wb_stb_o(wbs5_stb), .wb_cyc_o(wbs5_cyc), .wb_ack_i(wbs5_ack), .wb_err_i(1'b0)
    );

    axi4_to_wb_bridge #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(8), .WB_ADDR_WIDTH(8), .WB_DATA_WIDTH(32)) u_bridge_s6 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(m06_axi_awid), .s_axi_awaddr(m06_axi_awaddr), .s_axi_awlen(m06_axi_awlen), .s_axi_awsize(m06_axi_awsize),
        .s_axi_awburst(m06_axi_awburst), .s_axi_awprot(m06_axi_awprot), .s_axi_awvalid(m06_axi_awvalid), .s_axi_awready(m06_axi_awready),
        .s_axi_wdata(m06_axi_wdata), .s_axi_wstrb(m06_axi_wstrb), .s_axi_wlast(m06_axi_wlast), .s_axi_wvalid(m06_axi_wvalid), .s_axi_wready(m06_axi_wready),
        .s_axi_bid(m06_axi_bid), .s_axi_bresp(m06_axi_bresp), .s_axi_bvalid(m06_axi_bvalid), .s_axi_bready(m06_axi_bready),
        .s_axi_arid(m06_axi_arid), .s_axi_araddr(m06_axi_araddr), .s_axi_arlen(m06_axi_arlen), .s_axi_arsize(m06_axi_arsize),
        .s_axi_arburst(m06_axi_arburst), .s_axi_arprot(m06_axi_arprot), .s_axi_arvalid(m06_axi_arvalid), .s_axi_arready(m06_axi_arready),
        .s_axi_rid(m06_axi_rid), .s_axi_rdata(m06_axi_rdata), .s_axi_rresp(m06_axi_rresp), .s_axi_rlast(m06_axi_rlast), .s_axi_rvalid(m06_axi_rvalid), .s_axi_rready(m06_axi_rready),
        .wb_adr_o(wbs6_adr), .wb_dat_o(wbs6_dat_o), .wb_dat_i(wbs6_dat_i), .wb_we_o(wbs6_we), .wb_sel_o(wbs6_sel),
        .wb_stb_o(wbs6_stb), .wb_cyc_o(wbs6_cyc), .wb_ack_i(wbs6_ack), .wb_err_i(1'b0)
    );

    // ========================================================================
    // Peripheral Direct Connections (No Global Crossbar)
    // ========================================================================
    // S0: UART (immediate ack stub)
    assign wbs0_dat_i = 32'h0;
    assign wbs0_ack   = wbs0_stb & wbs0_cyc;

    // S1: Timer (immediate ack stub)
    assign wbs1_dat_i = 32'h0;
    assign wbs1_ack   = wbs1_stb & wbs1_cyc;

    // S2: GPIO (immediate ack stub)
    assign wbs2_dat_i = 32'h0;
    assign wbs2_ack   = wbs2_stb & wbs2_cyc;

    // S3: Heartbeat Monitor
    heartbeat_monitor u_hbm (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs3_adr), .wb_dat_i(wbs3_dat_o), .wb_dat_o(wbs3_dat_i),
        .wb_we_i(wbs3_we), .wb_sel_i(wbs3_sel),
        .wb_stb_i(wbs3_stb), .wb_cyc_i(wbs3_cyc), .wb_ack_o(wbs3_ack),
        .heartbeat_in(heartbeat_in), .hb_irq(hb_irq)
    );

    // S4: Reset Sequencer
    reset_sequencer u_rst (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs4_adr), .wb_dat_i(wbs4_dat_o), .wb_dat_o(wbs4_dat_i),
        .wb_we_i(wbs4_we), .wb_sel_i(wbs4_sel),
        .wb_stb_i(wbs4_stb), .wb_cyc_i(wbs4_cyc), .wb_ack_o(wbs4_ack),
        .reset_out(reset_out)
    );

    // S5: Recovery Policy
    recovery_policy u_pol (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs5_adr), .wb_dat_i(wbs5_dat_o), .wb_dat_o(wbs5_dat_i),
        .wb_we_i(wbs5_we), .wb_sel_i(wbs5_sel),
        .wb_stb_i(wbs5_stb), .wb_cyc_i(wbs5_cyc), .wb_ack_o(wbs5_ack)
    );

    // S6: VGA stub
    assign wbs6_dat_i = 32'h0;
    assign wbs6_ack   = wbs6_stb & wbs6_cyc;

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // Bus Master Helper Tasks
    // ========================================================================

    // ---- Master 0 Write ----
    task m0_write(
        input [S_ID_WIDTH-1:0] id,
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [STRB_WIDTH-1:0] strb,
        output [1:0]           resp
    );
        reg aw_done, w_done;
        begin
            @(posedge clk);
            s00_axi_awid    <= id;
            s00_axi_awaddr  <= addr;
            s00_axi_awlen   <= 8'd0;
            s00_axi_awsize  <= 3'd3; // 8 bytes (64-bit)
            s00_axi_awburst <= 2'b01;
            s00_axi_awlock  <= 1'b0;
            s00_axi_awcache <= 4'd0;
            s00_axi_awprot  <= 3'd0;
            s00_axi_awqos   <= 4'd0;
            s00_axi_awvalid <= 1'b1;

            s00_axi_wdata   <= data;
            s00_axi_wstrb   <= strb;
            s00_axi_wlast   <= 1'b1;
            s00_axi_wvalid  <= 1'b1;
            s00_axi_bready  <= 1'b1;

            aw_done = 0;
            w_done  = 0;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (s00_axi_awvalid && s00_axi_awready) begin
                    s00_axi_awvalid <= 1'b0;
                    aw_done = 1;
                end
                if (s00_axi_wvalid && s00_axi_wready) begin
                    s00_axi_wvalid <= 1'b0;
                    w_done = 1;
                end
            end

            // Wait for B response
            while (!s00_axi_bvalid) @(posedge clk);
            resp = s00_axi_bresp;
            if (s00_axi_bid != id) begin
                $display("ERROR: M0 Write BID mismatch! Exp: 0x%02x, Got: 0x%02x", id, s00_axi_bid);
                fail_count = fail_count + 1;
            end
            @(posedge clk);
            s00_axi_bready <= 1'b0;
        end
    endtask

    // ---- Master 0 Read ----
    task m0_read(
        input  [S_ID_WIDTH-1:0] id,
        input  [ADDR_WIDTH-1:0] addr,
        output [DATA_WIDTH-1:0] rdata,
        output [1:0]            resp
    );
        begin
            @(posedge clk);
            s00_axi_arid    <= id;
            s00_axi_araddr  <= addr;
            s00_axi_arlen   <= 8'd0;
            s00_axi_arsize  <= 3'd3;
            s00_axi_arburst <= 2'b01;
            s00_axi_arlock  <= 1'b0;
            s00_axi_arcache <= 4'd0;
            s00_axi_arprot  <= 3'd0;
            s00_axi_arqos   <= 4'd0;
            s00_axi_arvalid <= 1'b1;
            s00_axi_rready  <= 1'b1;

            @(posedge clk);
            while (!s00_axi_arready) @(posedge clk);
            s00_axi_arvalid <= 1'b0;

            while (!s00_axi_rvalid) @(posedge clk);
            rdata = s00_axi_rdata;
            resp  = s00_axi_rresp;
            if (s00_axi_rid != id) begin
                $display("ERROR: M0 Read RID mismatch! Exp: 0x%02x, Got: 0x%02x", id, s00_axi_rid);
                fail_count = fail_count + 1;
            end
            if (!s00_axi_rlast) begin
                $display("ERROR: M0 Read RLAST not asserted!");
                fail_count = fail_count + 1;
            end
            @(posedge clk);
            s00_axi_rready <= 1'b0;
        end
    endtask

    // ---- Master 1 Write ----
    task m1_write(
        input [S_ID_WIDTH-1:0] id,
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [STRB_WIDTH-1:0] strb,
        output [1:0]           resp
    );
        reg aw_done, w_done;
        begin
            @(posedge clk);
            s01_axi_awid    <= id;
            s01_axi_awaddr  <= addr;
            s01_axi_awlen   <= 8'd0;
            s01_axi_awsize  <= 3'd3;
            s01_axi_awburst <= 2'b01;
            s01_axi_awlock  <= 1'b0;
            s01_axi_awcache <= 4'd0;
            s01_axi_awprot  <= 3'd0;
            s01_axi_awqos   <= 4'd0;
            s01_axi_awvalid <= 1'b1;

            s01_axi_wdata   <= data;
            s01_axi_wstrb   <= strb;
            s01_axi_wlast   <= 1'b1;
            s01_axi_wvalid  <= 1'b1;
            s01_axi_bready  <= 1'b1;

            aw_done = 0;
            w_done  = 0;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (s01_axi_awvalid && s01_axi_awready) begin
                    s01_axi_awvalid <= 1'b0;
                    aw_done = 1;
                end
                if (s01_axi_wvalid && s01_axi_wready) begin
                    s01_axi_wvalid <= 1'b0;
                    w_done = 1;
                end
            end

            while (!s01_axi_bvalid) @(posedge clk);
            resp = s01_axi_bresp;
            if (s01_axi_bid != id) begin
                $display("ERROR: M1 Write BID mismatch! Exp: 0x%02x, Got: 0x%02x", id, s01_axi_bid);
                fail_count = fail_count + 1;
            end
            @(posedge clk);
            s01_axi_bready <= 1'b0;
        end
    endtask

    // ---- Master 1 Read ----
    task m1_read(
        input  [S_ID_WIDTH-1:0] id,
        input  [ADDR_WIDTH-1:0] addr,
        output [DATA_WIDTH-1:0] rdata,
        output [1:0]            resp
    );
        begin
            @(posedge clk);
            s01_axi_arid    <= id;
            s01_axi_araddr  <= addr;
            s01_axi_arlen   <= 8'd0;
            s01_axi_arsize  <= 3'd3;
            s01_axi_arburst <= 2'b01;
            s01_axi_arlock  <= 1'b0;
            s01_axi_arcache <= 4'd0;
            s01_axi_arprot  <= 3'd0;
            s01_axi_arqos   <= 4'd0;
            s01_axi_arvalid <= 1'b1;
            s01_axi_rready  <= 1'b1;

            @(posedge clk);
            while (!s01_axi_arready) @(posedge clk);
            s01_axi_arvalid <= 1'b0;

            while (!s01_axi_rvalid) @(posedge clk);
            rdata = s01_axi_rdata;
            resp  = s01_axi_rresp;
            if (s01_axi_rid != id) begin
                $display("ERROR: M1 Read RID mismatch! Exp: 0x%02x, Got: 0x%02x", id, s01_axi_rid);
                fail_count = fail_count + 1;
            end
            if (!s01_axi_rlast) begin
                $display("ERROR: M1 Read RLAST not asserted!");
                fail_count = fail_count + 1;
            end
            @(posedge clk);
            s01_axi_rready <= 1'b0;
        end
    endtask

    // ========================================================================
    // Main Verification Flow
    // ========================================================================
    reg [DATA_WIDTH-1:0] rdata;
    reg [1:0]            resp;

    initial begin
        // Waveform dump
        $dumpfile("tb_axi_interconnect.vcd");
        $dumpvars(0, tb_axi_interconnect);
        if ($test$plusargs("fsdb")) begin
            $fsdbDumpfile("tb_axi_interconnect.fsdb");
            $fsdbDumpvars(0, tb_axi_interconnect);
        end

        // Signal initialization
        rst_n           = 1'b0;
        heartbeat_in    = 1'b0;

        s00_axi_awid    = 0; s00_axi_awaddr  = 0; s00_axi_awlen   = 0;
        s00_axi_awsize  = 0; s00_axi_awburst = 0; s00_axi_awlock  = 0;
        s00_axi_awcache = 0; s00_axi_awprot  = 0; s00_axi_awqos   = 0;
        s00_axi_awvalid = 0; s00_axi_wdata   = 0; s00_axi_wstrb   = 0;
        s00_axi_wlast   = 0; s00_axi_wvalid  = 0; s00_axi_bready  = 0;
        s00_axi_arid    = 0; s00_axi_araddr  = 0; s00_axi_arlen   = 0;
        s00_axi_arsize  = 0; s00_axi_arburst = 0; s00_axi_arlock  = 0;
        s00_axi_arcache = 0; s00_axi_arprot  = 0; s00_axi_arqos   = 0;
        s00_axi_arvalid = 0; s00_axi_rready  = 0;

        s01_axi_awid    = 0; s01_axi_awaddr  = 0; s01_axi_awlen   = 0;
        s01_axi_awsize  = 0; s01_axi_awburst = 0; s01_axi_awlock  = 0;
        s01_axi_awcache = 0; s01_axi_awprot  = 0; s01_axi_awqos   = 0;
        s01_axi_awvalid = 0; s01_axi_wdata   = 0; s01_axi_wstrb   = 0;
        s01_axi_wlast   = 0; s01_axi_wvalid  = 0; s01_axi_bready  = 0;
        s01_axi_arid    = 0; s01_axi_araddr  = 0; s01_axi_arlen   = 0;
        s01_axi_arsize  = 0; s01_axi_arburst = 0; s01_axi_arlock  = 0;
        s01_axi_arcache = 0; s01_axi_arprot  = 0; s01_axi_arqos   = 0;
        s01_axi_arvalid = 0; s01_axi_rready  = 0;

        // Reset sequence
        #100;
        rst_n = 1'b1;
        #50;

        $display("================================================================");
        $display("  BMC SoC — AXI4 Interconnect Verification Testbench");
        $display("================================================================");

        // --------------------------------------------------------------------
        // Test 1: Master 0 (LSU) Write & Read with ID Tag Matching
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] Master 0 (LSU) Write & Read (HB_THRESHOLD)", test_num);
        // Write 0x0000_1234 to HB_THRESHOLD (0x0002_0304) with ID 0x11
        // Note: addr[2]=1, so data is steered from wdata[63:32]
        m0_write(8'h11, ADDR_HB_THRESHOLD, {32'h0000_1234, 32'h0000_0000}, 8'hF0, resp);
        if (resp == 2'b00) begin
            $display("  -> M0 Write OKAY (BID=0x11, BRESP=0)");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: M0 Write failed with resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Read back HB_THRESHOLD with ID 0x12
        m0_read(8'h12, ADDR_HB_THRESHOLD, rdata, resp);
        if (resp == 2'b00 && rdata[31:0] == 32'h0000_1234 && rdata[63:32] == 32'h0000_1234) begin
            $display("  -> M0 Read PASS: rdata=0x%016h, RID=0x12, RRESP=0", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: M0 Read failed: rdata=0x%016h, resp=%b", rdata, resp);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Test 2: Master 1 (SB / Debug) Write & Read
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] Master 1 (SB) Write & Read (RST_HOLD_CYCLES)", test_num);
        // Write 0x0000_00C8 to RST_HOLD_CYCLES (0x0002_0404) with ID 0x21
        m1_write(8'h21, ADDR_RST_HOLD_CYCLES, {32'h0000_00C8, 32'h0000_0000}, 8'hF0, resp);
        if (resp == 2'b00) begin
            $display("  -> M1 Write OKAY (BID=0x21, BRESP=0)");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: M1 Write failed with resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Read back RST_HOLD_CYCLES with ID 0x22
        m1_read(8'h22, ADDR_RST_HOLD_CYCLES, rdata, resp);
        if (resp == 2'b00 && rdata[31:0] == 32'h0000_00C8) begin
            $display("  -> M1 Read PASS: rdata=0x%016h, RID=0x22, RRESP=0", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: M1 Read failed: rdata=0x%016h, resp=%b", rdata, resp);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Test 3: Address Alignment & 64-bit Steering (addr[2]=0 vs addr[2]=1)
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] 64-to-32 bit Data Steering (addr[2]=0 and addr[2]=1)", test_num);
        // Write to POL_WINDOW (addr[2]=1) -> value 0x0000_0100 on [63:32]
        m0_write(8'h31, ADDR_POL_WINDOW, {32'h0000_0100, 32'h0000_0000}, 8'hF0, resp);
        // Write to POL_THRESHOLD (addr[2]=0) -> value 0x0000_0005 on [31:0]
        m0_write(8'h32, ADDR_POL_THRESHOLD, {32'h0000_0000, 32'h0000_0005}, 8'h0F, resp);

        // Read back POL_WINDOW (addr[2]=1)
        m0_read(8'h33, ADDR_POL_WINDOW, rdata, resp);
        if (resp == 2'b00 && rdata[31:0] == 32'h0000_0100) begin
            $display("  -> Steered addr[2]=1 (POL_WINDOW) PASS: 0x%08h", rdata[31:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: POL_WINDOW mismatch: got 0x%08h", rdata[31:0]);
            fail_count = fail_count + 1;
        end

        // Read back POL_THRESHOLD (addr[2]=0)
        m0_read(8'h34, ADDR_POL_THRESHOLD, rdata, resp);
        if (resp == 2'b00 && rdata[31:0] == 32'h0000_0005) begin
            $display("  -> Steered addr[2]=0 (POL_THRESHOLD) PASS: 0x%08h", rdata[31:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: POL_THRESHOLD mismatch: got 0x%08h", rdata[31:0]);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Test 4: Concurrent / Simultaneous Requests from M0 and M1
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] Concurrent Arbitration (M0 & M1 request simultaneously)", test_num);
        fork
            begin
                // Master 0 writes to HB_THRESHOLD
                m0_write(8'hA1, ADDR_HB_THRESHOLD, {32'h0000_CAFE, 32'h0000_0000}, 8'hF0, resp);
                if (resp == 2'b00) begin
                    $display("  -> Concurrent M0 Write completed OKAY");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  -> Concurrent M0 Write ERROR: resp=%b", resp);
                    fail_count = fail_count + 1;
                end
            end
            begin
                // Master 1 writes to RST_HOLD_CYCLES on the same clock cycle
                m1_write(8'hB1, ADDR_RST_HOLD_CYCLES, {32'h0000_BEEF, 32'h0000_0000}, 8'hF0, resp);
                if (resp == 2'b00) begin
                    $display("  -> Concurrent M1 Write completed OKAY");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  -> Concurrent M1 Write ERROR: resp=%b", resp);
                    fail_count = fail_count + 1;
                end
            end
        join

        // Verify both written registers retain their correct values without cross-contamination
        m0_read(8'hA2, ADDR_HB_THRESHOLD, rdata, resp);
        if (rdata[31:0] == 32'h0000_CAFE) begin
            $display("  -> Post-arbitration HB_THRESHOLD = 0x%08h PASS", rdata[31:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Post-arbitration HB_THRESHOLD ERROR: got 0x%08h", rdata[31:0]);
            fail_count = fail_count + 1;
        end

        m1_read(8'hB2, ADDR_RST_HOLD_CYCLES, rdata, resp);
        if (rdata[31:0] == 32'h0000_BEEF) begin
            $display("  -> Post-arbitration RST_HOLD_CYCLES = 0x%08h PASS", rdata[31:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Post-arbitration RST_HOLD_CYCLES ERROR: got 0x%08h", rdata[31:0]);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Test 5: Unmapped Address Handling (DECERR / SLVERR)
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] Unmapped Address Error Handling (DECERR/SLVERR)", test_num);
        // Master 0 reads unmapped address 0x0002_0800
        m0_read(8'hEE, ADDR_UNMAPPED, rdata, resp);
        if (resp == 2'b11 || resp == 2'b10) begin // 2'b11 = DECERR, 2'b10 = SLVERR
            $display("  -> Unmapped read correctly returned AXI error (resp=%b) PASS", resp);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: Expected DECERR (2'b11) or SLVERR (2'b10), got resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Test 6: Verify All 7 Dedicated Peripheral Slave Ports
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] Verify Access across All 7 Dedicated Peripheral Slave Ports", test_num);

        // Slave 0: UART @ 0x0002_0000
        m0_read(8'h50, 32'h0002_0000, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 0 (UART @ 0x0002_0000) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 0 (UART) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Slave 1: Timer @ 0x0002_0100
        m0_read(8'h51, 32'h0002_0100, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 1 (Timer @ 0x0002_0100) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 1 (Timer) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Slave 2: GPIO @ 0x0002_0200
        m0_read(8'h52, 32'h0002_0200, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 2 (GPIO @ 0x0002_0200) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 2 (GPIO) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Slave 3: Heartbeat Monitor @ 0x0002_0300
        m0_read(8'h53, 32'h0002_0300, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 3 (HB Mon @ 0x0002_0300) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 3 (HB Mon) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Slave 4: Reset Sequencer @ 0x0002_0400
        m0_read(8'h54, 32'h0002_0400, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 4 (Reset Seq @ 0x0002_0400) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 4 (Reset Seq) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Slave 5: Recovery Policy @ 0x0002_0500
        m0_read(8'h55, 32'h0002_0500, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 5 (Rec Policy @ 0x0002_0500) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 5 (Rec Policy) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // Slave 6: VGA Dashboard @ 0x0002_0600
        m0_read(8'h56, 32'h0002_0600, rdata, resp);
        if (resp == 2'b00) begin
            $display("  -> Slave 6 (VGA @ 0x0002_0600) accessible OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Slave 6 (VGA) ERROR: resp=%b", resp);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Summary
        // --------------------------------------------------------------------
        #100;
        $display("\n================================================================");
        $display("  AXI4 INTERCONNECT VERIFICATION SUMMARY");
        $display("================================================================");
        $display("  Tests executed : %0d", pass_count + fail_count);
        $display("  Assertions PASSED: %0d", pass_count);
        $display("  Assertions FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("  >>> ALL AXI INTERCONNECT TESTS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display("  >>> SOME TESTS FAILED! <<<");
        end
        $display("================================================================\n");

        $finish;
    end

endmodule
