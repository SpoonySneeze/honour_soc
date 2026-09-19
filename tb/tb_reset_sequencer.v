// ============================================================================
// Testbench — Power/Reset Sequencer (Unit Test)
// ============================================================================
// Tests:
//   1. Basic reset pulse: trigger → reset_out low for RST_HOLD_CYCLES
//   2. Status flags: in_progress and complete track correctly
//   3. Re-trigger while busy: second trigger is ignored
//   4. Configurable hold duration
//   5. Back-to-back triggers (sequential)
// ============================================================================

`timescale 1ns / 1ps

module tb_reset_sequencer;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CLK_PERIOD = 10;  // 100 MHz

    // Register offsets
    localparam ADDR_RST_CTRL        = 8'h00;
    localparam ADDR_RST_HOLD_CYCLES = 8'h04;
    localparam ADDR_RST_STATUS      = 8'h08;

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

    wire        reset_out;
    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    axi_reset_sequencer dut (
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
        .reset_out(reset_out)
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

    // ========================================================================
    // Reset Pulse Measurement
    // ========================================================================
    integer reset_low_count;

    always @(posedge clk) begin
        if (!reset_out)
            reset_low_count <= reset_low_count + 1;
    end

    // ========================================================================
    // Test Stimulus
    // ========================================================================
    initial begin
        $dumpfile("tb_reset_sequencer.vcd");
        $dumpvars(0, tb_reset_sequencer);

        // Initialize
        rst            = 1;
        axi_awaddr  = 0;
        axi_awvalid = 0;
        axi_wdata   = 0;
        axi_wstrb   = 0;
        axi_wvalid  = 0;
        axi_bready  = 0;
        axi_araddr  = 0;
        axi_arvalid = 0;
        axi_rready  = 0;
        test_num       = 0;
        pass_count     = 0;
        fail_count     = 0;
        reset_low_count = 0;

        // System reset
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // Check initial state: reset_out should be high (deasserted)
        check(1'b1, reset_out, "Initial reset_out deasserted");

        // ==================================================================
        // TEST 1: Basic Reset Pulse — 50 cycle hold
        // ==================================================================
        test_num = 1;
        $display("\n=== TEST %0d: Basic Reset Pulse (50 cycles) ===", test_num);

        axi_write(ADDR_RST_HOLD_CYCLES, 32'd50);
        reset_low_count = 0;

        // Trigger
        axi_write(ADDR_RST_CTRL, 32'h0001);

        // Wait for completion
        repeat (70) @(posedge clk);

        // Check status — should be complete
        axi_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "RST_STATUS: complete=1, in_progress=0");

        // Check reset_out returned high
        check(1'b1, reset_out, "reset_out deasserted after sequence");

        // Check hold duration (approximately 50+1 cycles including the ASSERT→DEASSERT)
        $display("  [INFO] reset_out was low for %0d cycles", reset_low_count);
        if (reset_low_count >= 50 && reset_low_count <= 53) begin
            $display("  [PASS] Hold duration in expected range [50..53]");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Hold duration out of range: %0d", reset_low_count);
            fail_count = fail_count + 1;
        end

        // ==================================================================
        // TEST 2: Status Flags — in_progress during sequence
        // ==================================================================
        test_num = 2;
        $display("\n=== TEST %0d: Status Flags ===", test_num);

        axi_write(ADDR_RST_HOLD_CYCLES, 32'd100);

        // Trigger
        axi_write(ADDR_RST_CTRL, 32'h0001);

        // Read status immediately — should be in_progress
        repeat (3) @(posedge clk);
        axi_read(ADDR_RST_STATUS, read_data);
        check(32'h0001, read_data & 32'h0001, "in_progress=1 during sequence");

        // Wait for completion
        repeat (120) @(posedge clk);

        axi_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "complete=1 after sequence");

        // ==================================================================
        // TEST 3: Re-trigger while busy — should be ignored
        // ==================================================================
        test_num = 3;
        $display("\n=== TEST %0d: Re-trigger While Busy ===", test_num);

        axi_write(ADDR_RST_HOLD_CYCLES, 32'd80);
        reset_low_count = 0;

        // Trigger first sequence
        axi_write(ADDR_RST_CTRL, 32'h0001);
        repeat (20) @(posedge clk);

        // Try to re-trigger (should be ignored)
        axi_write(ADDR_RST_CTRL, 32'h0001);

        // Wait for original sequence to complete
        repeat (100) @(posedge clk);

        // Reset_out should be high
        check(1'b1, reset_out, "reset_out deasserted after ignored re-trigger");

        // Hold duration should match original (not doubled)
        $display("  [INFO] reset_out was low for %0d cycles (should be ~80)", reset_low_count);
        if (reset_low_count >= 80 && reset_low_count <= 83) begin
            $display("  [PASS] Hold duration matches original sequence");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Hold duration unexpected: %0d", reset_low_count);
            fail_count = fail_count + 1;
        end

        // ==================================================================
        // TEST 4: Different hold duration
        // ==================================================================
        test_num = 4;
        $display("\n=== TEST %0d: Configurable Hold Duration (10 cycles) ===", test_num);

        axi_write(ADDR_RST_HOLD_CYCLES, 32'd10);
        reset_low_count = 0;

        axi_write(ADDR_RST_CTRL, 32'h0001);
        repeat (30) @(posedge clk);

        axi_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "Complete after short hold");

        $display("  [INFO] reset_out was low for %0d cycles", reset_low_count);
        if (reset_low_count >= 10 && reset_low_count <= 13) begin
            $display("  [PASS] Short hold duration correct");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Short hold duration unexpected: %0d", reset_low_count);
            fail_count = fail_count + 1;
        end

        // ==================================================================
        // TEST 5: Back-to-back Sequential Triggers
        // ==================================================================
        test_num = 5;
        $display("\n=== TEST %0d: Back-to-Back Sequential Triggers ===", test_num);

        axi_write(ADDR_RST_HOLD_CYCLES, 32'd15);

        // First trigger
        axi_write(ADDR_RST_CTRL, 32'h0001);
        repeat (30) @(posedge clk);
        axi_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "First sequential trigger complete");

        // Second trigger
        reset_low_count = 0;
        axi_write(ADDR_RST_CTRL, 32'h0001);
        repeat (30) @(posedge clk);
        axi_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "Second sequential trigger complete");

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
