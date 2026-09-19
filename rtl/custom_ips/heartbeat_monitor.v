// ============================================================================
// Heartbeat Monitor — Core IP (Generic Register Interface)
// ============================================================================
module heartbeat_monitor (
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
    input  wire        heartbeat_in,
    output wire        hb_irq
);

    localparam ADDR_HB_CTRL      = 8'h00;
    localparam ADDR_HB_THRESHOLD = 8'h04;
    localparam ADDR_HB_STATUS    = 8'h08;
    localparam ADDR_HB_ELAPSED   = 8'h0C;

    localparam [1:0] ST_DISABLED     = 2'b00,
                     ST_IDLE         = 2'b01,
                     ST_COUNTING     = 2'b10,
                     ST_UNRESPONSIVE = 2'b11;

    reg [1:0]  hb_state;
    reg [31:0] hb_counter;
    reg [31:0] hb_threshold_reg;
    reg        hb_unresponsive_flag;
    reg        hb_enable;
    reg        hb_prev_sample;
    wire       hb_rising_edge;
    reg        clear_flag_req;

    assign hb_irq = hb_unresponsive_flag;

    always @(posedge clk) begin
        if (!rst_n)
            hb_prev_sample <= 1'b0;
        else
            hb_prev_sample <= heartbeat_in;
    end
    assign hb_rising_edge = heartbeat_in & ~hb_prev_sample;

    // Register Acknowledge
    always @(posedge clk) begin
        if (!rst_n)
            reg_ack <= 1'b0;
        else
            reg_ack <= reg_en & ~reg_ack;
    end

    // Register Writes
    always @(posedge clk) begin
        if (!rst_n) begin
            hb_enable <= 1'b0;
            clear_flag_req <= 1'b0;
            hb_threshold_reg <= 32'd0;
        end else begin
            clear_flag_req <= 1'b0;
            if (reg_en && reg_we && !reg_ack) begin
                case (reg_addr)
                    ADDR_HB_CTRL: begin
                        hb_enable      <= reg_wdata[0];
                        clear_flag_req <= reg_wdata[1];
                    end
                    ADDR_HB_THRESHOLD: begin
                        hb_threshold_reg <= reg_wdata;
                    end
                endcase
            end
        end
    end

    // Register Reads
    always @(*) begin
        reg_rdata = 32'd0;
        case (reg_addr)
            ADDR_HB_CTRL:      reg_rdata = {30'd0, 1'b0, hb_enable};
            ADDR_HB_THRESHOLD: reg_rdata = hb_threshold_reg;
            ADDR_HB_STATUS:    reg_rdata = {30'd0, heartbeat_in, hb_unresponsive_flag};
            ADDR_HB_ELAPSED:   reg_rdata = hb_counter;
            default:           reg_rdata = 32'd0;
        endcase
    end

    // FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            hb_state             <= ST_DISABLED;
            hb_counter           <= 32'd0;
            hb_unresponsive_flag <= 1'b0;
        end else begin
            case (hb_state)
                ST_DISABLED: begin
                    hb_counter           <= 32'd0;
                    hb_unresponsive_flag <= 1'b0;
                    if (hb_enable) hb_state <= ST_IDLE;
                end
                ST_IDLE: begin
                    hb_counter <= 32'd0;
                    if (!hb_enable) hb_state <= ST_DISABLED;
                    else if (hb_rising_edge) hb_state <= ST_COUNTING;
                end
                ST_COUNTING: begin
                    if (!hb_enable) begin
                        hb_state <= ST_DISABLED;
                    end else if (hb_rising_edge) begin
                        hb_counter <= 32'd0;
                    end else if (hb_counter >= hb_threshold_reg && hb_threshold_reg != 32'd0) begin
                        hb_unresponsive_flag <= 1'b1;
                        hb_state <= ST_UNRESPONSIVE;
                    end else begin
                        hb_counter <= hb_counter + 32'd1;
                    end
                end
                ST_UNRESPONSIVE: begin
                    if (!hb_enable) begin
                        hb_state <= ST_DISABLED;
                    end else if (clear_flag_req) begin
                        hb_unresponsive_flag <= 1'b0;
                        hb_counter <= 32'd0;
                        hb_state <= ST_IDLE;
                    end else begin
                        if (hb_counter != 32'hFFFF_FFFF)
                            hb_counter <= hb_counter + 32'd1;
                    end
                end
                default: hb_state <= ST_DISABLED;
            endcase
        end
    end
endmodule
