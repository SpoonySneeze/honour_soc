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
    localparam M_ID_WIDTH = 9;

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
    // Crossbar Output (M00) to Bridge
    // ------------------------------------------------------------------------
    wire [M_ID_WIDTH-1:0]  m00_axi_awid;
    wire [ADDR_WIDTH-1:0]  m00_axi_awaddr;
    wire [7:0]             m00_axi_awlen;
    wire [2:0]             m00_axi_awsize;
    wire [1:0]             m00_axi_awburst;
    wire                   m00_axi_awlock;
    wire [3:0]             m00_axi_awcache;
    wire [2:0]             m00_axi_awprot;
    wire [3:0]             m00_axi_awqos;
    wire [3:0]             m00_axi_awregion;
    wire                   m00_axi_awvalid;
    wire                   m00_axi_awready;
    wire [DATA_WIDTH-1:0]  m00_axi_wdata;
    wire [STRB_WIDTH-1:0]  m00_axi_wstrb;
    wire                   m00_axi_wlast;
    wire                   m00_axi_wvalid;
    wire                   m00_axi_wready;
    wire [M_ID_WIDTH-1:0]  m00_axi_bid;
    wire [1:0]             m00_axi_bresp;
    wire                   m00_axi_bvalid;
    wire                   m00_axi_bready;
    wire [M_ID_WIDTH-1:0]  m00_axi_arid;
    wire [ADDR_WIDTH-1:0]  m00_axi_araddr;
    wire [7:0]             m00_axi_arlen;
    wire [2:0]             m00_axi_arsize;
    wire [1:0]             m00_axi_arburst;
    wire                   m00_axi_arlock;
    wire [3:0]             m00_axi_arcache;
    wire [2:0]             m00_axi_arprot;
    wire [3:0]             m00_axi_arqos;
    wire [3:0]             m00_axi_arregion;
    wire                   m00_axi_arvalid;
    wire                   m00_axi_arready;
    wire [M_ID_WIDTH-1:0]  m00_axi_rid;
    wire [DATA_WIDTH-1:0]  m00_axi_rdata;
    wire [1:0]             m00_axi_rresp;
    wire                   m00_axi_rlast;
    wire                   m00_axi_rvalid;
    wire                   m00_axi_rready;

    // ------------------------------------------------------------------------
    // Wishbone Master & Slaves
    // ------------------------------------------------------------------------
    wire [31:0] wbm_adr, wbm_dat_m2s, wbm_dat_s2m;
    wire        wbm_we, wbm_stb, wbm_cyc, wbm_ack, wbm_err;
    wire [3:0]  wbm_sel;

    wire [7:0]  wbs0_adr, wbs1_adr, wbs2_adr, wbs3_adr, wbs4_adr, wbs5_adr, wbs6_adr;
    wire [31:0] wbs0_dat_o, wbs1_dat_o, wbs2_dat_o, wbs3_dat_o, wbs4_dat_o, wbs5_dat_o, wbs6_dat_o;
    wire [31:0] wbs3_dat_i, wbs4_dat_i, wbs5_dat_i;
    wire        wbs0_we, wbs1_we, wbs2_we, wbs3_we, wbs4_we, wbs5_we, wbs6_we;
    wire        wbs0_stb, wbs1_stb, wbs2_stb, wbs3_stb, wbs4_stb, wbs5_stb, wbs6_stb;
    wire        wbs0_cyc, wbs1_cyc, wbs2_cyc, wbs3_cyc, wbs4_cyc, wbs5_cyc, wbs6_cyc;
    wire        wbs3_ack, wbs4_ack, wbs5_ack;
    wire [3:0]  wbs0_sel, wbs1_sel, wbs2_sel, wbs3_sel, wbs4_sel, wbs5_sel, wbs6_sel;

    wire        hb_irq;
    reg         heartbeat_in;
    wire        reset_out;

    // Test execution bookkeeping
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num = 0;

    // ========================================================================
    // DUT: AXI4 Interconnect
    // ========================================================================
    axi_interconnect #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .S_ID_WIDTH (S_ID_WIDTH),
        .M_ID_WIDTH (M_ID_WIDTH)
    ) u_intercon (
        .clk             (clk),
        .rst_n           (rst_n),

        // Master 0 (S00)
        .s00_axi_awid    (s00_axi_awid),
        .s00_axi_awaddr  (s00_axi_awaddr),
        .s00_axi_awlen   (s00_axi_awlen),
        .s00_axi_awsize  (s00_axi_awsize),
        .s00_axi_awburst (s00_axi_awburst),
        .s00_axi_awlock  (s00_axi_awlock),
        .s00_axi_awcache (s00_axi_awcache),
        .s00_axi_awprot  (s00_axi_awprot),
        .s00_axi_awqos   (s00_axi_awqos),
        .s00_axi_awvalid (s00_axi_awvalid),
        .s00_axi_awready (s00_axi_awready),
        .s00_axi_wdata   (s00_axi_wdata),
        .s00_axi_wstrb   (s00_axi_wstrb),
        .s00_axi_wlast   (s00_axi_wlast),
        .s00_axi_wvalid  (s00_axi_wvalid),
        .s00_axi_wready  (s00_axi_wready),
        .s00_axi_bid     (s00_axi_bid),
        .s00_axi_bresp   (s00_axi_bresp),
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
        .s00_axi_arvalid (s00_axi_arvalid),
        .s00_axi_arready (s00_axi_arready),
        .s00_axi_rid     (s00_axi_rid),
        .s00_axi_rdata   (s00_axi_rdata),
        .s00_axi_rresp   (s00_axi_rresp),
        .s00_axi_rlast   (s00_axi_rlast),
        .s00_axi_rvalid  (s00_axi_rvalid),
        .s00_axi_rready  (s00_axi_rready),

        // Master 1 (S01)
        .s01_axi_awid    (s01_axi_awid),
        .s01_axi_awaddr  (s01_axi_awaddr),
        .s01_axi_awlen   (s01_axi_awlen),
        .s01_axi_awsize  (s01_axi_awsize),
        .s01_axi_awburst (s01_axi_awburst),
        .s01_axi_awlock  (s01_axi_awlock),
        .s01_axi_awcache (s01_axi_awcache),
        .s01_axi_awprot  (s01_axi_awprot),
        .s01_axi_awqos   (s01_axi_awqos),
        .s01_axi_awvalid (s01_axi_awvalid),
        .s01_axi_awready (s01_axi_awready),
        .s01_axi_wdata   (s01_axi_wdata),
        .s01_axi_wstrb   (s01_axi_wstrb),
        .s01_axi_wlast   (s01_axi_wlast),
        .s01_axi_wvalid  (s01_axi_wvalid),
        .s01_axi_wready  (s01_axi_wready),
        .s01_axi_bid     (s01_axi_bid),
        .s01_axi_bresp   (s01_axi_bresp),
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
        .s01_axi_arvalid (s01_axi_arvalid),
        .s01_axi_arready (s01_axi_arready),
        .s01_axi_rid     (s01_axi_rid),
        .s01_axi_rdata   (s01_axi_rdata),
        .s01_axi_rresp   (s01_axi_rresp),
        .s01_axi_rlast   (s01_axi_rlast),
        .s01_axi_rvalid  (s01_axi_rvalid),
        .s01_axi_rready  (s01_axi_rready),

        // Slave 0 (M00)
        .m00_axi_awid    (m00_axi_awid),
        .m00_axi_awaddr  (m00_axi_awaddr),
        .m00_axi_awlen   (m00_axi_awlen),
        .m00_axi_awsize  (m00_axi_awsize),
        .m00_axi_awburst (m00_axi_awburst),
        .m00_axi_awlock  (m00_axi_awlock),
        .m00_axi_awcache (m00_axi_awcache),
        .m00_axi_awprot  (m00_axi_awprot),
        .m00_axi_awqos   (m00_axi_awqos),
        .m00_axi_awregion(m00_axi_awregion),
        .m00_axi_awvalid (m00_axi_awvalid),
        .m00_axi_awready (m00_axi_awready),
        .m00_axi_wdata   (m00_axi_wdata),
        .m00_axi_wstrb   (m00_axi_wstrb),
        .m00_axi_wlast   (m00_axi_wlast),
        .m00_axi_wvalid  (m00_axi_wvalid),
        .m00_axi_wready  (m00_axi_wready),
        .m00_axi_bid     (m00_axi_bid),
        .m00_axi_bresp   (m00_axi_bresp),
        .m00_axi_bvalid  (m00_axi_bvalid),
        .m00_axi_bready  (m00_axi_bready),
        .m00_axi_arid    (m00_axi_arid),
        .m00_axi_araddr  (m00_axi_araddr),
        .m00_axi_arlen   (m00_axi_arlen),
        .m00_axi_arsize  (m00_axi_arsize),
        .m00_axi_arburst (m00_axi_arburst),
        .m00_axi_arlock  (m00_axi_arlock),
        .m00_axi_arcache (m00_axi_arcache),
        .m00_axi_arprot  (m00_axi_arprot),
        .m00_axi_arqos   (m00_axi_arqos),
        .m00_axi_arregion(m00_axi_arregion),
        .m00_axi_arvalid (m00_axi_arvalid),
        .m00_axi_arready (m00_axi_arready),
        .m00_axi_rid     (m00_axi_rid),
        .m00_axi_rdata   (m00_axi_rdata),
        .m00_axi_rresp   (m00_axi_rresp),
        .m00_axi_rlast   (m00_axi_rlast),
        .m00_axi_rvalid  (m00_axi_rvalid),
        .m00_axi_rready  (m00_axi_rready)
    );

    // ========================================================================
    // AXI4-to-Wishbone Bridge
    // ========================================================================
    axi4_to_wb_bridge #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH),
        .AXI_ID_WIDTH   (M_ID_WIDTH),
        .WB_ADDR_WIDTH  (32),
        .WB_DATA_WIDTH  (32)
    ) u_bridge (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awid     (m00_axi_awid),
        .s_axi_awaddr   (m00_axi_awaddr),
        .s_axi_awlen    (m00_axi_awlen),
        .s_axi_awsize   (m00_axi_awsize),
        .s_axi_awburst  (m00_axi_awburst),
        .s_axi_awprot   (m00_axi_awprot),
        .s_axi_awvalid  (m00_axi_awvalid),
        .s_axi_awready  (m00_axi_awready),
        .s_axi_wdata    (m00_axi_wdata),
        .s_axi_wstrb    (m00_axi_wstrb),
        .s_axi_wlast    (m00_axi_wlast),
        .s_axi_wvalid   (m00_axi_wvalid),
        .s_axi_wready   (m00_axi_wready),
        .s_axi_bid      (m00_axi_bid),
        .s_axi_bresp    (m00_axi_bresp),
        .s_axi_bvalid   (m00_axi_bvalid),
        .s_axi_bready   (m00_axi_bready),
        .s_axi_arid     (m00_axi_arid),
        .s_axi_araddr   (m00_axi_araddr),
        .s_axi_arlen    (m00_axi_arlen),
        .s_axi_arsize   (m00_axi_arsize),
        .s_axi_arburst  (m00_axi_arburst),
        .s_axi_arprot   (m00_axi_arprot),
        .s_axi_arvalid  (m00_axi_arvalid),
        .s_axi_arready  (m00_axi_arready),
        .s_axi_rid      (m00_axi_rid),
        .s_axi_rdata    (m00_axi_rdata),
        .s_axi_rresp    (m00_axi_rresp),
        .s_axi_rlast    (m00_axi_rlast),
        .s_axi_rvalid   (m00_axi_rvalid),
        .s_axi_rready   (m00_axi_rready),
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
    // Wishbone Interconnect & Peripherals
    // ========================================================================
    wb_interconnect u_wb_intercon (
        .wbm_adr_i(wbm_adr), .wbm_dat_i(wbm_dat_m2s), .wbm_dat_o(wbm_dat_s2m),
        .wbm_we_i(wbm_we), .wbm_sel_i(wbm_sel), .wbm_stb_i(wbm_stb),
        .wbm_cyc_i(wbm_cyc), .wbm_ack_o(wbm_ack), .wbm_err_o(wbm_err),

        // S0: UART (immediate ack stub)
        .wbs0_adr_o(wbs0_adr), .wbs0_dat_o(wbs0_dat_o), .wbs0_dat_i(32'h0),
        .wbs0_we_o(wbs0_we), .wbs0_sel_o(wbs0_sel), .wbs0_stb_o(wbs0_stb),
        .wbs0_cyc_o(wbs0_cyc), .wbs0_ack_i(wbs0_stb & wbs0_cyc),

        // S1: Timer (immediate ack stub)
        .wbs1_adr_o(wbs1_adr), .wbs1_dat_o(wbs1_dat_o), .wbs1_dat_i(32'h0),
        .wbs1_we_o(wbs1_we), .wbs1_sel_o(wbs1_sel), .wbs1_stb_o(wbs1_stb),
        .wbs1_cyc_o(wbs1_cyc), .wbs1_ack_i(wbs1_stb & wbs1_cyc),

        // S2: GPIO (immediate ack stub)
        .wbs2_adr_o(wbs2_adr), .wbs2_dat_o(wbs2_dat_o), .wbs2_dat_i(32'h0),
        .wbs2_we_o(wbs2_we), .wbs2_sel_o(wbs2_sel), .wbs2_stb_o(wbs2_stb),
        .wbs2_cyc_o(wbs2_cyc), .wbs2_ack_i(wbs2_stb & wbs2_cyc),

        // S3: Heartbeat Monitor
        .wbs3_adr_o(wbs3_adr), .wbs3_dat_o(wbs3_dat_o), .wbs3_dat_i(wbs3_dat_i),
        .wbs3_we_o(wbs3_we), .wbs3_sel_o(wbs3_sel), .wbs3_stb_o(wbs3_stb),
        .wbs3_cyc_o(wbs3_cyc), .wbs3_ack_i(wbs3_ack),

        // S4: Reset Sequencer
        .wbs4_adr_o(wbs4_adr), .wbs4_dat_o(wbs4_dat_o), .wbs4_dat_i(wbs4_dat_i),
        .wbs4_we_o(wbs4_we), .wbs4_sel_o(wbs4_sel), .wbs4_stb_o(wbs4_stb),
        .wbs4_cyc_o(wbs4_cyc), .wbs4_ack_i(wbs4_ack),

        // S5: Recovery Policy
        .wbs5_adr_o(wbs5_adr), .wbs5_dat_o(wbs5_dat_o), .wbs5_dat_i(wbs5_dat_i),
        .wbs5_we_o(wbs5_we), .wbs5_sel_o(wbs5_sel), .wbs5_stb_o(wbs5_stb),
        .wbs5_cyc_o(wbs5_cyc), .wbs5_ack_i(wbs5_ack),

        // S6: VGA stub
        .wbs6_adr_o(wbs6_adr), .wbs6_dat_o(wbs6_dat_o), .wbs6_dat_i(32'h0),
        .wbs6_we_o(wbs6_we), .wbs6_sel_o(wbs6_sel), .wbs6_stb_o(wbs6_stb),
        .wbs6_cyc_o(wbs6_cyc), .wbs6_ack_i(wbs6_stb & wbs6_cyc)
    );

    // Heartbeat Monitor instance
    heartbeat_monitor u_hbm (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs3_adr), .wb_dat_i(wbs3_dat_o), .wb_dat_o(wbs3_dat_i),
        .wb_we_i(wbs3_we), .wb_sel_i(wbs3_sel),
        .wb_stb_i(wbs3_stb), .wb_cyc_i(wbs3_cyc), .wb_ack_o(wbs3_ack),
        .heartbeat_in(heartbeat_in), .hb_irq(hb_irq)
    );

    // Reset Sequencer instance
    reset_sequencer u_rst (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs4_adr), .wb_dat_i(wbs4_dat_o), .wb_dat_o(wbs4_dat_i),
        .wb_we_i(wbs4_we), .wb_sel_i(wbs4_sel),
        .wb_stb_i(wbs4_stb), .wb_cyc_i(wbs4_cyc), .wb_ack_o(wbs4_ack),
        .reset_out(reset_out)
    );

    // Recovery Policy instance
    recovery_policy u_pol (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs5_adr), .wb_dat_i(wbs5_dat_o), .wb_dat_o(wbs5_dat_i),
        .wb_we_i(wbs5_we), .wb_sel_i(wbs5_sel),
        .wb_stb_i(wbs5_stb), .wb_cyc_i(wbs5_cyc), .wb_ack_o(wbs5_ack)
    );

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
        // Test 5: Unmapped Address Handling (SLVERR)
        // --------------------------------------------------------------------
        test_num = test_num + 1;
        $display("\n[TEST %0d] Unmapped Address Error Handling (SLVERR)", test_num);
        // Master 0 reads unmapped address 0x0002_0800
        m0_read(8'hEE, ADDR_UNMAPPED, rdata, resp);
        if (resp == 2'b10) begin // 2'b10 = SLVERR
            $display("  -> Unmapped read correctly returned AXI SLVERR (resp=2'b10) PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> ERROR: Expected SLVERR (2'b10), got resp=%b", resp);
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
