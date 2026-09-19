// ============================================================================
// Reset Sequencer — Core IP (Generic Register Interface)
// ============================================================================
module reset_sequencer (
    input  wire        clk,
    input  wire        rst_n,

    // Generic Register Interface
    input  wire        reg_en,
    input  wire        reg_we,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,
    output reg         reg_ack,

    // Functional
    output reg         reset_out
);

    localparam ADDR_RST_CTRL        = 8'h00;
    localparam ADDR_RST_HOLD_CYCLES = 8'h04;
    localparam ADDR_RST_STATUS      = 8'h08;

    localparam [1:0] ST_IDLE     = 2'b00,
                     ST_ASSERT   = 2'b01,
                     ST_DEASSERT = 2'b10;

    reg [1:0]  rst_state;
    reg [31:0] rst_countdown;
    reg [31:0] rst_hold_cycles_reg;
    reg        in_progress;
    reg        complete;
    reg        trigger_req;

    // Register Acknowledge
    always @(posedge clk) begin
        if (!rst_n) reg_ack <= 1'b0;
        else        reg_ack <= reg_en & ~reg_ack;
    end

    // Register Writes
    always @(posedge clk) begin
        if (!rst_n) begin
            rst_hold_cycles_reg <= 32'd100;
            trigger_req <= 1'b0;
        end else begin
            trigger_req <= 1'b0;
            if (reg_en && reg_we && !reg_ack) begin
                case (reg_addr)
                    ADDR_RST_CTRL:        trigger_req <= reg_wdata[0];
                    ADDR_RST_HOLD_CYCLES: rst_hold_cycles_reg <= reg_wdata;
                endcase
            end
        end
    end

    // Register Reads
    always @(*) begin
        reg_rdata = 32'd0;
        case (reg_addr)
            ADDR_RST_HOLD_CYCLES: reg_rdata = rst_hold_cycles_reg;
            ADDR_RST_STATUS:      reg_rdata = {30'd0, complete, in_progress};
        endcase
    end

    // FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            rst_state     <= ST_IDLE;
            reset_out     <= 1'b1;
            in_progress   <= 1'b0;
            complete      <= 1'b0;
            rst_countdown <= 32'd0;
        end else begin
            if (trigger_req && rst_state == ST_IDLE) begin
                rst_state     <= ST_ASSERT;
                reset_out     <= 1'b0;
                in_progress   <= 1'b1;
                complete      <= 1'b0;
                rst_countdown <= rst_hold_cycles_reg;
            end else begin
                case (rst_state)
                    ST_IDLE: begin
                        reset_out   <= 1'b1;
                        in_progress <= 1'b0;
                    end
                    ST_ASSERT: begin
                        if (rst_countdown == 32'd0) begin
                            rst_state <= ST_DEASSERT;
                        end else begin
                            rst_countdown <= rst_countdown - 32'd1;
                        end
                    end
                    ST_DEASSERT: begin
                        reset_out   <= 1'b1;
                        in_progress <= 1'b0;
                        complete    <= 1'b1;
                        rst_state   <= ST_IDLE;
                    end
                    default: rst_state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
