// ============================================================================
// Recovery Policy & Event Log — Custom IP #3
// ============================================================================
// Tracks recovery event history and enforces a crash-loop lockout policy.
// Contains a 16-entry circular timestamp log and a fixed-window recovery
// counter that triggers lockout when too many recoveries occur.
//
// Register Map (Wishbone slave, 32-bit registers):
//   0x00  POL_CTRL       W    [0] record_event (self-clearing)
//                              [1] clear_lockout (self-clearing)
//   0x04  POL_WINDOW     R/W  Rolling window size in clock cycles
//   0x08  POL_THRESHOLD  R/W  [7:0] Max recoveries per window before lockout
//   0x0C  POL_STATUS     R    [0] lockout_flag, [15:8] window_recovery_count
//   0x10  POL_EVENT_TS   W    Staged timestamp (written before record_event)
//   0x14  LOG_READ_IDX   R/W  [3:0] Read pointer into circular log
//   0x18  LOG_READ_DATA  R    Timestamp at LOG_READ_IDX
//   0x1C  LOG_COUNT      R    Total events logged (saturating)
//
// Window Policy: Fixed-window approximation. window_counter counts up to
// policy_window_reg then resets along with window_recovery_count.
// ============================================================================

module recovery_policy (
    // ---- Wishbone Slave Interface ----
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reg_en,
    input  wire        reg_we,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output wire        lockout_irq,
    output reg  [31:0] reg_rdata,
    output reg         reg_ack
);

    // ========================================================================
    // Register Offset Definitions
    // ========================================================================
    localparam ADDR_POL_CTRL      = 8'h00;
    localparam ADDR_POL_WINDOW    = 8'h04;
    localparam ADDR_POL_THRESHOLD = 8'h08;
    localparam ADDR_POL_STATUS    = 8'h0C;
    localparam ADDR_POL_EVENT_TS  = 8'h10;
    localparam ADDR_LOG_READ_IDX  = 8'h14;
    localparam ADDR_LOG_READ_DATA = 8'h18;
    localparam ADDR_LOG_COUNT     = 8'h1C;

    // ========================================================================
    // Internal Registers
    // ========================================================================

    // Circular log buffer — 16 entries × 32-bit timestamps
    reg [31:0] log_buffer [0:15];
    reg [3:0]  log_wr_ptr;
    reg [31:0] log_count;

    // Staged timestamp (written by firmware before triggering record)
    reg [31:0] staged_timestamp;

    // Window policy
    reg [31:0] policy_window_reg;
    reg [7:0]  policy_threshold_reg;
    reg [31:0] window_counter;
    reg [7:0]  window_recovery_count;
    reg        lockout_flag;

    // Read index for log readback
    reg [3:0]  log_read_idx;

    // Self-clearing control bits
    reg        record_event_req;
    reg        clear_lockout_req;

    // ========================================================================
    // Wishbone Bus Interface — Single-Cycle Acknowledge
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            reg_ack <= 1'b0;
        else
            reg_ack <= reg_en & ~reg_ack;
    end

    // ========================================================================
    // Register Writes
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            record_event_req     <= 1'b0;
            clear_lockout_req    <= 1'b0;
            policy_window_reg    <= 32'd0;
            policy_threshold_reg <= 8'd3;   // Default: lockout after 3 recoveries
            staged_timestamp     <= 32'd0;
            log_read_idx         <= 4'd0;
        end else begin
            // Self-clearing bits — deassert after one cycle
            record_event_req  <= 1'b0;
            clear_lockout_req <= 1'b0;

            if (reg_en && reg_we && !reg_ack) begin
                case (reg_addr)
                    ADDR_POL_CTRL: begin
                        record_event_req  <= reg_wdata[0];
                        clear_lockout_req <= reg_wdata[1];
                    end
                    ADDR_POL_WINDOW: begin
                        policy_window_reg <= reg_wdata;
                    end
                    ADDR_POL_THRESHOLD: begin
                        policy_threshold_reg <= reg_wdata[7:0];
                    end
                    ADDR_POL_EVENT_TS: begin
                        staged_timestamp <= reg_wdata;
                    end
                    ADDR_LOG_READ_IDX: begin
                        log_read_idx <= reg_wdata[3:0];
                    end
                    // POL_STATUS, LOG_READ_DATA, LOG_COUNT are read-only
                    default: ;
                endcase
            end
        end
    end

    // ========================================================================
    // Register Reads
    // ========================================================================
    always @(*) begin
        reg_rdata = 32'd0;
        case (reg_addr)
            ADDR_POL_CTRL:      reg_rdata = 32'd0;  // Write-only
            ADDR_POL_WINDOW:    reg_rdata = policy_window_reg;
            ADDR_POL_THRESHOLD: reg_rdata = {24'd0, policy_threshold_reg};
            ADDR_POL_STATUS:    reg_rdata = {16'd0, window_recovery_count, 7'd0, lockout_flag};
            ADDR_POL_EVENT_TS:  reg_rdata = 32'd0;  // Write-only
            ADDR_LOG_READ_IDX:  reg_rdata = {28'd0, log_read_idx};
            ADDR_LOG_READ_DATA: reg_rdata = log_buffer[log_read_idx];
            ADDR_LOG_COUNT:     reg_rdata = log_count;
            default:            reg_rdata = 32'd0;
        endcase
    end

    // ========================================================================
    // Event Recording Logic
    // ========================================================================
    // When record_event is triggered:
    //   1. Write staged_timestamp into log_buffer[log_wr_ptr]
    //   2. Increment log_wr_ptr (wraps at 16)
    //   3. Increment log_count (saturates at 0xFFFFFFFF)
    //   4. Increment window_recovery_count
    //   5. Check threshold → set lockout if exceeded

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            log_wr_ptr             <= 4'd0;
            log_count              <= 32'd0;
            window_recovery_count  <= 8'd0;
            lockout_flag           <= 1'b0;
            window_counter         <= 32'd0;
            for (i = 0; i < 16; i = i + 1)
                log_buffer[i] <= 32'd0;
        end else begin
            // ---- Window Counter ----
            // Free-running counter; resets when it reaches policy_window_reg
            if (policy_window_reg != 32'd0) begin
                if (window_counter >= policy_window_reg) begin
                    window_counter        <= 32'd0;
                    window_recovery_count <= 8'd0;  // Reset count at window boundary
                end else begin
                    window_counter <= window_counter + 32'd1;
                end
            end

            // ---- Record Event ----
            if (record_event_req) begin
                // Write timestamp into circular buffer
                log_buffer[log_wr_ptr] <= staged_timestamp;

                // Advance write pointer (wraps at 16)
                log_wr_ptr <= log_wr_ptr + 4'd1;

                // Increment total log count (saturating)
                if (log_count != 32'hFFFF_FFFF)
                    log_count <= log_count + 32'd1;

                // Increment window recovery count
                window_recovery_count <= window_recovery_count + 8'd1;

                // Check lockout threshold
                // Use +1 because the increment hasn't taken effect yet in this cycle
                if ((window_recovery_count + 8'd1) >= policy_threshold_reg &&
                     policy_threshold_reg != 8'd0) begin
                    lockout_flag <= 1'b1;
                end
            end

            // ---- Clear Lockout ----
            if (clear_lockout_req) begin
                lockout_flag          <= 1'b0;
                window_recovery_count <= 8'd0;
                window_counter        <= 32'd0;
            end
        end
    end


    // ========================================================================
    // Hardware Interrupt Generation
    // ========================================================================
    reg lockout_prev;
    always @(posedge clk) begin
        if (!rst_n) lockout_prev <= 1'b0;
        else lockout_prev <= lockout_flag;
    end
    
    // Pulse lockout_irq for one clock cycle on rising edge of lockout_flag
    assign lockout_irq = lockout_flag & ~lockout_prev;

endmodule
