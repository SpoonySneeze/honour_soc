// ============================================================================
// AXI4-Lite to Wishbone B4 Bridge
// ============================================================================
// Translates AXI4-Lite read/write transactions into Wishbone B4 single-cycle
// bus transactions. Supports 32-bit data, 32-bit address.
//
// AXI4-Lite slave side ← VeeR EL2 (via AXI interconnect)
// Wishbone B4 master side → Wishbone peripheral bus
// ============================================================================

module axi4_to_wb_bridge #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter WB_ADDR_WIDTH  = 32,
    parameter WB_DATA_WIDTH  = 32
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // ---- AXI4-Lite Slave Interface ----

    // Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]                  s_axi_awprot,
    input  wire                        s_axi_awvalid,
    output reg                         s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                        s_axi_wvalid,
    output reg                         s_axi_wready,

    // Write Response Channel
    output reg  [1:0]                  s_axi_bresp,
    output reg                         s_axi_bvalid,
    input  wire                        s_axi_bready,

    // Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]                  s_axi_arprot,
    input  wire                        s_axi_arvalid,
    output reg                         s_axi_arready,

    // Read Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]                  s_axi_rresp,
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
                     ST_WR_ACCEPT  = 3'd1,
                     ST_WR_WB_CYC  = 3'd2,
                     ST_WR_RESPOND = 3'd3,
                     ST_RD_WB_CYC  = 3'd4,
                     ST_RD_RESPOND = 3'd5;

    reg [2:0] state, state_next;

    // Latched AXI transaction data
    reg [AXI_ADDR_WIDTH-1:0] axi_addr_r;
    reg [AXI_DATA_WIDTH-1:0] axi_wdata_r;
    reg [AXI_DATA_WIDTH/8-1:0] axi_wstrb_r;
    reg [WB_DATA_WIDTH-1:0]  wb_rdata_r;
    reg                      wb_err_r;

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
                // Write has priority over read if both arrive simultaneously
                if (s_axi_awvalid && s_axi_wvalid)
                    state_next = ST_WR_WB_CYC;
                else if (s_axi_awvalid)
                    state_next = ST_WR_ACCEPT;
                else if (s_axi_arvalid)
                    state_next = ST_RD_WB_CYC;
            end

            ST_WR_ACCEPT: begin
                // Waiting for write data to arrive (address arrived first)
                if (s_axi_wvalid)
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
    // Latch AXI Transaction Data
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_addr_r  <= {AXI_ADDR_WIDTH{1'b0}};
            axi_wdata_r <= {AXI_DATA_WIDTH{1'b0}};
            axi_wstrb_r <= {(AXI_DATA_WIDTH/8){1'b0}};
        end else begin
            // Latch write address
            if (state == ST_IDLE && s_axi_awvalid)
                axi_addr_r <= s_axi_awaddr;
            // Latch read address
            else if (state == ST_IDLE && s_axi_arvalid)
                axi_addr_r <= s_axi_araddr;

            // Latch write data
            if ((state == ST_IDLE || state == ST_WR_ACCEPT) && s_axi_wvalid) begin
                axi_wdata_r <= s_axi_wdata;
                axi_wstrb_r <= s_axi_wstrb;
            end
        end
    end

    // Latch Wishbone read data and error on ack
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
    // AXI Handshake Outputs
    // ========================================================================
    always @(*) begin
        // Defaults
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        s_axi_bvalid  = 1'b0;
        s_axi_bresp   = 2'b00;     // OKAY
        s_axi_arready = 1'b0;
        s_axi_rvalid  = 1'b0;
        s_axi_rdata   = {AXI_DATA_WIDTH{1'b0}};
        s_axi_rresp   = 2'b00;     // OKAY

        case (state)
            ST_IDLE: begin
                if (s_axi_awvalid && s_axi_wvalid) begin
                    // Accept both address and data simultaneously
                    s_axi_awready = 1'b1;
                    s_axi_wready  = 1'b1;
                end else if (s_axi_awvalid) begin
                    // Accept write address, wait for data
                    s_axi_awready = 1'b1;
                end else if (s_axi_arvalid) begin
                    // Accept read address
                    s_axi_arready = 1'b1;
                end
            end

            ST_WR_ACCEPT: begin
                // Accept write data when it arrives
                s_axi_wready = s_axi_wvalid;
            end

            ST_WR_RESPOND: begin
                s_axi_bvalid = 1'b1;
                s_axi_bresp  = wb_err_r ? 2'b10 : 2'b00; // SLVERR or OKAY
            end

            ST_RD_RESPOND: begin
                s_axi_rvalid = 1'b1;
                s_axi_rdata  = wb_rdata_r;
                s_axi_rresp  = wb_err_r ? 2'b10 : 2'b00; // SLVERR or OKAY
            end

            default: ;
        endcase
    end

    // ========================================================================
    // Wishbone Master Outputs
    // ========================================================================
    always @(*) begin
        wb_cyc_o = 1'b0;
        wb_stb_o = 1'b0;
        wb_we_o  = 1'b0;
        wb_adr_o = axi_addr_r;
        wb_dat_o = axi_wdata_r;
        wb_sel_o = {(WB_DATA_WIDTH/8){1'b1}};  // Default: all bytes selected

        case (state)
            ST_WR_WB_CYC: begin
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o  = 1'b1;
                wb_adr_o = axi_addr_r;
                wb_dat_o = axi_wdata_r;
                wb_sel_o = axi_wstrb_r;
            end

            ST_RD_WB_CYC: begin
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o  = 1'b0;
                wb_adr_o = axi_addr_r;
                wb_dat_o = {WB_DATA_WIDTH{1'b0}};
                wb_sel_o = {(WB_DATA_WIDTH/8){1'b1}};
            end

            default: ;
        endcase
    end

endmodule
