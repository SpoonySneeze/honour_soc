// ============================================================================
// Testbench — Heartbeat Monitor (Unit Test)
// ============================================================================
// Tests:
//   1. Happy path: heartbeat toggles faster than threshold → no flag
//   2. Timeout detection: heartbeat stops → flag sets at threshold
//   3. Flag latching: heartbeat resumes → flag stays until cleared
//   4. Counter accuracy: HB_ELAPSED matches actual elapsed cycles
//   5. Disable/re-enable: transitions through DISABLED correctly
// ============================================================================

`timescale 1ns / 1ps

module tb_heartbeat_monitor;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CLK_PERIOD = 10;  // 100 MHz

    // Register offsets
    localparam ADDR_HB_CTRL      = 8'h00;
    localparam ADDR_HB_THRESHOLD = 8'h04;
    localparam ADDR_HB_STATUS    = 8'h08;
    localparam ADDR_HB_ELAPSED   = 8'h0C;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg         clk;
    reg         rst;
    reg  [7:0]  wb_adr;
    reg  [31:0] wb_dat_wr;
    wire [31:0] wb_dat_rd;
    reg         wb_we;
    reg  [3:0]  wb_sel;
    reg         wb_stb;
    reg         wb_cyc;
    wire        wb_ack;

    reg         heartbeat_in;
    wire        hb_irq;

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    heartbeat_monitor dut (
        .wb_clk_i    (clk),
        .wb_rst_i    (rst),
        .wb_adr_i    (wb_adr),
        .wb_dat_i    (wb_dat_wr),
        .wb_dat_o    (wb_dat_rd),
        .wb_we_i     (wb_we),
        .wb_sel_i    (wb_sel),
        .wb_stb_i    (wb_stb),
        .wb_cyc_i    (wb_cyc),
        .wb_ack_o    (wb_ack),
        .heartbeat_in(heartbeat_in),
        .hb_irq      (hb_irq)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // Wishbone Bus Tasks
    // ========================================================================
    task wb_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            wb_adr    <= addr;
            wb_dat_wr <= data;
            wb_we     <= 1'b1;
            wb_sel    <= 4'hF;
            wb_stb    <= 1'b1;
            wb_cyc    <= 1'b1;
            @(posedge clk);
            while (!wb_ack) @(posedge clk);
            wb_stb <= 1'b0;
            wb_cyc <= 1'b0;
            wb_we  <= 1'b0;
            @(posedge clk);
        end
    endtask

    task wb_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            wb_adr <= addr;
            wb_we  <= 1'b0;
            wb_sel <= 4'hF;
            wb_stb <= 1'b1;
            wb_cyc <= 1'b1;
            @(posedge clk);
            while (!wb_ack) @(posedge clk);
            data = wb_dat_rd;
            wb_stb <= 1'b0;
            wb_cyc <= 1'b0;
            @(posedge clk);
        end
    endtask

    task check(input [31:0] expected, input [31:0] actual, input [255:0] msg);
        begin
            if (actual === expected) begin
                $display("  [PASS] %0s: expected=0x%08h, got=0x%08h", msg, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s: expected=0x%08h, got=0x%08h", msg, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Generate a heartbeat pulse (single cycle high)
    task send_heartbeat;
        begin
            @(posedge clk);
            heartbeat_in <= 1'b1;
            @(posedge clk);
            heartbeat_in <= 1'b0;
        end
    endtask

    // ========================================================================
    // Test Stimulus
    // ========================================================================
    initial begin
        $dumpfile("tb_heartbeat_monitor.vcd");
        $dumpvars(0, tb_heartbeat_monitor);

        // Initialize
        rst          = 1;
        wb_adr       = 0;
        wb_dat_wr    = 0;
        wb_we        = 0;
        wb_sel       = 0;
        wb_stb       = 0;
        wb_cyc       = 0;
        heartbeat_in = 0;
        test_num     = 0;
        pass_count   = 0;
        fail_count   = 0;

        // Reset
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ==================================================================
        // TEST 1: Happy Path — heartbeat faster than threshold
        // ==================================================================
        test_num = 1;
        $display("\n=== TEST %0d: Happy Path ===", test_num);

        // Set threshold to 50 cycles
        wb_write(ADDR_HB_THRESHOLD, 32'd50);

        // Enable monitoring
        wb_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat to transition from IDLE → COUNTING
        send_heartbeat;

        // Send heartbeats every 20 cycles (well under threshold)
        repeat (5) begin
            repeat (20) @(posedge clk);
            send_heartbeat;
        end

        // Check: unresponsive flag should NOT be set
        wb_read(ADDR_HB_STATUS, read_data);
        check(32'd0, read_data[0], "Unresponsive flag should be 0");

        // Disable
        wb_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 2: Timeout Detection — heartbeat stops
        // ==================================================================
        test_num = 2;
        $display("\n=== TEST %0d: Timeout Detection ===", test_num);

        // Set threshold to 30 cycles
        wb_write(ADDR_HB_THRESHOLD, 32'd30);

        // Enable monitoring
        wb_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat
        send_heartbeat;

        // Wait well past threshold without sending heartbeat
        repeat (50) @(posedge clk);

        // Check: unresponsive flag should be set
        wb_read(ADDR_HB_STATUS, read_data);
        check(32'd1, read_data[0], "Unresponsive flag should be 1");

        // Check: IRQ output should be high
        check(1'b1, hb_irq, "hb_irq should be asserted");

        // Disable
        wb_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 3: Flag Latching — heartbeat resumes but flag stays
        // ==================================================================
        test_num = 3;
        $display("\n=== TEST %0d: Flag Latching ===", test_num);

        // Set threshold to 20 cycles
        wb_write(ADDR_HB_THRESHOLD, 32'd20);
        wb_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat, then let it timeout
        send_heartbeat;
        repeat (30) @(posedge clk);

        // Verify flag is set
        wb_read(ADDR_HB_STATUS, read_data);
        check(32'd1, read_data[0], "Flag set after timeout");

        // Resume heartbeats — flag should STAY set (latched)
        send_heartbeat;
        repeat (5) @(posedge clk);
        send_heartbeat;
        repeat (5) @(posedge clk);

        wb_read(ADDR_HB_STATUS, read_data);
        check(32'd1, read_data[0], "Flag stays latched after heartbeat resumes");

        // Now clear the flag via HB_CTRL.clear_flag
        wb_write(ADDR_HB_CTRL, 32'h0003);  // enable + clear_flag
        repeat (3) @(posedge clk);

        wb_read(ADDR_HB_STATUS, read_data);
        check(32'd0, read_data[0], "Flag cleared after firmware clear");

        // Disable
        wb_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 4: Counter Accuracy — HB_ELAPSED
        // ==================================================================
        test_num = 4;
        $display("\n=== TEST %0d: Counter Accuracy ===", test_num);

        wb_write(ADDR_HB_THRESHOLD, 32'd1000);  // High threshold
        wb_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat to start counting
        send_heartbeat;

        // Wait exactly 25 cycles
        repeat (25) @(posedge clk);

        // Read elapsed — should be approximately 25
        // (exact value depends on cycle alignment of the read itself)
        wb_read(ADDR_HB_ELAPSED, read_data);
        $display("  [INFO] HB_ELAPSED after ~25 cycles: %0d", read_data);
        if (read_data >= 32'd22 && read_data <= 32'd30) begin
            $display("  [PASS] HB_ELAPSED in expected range [22..30]");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] HB_ELAPSED out of range: %0d", read_data);
            fail_count = fail_count + 1;
        end

        // Disable
        wb_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 5: Disable/Re-enable
        // ==================================================================
        test_num = 5;
        $display("\n=== TEST %0d: Disable/Re-enable ===", test_num);

        // Start monitoring
        wb_write(ADDR_HB_THRESHOLD, 32'd20);
        wb_write(ADDR_HB_CTRL, 32'h0001);
        send_heartbeat;
        repeat (10) @(posedge clk);

        // Disable mid-count
        wb_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // Counter should be reset
        wb_read(ADDR_HB_ELAPSED, read_data);
        check(32'd0, read_data, "Counter resets on disable");

        // Flag should be cleared
        wb_read(ADDR_HB_STATUS, read_data);
        check(32'd0, read_data[0], "Flag cleared on disable");

        // ==================================================================
        // Summary
        // ==================================================================
        repeat (10) @(posedge clk);
        $display("\n========================================");
        $display("  RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count > 0)
            $display("*** SOME TESTS FAILED ***");
        else
            $display("*** ALL TESTS PASSED ***");

        $finish;
    end

endmodule
