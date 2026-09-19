// ============================================================================
// AXI4 to Wishbone B4 Bridge
// ============================================================================
// Translates AXI4 read/write transactions into Wishbone B4 single-cycle
// bus transactions. Supports:
//   - Parameterized AXI data width (32-bit or 64-bit for VeeR EL2)
//   - 64-bit to 32-bit data steering on writes (based on addr[2])
//   - Read data replication to both 32-bit words for 64-bit buses
//   - AXI transaction ID latching & reflection on bid and rid
//   - Proper rlast assertion on read completion
//   - Wishbone error mapping to AXI SLVERR response
//
// AXI4 slave side ← VeeR EL2 / AXI Interconnect
// Wishbone B4 master side → Wishbone peripheral bus
// ============================================================================

module axi4_to_wb_bridge #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 64,     // 64-bit from VeeR / AXI Interconnect
    parameter AXI_ID_WIDTH   = 9,      // Matches M_ID_WIDTH of interconnect
    parameter WB_ADDR_WIDTH  = 32,
    parameter WB_DATA_WIDTH  = 32      // 32-bit to Wishbone peripherals
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // ---- AXI4 Slave Interface ----

    // Write Address Channel
    input  wire [AXI_ID_WIDTH-1:0]     s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]                  s_axi_awlen,
    input  wire [2:0]                  s_axi_awsize,
    input  wire [1:0]                  s_axi_awburst,
    input  wire [2:0]                  s_axi_awprot,
    input  wire                        s_axi_awvalid,
    output reg                         s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                        s_axi_wlast,
    input  wire                        s_axi_wvalid,
    output reg                         s_axi_wready,

    // Write Response Channel
    output reg  [AXI_ID_WIDTH-1:0]     s_axi_bid,
    output reg  [1:0]                  s_axi_bresp,
    output reg                         s_axi_bvalid,
    input  wire                        s_axi_bready,

    // Read Address Channel
    input  wire [AXI_ID_WIDTH-1:0]     s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]                  s_axi_arlen,
    input  wire [2:0]                  s_axi_arsize,
    input  wire [1:0]                  s_axi_arburst,
    input  wire [2:0]                  s_axi_arprot,
    input  wire                        s_axi_arvalid,
    output reg                         s_axi_arready,

    // Read Data Channel
    output reg  [AXI_ID_WIDTH-1:0]     s_axi_rid,
    output reg  [AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]                  s_axi_rresp,
    output reg                         s_axi_rlast,
    output reg                         s_axi_rvalid,
    input  wire                        s_axi_rready,

    // ---- Wishbone B4 Master Interface ----

    output reg  [WB_ADDR_WIDTH-1:0]    wb_adr_o,
    output reg  [WB_DATA_WIDTH-1:0]    wb_dat_o,
    input  wire [WB_DATA_WIDTH-1:0]    wb_dat_i,
    output reg                         wb_we_o,
    output reg  [WB_DATA_WIDTH/8-1:0]  wb_sel_o,
    output reg                         wb_stb_o,
    output reg                         wb_cyc_o,
    input  wire                        wb_ack_i,
    input  wire                        wb_err_i
);

    // ========================================================================
    // FSM States
    // ========================================================================
    localparam [2:0] ST_IDLE       = 3'd0,
                     ST_WR_DATA    = 3'd1, // Address received, waiting for data
                     ST_WR_ADDR    = 3'd2, // Data received, waiting for address
                     ST_WR_WB_CYC  = 3'd3, // Executing Wishbone write
                     ST_WR_RESPOND = 3'd4, // Returning AXI B response
                     ST_RD_WB_CYC  = 3'd5, // Executing Wishbone read
                     ST_RD_RESPOND = 3'd6; // Returning AXI R response

    reg [2:0] state, state_next;

    // Latched AXI transaction registers
    reg [AXI_ID_WIDTH-1:0]     axi_awid_r;
    reg [AXI_ADDR_WIDTH-1:0]   axi_awaddr_r;
    reg [AXI_ID_WIDTH-1:0]     axi_arid_r;
    reg [AXI_ADDR_WIDTH-1:0]   axi_araddr_r;
    reg [AXI_DATA_WIDTH-1:0]   axi_wdata_r;
    reg [AXI_DATA_WIDTH/8-1:0] axi_wstrb_r;
    reg [WB_DATA_WIDTH-1:0]    wb_rdata_r;
    reg                        wb_err_r;

    // ========================================================================
    // FSM — Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= state_next;
    end

    // ========================================================================
    // FSM — Next State Logic
    // ========================================================================
    always @(*) begin
        state_next = state;
        case (state)
            ST_IDLE: begin
                // Write has priority if both write and read arrive together
                if (s_axi_awvalid && s_axi_wvalid)
                    state_next = ST_WR_WB_CYC;
                else if (s_axi_awvalid)
                    state_next = ST_WR_DATA;
                else if (s_axi_wvalid)
                    state_next = ST_WR_ADDR;
                else if (s_axi_arvalid)
                    state_next = ST_RD_WB_CYC;
            end

            ST_WR_DATA: begin
                // Address already accepted; wait for data
                if (s_axi_wvalid)
                    state_next = ST_WR_WB_CYC;
            end

            ST_WR_ADDR: begin
                // Data already accepted; wait for address
                if (s_axi_awvalid)
                    state_next = ST_WR_WB_CYC;
            end

            ST_WR_WB_CYC: begin
                if (wb_ack_i || wb_err_i)
                    state_next = ST_WR_RESPOND;
            end

            ST_WR_RESPOND: begin
                if (s_axi_bready)
                    state_next = ST_IDLE;
            end

            ST_RD_WB_CYC: begin
                if (wb_ack_i || wb_err_i)
                    state_next = ST_RD_RESPOND;
            end

            ST_RD_RESPOND: begin
                if (s_axi_rready)
                    state_next = ST_IDLE;
            end

            default: state_next = ST_IDLE;
        endcase
    end

    // ========================================================================
    // Latch AXI Request Signals
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_awid_r   <= {AXI_ID_WIDTH{1'b0}};
            axi_awaddr_r <= {AXI_ADDR_WIDTH{1'b0}};
            axi_arid_r   <= {AXI_ID_WIDTH{1'b0}};
            axi_araddr_r <= {AXI_ADDR_WIDTH{1'b0}};
            axi_wdata_r  <= {AXI_DATA_WIDTH{1'b0}};
            axi_wstrb_r  <= {(AXI_DATA_WIDTH/8){1'b0}};
        end else begin
            // Latch write address
            if ((state == ST_IDLE || state == ST_WR_ADDR) && s_axi_awvalid) begin
                axi_awid_r   <= s_axi_awid;
                axi_awaddr_r <= s_axi_awaddr;
            end

            // Latch write data
            if ((state == ST_IDLE || state == ST_WR_DATA) && s_axi_wvalid) begin
                axi_wdata_r  <= s_axi_wdata;
                axi_wstrb_r  <= s_axi_wstrb;
            end

            // Latch read address
            if (state == ST_IDLE && !s_axi_awvalid && !s_axi_wvalid && s_axi_arvalid) begin
                axi_arid_r   <= s_axi_arid;
                axi_araddr_r <= s_axi_araddr;
            end
        end
    end

    // Latch Wishbone read data and error flag
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_rdata_r <= {WB_DATA_WIDTH{1'b0}};
            wb_err_r   <= 1'b0;
        end else if ((state == ST_RD_WB_CYC || state == ST_WR_WB_CYC) && (wb_ack_i || wb_err_i)) begin
            wb_rdata_r <= wb_dat_i;
            wb_err_r   <= wb_err_i;
        end
    end

    // ========================================================================
    // AXI Slave Handshake Outputs
    // ========================================================================
    always @(*) begin
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        s_axi_bvalid  = 1'b0;
        s_axi_bid     = axi_awid_r;
        s_axi_bresp   = wb_err_r ? 2'b10 : 2'b00; // 2'b10 = SLVERR, 2'b00 = OKAY
        s_axi_arready = 1'b0;
        s_axi_rvalid  = 1'b0;
        s_axi_rid     = axi_arid_r;
        s_axi_rlast   = 1'b1;
        s_axi_rresp   = wb_err_r ? 2'b10 : 2'b00;

        // Read data output: replicate 32-bit Wishbone data to both halves for 64-bit AXI
        if (AXI_DATA_WIDTH == 64)
            s_axi_rdata = {wb_rdata_r, wb_rdata_r};
        else
            s_axi_rdata = wb_rdata_r;

        case (state)
            ST_IDLE: begin
                if (s_axi_awvalid && s_axi_wvalid) begin
                    s_axi_awready = 1'b1;
                    s_axi_wready  = 1'b1;
                end else if (s_axi_awvalid) begin
                    s_axi_awready = 1'b1;
                end else if (s_axi_wvalid) begin
                    s_axi_wready  = 1'b1;
                end else if (s_axi_arvalid) begin
                    s_axi_arready = 1'b1;
                end
            end

            ST_WR_DATA: begin
                s_axi_wready = s_axi_wvalid;
            end

            ST_WR_ADDR: begin
                s_axi_awready = s_axi_awvalid;
            end

            ST_WR_RESPOND: begin
                s_axi_bvalid = 1'b1;
            end

            ST_RD_RESPOND: begin
                s_axi_rvalid = 1'b1;
            end

            default: ;
        endcase
    end

    // ========================================================================
    // Wishbone Master Driving Logic
    // ========================================================================
    always @(*) begin
        wb_cyc_o = 1'b0;
        wb_stb_o = 1'b0;
        wb_we_o  = 1'b0;
        wb_adr_o = {WB_ADDR_WIDTH{1'b0}};
        wb_dat_o = {WB_DATA_WIDTH{1'b0}};
        wb_sel_o = {(WB_DATA_WIDTH/8){1'b1}};

        case (state)
            ST_WR_WB_CYC: begin
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o  = 1'b1;
                wb_adr_o = axi_awaddr_r;

                // 64-bit to 32-bit data steering based on address bit [2]
                if (AXI_DATA_WIDTH == 64) begin
                    wb_dat_o = axi_awaddr_r[2] ? axi_wdata_r[63:32] : axi_wdata_r[31:0];
                    wb_sel_o = axi_awaddr_r[2] ? axi_wstrb_r[7:4]   : axi_wstrb_r[3:0];
                end else begin
                    wb_dat_o = axi_wdata_r[31:0];
                    wb_sel_o = axi_wstrb_r[3:0];
                end
            end

            ST_RD_WB_CYC: begin
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o  = 1'b0;
                wb_adr_o = axi_araddr_r;
                wb_dat_o = {WB_DATA_WIDTH{1'b0}};
                wb_sel_o = {(WB_DATA_WIDTH/8){1'b1}};
            end

            default: ;
        endcase
    end

endmodule
