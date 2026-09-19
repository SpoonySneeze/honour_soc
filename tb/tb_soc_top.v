// ============================================================================
// Testbench — Full SoC System Integration Test
// ============================================================================
// Exercises the entire BMC SoC by driving the AXI bus interface directly
// (standing in for the VeeR core), simulating what firmware would do:
//
//   Scenario 1: Normal heartbeat — system stays online
//   Scenario 2: Single freeze → detection → recovery → log
//   Scenario 3: Repeated freezes → lockout triggers
//   Scenario 4: Manual override — force reset, clear lockout
//
// The testbench drives heartbeat_in and observes reset_out, while issuing
// Wishbone-level register transactions through the AXI-to-WB bridge.
// ============================================================================

`timescale 1ns / 1ps

module tb_soc_top;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CLK_PERIOD = 10;  // 100 MHz

    // Peripheral base addresses (full 32-bit)
    localparam HB_BASE  = 32'h0002_0300;
    localparam RST_BASE = 32'h0002_0400;
    localparam POL_BASE = 32'h0002_0500;
    localparam TMR_BASE = 32'h0002_0100;

    // Register offsets
    localparam HB_CTRL      = 8'h00;
    localparam HB_THRESHOLD = 8'h04;
    localparam HB_STATUS    = 8'h08;
    localparam HB_ELAPSED   = 8'h0C;

    localparam RST_CTRL        = 8'h00;
    localparam RST_HOLD_CYCLES = 8'h04;
    localparam RST_STATUS      = 8'h08;

    localparam POL_CTRL      = 8'h00;
    localparam POL_WINDOW    = 8'h04;
    localparam POL_THRESHOLD = 8'h08;
    localparam POL_STATUS    = 8'h0C;
    localparam POL_EVENT_TS  = 8'h10;
    localparam LOG_READ_IDX  = 8'h14;
    localparam LOG_READ_DATA = 8'h18;
    localparam LOG_COUNT     = 8'h1C;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;
    reg         heartbeat_in;
    wire        reset_out;
    reg         uart_rx;
    wire        uart_tx;
    wire        vga_hsync, vga_vsync;
    wire [11:0] vga_rgb;

    // AXI Master 0 interface (driving LSU port of interconnect)
    reg  [7:0]  axi_awid;
    reg  [31:0] axi_awaddr;
    reg  [7:0]  axi_awlen;
    reg  [2:0]  axi_awsize;
    reg  [1:0]  axi_awburst;
    reg         axi_awlock;
    reg  [3:0]  axi_awcache;
    reg  [2:0]  axi_awprot;
    reg  [3:0]  axi_awqos;
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [63:0] axi_wdata;
    reg  [7:0]  axi_wstrb;
    reg         axi_wlast;
    reg         axi_wvalid;
    wire        axi_wready;
    wire [7:0]  axi_bid;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready;
    reg  [7:0]  axi_arid;
    reg  [31:0] axi_araddr;
    reg  [7:0]  axi_arlen;
    reg  [2:0]  axi_arsize;
    reg  [1:0]  axi_arburst;
    reg         axi_arlock;
    reg  [3:0]  axi_arcache;
    reg  [2:0]  axi_arprot;
    reg  [3:0]  axi_arqos;
    reg         axi_arvalid;
    wire        axi_arready;
    wire [7:0]  axi_rid;
    wire [63:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rlast;
    wire        axi_rvalid;
    reg         axi_rready;

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

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ========================================================================
    // DUT — Instantiate complete peripheral subsystem with AXI 2x7 interconnect
    // ========================================================================
    wire        wb_rst = ~rst_n;

    // Wishbone slave interfaces
    wire [7:0]  wbs0_adr, wbs1_adr, wbs2_adr, wbs6_adr;
    wire [31:0] wbs0_dat_o, wbs1_dat_o, wbs2_dat_o, wbs6_dat_o;
    wire [31:0] wbs0_dat_i, wbs1_dat_i, wbs2_dat_i, wbs6_dat_i;
    wire        wbs0_we, wbs1_we, wbs2_we, wbs6_we;
    wire        wbs0_stb, wbs1_stb, wbs2_stb, wbs6_stb;
    wire        wbs0_cyc, wbs1_cyc, wbs2_cyc, wbs6_cyc;
    wire        wbs0_ack, wbs1_ack, wbs2_ack, wbs6_ack;
    wire [3:0]  wbs0_sel, wbs1_sel, wbs2_sel, wbs6_sel;

    wire        hb_irq;
    wire        reset_out_w;

    // AXI Interconnect (2 Masters x 7 Slaves)
    axi_interconnect_wrap_2x7 #(
        .DATA_WIDTH        (64),
        .ADDR_WIDTH        (32),
        .STRB_WIDTH        (8),
        .ID_WIDTH          (8),
        .FORWARD_ID        (1),
        .M_REGIONS         (1),

        // Slave 0: UART (0x0002_0000 - 0x0002_00FF, 256 B = 8-bit offset)
        .M00_BASE_ADDR     (32'h0002_0000),
        .M00_ADDR_WIDTH    (32'd8),
        .M00_CONNECT_READ  (2'b11),
        .M00_CONNECT_WRITE (2'b11),
        .M00_SECURE        (1'b0),

        // Slave 1: Timer (0x0002_0100 - 0x0002_01FF, 256 B = 8-bit offset)
        .M01_BASE_ADDR     (32'h0002_0100),
        .M01_ADDR_WIDTH    (32'd8),
        .M01_CONNECT_READ  (2'b11),
        .M01_CONNECT_WRITE (2'b11),
        .M01_SECURE        (1'b0),

        // Slave 2: GPIO (0x0002_0200 - 0x0002_02FF, 256 B = 8-bit offset)
        .M02_BASE_ADDR     (32'h0002_0200),
        .M02_ADDR_WIDTH    (32'd8),
        .M02_CONNECT_READ  (2'b11),
        .M02_CONNECT_WRITE (2'b11),
        .M02_SECURE        (1'b0),

        // Slave 3: Heartbeat Monitor (0x0002_0300 - 0x0002_03FF, 256 B = 8-bit offset)
        .M03_BASE_ADDR     (HB_BASE),
        .M03_ADDR_WIDTH    (32'd8),
        .M03_CONNECT_READ  (2'b11),
        .M03_CONNECT_WRITE (2'b11),
        .M03_SECURE        (1'b0),

        // Slave 4: Reset Sequencer (0x0002_0400 - 0x0002_04FF, 256 B = 8-bit offset)
        .M04_BASE_ADDR     (RST_BASE),
        .M04_ADDR_WIDTH    (32'd8),
        .M04_CONNECT_READ  (2'b11),
        .M04_CONNECT_WRITE (2'b11),
        .M04_SECURE        (1'b0),

        // Slave 5: Recovery Policy (0x0002_0500 - 0x0002_05FF, 256 B = 8-bit offset)
        .M05_BASE_ADDR     (POL_BASE),
        .M05_ADDR_WIDTH    (32'd8),
        .M05_CONNECT_READ  (2'b11),
        .M05_CONNECT_WRITE (2'b11),
        .M05_SECURE        (1'b0),

        // Slave 6: VGA Dashboard (0x0002_0600 - 0x0002_06FF, 256 B = 8-bit offset)
        .M06_BASE_ADDR     (32'h0002_0600),
        .M06_ADDR_WIDTH    (32'd8),
        .M06_CONNECT_READ  (2'b11),
        .M06_CONNECT_WRITE (2'b11),
        .M06_SECURE        (1'b0)
    ) u_axi_intercon (
        .clk             (clk),
        .rst             (wb_rst),

        // Master 0 (driven by testbench)
        .s00_axi_awid    (axi_awid),
        .s00_axi_awaddr  (axi_awaddr),
        .s00_axi_awlen   (axi_awlen),
        .s00_axi_awsize  (axi_awsize),
        .s00_axi_awburst (axi_awburst),
        .s00_axi_awlock  (axi_awlock),
        .s00_axi_awcache (axi_awcache),
        .s00_axi_awprot  (axi_awprot),
        .s00_axi_awqos   (axi_awqos),
        .s00_axi_awuser  (1'b0),
        .s00_axi_awvalid (axi_awvalid),
        .s00_axi_awready (axi_awready),
        .s00_axi_wdata   (axi_wdata),
        .s00_axi_wstrb   (axi_wstrb),
        .s00_axi_wlast   (axi_wlast),
        .s00_axi_wuser   (1'b0),
        .s00_axi_wvalid  (axi_wvalid),
        .s00_axi_wready  (axi_wready),
        .s00_axi_bid     (axi_bid),
        .s00_axi_bresp   (axi_bresp),
        .s00_axi_buser   (),
        .s00_axi_bvalid  (axi_bvalid),
        .s00_axi_bready  (axi_bready),
        .s00_axi_arid    (axi_arid),
        .s00_axi_araddr  (axi_araddr),
        .s00_axi_arlen   (axi_arlen),
        .s00_axi_arsize  (axi_arsize),
        .s00_axi_arburst (axi_arburst),
        .s00_axi_arlock  (axi_arlock),
        .s00_axi_arcache (axi_arcache),
        .s00_axi_arprot  (axi_arprot),
        .s00_axi_arqos   (axi_arqos),
        .s00_axi_aruser  (1'b0),
        .s00_axi_arvalid (axi_arvalid),
        .s00_axi_arready (axi_arready),
        .s00_axi_rid     (axi_rid),
        .s00_axi_rdata   (axi_rdata),
        .s00_axi_rresp   (axi_rresp),
        .s00_axi_rlast   (axi_rlast),
        .s00_axi_ruser   (),
        .s00_axi_rvalid  (axi_rvalid),
        .s00_axi_rready  (axi_rready),

        // Master 1 (idle)
        .s01_axi_awid    (8'h0),
        .s01_axi_awaddr  (32'h0),
        .s01_axi_awlen   (8'h0),
        .s01_axi_awsize  (3'h3),
        .s01_axi_awburst (2'h1),
        .s01_axi_awlock  (1'b0),
        .s01_axi_awcache (4'h0),
        .s01_axi_awprot  (3'h0),
        .s01_axi_awqos   (4'h0),
        .s01_axi_awuser  (1'b0),
        .s01_axi_awvalid (1'b0),
        .s01_axi_awready (),
        .s01_axi_wdata   (64'h0),
        .s01_axi_wstrb   (8'h0),
        .s01_axi_wlast   (1'b0),
        .s01_axi_wuser   (1'b0),
        .s01_axi_wvalid  (1'b0),
        .s01_axi_wready  (),
        .s01_axi_bid     (),
        .s01_axi_bresp   (),
        .s01_axi_buser   (),
        .s01_axi_bvalid  (),
        .s01_axi_bready  (1'b0),
        .s01_axi_arid    (8'h0),
        .s01_axi_araddr  (32'h0),
        .s01_axi_arlen   (8'h0),
        .s01_axi_arsize  (3'h3),
        .s01_axi_arburst (2'h1),
        .s01_axi_arlock  (1'b0),
        .s01_axi_arcache (4'h0),
        .s01_axi_arprot  (3'h0),
        .s01_axi_arqos   (4'h0),
        .s01_axi_aruser  (1'b0),
        .s01_axi_arvalid (1'b0),
        .s01_axi_arready (),
        .s01_axi_rid     (),
        .s01_axi_rdata   (),
        .s01_axi_rresp   (),
        .s01_axi_rlast   (),
        .s01_axi_ruser   (),
        .s01_axi_rvalid  (),
        .s01_axi_rready  (1'b0),

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
    // Peripheral Stubs (S0, S1, S2, S6)
    // ========================================================================
    assign wbs0_dat_i = 32'd0;
    assign wbs0_ack   = wbs0_stb & wbs0_cyc;

    assign wbs1_dat_i = 32'd0;
    assign wbs1_ack   = wbs1_stb & wbs1_cyc;

    assign wbs2_dat_i = {30'd0, reset_out_w, heartbeat_in};
    assign wbs2_ack   = wbs2_stb & wbs2_cyc;

    assign wbs6_dat_i = 32'd0;
    assign wbs6_ack   = wbs6_stb & wbs6_cyc;

    // Heartbeat Monitor
    heartbeat_monitor u_hbm (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs3_adr), .wb_dat_i(wbs3_dat_o), .wb_dat_o(wbs3_dat_i),
        .wb_we_i(wbs3_we), .wb_sel_i(wbs3_sel),
        .wb_stb_i(wbs3_stb), .wb_cyc_i(wbs3_cyc), .wb_ack_o(wbs3_ack),
        .heartbeat_in(heartbeat_in), .hb_irq(hb_irq)
    );

    // Reset Sequencer
    reset_sequencer u_rst (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs4_adr), .wb_dat_i(wbs4_dat_o), .wb_dat_o(wbs4_dat_i),
        .wb_we_i(wbs4_we), .wb_sel_i(wbs4_sel),
        .wb_stb_i(wbs4_stb), .wb_cyc_i(wbs4_cyc), .wb_ack_o(wbs4_ack),
        .reset_out(reset_out_w)
    );

    // Recovery Policy
    recovery_policy u_pol (
        .wb_clk_i(clk), .wb_rst_i(wb_rst),
        .wb_adr_i(wbs5_adr), .wb_dat_i(wbs5_dat_o), .wb_dat_o(wbs5_dat_i),
        .wb_we_i(wbs5_we), .wb_sel_i(wbs5_sel),
        .wb_stb_i(wbs5_stb), .wb_cyc_i(wbs5_cyc), .wb_ack_o(wbs5_ack)
    );

    assign reset_out = reset_out_w;

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // AXI Bus Transaction Tasks
    // ========================================================================
    task axi_write(input [31:0] addr, input [31:0] data);
        reg aw_done, w_done;
        begin
            @(posedge clk);
            // Present address and data simultaneously
            axi_awid    <= 8'h01;
            axi_awaddr  <= addr;
            axi_awlen   <= 8'd0;
            axi_awsize  <= 3'd3;
            axi_awburst <= 2'b01;
            axi_awlock  <= 1'b0;
            axi_awcache <= 4'd0;
            axi_awprot  <= 3'd0;
            axi_awqos   <= 4'd0;
            axi_awvalid <= 1'b1;

            axi_wdata   <= addr[2] ? {data, 32'h0} : {32'h0, data};
            axi_wstrb   <= addr[2] ? 8'hF0 : 8'h0F;
            axi_wlast   <= 1'b1;
            axi_wvalid  <= 1'b1;
            axi_bready  <= 1'b1;

            aw_done = 0;
            w_done  = 0;
            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (axi_awvalid && axi_awready) begin
                    axi_awvalid <= 1'b0;
                    aw_done = 1;
                end
                if (axi_wvalid && axi_wready) begin
                    axi_wvalid <= 1'b0;
                    w_done = 1;
                end
            end

            // Wait for write response
            while (!axi_bvalid) @(posedge clk);
            @(posedge clk);
            axi_bready <= 1'b0;
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            axi_arid    <= 8'h02;
            axi_araddr  <= addr;
            axi_arlen   <= 8'd0;
            axi_arsize  <= 3'd3;
            axi_arburst <= 2'b01;
            axi_arlock  <= 1'b0;
            axi_arcache <= 4'd0;
            axi_arprot  <= 3'd0;
            axi_arqos   <= 4'd0;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;

            @(posedge clk);
            while (!axi_arready) @(posedge clk);
            axi_arvalid <= 1'b0;

            // Wait for read data
            while (!axi_rvalid) @(posedge clk);
            data = addr[2] ? axi_rdata[63:32] : axi_rdata[31:0];
            @(posedge clk);
            axi_rready <= 1'b0;
        end
    endtask

    // Convenience: write to peripheral register (base + offset)
    task periph_write(input [31:0] base, input [7:0] offset, input [31:0] data);
        axi_write(base + {24'd0, offset}, data);
    endtask

    task periph_read(input [31:0] base, input [7:0] offset, output [31:0] data);
        axi_read(base + {24'd0, offset}, data);
    endtask

    task check(input [31:0] expected, input [31:0] actual, input [255:0] msg);
        begin
            if (actual === expected) begin
                $display("  [PASS] %0s: expected=0x%08h, got=0x%08h", msg, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s: expected=0x%08h, got=0x%08h", msg, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task send_heartbeat;
        begin
            @(posedge clk);
            heartbeat_in <= 1'b1;
            @(posedge clk);
            heartbeat_in <= 1'b0;
        end
    endtask

    // ========================================================================
    // Test Stimulus — Full System Scenarios
    // ========================================================================
    initial begin
        $dumpfile("tb_soc_top.vcd");
        $dumpvars(0, tb_soc_top);
        if ($test$plusargs("fsdb")) begin
            $dumpfile("tb_soc_top.vcd");
            $dumpvars(0, tb_soc_top);
        end

        // Initialize all AXI signals
        rst_n        = 0;
        heartbeat_in = 0;
        uart_rx      = 1;
        axi_awaddr   = 0; axi_awprot  = 0; axi_awvalid = 0;
        axi_wdata    = 0; axi_wstrb   = 0; axi_wvalid  = 0;
        axi_bready   = 0;
        axi_araddr   = 0; axi_arprot  = 0; axi_arvalid = 0;
        axi_rready   = 0;
        pass_count   = 0;
        fail_count   = 0;

        // System reset
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ==================================================================
        // INIT: Configure all custom IPs (emulating firmware boot)
        // ==================================================================
        $display("\n=== INIT: Configuring Custom IPs ===");

        // Heartbeat Monitor: threshold = 40 cycles
        periph_write(HB_BASE, HB_THRESHOLD, 32'd40);
        periph_write(HB_BASE, HB_CTRL, 32'h0001);  // Enable

        // Reset Sequencer: hold = 20 cycles
        periph_write(RST_BASE, RST_HOLD_CYCLES, 32'd20);

        // Recovery Policy: window = 5000 cycles, threshold = 3
        periph_write(POL_BASE, POL_WINDOW, 32'd5000);
        periph_write(POL_BASE, POL_THRESHOLD, 32'd3);

        $display("  Configuration complete.");

        // ==================================================================
        // SCENARIO 1: Normal Heartbeat — system stays online
        // ==================================================================
        test_num = 1;
        $display("\n=== SCENARIO %0d: Normal Heartbeat ===", test_num);

        // Send initial heartbeat to start monitoring
        send_heartbeat;

        // Send heartbeats every 15 cycles (well under 40 threshold)
        repeat (6) begin
            repeat (15) @(posedge clk);
            send_heartbeat;
        end

        // Check: system should be online
        periph_read(HB_BASE, HB_STATUS, read_data);
        check(32'd0, read_data[0], "System ONLINE — no timeout");
        check(1'b1, reset_out, "reset_out stays HIGH (no reset issued)");

        // ==================================================================
        // SCENARIO 2: Single Freeze → Detection → Recovery → Log
        // ==================================================================
        test_num = 2;
        $display("\n=== SCENARIO %0d: Single Freeze-Recover Cycle ===", test_num);

        // Stop heartbeat — let it timeout
        repeat (60) @(posedge clk);

        // Check: unresponsive flag should be set
        periph_read(HB_BASE, HB_STATUS, read_data);
        check(1'b1, read_data[0], "Heartbeat timeout detected");

        // Emulate firmware: check policy lockout
        periph_read(POL_BASE, POL_STATUS, read_data);
        check(1'b0, read_data[0], "Not locked out — proceed with recovery");

        // Trigger reset sequence
        periph_write(RST_BASE, RST_CTRL, 32'h0001);
        $display("  Reset sequence triggered...");

        // Wait for reset to complete
        repeat (40) @(posedge clk);

        periph_read(RST_BASE, RST_STATUS, read_data);
        check(1'b1, read_data[1], "Reset sequence complete");

        // Record recovery event with timestamp
        periph_write(POL_BASE, POL_EVENT_TS, 32'h0000_1000);
        periph_write(POL_BASE, POL_CTRL, 32'h0001);  // record_event

        // Clear heartbeat flag
        periph_write(HB_BASE, HB_CTRL, 32'h0003);  // enable + clear_flag

        // Resume heartbeat (main system "recovered")
        send_heartbeat;

        // Verify log
        periph_read(POL_BASE, LOG_COUNT, read_data);
        check(32'd1, read_data, "1 event logged");

        $display("  Recovery cycle completed successfully.");

        // ==================================================================
        // SCENARIO 3: Repeated Freezes → Lockout
        // ==================================================================
        test_num = 3;
        $display("\n=== SCENARIO %0d: Repeated Freezes → Lockout ===", test_num);

        // 2nd freeze
        repeat (60) @(posedge clk);
        periph_read(HB_BASE, HB_STATUS, read_data);
        check(1'b1, read_data[0], "2nd timeout detected");
        periph_write(RST_BASE, RST_CTRL, 32'h0001);
        repeat (40) @(posedge clk);
        periph_write(POL_BASE, POL_EVENT_TS, 32'h0000_2000);
        periph_write(POL_BASE, POL_CTRL, 32'h0001);
        periph_write(HB_BASE, HB_CTRL, 32'h0003);
        send_heartbeat;

        periph_read(POL_BASE, POL_STATUS, read_data);
        check(1'b0, read_data[0], "Still not locked out after 2nd recovery");

        // 3rd freeze → should trigger lockout (threshold=3)
        repeat (60) @(posedge clk);
        periph_read(HB_BASE, HB_STATUS, read_data);
        check(1'b1, read_data[0], "3rd timeout detected");

        periph_write(RST_BASE, RST_CTRL, 32'h0001);
        repeat (40) @(posedge clk);
        periph_write(POL_BASE, POL_EVENT_TS, 32'h0000_3000);
        periph_write(POL_BASE, POL_CTRL, 32'h0001);

        periph_read(POL_BASE, POL_STATUS, read_data);
        check(1'b1, read_data[0], "LOCKOUT triggered after 3 recoveries");

        // 4th freeze — firmware should NOT trigger reset (emulate lockout check)
        periph_write(HB_BASE, HB_CTRL, 32'h0003);
        send_heartbeat;
        repeat (60) @(posedge clk);
        periph_read(HB_BASE, HB_STATUS, read_data);
        check(1'b1, read_data[0], "4th timeout detected");
        periph_read(POL_BASE, POL_STATUS, read_data);
        check(1'b1, read_data[0], "Lockout still active — no auto-recovery");

        $display("  Lockout prevents further auto-recovery. Correct!");

        // ==================================================================
        // SCENARIO 4: Manual Override — Clear Lockout
        // ==================================================================
        test_num = 4;
        $display("\n=== SCENARIO %0d: Manual Override ===", test_num);

        // Clear lockout (emulate "clear lockout" UART command)
        periph_write(POL_BASE, POL_CTRL, 32'h0002);  // clear_lockout
        repeat (5) @(posedge clk);

        periph_read(POL_BASE, POL_STATUS, read_data);
        check(1'b0, read_data[0], "Lockout cleared");

        // Force reset (emulate "force reset" UART command)
        periph_write(RST_BASE, RST_CTRL, 32'h0001);
        repeat (40) @(posedge clk);
        periph_read(RST_BASE, RST_STATUS, read_data);
        check(1'b1, read_data[1], "Manual force reset completed");

        // Clear HB flag and resume
        periph_write(HB_BASE, HB_CTRL, 32'h0003);
        send_heartbeat;

        // Verify event log has all entries
        periph_read(POL_BASE, LOG_COUNT, read_data);
        $display("  [INFO] Total events logged: %0d", read_data);

        // Read back log entries
        periph_write(POL_BASE, LOG_READ_IDX, 32'd0);
        periph_read(POL_BASE, LOG_READ_DATA, read_data);
        check(32'h0000_1000, read_data, "Log entry 0 timestamp");

        periph_write(POL_BASE, LOG_READ_IDX, 32'd1);
        periph_read(POL_BASE, LOG_READ_DATA, read_data);
        check(32'h0000_2000, read_data, "Log entry 1 timestamp");

        periph_write(POL_BASE, LOG_READ_IDX, 32'd2);
        periph_read(POL_BASE, LOG_READ_DATA, read_data);
        check(32'h0000_3000, read_data, "Log entry 2 timestamp");

        // ==================================================================
        // Summary
        // ==================================================================
        repeat (20) @(posedge clk);
        $display("\n========================================");
        $display("  SYSTEM TEST RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count > 0)
            $display("*** SOME TESTS FAILED ***");
        else
            $display("*** ALL SYSTEM TESTS PASSED ***");

        $finish;
    end

    // ========================================================================
    // Timeout watchdog — prevent infinite simulation
    // ========================================================================
    initial begin
        #500000;
        $display("\n*** TIMEOUT: Simulation exceeded maximum time ***");
        $finish;
    end

endmodule
