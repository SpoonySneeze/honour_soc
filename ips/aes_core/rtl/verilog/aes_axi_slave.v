`include "timescale.v"
// ============================================================
// aes_axi_slave.v
// AXI4-Lite Slave Protocol Logic
//
// Implements a simple, robust AXI4-Lite slave.
// Write path:  latches AW and W independently; commits when both
//              captured and no B response is outstanding.
// Read path:   accepts AR; returns data one cycle later.
//
// Internal CSR bus uses split write/read address ports to avoid
// multiple-driver issues in aes_csr_regs.
// ============================================================

module aes_axi_slave (
    input  wire        aclk,
    input  wire        aresetn,

    // Write address
    input  wire [7:0]  awaddr,
    input  wire        awvalid,
    output reg         awready,

    // Write data
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    input  wire        wvalid,
    output reg         wready,

    // Write response
    output reg  [1:0]  bresp,
    output reg         bvalid,
    input  wire        bready,

    // Read address
    input  wire [7:0]  araddr,
    input  wire        arvalid,
    output reg         arready,

    // Read data
    output reg  [31:0] rdata,
    output reg  [1:0]  rresp,
    output reg         rvalid,
    input  wire        rready,

    // CSR write bus
    output reg         csr_wr_en,
    output reg  [5:0]  csr_wr_addr,
    output reg  [31:0] csr_wdata,
    output reg  [3:0]  csr_wstrb,

    // CSR read bus
    output reg         csr_rd_en,
    output reg  [5:0]  csr_rd_addr,
    input  wire [31:0] csr_rdata
);

// ----------------------------------------------------------------
// Write path
// ----------------------------------------------------------------
reg        aw_latched;
reg [7:0]  aw_addr_r;
reg        w_latched;
reg [31:0] w_data_r;
reg [3:0]  w_strb_r;

always @(posedge aclk) begin
    if (!aresetn) begin
        awready     <= 1'b0;
        aw_latched  <= 1'b0;
        aw_addr_r   <= 8'h0;
        wready      <= 1'b0;
        w_latched   <= 1'b0;
        w_data_r    <= 32'h0;
        w_strb_r    <= 4'h0;
        bvalid      <= 1'b0;
        bresp       <= 2'b00;
        csr_wr_en   <= 1'b0;
        csr_wr_addr <= 6'h0;
        csr_wdata   <= 32'h0;
        csr_wstrb   <= 4'h0;
    end else begin
        // Clear one-cycle strobes by default
        awready   <= 1'b0;
        wready    <= 1'b0;
        csr_wr_en <= 1'b0;

        // ---- Latch AW ----
        // Accept new address only when we don't already hold one.
        if (awvalid && !aw_latched) begin
            awready   <= 1'b1;
            aw_latched <= 1'b1;
            aw_addr_r  <= awaddr;
        end

        // ---- Latch W ----
        if (wvalid && !w_latched) begin
            wready    <= 1'b1;
            w_latched  <= 1'b1;
            w_data_r   <= wdata;
            w_strb_r   <= wstrb;
        end

        // ---- Commit: both latched AND no B outstanding ----
        if (aw_latched && w_latched && !bvalid) begin
            csr_wr_en   <= 1'b1;
            csr_wr_addr <= aw_addr_r[5:0];
            csr_wdata   <= w_data_r;
            csr_wstrb   <= w_strb_r;
            aw_latched  <= 1'b0;
            w_latched   <= 1'b0;
            bvalid      <= 1'b1;
            bresp       <= 2'b00;   // OKAY
        end

        // ---- B handshake ----
        if (bvalid && bready)
            bvalid <= 1'b0;
    end
end

// ----------------------------------------------------------------
// Read path
// ----------------------------------------------------------------
always @(posedge aclk) begin
    if (!aresetn) begin
        arready     <= 1'b0;
        rvalid      <= 1'b0;
        rdata       <= 32'h0;
        rresp       <= 2'b00;
        csr_rd_en   <= 1'b0;
        csr_rd_addr <= 6'h0;
    end else begin
        arready   <= 1'b0;
        csr_rd_en <= 1'b0;

        // Accept AR when no pending read response
        if (arvalid && !rvalid && !arready) begin
            arready     <= 1'b1;
            csr_rd_en   <= 1'b1;
            csr_rd_addr <= araddr[5:0];
        end

        // One cycle after arready: CSR has produced rdata
        if (arready) begin
            rdata  <= csr_rdata;
            rresp  <= 2'b00;    // OKAY
            rvalid <= 1'b1;
        end

        // R handshake
        if (rvalid && rready)
            rvalid <= 1'b0;
    end
end

endmodule
