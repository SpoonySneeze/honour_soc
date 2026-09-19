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
    axi_heartbeat_monitor dut (
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
        .s_axi_rready (axi_rready),
        .heartbeat_in(heartbeat_in),
        .hb_irq      (hb_irq)
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
            $display("axi_write: start addr=%h data=%h", addr, data);
            @(posedge clk);
            axi_awaddr  <= addr;
            axi_awvalid <= 1'b1;
            axi_wdata   <= data;
            axi_wstrb   <= 4'hF;
            axi_wvalid  <= 1'b1;
            axi_bready  <= 1'b1;
            
            while (axi_awvalid || axi_wvalid) begin
                @(posedge clk);
                $display("axi_write: wait valid aw=%b w=%b awready=%b wready=%b", axi_awvalid, axi_wvalid, axi_awready, axi_wready);
            end
            
            while (!axi_bvalid) begin
                @(posedge clk);
                $display("axi_write: wait bvalid=%b bready=%b", axi_bvalid, axi_bready);
            end
            axi_bready <= 1'b0;
            @(posedge clk);
            $display("axi_write: done");
        end
    endtask

    task axi_read(input [7:0] addr, output [31:0] data);
        begin
            $display("axi_read: start addr=%h", addr);
            @(posedge clk);
            axi_araddr  <= addr;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;
            
            while (axi_arvalid) begin
                @(posedge clk);
                $display("axi_read: wait valid ar=%b arready=%b", axi_arvalid, axi_arready);
            end
            
            while (!axi_rvalid) begin
                @(posedge clk);
                $display("axi_read: wait rvalid=%b rready=%b", axi_rvalid, axi_rready);
            end
            data = axi_rdata;
            axi_rready <= 1'b0;
            @(posedge clk);
            $display("axi_read: done data=%h", data);
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
            $display("send_heartbeat: start");
            @(posedge clk);
            heartbeat_in <= 1'b1;
            @(posedge clk);
            heartbeat_in <= 1'b0;
            $display("send_heartbeat: done");
        end
    endtask

    // ========================================================================
    // Test Stimulus
    // ========================================================================
    initial begin
        $dumpfile("tb_heartbeat_monitor.vcd");
        $dumpvars(0, tb_heartbeat_monitor);

        // Initialize
        rst         = 1;
        axi_awaddr  = 0;
        axi_awvalid = 0;
        axi_wdata   = 0;
        axi_wstrb   = 0;
        axi_wvalid  = 0;
        axi_bready  = 0;
        axi_araddr  = 0;
        axi_arvalid = 0;
        axi_rready  = 0;
        heartbeat_in = 0;
        test_num    = 0;
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
        axi_write(ADDR_HB_THRESHOLD, 32'd50);

        // Enable monitoring
        axi_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat to transition from IDLE → COUNTING
        send_heartbeat;

        // Send heartbeats every 20 cycles (well under threshold)
        repeat (5) begin
            repeat (20) @(posedge clk);
            send_heartbeat;
        end
        $display("Finished repeat loop");

        // Check: unresponsive flag should NOT be set
        axi_read(ADDR_HB_STATUS, read_data);
        check(32'd0, read_data[0], "Unresponsive flag should be 0");

        // Disable
        axi_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 2: Timeout Detection — heartbeat stops
        // ==================================================================
        test_num = 2;
        $display("\n=== TEST %0d: Timeout Detection ===", test_num);

        // Set threshold to 30 cycles
        axi_write(ADDR_HB_THRESHOLD, 32'd30);

        // Enable monitoring
        axi_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat
        send_heartbeat;

        // Wait well past threshold without sending heartbeat
        repeat (50) @(posedge clk);

        // Check: unresponsive flag should be set
        axi_read(ADDR_HB_STATUS, read_data);
        check(32'd1, read_data[0], "Unresponsive flag should be 1");

        // Check: IRQ output should be high
        check(1'b1, hb_irq, "hb_irq should be asserted");

        // Disable
        axi_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 3: Flag Latching — heartbeat resumes but flag stays
        // ==================================================================
        test_num = 3;
        $display("\n=== TEST %0d: Flag Latching ===", test_num);

        // Set threshold to 20 cycles
        axi_write(ADDR_HB_THRESHOLD, 32'd20);
        axi_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat, then let it timeout
        send_heartbeat;
        repeat (30) @(posedge clk);

        // Verify flag is set
        axi_read(ADDR_HB_STATUS, read_data);
        check(32'd1, read_data[0], "Flag set after timeout");

        // Resume heartbeats — flag should STAY set (latched)
        send_heartbeat;
        repeat (5) @(posedge clk);
        send_heartbeat;
        repeat (5) @(posedge clk);

        axi_read(ADDR_HB_STATUS, read_data);
        check(32'd1, read_data[0], "Flag stays latched after heartbeat resumes");

        // Now clear the flag via HB_CTRL.clear_flag
        axi_write(ADDR_HB_CTRL, 32'h0003);  // enable + clear_flag
        repeat (3) @(posedge clk);

        axi_read(ADDR_HB_STATUS, read_data);
        check(32'd0, read_data[0], "Flag cleared after firmware clear");

        // Disable
        axi_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 4: Counter Accuracy — HB_ELAPSED
        // ==================================================================
        test_num = 4;
        $display("\n=== TEST %0d: Counter Accuracy ===", test_num);

        axi_write(ADDR_HB_THRESHOLD, 32'd1000);  // High threshold
        axi_write(ADDR_HB_CTRL, 32'h0001);

        // Send first heartbeat to start counting
        send_heartbeat;

        // Wait exactly 25 cycles
        repeat (25) @(posedge clk);

        // Read elapsed — should be approximately 25
        // (exact value depends on cycle alignment of the read itself)
        axi_read(ADDR_HB_ELAPSED, read_data);
        $display("  [INFO] HB_ELAPSED after ~25 cycles: %0d", read_data);
        if (read_data >= 32'd22 && read_data <= 32'd30) begin
            $display("  [PASS] HB_ELAPSED in expected range [22..30]");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] HB_ELAPSED out of range: %0d", read_data);
            fail_count = fail_count + 1;
        end

        // Disable
        axi_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // ==================================================================
        // TEST 5: Disable/Re-enable
        // ==================================================================
        test_num = 5;
        $display("\n=== TEST %0d: Disable/Re-enable ===", test_num);

        // Start monitoring
        axi_write(ADDR_HB_THRESHOLD, 32'd20);
        axi_write(ADDR_HB_CTRL, 32'h0001);
        send_heartbeat;
        repeat (10) @(posedge clk);

        // Disable mid-count
        axi_write(ADDR_HB_CTRL, 32'h0000);
        repeat (5) @(posedge clk);

        // Counter should be reset
        axi_read(ADDR_HB_ELAPSED, read_data);
        check(32'd0, read_data, "Counter resets on disable");

        // Flag should be cleared
        axi_read(ADDR_HB_STATUS, read_data);
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
