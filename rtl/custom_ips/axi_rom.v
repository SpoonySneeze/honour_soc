`timescale 1ns / 1ps

module axi_rom #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    parameter MEM_SIZE   = 8192 // 8KB
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // AR Channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    // R Channel
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // AW, W, B channels
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
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

    // Memory array
    reg [7:0] mem [0:MEM_SIZE-1];

    // Initialization
    initial begin
        $readmemh("firmware.hex", mem);
    end

    // AR FSM
    reg [ID_WIDTH-1:0]   arid_q;
    reg [ADDR_WIDTH-1:0] araddr_q;
    reg [7:0]            arlen_q;
    reg                  ar_active;

    assign s_axi_arready = !ar_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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

    // R FSM
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
                        r_count <= r_count + 1;
                end
            end
        end
    end

    assign s_axi_rvalid = ar_active;
    assign s_axi_rlast  = r_done;
    assign s_axi_rid    = arid_q;
    assign s_axi_rresp  = 2'b00;

    // Read Data Output
    wire [ADDR_WIDTH-1:0] current_addr = araddr_q + (r_count * (DATA_WIDTH/8));
    wire [ADDR_WIDTH-1:0] base_idx = current_addr & ~(DATA_WIDTH/8 - 1); // 8-byte aligned

    assign s_axi_rdata = {
        mem[base_idx+7], mem[base_idx+6], mem[base_idx+5], mem[base_idx+4],
        mem[base_idx+3], mem[base_idx+2], mem[base_idx+1], mem[base_idx+0]
    };

    // Ignore Writes but respond to them properly
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_bid    <= 0;
        end else begin
            if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
                s_axi_bid    <= s_axi_awid;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule
