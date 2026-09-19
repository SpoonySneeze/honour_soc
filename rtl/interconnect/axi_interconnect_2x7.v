// ============================================================================
// AXI4 Interconnect (2 Masters x 7 Slaves)
// ============================================================================
// Direct 2-Master x 7-Slave crossbar interconnect designed for the BMC SoC:
//   - Master 0 (S00): VeeR EL2 Load/Store Unit (LSU) — 64-bit data, 32-bit addr
//   - Master 1 (S01): VeeR EL2 System Bus / Debug (SB) — 64-bit data, 32-bit addr
//
// 7 Dedicated 32-bit AXI-Lite Slave Ports:
//   - Slave 0 (M00): UART Peripheral            [0x0002_0000 - 0x0002_00FF]
//   - Slave 1 (M01): Timer Peripheral           [0x0002_0100 - 0x0002_01FF]
//   - Slave 2 (M02): GPIO Peripheral            [0x0002_0200 - 0x0002_02FF]
//   - Slave 3 (M03): Heartbeat Monitor (IP #1)  [0x0002_0300 - 0x0002_03FF]
//   - Slave 4 (M04): Reset Sequencer (IP #2)    [0x0002_0400 - 0x0002_04FF]
//   - Slave 5 (M05): Recovery Policy (IP #3)    [0x0002_0500 - 0x0002_05FF]
//   - Slave 6 (M06): VGA Controller (IP #4)     [0x0002_0600 - 0x0002_06FF]
//
// Features:
//   - Sub-4KB per-peripheral address decoding (addr[15:8] = 0x00 .. 0x06).
//   - Native 64-to-32 bit write data & strobe steering based on addr[2].
//   - 32-to-64 bit read data word replication across both 32-bit lanes.
//   - Independent Write and Read arbitration with round-robin priority.
//   - Full ID tag tracking and reflection (bid/rid mirror awid/arid).
//   - Unmapped address detection returning standard AXI SLVERR (2'b10).
// ============================================================================

`timescale 1ns / 1ps

module axi_interconnect_2x7 #(
    parameter DATA_WIDTH   = 64,       // Master data bus width
    parameter ADDR_WIDTH   = 32,       // System address bus width
    parameter STRB_WIDTH   = 8,        // Master strobe width (DATA_WIDTH/8)
    parameter S_ID_WIDTH   = 8,        // Master ID tag width
    parameter M_DATA_WIDTH = 32,       // Slave data bus width (AXI-Lite)
    parameter M_STRB_WIDTH = 4         // Slave strobe width (M_DATA_WIDTH/8)
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ========================================================================
    // Master 0 Interface (S00) — VeeR LSU (64-bit)
    // ========================================================================
    input  wire [S_ID_WIDTH-1:0]   s00_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s00_axi_awaddr,
    input  wire [7:0]              s00_axi_awlen,
    input  wire [2:0]              s00_axi_awsize,
    input  wire [1:0]              s00_axi_awburst,
    input  wire                    s00_axi_awlock,
    input  wire [3:0]              s00_axi_awcache,
    input  wire [2:0]              s00_axi_awprot,
    input  wire [3:0]              s00_axi_awqos,
    input  wire                    s00_axi_awvalid,
    output reg                     s00_axi_awready,
    input  wire [DATA_WIDTH-1:0]   s00_axi_wdata,
    input  wire [STRB_WIDTH-1:0]   s00_axi_wstrb,
    input  wire                    s00_axi_wlast,
    input  wire                    s00_axi_wvalid,
    output reg                     s00_axi_wready,
    output reg  [S_ID_WIDTH-1:0]   s00_axi_bid,
    output reg  [1:0]              s00_axi_bresp,
    output reg                     s00_axi_bvalid,
    input  wire                    s00_axi_bready,
    input  wire [S_ID_WIDTH-1:0]   s00_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s00_axi_araddr,
    input  wire [7:0]              s00_axi_arlen,
    input  wire [2:0]              s00_axi_arsize,
    input  wire [1:0]              s00_axi_arburst,
    input  wire                    s00_axi_arlock,
    input  wire [3:0]              s00_axi_arcache,
    input  wire [2:0]              s00_axi_arprot,
    input  wire [3:0]              s00_axi_arqos,
    input  wire                    s00_axi_arvalid,
    output reg                     s00_axi_arready,
    output reg  [S_ID_WIDTH-1:0]   s00_axi_rid,
    output reg  [DATA_WIDTH-1:0]   s00_axi_rdata,
    output reg  [1:0]              s00_axi_rresp,
    output reg                     s00_axi_rlast,
    output reg                     s00_axi_rvalid,
    input  wire                    s00_axi_rready,

    // ========================================================================
    // Master 1 Interface (S01) — VeeR System Bus / Debug (64-bit)
    // ========================================================================
    input  wire [S_ID_WIDTH-1:0]   s01_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s01_axi_awaddr,
    input  wire [7:0]              s01_axi_awlen,
    input  wire [2:0]              s01_axi_awsize,
    input  wire [1:0]              s01_axi_awburst,
    input  wire                    s01_axi_awlock,
    input  wire [3:0]              s01_axi_awcache,
    input  wire [2:0]              s01_axi_awprot,
    input  wire [3:0]              s01_axi_awqos,
    input  wire                    s01_axi_awvalid,
    output reg                     s01_axi_awready,
    input  wire [DATA_WIDTH-1:0]   s01_axi_wdata,
    input  wire [STRB_WIDTH-1:0]   s01_axi_wstrb,
    input  wire                    s01_axi_wlast,
    input  wire                    s01_axi_wvalid,
    output reg                     s01_axi_wready,
    output reg  [S_ID_WIDTH-1:0]   s01_axi_bid,
    output reg  [1:0]              s01_axi_bresp,
    output reg                     s01_axi_bvalid,
    input  wire                    s01_axi_bready,
    input  wire [S_ID_WIDTH-1:0]   s01_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s01_axi_araddr,
    input  wire [7:0]              s01_axi_arlen,
    input  wire [2:0]              s01_axi_arsize,
    input  wire [1:0]              s01_axi_arburst,
    input  wire                    s01_axi_arlock,
    input  wire [3:0]              s01_axi_arcache,
    input  wire [2:0]              s01_axi_arprot,
    input  wire [3:0]              s01_axi_arqos,
    input  wire                    s01_axi_arvalid,
    output reg                     s01_axi_arready,
    output reg  [S_ID_WIDTH-1:0]   s01_axi_rid,
    output reg  [DATA_WIDTH-1:0]   s01_axi_rdata,
    output reg  [1:0]              s01_axi_rresp,
    output reg                     s01_axi_rlast,
    output reg                     s01_axi_rvalid,
    input  wire                    s01_axi_rready,

    // ========================================================================
    // Slave 0 (M00): UART [0x0002_0000 - 0x0002_00FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m00_axi_awaddr,
    output reg  [2:0]              m00_axi_awprot,
    output reg                     m00_axi_awvalid,
    input  wire                    m00_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m00_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m00_axi_wstrb,
    output reg                     m00_axi_wvalid,
    input  wire                    m00_axi_wready,
    input  wire [1:0]              m00_axi_bresp,
    input  wire                    m00_axi_bvalid,
    output reg                     m00_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m00_axi_araddr,
    output reg  [2:0]              m00_axi_arprot,
    output reg                     m00_axi_arvalid,
    input  wire                    m00_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m00_axi_rdata,
    input  wire [1:0]              m00_axi_rresp,
    input  wire                    m00_axi_rvalid,
    output reg                     m00_axi_rready,

    // ========================================================================
    // Slave 1 (M01): Timer [0x0002_0100 - 0x0002_01FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m01_axi_awaddr,
    output reg  [2:0]              m01_axi_awprot,
    output reg                     m01_axi_awvalid,
    input  wire                    m01_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m01_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m01_axi_wstrb,
    output reg                     m01_axi_wvalid,
    input  wire                    m01_axi_wready,
    input  wire [1:0]              m01_axi_bresp,
    input  wire                    m01_axi_bvalid,
    output reg                     m01_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m01_axi_araddr,
    output reg  [2:0]              m01_axi_arprot,
    output reg                     m01_axi_arvalid,
    input  wire                    m01_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m01_axi_rdata,
    input  wire [1:0]              m01_axi_rresp,
    input  wire                    m01_axi_rvalid,
    output reg                     m01_axi_rready,

    // ========================================================================
    // Slave 2 (M02): GPIO [0x0002_0200 - 0x0002_02FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m02_axi_awaddr,
    output reg  [2:0]              m02_axi_awprot,
    output reg                     m02_axi_awvalid,
    input  wire                    m02_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m02_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m02_axi_wstrb,
    output reg                     m02_axi_wvalid,
    input  wire                    m02_axi_wready,
    input  wire [1:0]              m02_axi_bresp,
    input  wire                    m02_axi_bvalid,
    output reg                     m02_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m02_axi_araddr,
    output reg  [2:0]              m02_axi_arprot,
    output reg                     m02_axi_arvalid,
    input  wire                    m02_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m02_axi_rdata,
    input  wire [1:0]              m02_axi_rresp,
    input  wire                    m02_axi_rvalid,
    output reg                     m02_axi_rready,

    // ========================================================================
    // Slave 3 (M03): Heartbeat Monitor [0x0002_0300 - 0x0002_03FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m03_axi_awaddr,
    output reg  [2:0]              m03_axi_awprot,
    output reg                     m03_axi_awvalid,
    input  wire                    m03_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m03_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m03_axi_wstrb,
    output reg                     m03_axi_wvalid,
    input  wire                    m03_axi_wready,
    input  wire [1:0]              m03_axi_bresp,
    input  wire                    m03_axi_bvalid,
    output reg                     m03_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m03_axi_araddr,
    output reg  [2:0]              m03_axi_arprot,
    output reg                     m03_axi_arvalid,
    input  wire                    m03_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m03_axi_rdata,
    input  wire [1:0]              m03_axi_rresp,
    input  wire                    m03_axi_rvalid,
    output reg                     m03_axi_rready,

    // ========================================================================
    // Slave 4 (M04): Power/Reset Sequencer [0x0002_0400 - 0x0002_04FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m04_axi_awaddr,
    output reg  [2:0]              m04_axi_awprot,
    output reg                     m04_axi_awvalid,
    input  wire                    m04_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m04_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m04_axi_wstrb,
    output reg                     m04_axi_wvalid,
    input  wire                    m04_axi_wready,
    input  wire [1:0]              m04_axi_bresp,
    input  wire                    m04_axi_bvalid,
    output reg                     m04_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m04_axi_araddr,
    output reg  [2:0]              m04_axi_arprot,
    output reg                     m04_axi_arvalid,
    input  wire                    m04_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m04_axi_rdata,
    input  wire [1:0]              m04_axi_rresp,
    input  wire                    m04_axi_rvalid,
    output reg                     m04_axi_rready,

    // ========================================================================
    // Slave 5 (M05): Recovery Policy & Event Log [0x0002_0500 - 0x0002_05FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m05_axi_awaddr,
    output reg  [2:0]              m05_axi_awprot,
    output reg                     m05_axi_awvalid,
    input  wire                    m05_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m05_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m05_axi_wstrb,
    output reg                     m05_axi_wvalid,
    input  wire                    m05_axi_wready,
    input  wire [1:0]              m05_axi_bresp,
    input  wire                    m05_axi_bvalid,
    output reg                     m05_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m05_axi_araddr,
    output reg  [2:0]              m05_axi_arprot,
    output reg                     m05_axi_arvalid,
    input  wire                    m05_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m05_axi_rdata,
    input  wire [1:0]              m05_axi_rresp,
    input  wire                    m05_axi_rvalid,
    output reg                     m05_axi_rready,

    // ========================================================================
    // Slave 6 (M06): VGA Status Dashboard [0x0002_0600 - 0x0002_06FF]
    // ========================================================================
    output reg  [ADDR_WIDTH-1:0]   m06_axi_awaddr,
    output reg  [2:0]              m06_axi_awprot,
    output reg                     m06_axi_awvalid,
    input  wire                    m06_axi_awready,
    output reg  [M_DATA_WIDTH-1:0] m06_axi_wdata,
    output reg  [M_STRB_WIDTH-1:0] m06_axi_wstrb,
    output reg                     m06_axi_wvalid,
    input  wire                    m06_axi_wready,
    input  wire [1:0]              m06_axi_bresp,
    input  wire                    m06_axi_bvalid,
    output reg                     m06_axi_bready,
    output reg  [ADDR_WIDTH-1:0]   m06_axi_araddr,
    output reg  [2:0]              m06_axi_arprot,
    output reg                     m06_axi_arvalid,
    input  wire                    m06_axi_arready,
    input  wire [M_DATA_WIDTH-1:0] m06_axi_rdata,
    input  wire [1:0]              m06_axi_rresp,
    input  wire                    m06_axi_rvalid,
    output reg                     m06_axi_rready
);

    // ========================================================================
    // Address Decoding Function
    // ========================================================================
    // Base address: 0x0002_XX00
    //   0x00: Slave 0 (UART)
    //   0x01: Slave 1 (Timer)
    //   0x02: Slave 2 (GPIO)
    //   0x03: Slave 3 (Heartbeat Monitor)
    //   0x04: Slave 4 (Reset Sequencer)
    //   0x05: Slave 5 (Recovery Policy)
    //   0x06: Slave 6 (VGA Controller)
    //   Other: Slave 7 (Unmapped / Decode Error -> SLVERR 2'b10)
    // ========================================================================
    function [3:0] decode_slave(input [ADDR_WIDTH-1:0] addr);
        begin
            if (addr[31:16] == 16'h0002) begin
                case (addr[15:8])
                    8'h00: decode_slave = 4'd0;
                    8'h01: decode_slave = 4'd1;
                    8'h02: decode_slave = 4'd2;
                    8'h03: decode_slave = 4'd3;
                    8'h04: decode_slave = 4'd4;
                    8'h05: decode_slave = 4'd5;
                    8'h06: decode_slave = 4'd6;
                    default: decode_slave = 4'd7; // Unmapped
                endcase
            end else begin
                decode_slave = 4'd7; // Unmapped
            end
        end
    endfunction

    // ========================================================================
    // WRITE CHANNEL ARBITRATION & ROUTING FSM
    // ========================================================================
    localparam [1:0] W_IDLE = 2'd0,
                     W_XFER = 2'd1,
                     W_RESP = 2'd2,
                     W_ERR  = 2'd3;

    reg [1:0]            wr_state;
    reg                  wr_master;       // 0: S00, 1: S01
    reg                  wr_last_grant;   // Round-robin arbitration memory
    reg [3:0]            wr_slave;        // Decoded target slave (0..6 mapped, 7 unmapped)
    reg [S_ID_WIDTH-1:0] wr_id;           // Latched master ID
    reg [ADDR_WIDTH-1:0] wr_addr;         // Latched address
    reg [2:0]            wr_prot;         // Latched protection
    reg                  wr_aw_done;      // AW handshake completed
    reg                  wr_w_done;       // W handshake completed

    // Multiplexed Slave Write Response Inputs
    reg                  current_m_awready;
    reg                  current_m_wready;
    reg                  current_m_bvalid;
    reg [1:0]            current_m_bresp;

    always @(*) begin
        case (wr_slave)
            4'd0: begin
                current_m_awready = m00_axi_awready;
                current_m_wready  = m00_axi_wready;
                current_m_bvalid  = m00_axi_bvalid;
                current_m_bresp   = m00_axi_bresp;
            end
            4'd1: begin
                current_m_awready = m01_axi_awready;
                current_m_wready  = m01_axi_wready;
                current_m_bvalid  = m01_axi_bvalid;
                current_m_bresp   = m01_axi_bresp;
            end
            4'd2: begin
                current_m_awready = m02_axi_awready;
                current_m_wready  = m02_axi_wready;
                current_m_bvalid  = m02_axi_bvalid;
                current_m_bresp   = m02_axi_bresp;
            end
            4'd3: begin
                current_m_awready = m03_axi_awready;
                current_m_wready  = m03_axi_wready;
                current_m_bvalid  = m03_axi_bvalid;
                current_m_bresp   = m03_axi_bresp;
            end
            4'd4: begin
                current_m_awready = m04_axi_awready;
                current_m_wready  = m04_axi_wready;
                current_m_bvalid  = m04_axi_bvalid;
                current_m_bresp   = m04_axi_bresp;
            end
            4'd5: begin
                current_m_awready = m05_axi_awready;
                current_m_wready  = m05_axi_wready;
                current_m_bvalid  = m05_axi_bvalid;
                current_m_bresp   = m05_axi_bresp;
            end
            4'd6: begin
                current_m_awready = m06_axi_awready;
                current_m_wready  = m06_axi_wready;
                current_m_bvalid  = m06_axi_bvalid;
                current_m_bresp   = m06_axi_bresp;
            end
            default: begin
                current_m_awready = 1'b0;
                current_m_wready  = 1'b0;
                current_m_bvalid  = 1'b0;
                current_m_bresp   = 2'b10; // SLVERR
            end
        endcase
    end

    // 64-to-32 bit Write Data & Strobe Steering based on addr[2]
    wire [DATA_WIDTH-1:0] active_wdata = (wr_master == 1'b0) ? s00_axi_wdata : s01_axi_wdata;
    wire [STRB_WIDTH-1:0] active_wstrb = (wr_master == 1'b0) ? s00_axi_wstrb : s01_axi_wstrb;
    wire                  active_wvalid = (wr_master == 1'b0) ? s00_axi_wvalid : s01_axi_wvalid;
    wire                  active_awvalid = (wr_master == 1'b0) ? s00_axi_awvalid : s01_axi_awvalid;
    wire                  active_bready = (wr_master == 1'b0) ? s00_axi_bready : s01_axi_bready;

    wire [M_DATA_WIDTH-1:0] steered_wdata = (wr_addr[2] == 1'b1) ? active_wdata[63:32] : active_wdata[31:0];
    wire [M_STRB_WIDTH-1:0] steered_wstrb = (wr_addr[2] == 1'b1) ? active_wstrb[7:4]   : active_wstrb[3:0];

    // Write Sequential FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= W_IDLE;
            wr_master     <= 1'b0;
            wr_last_grant <= 1'b0;
            wr_slave      <= 4'd0;
            wr_id         <= {S_ID_WIDTH{1'b0}};
            wr_addr       <= {ADDR_WIDTH{1'b0}};
            wr_prot       <= 3'd0;
            wr_aw_done    <= 1'b0;
            wr_w_done     <= 1'b0;
        end else begin
            case (wr_state)
                W_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done  <= 1'b0;
                    if (s00_axi_awvalid || s01_axi_awvalid) begin
                        reg sel_m;
                        // Round-robin arbitration
                        if (s00_axi_awvalid && s01_axi_awvalid)
                            sel_m = ~wr_last_grant;
                        else if (s00_axi_awvalid)
                            sel_m = 1'b0;
                        else
                            sel_m = 1'b1;

                        wr_master     <= sel_m;
                        wr_last_grant <= sel_m;
                        wr_id         <= (sel_m == 1'b0) ? s00_axi_awid    : s01_axi_awid;
                        wr_addr       <= (sel_m == 1'b0) ? s00_axi_awaddr  : s01_axi_awaddr;
                        wr_prot       <= (sel_m == 1'b0) ? s00_axi_awprot  : s01_axi_awprot;
                        wr_slave      <= decode_slave((sel_m == 1'b0) ? s00_axi_awaddr : s01_axi_awaddr);

                        if (decode_slave((sel_m == 1'b0) ? s00_axi_awaddr : s01_axi_awaddr) == 4'd7)
                            wr_state <= W_ERR;
                        else
                            wr_state <= W_XFER;
                    end
                end

                W_XFER: begin
                    // Address channel handshake
                    if (!wr_aw_done && active_awvalid && current_m_awready)
                        wr_aw_done <= 1'b1;

                    // Data channel handshake
                    if (!wr_w_done && active_wvalid && current_m_wready)
                        wr_w_done <= 1'b1;

                    // Transition to response wait when both handshakes complete
                    if ((wr_aw_done || (active_awvalid && current_m_awready)) &&
                        (wr_w_done  || (active_wvalid  && current_m_wready))) begin
                        wr_state <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (current_m_bvalid && active_bready) begin
                        wr_state <= W_IDLE;
                    end
                end

                W_ERR: begin
                    // Handle unmapped address error
                    if (!wr_aw_done && active_awvalid)
                        wr_aw_done <= 1'b1;
                    if (!wr_w_done && active_wvalid)
                        wr_w_done <= 1'b1;

                    if ((wr_aw_done || active_awvalid) && (wr_w_done || active_wvalid)) begin
                        if (active_bready)
                            wr_state <= W_IDLE;
                    end
                end

                default: wr_state <= W_IDLE;
            endcase
        end
    end

    // Drive Master Write Handshake Outputs
    always @(*) begin
        s00_axi_awready = 1'b0;
        s00_axi_wready  = 1'b0;
        s00_axi_bid     = wr_id;
        s00_axi_bresp   = 2'b00;
        s00_axi_bvalid  = 1'b0;

        s01_axi_awready = 1'b0;
        s01_axi_wready  = 1'b0;
        s01_axi_bid     = wr_id;
        s01_axi_bresp   = 2'b00;
        s01_axi_bvalid  = 1'b0;

        case (wr_state)
            W_XFER: begin
                if (wr_master == 1'b0) begin
                    s00_axi_awready = !wr_aw_done & current_m_awready;
                    s00_axi_wready  = !wr_w_done  & current_m_wready;
                end else begin
                    s01_axi_awready = !wr_aw_done & current_m_awready;
                    s01_axi_wready  = !wr_w_done  & current_m_wready;
                end
            end

            W_RESP: begin
                if (wr_master == 1'b0) begin
                    s00_axi_bvalid = current_m_bvalid;
                    s00_axi_bresp  = current_m_bresp;
                    s00_axi_bid    = wr_id;
                end else begin
                    s01_axi_bvalid = current_m_bvalid;
                    s01_axi_bresp  = current_m_bresp;
                    s01_axi_bid    = wr_id;
                end
            end

            W_ERR: begin
                if (wr_master == 1'b0) begin
                    s00_axi_awready = !wr_aw_done;
                    s00_axi_wready  = !wr_w_done;
                    s00_axi_bresp   = 2'b10; // SLVERR
                    s00_axi_bid     = wr_id;
                    s00_axi_bvalid  = wr_aw_done & wr_w_done;
                end else begin
                    s01_axi_awready = !wr_aw_done;
                    s01_axi_wready  = !wr_w_done;
                    s01_axi_bresp   = 2'b10; // SLVERR
                    s01_axi_bid     = wr_id;
                    s01_axi_bvalid  = wr_aw_done & wr_w_done;
                end
            end

            default: ;
        endcase
    end

    // Drive Slave Write Bus Outputs
    always @(*) begin
        // Defaults: all slave write outputs inactive
        m00_axi_awaddr  = wr_addr;
        m00_axi_awprot  = wr_prot;
        m00_axi_awvalid = 1'b0;
        m00_axi_wdata   = steered_wdata;
        m00_axi_wstrb   = steered_wstrb;
        m00_axi_wvalid  = 1'b0;
        m00_axi_bready  = 1'b0;

        m01_axi_awaddr  = wr_addr;
        m01_axi_awprot  = wr_prot;
        m01_axi_awvalid = 1'b0;
        m01_axi_wdata   = steered_wdata;
        m01_axi_wstrb   = steered_wstrb;
        m01_axi_wvalid  = 1'b0;
        m01_axi_bready  = 1'b0;

        m02_axi_awaddr  = wr_addr;
        m02_axi_awprot  = wr_prot;
        m02_axi_awvalid = 1'b0;
        m02_axi_wdata   = steered_wdata;
        m02_axi_wstrb   = steered_wstrb;
        m02_axi_wvalid  = 1'b0;
        m02_axi_bready  = 1'b0;

        m03_axi_awaddr  = wr_addr;
        m03_axi_awprot  = wr_prot;
        m03_axi_awvalid = 1'b0;
        m03_axi_wdata   = steered_wdata;
        m03_axi_wstrb   = steered_wstrb;
        m03_axi_wvalid  = 1'b0;
        m03_axi_bready  = 1'b0;

        m04_axi_awaddr  = wr_addr;
        m04_axi_awprot  = wr_prot;
        m04_axi_awvalid = 1'b0;
        m04_axi_wdata   = steered_wdata;
        m04_axi_wstrb   = steered_wstrb;
        m04_axi_wvalid  = 1'b0;
        m04_axi_bready  = 1'b0;

        m05_axi_awaddr  = wr_addr;
        m05_axi_awprot  = wr_prot;
        m05_axi_awvalid = 1'b0;
        m05_axi_wdata   = steered_wdata;
        m05_axi_wstrb   = steered_wstrb;
        m05_axi_wvalid  = 1'b0;
        m05_axi_bready  = 1'b0;

        m06_axi_awaddr  = wr_addr;
        m06_axi_awprot  = wr_prot;
        m06_axi_awvalid = 1'b0;
        m06_axi_wdata   = steered_wdata;
        m06_axi_wstrb   = steered_wstrb;
        m06_axi_wvalid  = 1'b0;
        m06_axi_bready  = 1'b0;

        if (wr_state == W_XFER) begin
            case (wr_slave)
                4'd0: begin
                    m00_axi_awvalid = !wr_aw_done & active_awvalid;
                    m00_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                4'd1: begin
                    m01_axi_awvalid = !wr_aw_done & active_awvalid;
                    m01_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                4'd2: begin
                    m02_axi_awvalid = !wr_aw_done & active_awvalid;
                    m02_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                4'd3: begin
                    m03_axi_awvalid = !wr_aw_done & active_awvalid;
                    m03_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                4'd4: begin
                    m04_axi_awvalid = !wr_aw_done & active_awvalid;
                    m04_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                4'd5: begin
                    m05_axi_awvalid = !wr_aw_done & active_awvalid;
                    m05_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                4'd6: begin
                    m06_axi_awvalid = !wr_aw_done & active_awvalid;
                    m06_axi_wvalid  = !wr_w_done  & active_wvalid;
                end
                default: ;
            endcase
        end else if (wr_state == W_RESP) begin
            case (wr_slave)
                4'd0: m00_axi_bready = active_bready;
                4'd1: m01_axi_bready = active_bready;
                4'd2: m02_axi_bready = active_bready;
                4'd3: m03_axi_bready = active_bready;
                4'd4: m04_axi_bready = active_bready;
                4'd5: m05_axi_bready = active_bready;
                4'd6: m06_axi_bready = active_bready;
                default: ;
            endcase
        end
    end

    // ========================================================================
    // READ CHANNEL ARBITRATION & ROUTING FSM
    // ========================================================================
    localparam [1:0] R_IDLE = 2'd0,
                     R_XFER = 2'd1,
                     R_ERR  = 2'd2;

    reg [1:0]            rd_state;
    reg                  rd_master;       // 0: S00, 1: S01
    reg                  rd_last_grant;   // Round-robin arbitration memory
    reg [3:0]            rd_slave;        // Decoded target slave (0..6 mapped, 7 unmapped)
    reg [S_ID_WIDTH-1:0] rd_id;           // Latched master ID
    reg [ADDR_WIDTH-1:0] rd_addr;         // Latched address
    reg [2:0]            rd_prot;         // Latched protection
    reg                  rd_ar_done;      // AR handshake completed

    // Multiplexed Slave Read Data Inputs
    reg                  current_m_arready;
    reg [M_DATA_WIDTH-1:0] current_m_rdata;
    reg [1:0]            current_m_rresp;
    reg                  current_m_rvalid;

    always @(*) begin
        case (rd_slave)
            4'd0: begin
                current_m_arready = m00_axi_arready;
                current_m_rdata   = m00_axi_rdata;
                current_m_rresp   = m00_axi_rresp;
                current_m_rvalid  = m00_axi_rvalid;
            end
            4'd1: begin
                current_m_arready = m01_axi_arready;
                current_m_rdata   = m01_axi_rdata;
                current_m_rresp   = m01_axi_rresp;
                current_m_rvalid  = m01_axi_rvalid;
            end
            4'd2: begin
                current_m_arready = m02_axi_arready;
                current_m_rdata   = m02_axi_rdata;
                current_m_rresp   = m02_axi_rresp;
                current_m_rvalid  = m02_axi_rvalid;
            end
            4'd3: begin
                current_m_arready = m03_axi_arready;
                current_m_rdata   = m03_axi_rdata;
                current_m_rresp   = m03_axi_rresp;
                current_m_rvalid  = m03_axi_rvalid;
            end
            4'd4: begin
                current_m_arready = m04_axi_arready;
                current_m_rdata   = m04_axi_rdata;
                current_m_rresp   = m04_axi_rresp;
                current_m_rvalid  = m04_axi_rvalid;
            end
            4'd5: begin
                current_m_arready = m05_axi_arready;
                current_m_rdata   = m05_axi_rdata;
                current_m_rresp   = m05_axi_rresp;
                current_m_rvalid  = m05_axi_rvalid;
            end
            4'd6: begin
                current_m_arready = m06_axi_arready;
                current_m_rdata   = m06_axi_rdata;
                current_m_rresp   = m06_axi_rresp;
                current_m_rvalid  = m06_axi_rvalid;
            end
            default: begin
                current_m_arready = 1'b0;
                current_m_rdata   = {M_DATA_WIDTH{1'b0}};
                current_m_rresp   = 2'b10; // SLVERR
                current_m_rvalid  = 1'b0;
            end
        endcase
    end

    wire active_arvalid = (rd_master == 1'b0) ? s00_axi_arvalid : s01_axi_arvalid;
    wire active_rready  = (rd_master == 1'b0) ? s00_axi_rready  : s01_axi_rready;

    // Read Sequential FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= R_IDLE;
            rd_master     <= 1'b0;
            rd_last_grant <= 1'b0;
            rd_slave      <= 4'd0;
            rd_id         <= {S_ID_WIDTH{1'b0}};
            rd_addr       <= {ADDR_WIDTH{1'b0}};
            rd_prot       <= 3'd0;
            rd_ar_done    <= 1'b0;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    rd_ar_done <= 1'b0;
                    if (s00_axi_arvalid || s01_axi_arvalid) begin
                        reg sel_m;
                        // Round-robin arbitration
                        if (s00_axi_arvalid && s01_axi_arvalid)
                            sel_m = ~rd_last_grant;
                        else if (s00_axi_arvalid)
                            sel_m = 1'b0;
                        else
                            sel_m = 1'b1;

                        rd_master     <= sel_m;
                        rd_last_grant <= sel_m;
                        rd_id         <= (sel_m == 1'b0) ? s00_axi_arid    : s01_axi_arid;
                        rd_addr       <= (sel_m == 1'b0) ? s00_axi_araddr  : s01_axi_araddr;
                        rd_prot       <= (sel_m == 1'b0) ? s00_axi_arprot  : s01_axi_arprot;
                        rd_slave      <= decode_slave((sel_m == 1'b0) ? s00_axi_araddr : s01_axi_araddr);

                        if (decode_slave((sel_m == 1'b0) ? s00_axi_araddr : s01_axi_araddr) == 4'd7)
                            rd_state <= R_ERR;
                        else
                            rd_state <= R_XFER;
                    end
                end

                R_XFER: begin
                    // Address handshake
                    if (!rd_ar_done && active_arvalid && current_m_arready)
                        rd_ar_done <= 1'b1;

                    // Data handshake
                    if (current_m_rvalid && active_rready) begin
                        rd_state <= R_IDLE;
                    end
                end

                R_ERR: begin
                    if (!rd_ar_done && active_arvalid)
                        rd_ar_done <= 1'b1;

                    if (rd_ar_done && active_rready) begin
                        rd_state <= R_IDLE;
                    end
                end

                default: rd_state <= R_IDLE;
            endcase
        end
    end

    // Drive Master Read Handshake & Data Outputs
    always @(*) begin
        s00_axi_arready = 1'b0;
        s00_axi_rvalid  = 1'b0;
        s00_axi_rdata   = {current_m_rdata, current_m_rdata}; // 32-to-64 bit word replication
        s00_axi_rresp   = 2'b00;
        s00_axi_rid     = rd_id;
        s00_axi_rlast   = 1'b1;

        s01_axi_arready = 1'b0;
        s01_axi_rvalid  = 1'b0;
        s01_axi_rdata   = {current_m_rdata, current_m_rdata}; // 32-to-64 bit word replication
        s01_axi_rresp   = 2'b00;
        s01_axi_rid     = rd_id;
        s01_axi_rlast   = 1'b1;

        case (rd_state)
            R_XFER: begin
                if (rd_master == 1'b0) begin
                    s00_axi_arready = !rd_ar_done & current_m_arready;
                    s00_axi_rvalid  = current_m_rvalid;
                    s00_axi_rdata   = {current_m_rdata, current_m_rdata};
                    s00_axi_rresp   = current_m_rresp;
                    s00_axi_rid     = rd_id;
                    s00_axi_rlast   = 1'b1;
                end else begin
                    s01_axi_arready = !rd_ar_done & current_m_arready;
                    s01_axi_rvalid  = current_m_rvalid;
                    s01_axi_rdata   = {current_m_rdata, current_m_rdata};
                    s01_axi_rresp   = current_m_rresp;
                    s01_axi_rid     = rd_id;
                    s01_axi_rlast   = 1'b1;
                end
            end

            R_ERR: begin
                if (rd_master == 1'b0) begin
                    s00_axi_arready = !rd_ar_done;
                    s00_axi_rvalid  = rd_ar_done;
                    s00_axi_rdata   = {DATA_WIDTH{1'b0}};
                    s00_axi_rresp   = 2'b10; // SLVERR
                    s00_axi_rid     = rd_id;
                    s00_axi_rlast   = 1'b1;
                end else begin
                    s01_axi_arready = !rd_ar_done;
                    s01_axi_rvalid  = rd_ar_done;
                    s01_axi_rdata   = {DATA_WIDTH{1'b0}};
                    s01_axi_rresp   = 2'b10; // SLVERR
                    s01_axi_rid     = rd_id;
                    s01_axi_rlast   = 1'b1;
                end
            end

            default: ;
        endcase
    end

    // Drive Slave Read Bus Outputs
    always @(*) begin
        m00_axi_araddr  = rd_addr;
        m00_axi_arprot  = rd_prot;
        m00_axi_arvalid = 1'b0;
        m00_axi_rready  = 1'b0;

        m01_axi_araddr  = rd_addr;
        m01_axi_arprot  = rd_prot;
        m01_axi_arvalid = 1'b0;
        m01_axi_rready  = 1'b0;

        m02_axi_araddr  = rd_addr;
        m02_axi_arprot  = rd_prot;
        m02_axi_arvalid = 1'b0;
        m02_axi_rready  = 1'b0;

        m03_axi_araddr  = rd_addr;
        m03_axi_arprot  = rd_prot;
        m03_axi_arvalid = 1'b0;
        m03_axi_rready  = 1'b0;

        m04_axi_araddr  = rd_addr;
        m04_axi_arprot  = rd_prot;
        m04_axi_arvalid = 1'b0;
        m04_axi_rready  = 1'b0;

        m05_axi_araddr  = rd_addr;
        m05_axi_arprot  = rd_prot;
        m05_axi_arvalid = 1'b0;
        m05_axi_rready  = 1'b0;

        m06_axi_araddr  = rd_addr;
        m06_axi_arprot  = rd_prot;
        m06_axi_arvalid = 1'b0;
        m06_axi_rready  = 1'b0;

        if (rd_state == R_XFER) begin
            case (rd_slave)
                4'd0: begin
                    m00_axi_arvalid = !rd_ar_done & active_arvalid;
                    m00_axi_rready  = active_rready;
                end
                4'd1: begin
                    m01_axi_arvalid = !rd_ar_done & active_arvalid;
                    m01_axi_rready  = active_rready;
                end
                4'd2: begin
                    m02_axi_arvalid = !rd_ar_done & active_arvalid;
                    m02_axi_rready  = active_rready;
                end
                4'd3: begin
                    m03_axi_arvalid = !rd_ar_done & active_arvalid;
                    m03_axi_rready  = active_rready;
                end
                4'd4: begin
                    m04_axi_arvalid = !rd_ar_done & active_arvalid;
                    m04_axi_rready  = active_rready;
                end
                4'd5: begin
                    m05_axi_arvalid = !rd_ar_done & active_arvalid;
                    m05_axi_rready  = active_rready;
                end
                4'd6: begin
                    m06_axi_arvalid = !rd_ar_done & active_arvalid;
                    m06_axi_rready  = active_rready;
                end
                default: ;
            endcase
        end
    end

endmodule
