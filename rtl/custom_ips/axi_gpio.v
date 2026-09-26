// ============================================================================
// BMC SoC — Native Pure AXI4 GPIO Status Peripheral
// ============================================================================
// Direct status of external input/output pins.
// Base Address: 0x0002_0200 (Offset 0x00: GPIO_STAT, RO)
//   [0]: heartbeat_in live pin
//   [1]: reset_out pin level (active-low deasserted = 1)
//   [31:2]: Reserved (0)
// ============================================================================

`timescale 1ns / 1ps

module axi_gpio #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Functional pin monitoring
    input  wire                   heartbeat_in,
    input  wire                   reset_out,

    // AXI4 Read Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    // AXI4 Read Data Channel
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // AXI4 Write Channels (read-only peripheral with clean write acknowledgement)
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output reg  [ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready
);

    wire [31:0] gpio_status_word = {30'd0, reset_out, heartbeat_in};

    // AXI4 Read FSM
    reg [ID_WIDTH-1:0]   arid_q;
    reg [ADDR_WIDTH-1:0] araddr_q;
    reg [7:0]            arlen_q;
    reg                  ar_active;

    assign s_axi_arready = !ar_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arid_q    <= {ID_WIDTH{1'b0}};
            araddr_q  <= {ADDR_WIDTH{1'b0}};
            arlen_q   <= 8'd0;
            ar_active <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                arid_q    <= s_axi_arid;
                araddr_q  <= s_axi_araddr;
                arlen_q   <= s_axi_arlen;
                ar_active <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready && s_axi_rlast) begin
                ar_active <= 1'b0;
            end
        end
    end

    reg [7:0] r_count;
    wire      r_done = (r_count == arlen_q);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_count <= 8'd0;
        end else begin
            if (ar_active) begin
                if (s_axi_rvalid && s_axi_rready) begin
                    if (s_axi_rlast)
                        r_count <= 8'd0;
                    else
                        r_count <= r_count + 8'd1;
                end
            end
        end
    end

    assign s_axi_rvalid = ar_active;
    assign s_axi_rlast  = r_done;
    assign s_axi_rid    = arid_q;
    assign s_axi_rresp  = 2'b00; // OKAY
    assign s_axi_rdata  = {gpio_status_word, gpio_status_word}; // Replicated across 64-bit bus

    // AXI4 Write Channels
    reg aw_seen;
    reg w_seen;
    reg [ID_WIDTH-1:0] awid_q;

    assign s_axi_awready = !s_axi_bvalid && !aw_seen;
    assign s_axi_wready  = !s_axi_bvalid && !w_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_seen      <= 1'b0;
            w_seen       <= 1'b0;
            awid_q       <= {ID_WIDTH{1'b0}};
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_bid    <= {ID_WIDTH{1'b0}};
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_seen <= 1'b1;
                awid_q  <= s_axi_awid;
            end
            if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                w_seen  <= 1'b1;
            end

            if ((aw_seen || (s_axi_awvalid && s_axi_awready)) &&
                (w_seen  || (s_axi_wvalid && s_axi_wready && s_axi_wlast))) begin
                aw_seen      <= 1'b0;
                w_seen       <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                s_axi_bid    <= (s_axi_awvalid && s_axi_awready) ? s_axi_awid : awid_q;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule
