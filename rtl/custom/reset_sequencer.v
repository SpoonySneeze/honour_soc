// ============================================================================
// Power/Reset Sequencer — Custom IP #2
// ============================================================================
// Generates a precisely-timed reset pulse to the simulated main system.
// Firmware triggers it; hardware handles exact timing independently.
//
// Register Map (Wishbone slave, 32-bit registers):
//   0x00  RST_CTRL         W    [0] trigger (self-clearing)
//   0x04  RST_HOLD_CYCLES  R/W  Duration to hold reset_out low (in clk cycles)
//   0x08  RST_STATUS       R    [0] in_progress, [1] complete (sticky)
//
// FSM: IDLE → ASSERT → DEASSERT → DONE → IDLE
// ============================================================================

module reset_sequencer (
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
    output reg         reset_out       // Active-low reset to simulated main system
);

    // ========================================================================
    // Register Offset Definitions
    // ========================================================================
    localparam ADDR_RST_CTRL        = 8'h00;
    localparam ADDR_RST_HOLD_CYCLES = 8'h04;
    localparam ADDR_RST_STATUS      = 8'h08;

    // ========================================================================
    // FSM State Encoding
    // ========================================================================
    localparam [1:0] ST_IDLE     = 2'b00,
                     ST_ASSERT   = 2'b01,
                     ST_DEASSERT = 2'b10,
                     ST_DONE     = 2'b11;

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [1:0]  rst_state;
    reg [31:0] rst_countdown;
    reg [31:0] rst_hold_reg;
    reg        rst_in_progress;
    reg        rst_complete;

    // Self-clearing trigger
    reg        trigger_req;

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
            trigger_req  <= 1'b0;
            rst_hold_reg <= 32'd100;  // Default: 100 cycles
        end else begin
            // Self-clearing trigger
            trigger_req <= 1'b0;

            if (wb_stb_i && wb_cyc_i && wb_we_i && !wb_ack_o) begin
                case (wb_adr_i)
                    ADDR_RST_CTRL: begin
                        trigger_req <= wb_dat_i[0];
                    end
                    ADDR_RST_HOLD_CYCLES: begin
                        rst_hold_reg <= wb_dat_i;
                    end
                    // RST_STATUS is read-only — writes ignored
                    default: ;
                endcase
            end
        end
    end

    // Register reads
    always @(*) begin
        wb_dat_o = 32'd0;
        case (wb_adr_i)
            ADDR_RST_CTRL:        wb_dat_o = 32'd0;  // Write-only, reads as 0
            ADDR_RST_HOLD_CYCLES: wb_dat_o = rst_hold_reg;
            ADDR_RST_STATUS:      wb_dat_o = {30'd0, rst_complete, rst_in_progress};
            default:              wb_dat_o = 32'd0;
        endcase
    end

    // ========================================================================
    // FSM — Reset Sequence State Machine
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            rst_state       <= ST_IDLE;
            rst_countdown   <= 32'd0;
            rst_in_progress <= 1'b0;
            rst_complete    <= 1'b0;
            reset_out       <= 1'b1;  // Deasserted (active-low)
        end else begin
            case (rst_state)
                // ----------------------------------------------------------
                // IDLE: Waiting for trigger. reset_out = HIGH (deasserted).
                // ----------------------------------------------------------
                ST_IDLE: begin
                    reset_out       <= 1'b1;
                    rst_in_progress <= 1'b0;
                    if (trigger_req) begin
                        // Clear previous completion flag on new trigger
                        rst_complete    <= 1'b0;
                        rst_in_progress <= 1'b1;
                        rst_countdown   <= rst_hold_reg;
                        rst_state       <= ST_ASSERT;
                    end
                end

                // ----------------------------------------------------------
                // ASSERT: Drive reset_out LOW. Countdown from rst_hold_reg.
                // ----------------------------------------------------------
                ST_ASSERT: begin
                    reset_out <= 1'b0;  // Assert reset (active-low)
                    if (rst_countdown == 32'd0) begin
                        rst_state <= ST_DEASSERT;
                    end else begin
                        rst_countdown <= rst_countdown - 32'd1;
                    end
                end

                // ----------------------------------------------------------
                // DEASSERT: Drive reset_out HIGH. Transition state.
                // ----------------------------------------------------------
                ST_DEASSERT: begin
                    reset_out <= 1'b1;  // Deassert reset
                    rst_state <= ST_DONE;
                end

                // ----------------------------------------------------------
                // DONE: Set completion flag. Return to IDLE next cycle.
                // ----------------------------------------------------------
                ST_DONE: begin
                    reset_out       <= 1'b1;
                    rst_in_progress <= 1'b0;
                    rst_complete    <= 1'b1;
                    rst_state       <= ST_IDLE;
                end

                default: begin
                    rst_state <= ST_IDLE;
                    reset_out <= 1'b1;
                end
            endcase
        end
    end

endmodule
