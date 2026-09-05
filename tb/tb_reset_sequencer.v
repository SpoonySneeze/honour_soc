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
    reg  [7:0]  wb_adr;
    reg  [31:0] wb_dat_wr;
    wire [31:0] wb_dat_rd;
    reg         wb_we;
    reg  [3:0]  wb_sel;
    reg         wb_stb;
    reg         wb_cyc;
    wire        wb_ack;
    wire        reset_out;

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    reset_sequencer dut (
        .wb_clk_i  (clk),
        .wb_rst_i  (rst),
        .wb_adr_i  (wb_adr),
        .wb_dat_i  (wb_dat_wr),
        .wb_dat_o  (wb_dat_rd),
        .wb_we_i   (wb_we),
        .wb_sel_i  (wb_sel),
        .wb_stb_i  (wb_stb),
        .wb_cyc_i  (wb_cyc),
        .wb_ack_o  (wb_ack),
        .reset_out (reset_out)
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
        wb_adr         = 0;
        wb_dat_wr      = 0;
        wb_we          = 0;
        wb_sel         = 0;
        wb_stb         = 0;
        wb_cyc         = 0;
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

        wb_write(ADDR_RST_HOLD_CYCLES, 32'd50);
        reset_low_count = 0;

        // Trigger
        wb_write(ADDR_RST_CTRL, 32'h0001);

        // Wait for completion
        repeat (70) @(posedge clk);

        // Check status — should be complete
        wb_read(ADDR_RST_STATUS, read_data);
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

        wb_write(ADDR_RST_HOLD_CYCLES, 32'd100);

        // Trigger
        wb_write(ADDR_RST_CTRL, 32'h0001);

        // Read status immediately — should be in_progress
        repeat (3) @(posedge clk);
        wb_read(ADDR_RST_STATUS, read_data);
        check(32'h0001, read_data & 32'h0001, "in_progress=1 during sequence");

        // Wait for completion
        repeat (120) @(posedge clk);

        wb_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "complete=1 after sequence");

        // ==================================================================
        // TEST 3: Re-trigger while busy — should be ignored
        // ==================================================================
        test_num = 3;
        $display("\n=== TEST %0d: Re-trigger While Busy ===", test_num);

        wb_write(ADDR_RST_HOLD_CYCLES, 32'd80);
        reset_low_count = 0;

        // Trigger first sequence
        wb_write(ADDR_RST_CTRL, 32'h0001);
        repeat (20) @(posedge clk);

        // Try to re-trigger (should be ignored)
        wb_write(ADDR_RST_CTRL, 32'h0001);

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

        wb_write(ADDR_RST_HOLD_CYCLES, 32'd10);
        reset_low_count = 0;

        wb_write(ADDR_RST_CTRL, 32'h0001);
        repeat (30) @(posedge clk);

        wb_read(ADDR_RST_STATUS, read_data);
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

        wb_write(ADDR_RST_HOLD_CYCLES, 32'd15);

        // First trigger
        wb_write(ADDR_RST_CTRL, 32'h0001);
        repeat (30) @(posedge clk);
        wb_read(ADDR_RST_STATUS, read_data);
        check(32'h0002, read_data & 32'h0003, "First sequential trigger complete");

        // Second trigger
        reset_low_count = 0;
        wb_write(ADDR_RST_CTRL, 32'h0001);
        repeat (30) @(posedge clk);
        wb_read(ADDR_RST_STATUS, read_data);
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
