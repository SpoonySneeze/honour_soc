// ============================================================================
// Testbench — Recovery Policy & Event Log (Unit Test)
// ============================================================================
// Tests:
//   1. Single event recording
//   2. Multiple events & log readback
//   3. Circular buffer wrap (17+ events)
//   4. No lockout below threshold
//   5. Lockout triggers at threshold
//   6. Lockout is sticky
//   7. Clear lockout via firmware
//   8. Window reset clears recovery count
// ============================================================================

`timescale 1ns / 1ps

module tb_recovery_policy;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CLK_PERIOD = 10;  // 100 MHz

    // Register offsets
    localparam ADDR_POL_CTRL      = 8'h00;
    localparam ADDR_POL_WINDOW    = 8'h04;
    localparam ADDR_POL_THRESHOLD = 8'h08;
    localparam ADDR_POL_STATUS    = 8'h0C;
    localparam ADDR_POL_EVENT_TS  = 8'h10;
    localparam ADDR_LOG_READ_IDX  = 8'h14;
    localparam ADDR_LOG_READ_DATA = 8'h18;
    localparam ADDR_LOG_COUNT     = 8'h1C;

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

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    recovery_policy dut (
        .wb_clk_i  (clk),
        .wb_rst_i  (rst),
        .wb_adr_i  (wb_adr),
        .wb_dat_i  (wb_dat_wr),
        .wb_dat_o  (wb_dat_rd),
        .wb_we_i   (wb_we),
        .wb_sel_i  (wb_sel),
        .wb_stb_i  (wb_stb),
        .wb_cyc_i  (wb_cyc),
        .wb_ack_o  (wb_ack)
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

    // Record an event with a given timestamp
    task record_event(input [31:0] timestamp);
        begin
            wb_write(ADDR_POL_EVENT_TS, timestamp);
            wb_write(ADDR_POL_CTRL, 32'h0001);  // record_event
        end
    endtask

    // Read a log entry at a given index
    task read_log_entry(input [3:0] idx, output [31:0] data);
        begin
            wb_write(ADDR_LOG_READ_IDX, {28'd0, idx});
            wb_read(ADDR_LOG_READ_DATA, data);
        end
    endtask

    // ========================================================================
    // Test Stimulus
    // ========================================================================
    integer i;
    initial begin
        $dumpfile("tb_recovery_policy.vcd");
        $dumpvars(0, tb_recovery_policy);

        // Initialize
        rst        = 1;
        wb_adr     = 0;
        wb_dat_wr  = 0;
        wb_we      = 0;
        wb_sel     = 0;
        wb_stb     = 0;
        wb_cyc     = 0;
        pass_count = 0;
        fail_count = 0;

        // System reset
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ==================================================================
        // Configure: window=10000 cycles, threshold=3 recoveries
        // ==================================================================
        wb_write(ADDR_POL_WINDOW, 32'd10000);
        wb_write(ADDR_POL_THRESHOLD, 32'd3);

        // ==================================================================
        // TEST 1: Single Event Recording
        // ==================================================================
        test_num = 1;
        $display("\n=== TEST %0d: Single Event Recording ===", test_num);

        record_event(32'hAAAA_0001);

        // Check log count
        wb_read(ADDR_LOG_COUNT, read_data);
        check(32'd1, read_data, "LOG_COUNT after 1 event");

        // Read back the entry
        read_log_entry(4'd0, read_data);
        check(32'hAAAA_0001, read_data, "LOG_READ_DATA[0] timestamp");

        // ==================================================================
        // TEST 2: Multiple Events & Readback
        // ==================================================================
        test_num = 2;
        $display("\n=== TEST %0d: Multiple Events & Readback ===", test_num);

        record_event(32'hBBBB_0002);

        wb_read(ADDR_LOG_COUNT, read_data);
        check(32'd2, read_data, "LOG_COUNT after 2 events");

        read_log_entry(4'd0, read_data);
        check(32'hAAAA_0001, read_data, "LOG_READ_DATA[0] still correct");

        read_log_entry(4'd1, read_data);
        check(32'hBBBB_0002, read_data, "LOG_READ_DATA[1] correct");

        // ==================================================================
        // TEST 3: Lockout triggers at threshold (3rd event)
        // ==================================================================
        test_num = 3;
        $display("\n=== TEST %0d: Lockout at Threshold ===", test_num);

        // Check not locked out yet (2 events so far)
        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "No lockout after 2 events");

        // 3rd event → should trigger lockout (threshold=3)
        record_event(32'hCCCC_0003);

        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b1, read_data[0], "Lockout set after 3 events");

        // Check recovery count in status
        $display("  [INFO] window_recovery_count = %0d", read_data[15:8]);

        // ==================================================================
        // TEST 4: Lockout is Sticky
        // ==================================================================
        test_num = 4;
        $display("\n=== TEST %0d: Lockout is Sticky ===", test_num);

        // Wait some time
        repeat (50) @(posedge clk);

        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b1, read_data[0], "Lockout persists");

        // ==================================================================
        // TEST 5: Clear Lockout
        // ==================================================================
        test_num = 5;
        $display("\n=== TEST %0d: Clear Lockout ===", test_num);

        wb_write(ADDR_POL_CTRL, 32'h0002);  // clear_lockout
        repeat (3) @(posedge clk);

        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "Lockout cleared");

        // ==================================================================
        // TEST 6: Circular Buffer Wrap
        // ==================================================================
        test_num = 6;
        $display("\n=== TEST %0d: Circular Buffer Wrap ===", test_num);

        // We already have 3 events in the buffer.
        // Record 15 more to wrap (total 18, buffer holds 16)
        // First, set a very large window so we don't trigger lockout mid-test
        wb_write(ADDR_POL_WINDOW, 32'hFFFF_FFFF);
        wb_write(ADDR_POL_THRESHOLD, 32'd255);  // Very high threshold

        for (i = 4; i <= 18; i = i + 1) begin
            record_event(32'hDD00_0000 + i);
        end

        // Log count should be 18
        wb_read(ADDR_LOG_COUNT, read_data);
        check(32'd18, read_data, "LOG_COUNT after 18 events");

        // Oldest entries (0-1) should be overwritten
        // Buffer wraps at 16, so index 0 now holds event 17 (0xDD00_0011)
        // index 1 holds event 18 (0xDD00_0012)
        // index 2 still holds event 3 (0xCCCC_0003)
        read_log_entry(4'd2, read_data);
        check(32'hCCCC_0003, read_data, "Entry[2] preserved (event #3)");

        // Index 0 should be overwritten with event #17
        read_log_entry(4'd0, read_data);
        check(32'hDD00_0011, read_data, "Entry[0] overwritten with event #17");

        // Index 1 should be overwritten with event #18
        read_log_entry(4'd1, read_data);
        check(32'hDD00_0012, read_data, "Entry[1] overwritten with event #18");

        // ==================================================================
        // TEST 7: Window Reset Clears Recovery Count
        // ==================================================================
        test_num = 7;
        $display("\n=== TEST %0d: Window Reset Clears Recovery Count ===", test_num);

        // Reset everything via clear_lockout (resets counters)
        wb_write(ADDR_POL_CTRL, 32'h0002);
        repeat (3) @(posedge clk);

        // Configure short window and low threshold
        wb_write(ADDR_POL_WINDOW, 32'd50);
        wb_write(ADDR_POL_THRESHOLD, 32'd2);

        // Record 1 event
        record_event(32'hEE00_0001);
        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "No lockout after 1 event in new window");

        // Wait for window to expire (>50 cycles)
        repeat (60) @(posedge clk);

        // Record 1 more event — window should have reset, so count = 1 again
        record_event(32'hEE00_0002);
        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "No lockout — window reset cleared count");

        // ==================================================================
        // TEST 8: Rapid events within window trigger lockout
        // ==================================================================
        test_num = 8;
        $display("\n=== TEST %0d: Rapid Events Trigger Lockout ===", test_num);

        // Clear and reconfigure
        wb_write(ADDR_POL_CTRL, 32'h0002);
        repeat (3) @(posedge clk);

        wb_write(ADDR_POL_WINDOW, 32'd5000);
        wb_write(ADDR_POL_THRESHOLD, 32'd2);

        // 2 rapid events within window
        record_event(32'hFF00_0001);
        record_event(32'hFF00_0002);

        wb_read(ADDR_POL_STATUS, read_data);
        check(1'b1, read_data[0], "Lockout after 2 rapid events (threshold=2)");

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
