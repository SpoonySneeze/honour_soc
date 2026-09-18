`include "timescale.v"
// ============================================================
// tb_axi_master.v
// AXI Master BFM Testbench for AES AXI4-Lite Wrapper
//
// Tests:
//   1: CSR reset state
//   2: CSR read/write
//   3: Encryption (NIST FIPS-197 Appendix B)
//   4: Decryption (round-trip)
//   5: STATUS.DONE sticky + W1C
//   6: BUSY assertion
//   7: Back-to-back operations
// ============================================================

module tb_axi_master;

// ----------------------------------------------------------------
// Clock / reset
// ----------------------------------------------------------------
reg aclk, aresetn;
initial aclk = 0;
always #5 aclk = ~aclk;    // 100 MHz

// ----------------------------------------------------------------
// AXI master ports
// ----------------------------------------------------------------
reg  [7:0]  m_awaddr;  reg  m_awvalid; wire m_awready;
reg  [31:0] m_wdata;   reg  [3:0] m_wstrb; reg  m_wvalid; wire m_wready;
wire [1:0]  m_bresp;   wire m_bvalid;  reg  m_bready;
reg  [7:0]  m_araddr;  reg  m_arvalid; wire m_arready;
wire [31:0] m_rdata;   wire [1:0] m_rresp;  wire m_rvalid; reg  m_rready;

// ----------------------------------------------------------------
// DUT
// ----------------------------------------------------------------
aes_axi dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
    .s_axi_wdata(m_wdata),   .s_axi_wstrb(m_wstrb),    .s_axi_wvalid(m_wvalid),  .s_axi_wready(m_wready),
    .s_axi_bresp(m_bresp),   .s_axi_bvalid(m_bvalid),  .s_axi_bready(m_bready),
    .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid),.s_axi_arready(m_arready),
    .s_axi_rdata(m_rdata),   .s_axi_rresp(m_rresp),    .s_axi_rvalid(m_rvalid),  .s_axi_rready(m_rready)
);

// ----------------------------------------------------------------
// Address map
// ----------------------------------------------------------------
localparam ADDR_CTRL  = 8'h00;
localparam ADDR_STS   = 8'h04;
localparam ADDR_KEY0  = 8'h08;
localparam ADDR_KEY1  = 8'h0C;
localparam ADDR_KEY2  = 8'h10;
localparam ADDR_KEY3  = 8'h14;
localparam ADDR_TEXT0 = 8'h18;
localparam ADDR_TEXT1 = 8'h1C;
localparam ADDR_TEXT2 = 8'h20;
localparam ADDR_TEXT3 = 8'h24;
localparam ADDR_OUT0  = 8'h28;
localparam ADDR_OUT1  = 8'h2C;
localparam ADDR_OUT2  = 8'h30;
localparam ADDR_OUT3  = 8'h34;

integer error_cnt;

// ================================================================
// axi_write  – fully posedge-synchronous
// ================================================================
// The slave may assert awready and wready in the SAME clock cycle.
// Strategy:
//  - Drive AW+W valid on the falling edge before we start polling.
//  - Poll on posedge only; use registered flags to remember which
//    channels have been accepted; de-assert valid on the next falling
//    edge AFTER the sampling loop exits.
//  - No nested @(negedge) inside the posedge while-loop.
task axi_write;
    input [7:0]  addr;
    input [31:0] data;
    reg aw_done, w_done;
    integer cyc;
    begin
        aw_done = 0;
        w_done  = 0;

        // Present both channels before the next posedge
        @(negedge aclk);
        m_awaddr  = addr;
        m_awvalid = 1'b1;
        m_wdata   = data;
        m_wstrb   = 4'hF;
        m_wvalid  = 1'b1;
        m_bready  = 1'b1;

        // Poll on posedges. Sample ready, set flags; never
        // go to negedge inside this loop.
        cyc = 0;
        while ((!aw_done || !w_done) && cyc < 100) begin
            @(posedge aclk);
            if (m_awready) aw_done = 1;
            if (m_wready)  w_done  = 1;
            cyc = cyc + 1;
        end
        if (cyc >= 100) begin
            $display("ERROR: axi_write handshake timeout addr=%0h", addr);
            error_cnt = error_cnt + 1;
        end

        // De-assert valids on the next negedge (outside the loop)
        @(negedge aclk);
        m_awvalid = 1'b0;
        m_wvalid  = 1'b0;

        // Wait for B on posedge
        @(posedge aclk);
        while (!m_bvalid) @(posedge aclk);
        // bvalid is high; slave clears it next posedge (bvalid&&bready)
        @(posedge aclk);
        @(negedge aclk);
        m_bready = 1'b0;

        // One idle posedge
        @(posedge aclk);
    end
endtask

// ================================================================
// axi_read
// ================================================================
task axi_read;
    input  [7:0]  addr;
    output [31:0] data;
    begin
        @(negedge aclk);
        m_araddr  = addr;
        m_arvalid = 1'b1;
        m_rready  = 1'b1;

        @(posedge aclk);
        while (!m_arready) @(posedge aclk);
        @(negedge aclk);
        m_arvalid = 1'b0;

        @(posedge aclk);
        while (!m_rvalid) @(posedge aclk);
        data = m_rdata;
        @(negedge aclk);
        m_rready = 1'b0;

        @(posedge aclk);
    end
endtask

// ================================================================
// Higher-level tasks
// ================================================================
task aes_write_key;
    input [127:0] key;
    begin
        axi_write(ADDR_KEY0, key[31:0]);
        axi_write(ADDR_KEY1, key[63:32]);
        axi_write(ADDR_KEY2, key[95:64]);
        axi_write(ADDR_KEY3, key[127:96]);
    end
endtask

task aes_write_text;
    input [127:0] text;
    begin
        axi_write(ADDR_TEXT0, text[31:0]);
        axi_write(ADDR_TEXT1, text[63:32]);
        axi_write(ADDR_TEXT2, text[95:64]);
        axi_write(ADDR_TEXT3, text[127:96]);
    end
endtask

task aes_start;
    input decrypt;
    begin
        axi_write(ADDR_CTRL, {30'h0, decrypt[0], 1'b1});
    end
endtask

task aes_wait_done;
    reg [31:0] status;
    integer    timeout;
    begin
        timeout = 0;
        status  = 32'h0;
        while (!status[0] && timeout < 3000) begin
            axi_read(ADDR_STS, status);
            timeout = timeout + 1;
        end
        if (timeout >= 3000) begin
            $display("ERROR: aes_wait_done TIMEOUT at time %0t", $time);
            error_cnt = error_cnt + 1;
        end
    end
endtask

task aes_read_output;
    output [127:0] data;
    reg [31:0] tmp;
    begin
        axi_read(ADDR_OUT0, tmp); data[31:0]   = tmp;
        axi_read(ADDR_OUT1, tmp); data[63:32]  = tmp;
        axi_read(ADDR_OUT2, tmp); data[95:64]  = tmp;
        axi_read(ADDR_OUT3, tmp); data[127:96] = tmp;
    end
endtask

task aes_clear_done;
    begin
        axi_write(ADDR_STS, 32'h1);
    end
endtask

// ================================================================
// Checkers
// ================================================================
task check_eq;
    input [127:0] got;
    input [127:0] exp;
    input [8*32-1:0] label;
    begin
        if (got !== exp) begin
            $display("FAIL [%0s]: exp %032h  got %032h", label, exp, got);
            error_cnt = error_cnt + 1;
        end else
            $display("PASS [%0s]: %032h", label, got);
    end
endtask

task check_eq32;
    input [31:0] got;
    input [31:0] exp;
    input [8*32-1:0] label;
    begin
        if (got !== exp) begin
            $display("FAIL [%0s]: exp %08h  got %08h", label, exp, got);
            error_cnt = error_cnt + 1;
        end else
            $display("PASS [%0s]: %08h", label, got);
    end
endtask

// ----------------------------------------------------------------
// Test vectors
// ----------------------------------------------------------------
// NIST FIPS-197 Appendix B
localparam [127:0] NIST_KEY   = 128'h2b7e151628aed2a6abf7158809cf4f3c;
localparam [127:0] NIST_PLAIN = 128'h3243f6a8885a308d313198a2e0370734;
localparam [127:0] NIST_CIPH  = 128'h3925841d02dc09fbdc118597196a0b32;

// Original TB tv[0]
localparam [127:0] TV0_KEY   = 128'h0;
localparam [127:0] TV0_PLAIN = 128'hf34481ec3cc627bacd5dc3fb08f273e6;
localparam [127:0] TV0_CIPH  = 128'h0336763e966d92595a567cc9ce537f5e;

// ----------------------------------------------------------------
// Main
// ----------------------------------------------------------------
reg [127:0] result;
reg [31:0]  rd_val;

initial begin
    $fsdbDumpfile("wave.fsdb");
    $fsdbDumpvars(0, tb_axi_master);

    // Initialise all master signals idle
    m_awaddr=0; m_awvalid=0;
    m_wdata=0; m_wstrb=0; m_wvalid=0;
    m_bready=0;
    m_araddr=0; m_arvalid=0;
    m_rready=0;
    error_cnt = 0;

    // Reset
    aresetn = 0;
    repeat(8) @(posedge aclk);
    @(negedge aclk); aresetn = 1;
    repeat(4) @(posedge aclk);

    $display("\n=====================================================");
    $display(" AES AXI4-Lite Testbench Starting");
    $display("=====================================================");

    // ===========================================================
    // Test 1: CSR reset state
    // ===========================================================
    $display("\n--- Test 1: CSR Reset State ---");
    axi_read(ADDR_CTRL,  rd_val); check_eq32(rd_val, 32'h0, "CTRL  reset");
    axi_read(ADDR_STS,   rd_val); check_eq32(rd_val, 32'h0, "STATUS reset");
    axi_read(ADDR_KEY0,  rd_val); check_eq32(rd_val, 32'h0, "KEY0  reset");
    axi_read(ADDR_TEXT0, rd_val); check_eq32(rd_val, 32'h0, "TEXT0 reset");
    axi_read(ADDR_OUT0,  rd_val); check_eq32(rd_val, 32'h0, "OUT0  reset");

    // ===========================================================
    // Test 2: CSR read/write
    // ===========================================================
    $display("\n--- Test 2: CSR Read/Write ---");
    axi_write(ADDR_KEY0, 32'hDEADBEEF);
    axi_read (ADDR_KEY0, rd_val);
    check_eq32(rd_val, 32'hDEADBEEF, "KEY0 R/W");

    axi_write(ADDR_KEY1, 32'hCAFEBABE);
    axi_read (ADDR_KEY1, rd_val);
    check_eq32(rd_val, 32'hCAFEBABE, "KEY1 R/W");

    // OUT registers are RO
    axi_write(ADDR_OUT0, 32'hFFFFFFFF);
    axi_read (ADDR_OUT0, rd_val);
    check_eq32(rd_val, 32'h0, "OUT0 RO");

    // DECRYPT mode bit
    axi_write(ADDR_CTRL, 32'h2);
    axi_read (ADDR_CTRL, rd_val);
    check_eq32(rd_val[1], 1'b1, "CTRL DECRYPT set");
    axi_write(ADDR_CTRL, 32'h0);

    // ===========================================================
    // Test 3: Encryption – NIST FIPS-197 Appendix B
    // ===========================================================
    $display("\n--- Test 3: Encryption (NIST FIPS-197) ---");
    $display("  Key   : %032h", NIST_KEY);
    $display("  Plain : %032h", NIST_PLAIN);
    $display("  Expect: %032h", NIST_CIPH);
    aes_write_key (NIST_KEY);
    aes_write_text(NIST_PLAIN);
    aes_start(0);
    aes_wait_done();
    aes_read_output(result);
    check_eq(result, NIST_CIPH, "Encryption");
    aes_clear_done();

    // ===========================================================
    // Test 4: Decryption – round-trip
    // ===========================================================
    $display("\n--- Test 4: Decryption (round-trip) ---");
    aes_write_key (NIST_KEY);
    aes_write_text(NIST_CIPH);
    aes_start(1);
    aes_wait_done();
    aes_read_output(result);
    check_eq(result, NIST_PLAIN, "Decryption");
    aes_clear_done();

    // ===========================================================
    // Test 5: STATUS.DONE sticky + W1C
    // ===========================================================
    $display("\n--- Test 5: STATUS.DONE Sticky + W1C ---");
    aes_write_key (NIST_KEY);
    aes_write_text(NIST_PLAIN);
    aes_start(0);
    aes_wait_done();

    axi_read(ADDR_STS, rd_val);
    check_eq32(rd_val[0], 1'b1, "DONE is set");
    check_eq32(rd_val[1], 1'b0, "BUSY clear");

    axi_read(ADDR_STS, rd_val);
    check_eq32(rd_val[0], 1'b1, "DONE sticky after read");

    aes_clear_done();
    axi_read(ADDR_STS, rd_val);
    check_eq32(rd_val[0], 1'b0, "DONE cleared W1C");

    // ===========================================================
    // Test 6: BUSY assertion
    // ===========================================================
    $display("\n--- Test 6: BUSY Assertion ---");
    aes_write_key (NIST_KEY);
    aes_write_text(NIST_PLAIN);
    aes_start(0);

    // Read STATUS immediately after start — BUSY should be 1
    axi_read(ADDR_STS, rd_val);
    check_eq32(rd_val[1], 1'b1, "BUSY=1 during op");

    aes_wait_done();
    axi_read(ADDR_STS, rd_val);
    check_eq32(rd_val[1], 1'b0, "BUSY=0 after done");
    aes_clear_done();

    // ===========================================================
    // Test 7: Back-to-back operations
    // ===========================================================
    $display("\n--- Test 7: Back-to-Back Operations ---");

    aes_write_key (TV0_KEY);
    aes_write_text(TV0_PLAIN);
    aes_start(0);
    aes_wait_done();
    aes_read_output(result);
    check_eq(result, TV0_CIPH,  "BB enc1 (TV0)");
    aes_clear_done();

    aes_write_key (TV0_KEY);
    aes_write_text(TV0_CIPH);
    aes_start(1);
    aes_wait_done();
    aes_read_output(result);
    check_eq(result, TV0_PLAIN, "BB dec1 (TV0)");
    aes_clear_done();

    aes_write_key (NIST_KEY);
    aes_write_text(NIST_PLAIN);
    aes_start(0);
    aes_wait_done();
    aes_read_output(result);
    check_eq(result, NIST_CIPH, "BB enc2 (NIST)");
    aes_clear_done();

    aes_write_key (NIST_KEY);
    aes_write_text(NIST_CIPH);
    aes_start(1);
    aes_wait_done();
    aes_read_output(result);
    check_eq(result, NIST_PLAIN,"BB dec2 (NIST)");
    aes_clear_done();

    // ===========================================================
    // Summary
    // ===========================================================
    repeat(10) @(posedge aclk);
    $display("\n=====================================================");
    if (error_cnt == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" TESTS DONE: %0d FAILURE(S)", error_cnt);
    $display("=====================================================\n");
    $finish;
end

endmodule
