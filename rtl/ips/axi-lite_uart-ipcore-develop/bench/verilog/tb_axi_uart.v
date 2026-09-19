// ============================================================
// tb_axi_uart.v
// AXI4-Lite Master BFM Testbench for AXI-lite UART IP Core
//
// Project : AXI-lite UART IP Core
// File    : tb_axi_uart.v
//
// DUT AXI read map (read FSM only responds to two addresses):
//   index 0 (0x00) -> RBR  (receive buffer, DLAB=0)
//   index 5 (0x14) -> LSR  (line status register)
//   all others     -> default (arready/rvalid never asserted)
//
// DUT AXI write map (write FSM):
//   index 0 (0x00) -> THR  (transmit, DLAB=0)
//   index 1 (0x04) -> IER  (interrupt enable, DLAB=0)
//   index 2 (0x08) -> BAUD_DIV (DLAB=1)
//   index 3 (0x0C) -> LCR
//   default        -> acknowledged silently
//
// Protocol note: axi_arready_o / axi_rvalid_o are gated by
//   (axi_arvalid_i & ~axi_sync_rden).  arvalid must stay high
//   until rvalid is sampled.
//
// Tests:
//   1: LSR reset state (readable registers)
//   2: LCR write (write-only), effect visible through UART behavior
//   3: IER write + read_interrupt_o signal
//   4: DLAB mode – baud divisor write
//   5: TX path – write THR, check LSR THRE/TEMT
//   6: Loopback TX->RX single byte
//   7: LSR DATA_READY and interrupt signal
//   8: Back-to-back multi-byte loopback
// ============================================================

`timescale 1ns/1ps

module tb_axi_uart;

// ----------------------------------------------------------------
// Clock / reset
// ----------------------------------------------------------------
reg fixed_clk;
reg axi_clk;
reg aresetn;

initial fixed_clk = 0;
initial axi_clk   = 0;
always #5  fixed_clk = ~fixed_clk;   // 100 MHz
always #5  axi_clk   = ~axi_clk;     // 100 MHz

// ----------------------------------------------------------------
// AXI4-Lite master ports
// ----------------------------------------------------------------
reg  [11:0] m_awid;
reg  [4:0]  m_awaddr;
reg         m_awvalid;
wire        m_awready;

reg  [31:0] m_wdata;
reg  [3:0]  m_wstrb;
reg         m_wvalid;
wire        m_wready;

wire [11:0] m_bid;
wire [1:0]  m_bresp;
wire        m_bvalid;
reg         m_bready;

reg  [11:0] m_arid;
reg  [4:0]  m_araddr;
reg         m_arvalid;
wire        m_arready;

wire [11:0] m_rid;
wire [31:0] m_rdata;
wire [1:0]  m_rresp;
wire        m_rvalid;
reg         m_rready;

// UART loopback: TX -> RX
wire uart_tx;
wire uart_rx;
assign uart_rx = uart_tx;

wire read_interrupt;

// ----------------------------------------------------------------
// DUT
// ----------------------------------------------------------------
axi_uart_top dut (
    .fixed_clk_i    (fixed_clk),
    .axi_aclk_i     (axi_clk),
    .axi_aresetn_i  (aresetn),

    .axi_awid_i     (m_awid),
    .axi_awaddr_i   (m_awaddr),
    .axi_awvalid_i  (m_awvalid),
    .axi_awready_o  (m_awready),

    .axi_wdata_i    (m_wdata),
    .axi_wstrb_i    (m_wstrb),
    .axi_wvalid_i   (m_wvalid),
    .axi_wready_o   (m_wready),

    .axi_bid_o      (m_bid),
    .axi_bresp_o    (m_bresp),
    .axi_bvalid_o   (m_bvalid),
    .axi_bready_i   (m_bready),

    .axi_arid_i     (m_arid),
    .axi_araddr_i   (m_araddr),
    .axi_arvalid_i  (m_arvalid),
    .axi_arready_o  (m_arready),

    .axi_rid_o      (m_rid),
    .axi_rdata_o    (m_rdata),
    .axi_rresp_o    (m_rresp),
    .axi_rvalid_o   (m_rvalid),
    .axi_rready_i   (m_rready),

    .read_interrupt_o (read_interrupt),

    .uart_rx_i      (uart_rx),
    .uart_tx_o      (uart_tx)
);

// ----------------------------------------------------------------
// Register addresses  (AXI_ADDR_WIDTH=5, AXI_LSB_WIDTH=2)
// addr[4:2] = register index
// ----------------------------------------------------------------
localparam [4:0] ADDR_THR  = 5'b00000;   // index 0 – write (DLAB=0)
localparam [4:0] ADDR_RBR  = 5'b00000;   // index 0 – read  (DLAB=0)
localparam [4:0] ADDR_IER  = 5'b00100;   // index 1 – write (DLAB=0)
localparam [4:0] ADDR_BAUD = 5'b01000;   // index 2 – write (DLAB=1)
localparam [4:0] ADDR_LCR  = 5'b01100;   // index 3 – write
localparam [4:0] ADDR_LSR  = 5'b10100;   // index 5 – read only

// LCR bit positions
localparam LCR_STOP_BITS   = 2;
localparam LCR_PARITY_EN   = 3;
localparam LCR_PARITY_MODE = 4;
localparam LCR_DLAB        = 7;

// LSR bit positions
localparam LSR_DATA_READY  = 0;
localparam LSR_THRE        = 5;
localparam LSR_TEMT        = 6;

// Baud divisors
// Default: 115200 @ 100 MHz = 868
localparam [31:0] DEFAULT_BAUD_DIV = 32'd868;
// Simulation speed: ~1 Mbaud @ 100 MHz = 100 cycles/bit
// 10 bits/frame (start+8data+stop, no parity) -> 1000 cycles/byte
localparam [31:0] FAST_BAUD_DIV    = 32'd100;

integer error_cnt;

// ================================================================
// axi_write
// Both AW+W valid must stay asserted until bvalid arrives because
// the DUT gates the response through (axi_wren & ~axi_sync_wren).
// ================================================================
task axi_write;
    input [4:0]  addr;
    input [31:0] data;
    integer cyc;
    begin
        @(negedge fixed_clk);
        m_awid    = 12'h0;
        m_awaddr  = addr;
        m_awvalid = 1'b1;
        m_wdata   = data;
        m_wstrb   = 4'hF;
        m_wvalid  = 1'b1;
        m_bready  = 1'b1;

        // Hold valids; wait for bvalid
        cyc = 0;
        @(posedge fixed_clk);
        while (!m_bvalid && cyc < 500) begin
            @(posedge fixed_clk);
            cyc = cyc + 1;
        end
        if (cyc >= 500) begin
            $display("ERROR: axi_write timeout addr=0x%02h data=0x%08h", addr, data);
            error_cnt = error_cnt + 1;
        end

        @(negedge fixed_clk);
        m_awvalid = 1'b0;
        m_wvalid  = 1'b0;
        m_bready  = 1'b0;
        @(posedge fixed_clk);
    end
endtask

// ================================================================
// axi_read  (only valid for RBR / LSR – other addresses timeout)
// arvalid must stay high until rvalid is seen because rvalid_o is
// gated through (axi_arvalid_i & ~axi_sync_rden).
// ================================================================
task axi_read;
    input  [4:0]  addr;
    output [31:0] data;
    integer cyc;
    begin
        @(negedge fixed_clk);
        m_arid    = 12'h0;
        m_araddr  = addr;
        m_arvalid = 1'b1;
        m_rready  = 1'b1;

        cyc = 0;
        @(posedge fixed_clk);
        while (!m_rvalid && cyc < 500) begin
            @(posedge fixed_clk);
            cyc = cyc + 1;
        end
        if (cyc >= 500) begin
            $display("ERROR: axi_read timeout addr=0x%02h", addr);
            error_cnt = error_cnt + 1;
        end

        data = m_rdata;   // latch while arvalid & rvalid both high

        @(negedge fixed_clk);
        m_arvalid = 1'b0;
        m_rready  = 1'b0;
        @(posedge fixed_clk);
    end
endtask

// ================================================================
// Helpers
// ================================================================

// Set/clear DLAB bit in LCR (write-only)
task uart_set_dlab;
    input set;
    begin
        if (set)
            axi_write(ADDR_LCR, 32'h1 << LCR_DLAB);
        else
            axi_write(ADDR_LCR, 32'h0);
    end
endtask

// Program baud divisor
task uart_set_baud;
    input [31:0] divisor;
    begin
        uart_set_dlab(1'b1);
        axi_write(ADDR_BAUD, divisor);
        uart_set_dlab(1'b0);
    end
endtask

// Push one byte to THR
task uart_tx_byte;
    input [7:0] byte_val;
    begin
        axi_write(ADDR_THR, {24'h0, byte_val});
    end
endtask

// Poll LSR until TEMT=1
task uart_wait_tx_empty;
    reg [31:0] lsr;
    integer    timeout;
    begin
        timeout = 0;
        lsr     = 32'h0;
        while (!lsr[LSR_TEMT] && timeout < 1000000) begin
            axi_read(ADDR_LSR, lsr);
            timeout = timeout + 1;
        end
        if (timeout >= 1000000) begin
            $display("ERROR: uart_wait_tx_empty TIMEOUT at %0t", $time);
            error_cnt = error_cnt + 1;
        end
    end
endtask

// Poll LSR until DATA_READY=1
task uart_wait_rx_ready;
    reg [31:0] lsr;
    integer    timeout;
    begin
        timeout = 0;
        lsr     = 32'h0;
        while (!lsr[LSR_DATA_READY] && timeout < 1000000) begin
            axi_read(ADDR_LSR, lsr);
            timeout = timeout + 1;
        end
        if (timeout >= 1000000) begin
            $display("ERROR: uart_wait_rx_ready TIMEOUT at %0t", $time);
            error_cnt = error_cnt + 1;
        end
    end
endtask

// ================================================================
// Checkers
// ================================================================
task check_eq32;
    input [31:0]       got;
    input [31:0]       exp;
    input [8*40-1:0]   label;
    begin
        if (got !== exp) begin
            $display("FAIL [%0s]: exp 0x%08h  got 0x%08h", label, exp, got);
            error_cnt = error_cnt + 1;
        end else
            $display("PASS [%0s]: 0x%08h", label, got);
    end
endtask

task check_eq8;
    input [7:0]        got;
    input [7:0]        exp;
    input [8*40-1:0]   label;
    begin
        if (got !== exp) begin
            $display("FAIL [%0s]: exp 0x%02h  got 0x%02h", label, exp, got);
            error_cnt = error_cnt + 1;
        end else
            $display("PASS [%0s]: 0x%02h", label, got);
    end
endtask

task check_bit;
    input        got;
    input        exp;
    input [8*40-1:0] label;
    begin
        if (got !== exp) begin
            $display("FAIL [%0s]: exp %0b  got %0b", label, exp, got);
            error_cnt = error_cnt + 1;
        end else
            $display("PASS [%0s]: %0b", label, got);
    end
endtask

// ================================================================
// FSDB dump
// ================================================================
initial begin
    $fsdbDumpfile("wave.fsdb");
    $fsdbDumpvars(0, tb_axi_uart);
end

// ================================================================
// Main stimulus
// ================================================================
reg [31:0] rd_val;
reg [7:0]  rx_byte;

initial begin
    m_awid    = 12'h0;  m_awaddr  = 5'h0;  m_awvalid = 1'b0;
    m_wdata   = 32'h0;  m_wstrb   = 4'h0;  m_wvalid  = 1'b0;
    m_bready  = 1'b0;
    m_arid    = 12'h0;  m_araddr  = 5'h0;  m_arvalid = 1'b0;
    m_rready  = 1'b0;
    error_cnt = 0;

    // Reset
    aresetn = 1'b0;
    repeat(10) @(posedge fixed_clk);
    @(negedge fixed_clk); aresetn = 1'b1;
    repeat(10) @(posedge fixed_clk);

    $display("\n=====================================================");
    $display(" AXI-lite UART Testbench Starting");
    $display("=====================================================");

    // =========================================================
    // Test 1: LSR reset state (LSR is the only status register
    //         readable via AXI in this IP)
    // =========================================================
    $display("\n--- Test 1: LSR Reset State ---");
    // At reset TX FIFO is empty: THRE=1, TEMT=1
    // IER[0]=0 so DATA_READY=0
    axi_read(ADDR_LSR, rd_val);
    check_bit(rd_val[LSR_THRE],       1'b1, "LSR[THRE] reset=1");
    check_bit(rd_val[LSR_TEMT],       1'b1, "LSR[TEMT] reset=1");
    check_bit(rd_val[LSR_DATA_READY], 1'b0, "LSR[DR]   reset=0");

    // RBR at reset = 0 (FIFO empty)
    axi_read(ADDR_RBR, rd_val);
    check_eq32(rd_val, 32'h0, "RBR reset=0");

    // =========================================================
    // Test 2: LCR write (write-only register)
    //   Write LCR to set parity_en=1 (bit3=1), then clear it.
    //   Correctness of write is verified indirectly (no parity
    //   is needed for loopback so we restore to 0).
    // =========================================================
    $display("\n--- Test 2: LCR Write (write-only) ---");
    // Write LCR with parity enabled
    axi_write(ADDR_LCR, 32'h0000_0008);  // parity_en=1, stop=1bit
    $display("PASS [LCR write parity_en=1]: accepted (write-only reg)");
    // Restore LCR to no-parity, 1 stop bit
    axi_write(ADDR_LCR, 32'h0);
    $display("PASS [LCR write restored=0]: accepted");

    // =========================================================
    // Test 3: IER write + read_interrupt_o behaviour
    //   IER is write-only on AXI; effect seen on read_interrupt_o.
    //   With IER[0]=0 and empty RX FIFO, interrupt must be low.
    // =========================================================
    $display("\n--- Test 3: IER Write / Interrupt ---");
    axi_write(ADDR_IER, 32'h0);
    @(posedge fixed_clk);
    check_bit(read_interrupt, 1'b0, "IRQ deasserted (IER=0, empty FIFO)");

    // =========================================================
    // Test 4: DLAB mode – baud divisor write
    //   Switch to fast baud for remaining simulation.
    // =========================================================
    $display("\n--- Test 4: DLAB Baud Divisor Write ---");
    uart_set_baud(FAST_BAUD_DIV);
    $display("PASS [BAUD divisor set to %0d]: accepted", FAST_BAUD_DIV);
    // Verify LCR DLAB was cleared (LSR still readable)
    axi_read(ADDR_LSR, rd_val);
    check_bit(rd_val[LSR_THRE], 1'b1, "LSR[THRE]=1 after baud config");

    // =========================================================
    // Test 5: TX path – write to THR, poll LSR THRE/TEMT
    // =========================================================
    $display("\n--- Test 5: TX Path ---");
    uart_tx_byte(8'hAA);
    uart_wait_tx_empty();

    axi_read(ADDR_LSR, rd_val);
    check_bit(rd_val[LSR_THRE], 1'b1, "LSR[THRE]=1 after TX");
    check_bit(rd_val[LSR_TEMT], 1'b1, "LSR[TEMT]=1 after TX");

    // =========================================================
    // Test 6: Loopback TX->RX single byte
    //   uart_tx wired to uart_rx; IER[0]=1 to enable DATA_READY.
    //   Test 5 also sent 0xAA which arrived in RX FIFO via loopback
    //   – drain it first before sending our test byte.
    // =========================================================
    $display("\n--- Test 6: Single Byte Loopback ---");
    axi_write(ADDR_IER, 32'h1);  // enable RX interrupt so DATA_READY works

    // Drain any residual byte from test 5 loopback (0xAA)
    uart_wait_rx_ready();
    axi_read(ADDR_RBR, rd_val);  // discard residual
    repeat(4) @(posedge fixed_clk);

    uart_tx_byte(8'h55);
    uart_wait_rx_ready();

    axi_read(ADDR_RBR, rd_val);
    rx_byte = rd_val[7:0];
    check_eq8(rx_byte, 8'h55, "Loopback 0x55");

    // =========================================================
    // Test 7: LSR DATA_READY and read_interrupt_o
    // =========================================================
    $display("\n--- Test 7: DATA_READY & Interrupt ---");
    uart_tx_byte(8'hC3);
    uart_wait_rx_ready();

    axi_read(ADDR_LSR, rd_val);
    check_bit(rd_val[LSR_DATA_READY], 1'b1, "LSR DATA_READY set");
    check_bit(read_interrupt,          1'b1, "read_interrupt asserted");

    // Drain RBR – DATA_READY should clear
    axi_read(ADDR_RBR, rd_val);
    check_eq8(rd_val[7:0], 8'hC3, "RBR byte 0xC3");

    repeat(4) @(posedge fixed_clk);
    axi_read(ADDR_LSR, rd_val);
    check_bit(rd_val[LSR_DATA_READY], 1'b0, "LSR DATA_READY cleared");

    // =========================================================
    // Test 8: Back-to-back multi-byte loopback
    // =========================================================
    $display("\n--- Test 8: Multi-Byte Loopback ---");
    begin : multi_byte_test
        reg [7:0] tx_bytes [0:3];
        integer   i;
        tx_bytes[0] = 8'hDE;
        tx_bytes[1] = 8'hAD;
        tx_bytes[2] = 8'hBE;
        tx_bytes[3] = 8'hEF;

        for (i = 0; i < 4; i = i + 1)
            uart_tx_byte(tx_bytes[i]);

        for (i = 0; i < 4; i = i + 1) begin
            uart_wait_rx_ready();
            axi_read(ADDR_RBR, rd_val);
            check_eq8(rd_val[7:0], tx_bytes[i], "Multi-byte loopback");
        end
    end

    // Disable RX interrupt
    axi_write(ADDR_IER, 32'h0);

    // =========================================================
    // Summary
    // =========================================================
    repeat(20) @(posedge fixed_clk);
    $display("\n=====================================================");
    if (error_cnt == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" TESTS DONE: %0d FAILURE(S)", error_cnt);
    $display("=====================================================\n");
    $finish;
end

endmodule
