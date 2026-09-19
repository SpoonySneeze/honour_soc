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
    reg  [7:0]  axi_awaddr;
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [63:0] axi_wdata;
    reg  [3:0]  axi_wstrb;
    reg         axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready;
    reg  [7:0]  axi_araddr;
    reg         axi_arvalid;
    wire        axi_arready;
    wire [63:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    reg         axi_rready;

    // Concurrent handshake clear logic
    always @(posedge clk) begin
        if (rst) begin
            axi_awvalid <= 1'b0;
            axi_wvalid  <= 1'b0;
            axi_arvalid <= 1'b0;
        end else begin
            if (axi_awvalid && axi_awready) axi_awvalid <= 1'b0;
            if (axi_wvalid && axi_wready)   axi_wvalid <= 1'b0;
            if (axi_arvalid && axi_arready) axi_arvalid <= 1'b0;
        end
    end

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    axi_recovery_policy dut (
        .clk         (clk),
        .rst_n       (~rst),
        .s_axi_awaddr (axi_awaddr),
        .s_axi_awprot (3'b0),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),
        .s_axi_wdata  (axi_wdata),
        .s_axi_wstrb  (axi_wstrb),
        .s_axi_wvalid (axi_wvalid),
        .s_axi_wready (axi_wready),
        .s_axi_bresp  (axi_bresp),
        .s_axi_bvalid (axi_bvalid),
        .s_axi_bready (axi_bready),
        .s_axi_araddr (axi_araddr),
        .s_axi_arprot (3'b0),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),
        .s_axi_rdata  (axi_rdata),
        .s_axi_rresp  (axi_rresp),
        .s_axi_rvalid (axi_rvalid),
        .s_axi_rready (axi_rready)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // AXI-Lite Bus Tasks
    // ========================================================================
    task axi_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            axi_awaddr  <= addr;
            axi_awvalid <= 1'b1;
            axi_wdata   <= addr[2] ? {data, 32'd0} : {32'd0, data};
            axi_wstrb   <= 4'hF;
            axi_wvalid  <= 1'b1;
            axi_bready  <= 1'b1;
            
            while (axi_awvalid || axi_wvalid) @(posedge clk);
            
            while (!axi_bvalid) @(posedge clk);
            axi_bready <= 1'b0;
            @(posedge clk);
        end
    endtask

    task axi_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            axi_araddr  <= addr;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;
            
            while (axi_arvalid) @(posedge clk);
            
            while (!axi_rvalid) @(posedge clk);
            data = addr[2] ? axi_rdata[63:32] : axi_rdata[31:0];
            axi_rready <= 1'b0;
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
            axi_write(ADDR_POL_EVENT_TS, timestamp);
            axi_write(ADDR_POL_CTRL, 32'h0001);  // record_event
        end
    endtask

    // Read a log entry at a given index
    task read_log_entry(input [3:0] idx, output [31:0] data);
        begin
            axi_write(ADDR_LOG_READ_IDX, {28'd0, idx});
            axi_read(ADDR_LOG_READ_DATA, data);
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
        axi_awaddr  = 0;
        axi_awvalid = 0;
        axi_wdata   = 0;
        axi_wstrb   = 0;
        axi_wvalid  = 0;
        axi_bready  = 0;
        axi_araddr  = 0;
        axi_arvalid = 0;
        axi_rready  = 0;
        pass_count = 0;
        fail_count = 0;

        // System reset
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ==================================================================
        // Configure: window=10000 cycles, threshold=3 recoveries
        // ==================================================================
        axi_write(ADDR_POL_WINDOW, 32'd10000);
        axi_write(ADDR_POL_THRESHOLD, 32'd3);

        // ==================================================================
        // TEST 1: Single Event Recording
        // ==================================================================
        test_num = 1;
        $display("\n=== TEST %0d: Single Event Recording ===", test_num);

        record_event(32'hAAAA_0001);

        // Check log count
        axi_read(ADDR_LOG_COUNT, read_data);
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

        axi_read(ADDR_LOG_COUNT, read_data);
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
        axi_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "No lockout after 2 events");

        // 3rd event → should trigger lockout (threshold=3)
        record_event(32'hCCCC_0003);

        axi_read(ADDR_POL_STATUS, read_data);
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

        axi_read(ADDR_POL_STATUS, read_data);
        check(1'b1, read_data[0], "Lockout persists");

        // ==================================================================
        // TEST 5: Clear Lockout
        // ==================================================================
        test_num = 5;
        $display("\n=== TEST %0d: Clear Lockout ===", test_num);

        axi_write(ADDR_POL_CTRL, 32'h0002);  // clear_lockout
        repeat (3) @(posedge clk);

        axi_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "Lockout cleared");

        // ==================================================================
        // TEST 6: Circular Buffer Wrap
        // ==================================================================
        test_num = 6;
        $display("\n=== TEST %0d: Circular Buffer Wrap ===", test_num);

        // We already have 3 events in the buffer.
        // Record 15 more to wrap (total 18, buffer holds 16)
        // First, set a very large window so we don't trigger lockout mid-test
        axi_write(ADDR_POL_WINDOW, 32'hFFFF_FFFF);
        axi_write(ADDR_POL_THRESHOLD, 32'd255);  // Very high threshold

        for (i = 4; i <= 18; i = i + 1) begin
            record_event(32'hDD00_0000 + i);
        end

        // Log count should be 18
        axi_read(ADDR_LOG_COUNT, read_data);
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
        axi_write(ADDR_POL_CTRL, 32'h0002);
        repeat (3) @(posedge clk);

        // Configure short window and low threshold
        axi_write(ADDR_POL_WINDOW, 32'd50);
        axi_write(ADDR_POL_THRESHOLD, 32'd2);

        // Record 1 event
        record_event(32'hEE00_0001);
        axi_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "No lockout after 1 event in new window");

        // Wait for window to expire (>50 cycles)
        repeat (60) @(posedge clk);

        // Record 1 more event — window should have reset, so count = 1 again
        record_event(32'hEE00_0002);
        axi_read(ADDR_POL_STATUS, read_data);
        check(1'b0, read_data[0], "No lockout — window reset cleared count");

        // ==================================================================
        // TEST 8: Rapid events within window trigger lockout
        // ==================================================================
        test_num = 8;
        $display("\n=== TEST %0d: Rapid Events Trigger Lockout ===", test_num);

        // Clear and reconfigure
        axi_write(ADDR_POL_CTRL, 32'h0002);
        repeat (3) @(posedge clk);

        axi_write(ADDR_POL_WINDOW, 32'd5000);
        axi_write(ADDR_POL_THRESHOLD, 32'd2);

        // 2 rapid events within window
        record_event(32'hFF00_0001);
        record_event(32'hFF00_0002);

        axi_read(ADDR_POL_STATUS, read_data);
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
