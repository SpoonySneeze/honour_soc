// ============================================================================
// Recovery Policy — Native AXI4 Wrapper
// ============================================================================
module axi_recovery_policy (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Write Address
    input  wire [8:0]  s_axi_awid,
    input  wire [31:0] s_axi_awaddr,
    input  wire [7:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    // AXI4 Write Data
    input  wire [63:0] s_axi_wdata,
    input  wire [7:0]  s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    // AXI4 Write Response
    output reg  [8:0]  s_axi_bid,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    // AXI4 Read Address
    input  wire [8:0]  s_axi_arid,
    input  wire [31:0] s_axi_araddr,
    input  wire [7:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    // AXI4 Read Data
    output reg  [8:0]  s_axi_rid,
    output reg  [63:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rlast,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    // Internal signals for generic register interface
    reg         reg_en;
    reg         reg_we;
    reg  [7:0]  reg_addr;
    wire [31:0] reg_wdata;
    wire [31:0] reg_rdata;
    wire        reg_ack;

    assign reg_wdata = s_axi_awaddr[2] ? s_axi_wdata[63:32] : s_axi_wdata[31:0];

    recovery_policy u_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .reg_en    (reg_en),
        .reg_we    (reg_we),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_rdata (reg_rdata),
        .reg_ack   (reg_ack)
    );

    // AXI4 Slave FSM
    localparam [2:0] ST_IDLE   = 3'd0, ST_W_WAIT = 3'd1, ST_W_RESP = 3'd2, ST_R_WAIT = 3'd3, ST_R_RESP = 3'd4;
    reg [2:0] state;
    reg [8:0] latched_awid, latched_arid;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0;
            reg_en <= 1'b0; reg_we <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_arready <= 1'b0;
            if (s_axi_bready && s_axi_bvalid) s_axi_bvalid <= 1'b0;
            if (s_axi_rready && s_axi_rvalid) s_axi_rvalid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid) begin
                        s_axi_awready <= 1'b1; s_axi_wready <= 1'b1;
                        latched_awid <= s_axi_awid;
                        reg_en <= 1'b1; reg_we <= 1'b1; reg_addr <= s_axi_awaddr[7:0];
                        state <= ST_W_WAIT;
                    end else if (s_axi_arvalid && !s_axi_rvalid) begin
                        s_axi_arready <= 1'b1;
                        latched_arid <= s_axi_arid;
                        reg_en <= 1'b1; reg_we <= 1'b0; reg_addr <= s_axi_araddr[7:0];
                        state <= ST_R_WAIT;
                    end
                end
                ST_W_WAIT: begin
                    if (reg_ack) begin
                        reg_en <= 1'b0; s_axi_bvalid <= 1'b1;
                        s_axi_bid <= latched_awid; s_axi_bresp <= 2'b00;
                        state <= ST_W_RESP;
                    end
                end
                ST_W_RESP: begin if (!s_axi_bvalid || s_axi_bready) state <= ST_IDLE; end
                ST_R_WAIT: begin
                    if (reg_ack) begin
                        reg_en <= 1'b0; s_axi_rvalid <= 1'b1;
                        s_axi_rid <= latched_arid; s_axi_rresp <= 2'b00; s_axi_rlast <= 1'b1;
                        s_axi_rdata <= {reg_rdata, reg_rdata};
                        state <= ST_R_RESP;
                    end
                end
                ST_R_RESP: begin if (!s_axi_rvalid || s_axi_rready) state <= ST_IDLE; end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
