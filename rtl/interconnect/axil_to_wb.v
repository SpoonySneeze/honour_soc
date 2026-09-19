// ============================================================================
// AXI4-Lite to Wishbone B4 Peripheral Adapter
// ============================================================================
// Translates standard 32-bit AXI4-Lite transactions into Wishbone B4 cycles
// for an individual peripheral IP block.
// ============================================================================

`timescale 1ns / 1ps

module axil_to_wb #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- AXI-Lite Slave Interface ----
    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,

    // Write Response Channel
    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,

    // Read Data Channel
    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    // ---- Wishbone B4 Master Interface ----
    output reg  [ADDR_WIDTH-1:0]   wb_adr_o,
    output reg  [DATA_WIDTH-1:0]   wb_dat_o,
    input  wire [DATA_WIDTH-1:0]   wb_dat_i,
    output reg                     wb_we_o,
    output reg  [DATA_WIDTH/8-1:0] wb_sel_o,
    output reg                     wb_stb_o,
    output reg                     wb_cyc_o,
    input  wire                    wb_ack_i,
    input  wire                    wb_err_i
);

    localparam [2:0] ST_IDLE       = 3'd0,
                     ST_WR_DATA    = 3'd1,
                     ST_WR_ADDR    = 3'd2,
                     ST_WR_WB_CYC  = 3'd3,
                     ST_WR_RESPOND = 3'd4,
                     ST_RD_WB_CYC  = 3'd5,
                     ST_RD_RESPOND = 3'd6;

    reg [2:0] state, state_next;

    reg [ADDR_WIDTH-1:0]   addr_r;
    reg [DATA_WIDTH-1:0]   wdata_r;
    reg [DATA_WIDTH/8-1:0] wstrb_r;
    reg [DATA_WIDTH-1:0]   rdata_r;
    reg                    err_r;

    // Sequential State
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= state_next;
    end

    // Next State Logic
    always @(*) begin
        state_next = state;
        case (state)
            ST_IDLE: begin
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
                if (s_axi_wvalid)
                    state_next = ST_WR_WB_CYC;
            end

            ST_WR_ADDR: begin
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

    // Latch Request Signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_r  <= {ADDR_WIDTH{1'b0}};
            wdata_r <= {DATA_WIDTH{1'b0}};
            wstrb_r <= {(DATA_WIDTH/8){1'b0}};
            rdata_r <= {DATA_WIDTH{1'b0}};
            err_r   <= 1'b0;
        end else begin
            if ((state == ST_IDLE || state == ST_WR_ADDR) && s_axi_awvalid)
                addr_r <= s_axi_awaddr;
            else if (state == ST_IDLE && !s_axi_awvalid && !s_axi_wvalid && s_axi_arvalid)
                addr_r <= s_axi_araddr;

            if ((state == ST_IDLE || state == ST_WR_DATA) && s_axi_wvalid) begin
                wdata_r <= s_axi_wdata;
                wstrb_r <= s_axi_wstrb;
            end

            if ((state == ST_RD_WB_CYC || state == ST_WR_WB_CYC) && (wb_ack_i || wb_err_i)) begin
                rdata_r <= wb_dat_i;
                err_r   <= wb_err_i;
            end
        end
    end

    // AXI Slave Handshake Outputs
    always @(*) begin
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        s_axi_bvalid  = 1'b0;
        s_axi_bresp   = err_r ? 2'b10 : 2'b00;
        s_axi_arready = 1'b0;
        s_axi_rvalid  = 1'b0;
        s_axi_rresp   = err_r ? 2'b10 : 2'b00;
        s_axi_rdata   = rdata_r;

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

            ST_WR_DATA:    s_axi_wready  = s_axi_wvalid;
            ST_WR_ADDR:    s_axi_awready = s_axi_awvalid;
            ST_WR_RESPOND: s_axi_bvalid  = 1'b1;
            ST_RD_RESPOND: s_axi_rvalid  = 1'b1;
            default: ;
        endcase
    end

    // Wishbone Master Driving Logic
    always @(*) begin
        wb_cyc_o = 1'b0;
        wb_stb_o = 1'b0;
        wb_we_o  = 1'b0;
        wb_adr_o = addr_r;
        wb_dat_o = wdata_r;
        wb_sel_o = wstrb_r;

        case (state)
            ST_WR_WB_CYC: begin
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o  = 1'b1;
            end

            ST_RD_WB_CYC: begin
                wb_cyc_o = 1'b1;
                wb_stb_o = 1'b1;
                wb_we_o  = 1'b0;
                wb_dat_o = {DATA_WIDTH{1'b0}};
                wb_sel_o = {(DATA_WIDTH/8){1'b1}};
            end

            default: ;
        endcase
    end

endmodule
