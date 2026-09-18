// ============================================================================
// Heartbeat Monitor — Custom IP #1
// ============================================================================
// Detects loss of periodic heartbeat pulse from a simulated "main system."
// Hardware-timed: the core only configures thresholds and reads status.
//
// Register Map (Wishbone slave, 32-bit registers):
//   0x00  HB_CTRL       R/W  [0] enable, [1] clear_flag (self-clearing)
//   0x04  HB_THRESHOLD  R/W  Max cycles between heartbeat edges
//   0x08  HB_STATUS     R    [0] unresponsive, [1] heartbeat_in level
//   0x0C  HB_ELAPSED    R    Live cycle count since last heartbeat edge
//
// FSM: DISABLED → IDLE → COUNTING → UNRESPONSIVE
// ============================================================================

module heartbeat_monitor (
    // ---- Wishbone Slave Interface ----
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire [7:0]  wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire        wb_we_i,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,

    // ---- Functional Signals ----
    input  wire        heartbeat_in,    // From GPIO / external pad
    output wire        hb_irq           // Optional interrupt output
);

    // ========================================================================
    // Register Offset Definitions
    // ========================================================================
    localparam ADDR_HB_CTRL      = 8'h00;
    localparam ADDR_HB_THRESHOLD = 8'h04;
    localparam ADDR_HB_STATUS    = 8'h08;
    localparam ADDR_HB_ELAPSED   = 8'h0C;

    // ========================================================================
    // FSM State Encoding
    // ========================================================================
    localparam [1:0] ST_DISABLED     = 2'b00,
                     ST_IDLE         = 2'b01,
                     ST_COUNTING     = 2'b10,
                     ST_UNRESPONSIVE = 2'b11;

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [1:0]  hb_state;
    reg [31:0] hb_counter;
    reg [31:0] hb_threshold_reg;
    reg        hb_unresponsive_flag;
    reg        hb_enable;

    // Edge detection
    reg        hb_prev_sample;
    wire       hb_rising_edge;

    // Self-clearing control bits
    reg        clear_flag_req;

    // ========================================================================
    // Edge Detector
    // ========================================================================
    // Detect rising edge of heartbeat_in
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            hb_prev_sample <= 1'b0;
        else
            hb_prev_sample <= heartbeat_in;
    end

    assign hb_rising_edge = heartbeat_in & ~hb_prev_sample;

    // ========================================================================
    // Wishbone Bus Interface — Register Read/Write
    // ========================================================================
    // Single-cycle ack
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_stb_i & wb_cyc_i & ~wb_ack_o;
    end

    // Register writes
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            hb_enable       <= 1'b0;
            clear_flag_req  <= 1'b0;
            hb_threshold_reg <= 32'd0;
        end else begin
            // Self-clearing: deassert after one cycle
            clear_flag_req <= 1'b0;

            if (wb_stb_i && wb_cyc_i && wb_we_i && !wb_ack_o) begin
                case (wb_adr_i)
                    ADDR_HB_CTRL: begin
                        hb_enable      <= wb_dat_i[0];
                        clear_flag_req <= wb_dat_i[1];
                    end
                    ADDR_HB_THRESHOLD: begin
                        hb_threshold_reg <= wb_dat_i;
                    end
                    // HB_STATUS and HB_ELAPSED are read-only — writes ignored
                    default: ;
                endcase
            end
        end
    end

    // Register reads
    always @(*) begin
        wb_dat_o = 32'd0;
        case (wb_adr_i)
            ADDR_HB_CTRL:      wb_dat_o = {30'd0, 1'b0, hb_enable};
            ADDR_HB_THRESHOLD: wb_dat_o = hb_threshold_reg;
            ADDR_HB_STATUS:    wb_dat_o = {30'd0, heartbeat_in, hb_unresponsive_flag};
            ADDR_HB_ELAPSED:   wb_dat_o = hb_counter;
            default:           wb_dat_o = 32'd0;
        endcase
    end

    // ========================================================================
    // FSM — Heartbeat Monitoring State Machine
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            hb_state             <= ST_DISABLED;
            hb_counter           <= 32'd0;
            hb_unresponsive_flag <= 1'b0;
        end else begin
            case (hb_state)
                // ----------------------------------------------------------
                // DISABLED: Module is off. Counter halted. Flag cleared.
                // ----------------------------------------------------------
                ST_DISABLED: begin
                    hb_counter           <= 32'd0;
                    hb_unresponsive_flag <= 1'b0;
                    if (hb_enable)
                        hb_state <= ST_IDLE;
                end

                // ----------------------------------------------------------
                // IDLE: Enabled, waiting for first heartbeat edge to begin.
                // ----------------------------------------------------------
                ST_IDLE: begin
                    hb_counter <= 32'd0;
                    if (!hb_enable)
                        hb_state <= ST_DISABLED;
                    else if (hb_rising_edge)
                        hb_state <= ST_COUNTING;
                end

                // ----------------------------------------------------------
                // COUNTING: Actively monitoring. Counter increments each
                // cycle and resets on each heartbeat rising edge.
                // ----------------------------------------------------------
                ST_COUNTING: begin
                    if (!hb_enable) begin
                        hb_state <= ST_DISABLED;
                    end else if (hb_rising_edge) begin
                        // Heartbeat received — reset counter
                        hb_counter <= 32'd0;
                    end else if (hb_counter >= hb_threshold_reg && hb_threshold_reg != 32'd0) begin
                        // Threshold exceeded — system is unresponsive
                        hb_unresponsive_flag <= 1'b1;
                        hb_state <= ST_UNRESPONSIVE;
                    end else begin
                        // Normal counting
                        hb_counter <= hb_counter + 32'd1;
                    end
                end

                // ----------------------------------------------------------
                // UNRESPONSIVE: Flag latched. Only firmware can clear it.
                // Counter continues incrementing for HB_ELAPSED readback.
                // ----------------------------------------------------------
                ST_UNRESPONSIVE: begin
                    if (!hb_enable) begin
                        hb_state <= ST_DISABLED;
                    end else if (clear_flag_req) begin
                        hb_unresponsive_flag <= 1'b0;
                        hb_counter <= 32'd0;
                        hb_state <= ST_IDLE;
                    end else begin
                        // Keep counting (for elapsed time display)
                        if (hb_counter != 32'hFFFF_FFFF)
                            hb_counter <= hb_counter + 32'd1;
                    end
                end

                default: begin
                    hb_state <= ST_DISABLED;
                end
            endcase
        end
    end

    // ========================================================================
    // Interrupt Output (optional — directly mirrors unresponsive flag)
    // ========================================================================
    assign hb_irq = hb_unresponsive_flag;

endmodule
