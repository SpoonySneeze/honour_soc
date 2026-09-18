`include "timescale.v"
// ============================================================
// aes_csr_regs.v
// AES CSR Register File
//
// Register Map (32-bit AXI data width):
//   0x00  CTRL    [RW]  bit0=START (pulse), bit1=DECRYPT
//   0x04  STATUS  [RW]  bit0=DONE (W1C), bit1=BUSY (RO)
//   0x08  KEY0    [RW]  key[31:0]
//   0x0C  KEY1    [RW]  key[63:32]
//   0x10  KEY2    [RW]  key[95:64]
//   0x14  KEY3    [RW]  key[127:96]
//   0x18  TEXT0   [RW]  text_in[31:0]
//   0x1C  TEXT1   [RW]  text_in[63:32]
//   0x20  TEXT2   [RW]  text_in[95:64]
//   0x24  TEXT3   [RW]  text_in[127:96]
//   0x28  OUT0    [RO]  text_out[31:0]
//   0x2C  OUT1    [RO]  text_out[63:32]
//   0x30  OUT2    [RO]  text_out[95:64]
//   0x34  OUT3    [RO]  text_out[127:96]
// ============================================================

module aes_csr_regs (
    input  wire        clk,
    input  wire        rst,        // active-low synchronous reset

    // Internal CSR bus (split write / read addresses)
    input  wire        csr_wr_en,
    input  wire [5:0]  csr_wr_addr,
    input  wire [31:0] csr_wdata,
    input  wire [3:0]  csr_wstrb,

    input  wire        csr_rd_en,
    input  wire [5:0]  csr_rd_addr,
    output reg  [31:0] csr_rdata,

    // Control/status interface to FSM
    output reg         start_pulse,   // one-cycle pulse when START written
    output reg         decrypt_mode,  // 0=encrypt, 1=decrypt
    input  wire        busy,          // from FSM
    input  wire        done_event,    // one-cycle done pulse from FSM

    // AES data registers
    output reg  [127:0] key_reg,
    output reg  [127:0] text_reg,
    input  wire [127:0] output_reg    // written by FSM on capture
);

// ----------------------------------------------------------------
// Internal
// ----------------------------------------------------------------
reg done_status;   // sticky; W1C

// Word address from byte address bits [5:2]
wire [3:0] wr_waddr = csr_wr_addr[5:2];
wire [3:0] rd_waddr = csr_rd_addr[5:2];

// Address decode constants
localparam ADDR_CTRL  = 4'h0;
localparam ADDR_STS   = 4'h1;
localparam ADDR_KEY0  = 4'h2;
localparam ADDR_KEY1  = 4'h3;
localparam ADDR_KEY2  = 4'h4;
localparam ADDR_KEY3  = 4'h5;
localparam ADDR_TEXT0 = 4'h6;
localparam ADDR_TEXT1 = 4'h7;
localparam ADDR_TEXT2 = 4'h8;
localparam ADDR_TEXT3 = 4'h9;
localparam ADDR_OUT0  = 4'hA;
localparam ADDR_OUT1  = 4'hB;
localparam ADDR_OUT2  = 4'hC;
localparam ADDR_OUT3  = 4'hD;

// ----------------------------------------------------------------
// Byte-enable write helper
// ----------------------------------------------------------------
function [31:0] apply_wstrb;
    input [31:0] old_val;
    input [31:0] new_val;
    input [3:0]  strb;
    integer i;
    begin
        for (i = 0; i < 4; i = i + 1)
            apply_wstrb[i*8 +: 8] = strb[i] ? new_val[i*8 +: 8] : old_val[i*8 +: 8];
    end
endfunction

// ----------------------------------------------------------------
// Write logic
// ----------------------------------------------------------------
always @(posedge clk) begin
    if (!rst) begin
        key_reg      <= 128'h0;
        text_reg     <= 128'h0;
        decrypt_mode <= 1'b0;
        done_status  <= 1'b0;
        start_pulse  <= 1'b0;
    end else begin
        start_pulse <= 1'b0;   // default: clear every cycle

        // Latch FSM done_event into sticky status bit
        if (done_event)
            done_status <= 1'b1;

        if (csr_wr_en) begin
            case (wr_waddr)
                ADDR_CTRL: begin
                    if (csr_wstrb[0]) begin
                        decrypt_mode <= csr_wdata[1];
                        // START bit: pulse only when not already busy
                        if (csr_wdata[0] && !busy)
                            start_pulse <= 1'b1;
                    end
                end

                ADDR_STS: begin
                    // bit0 W1C: writing 1 clears DONE
                    if (csr_wstrb[0] && csr_wdata[0])
                        done_status <= 1'b0;
                    // bit1 (BUSY) is RO – ignore writes
                end

                ADDR_KEY0:  key_reg[31:0]    <= apply_wstrb(key_reg[31:0],    csr_wdata, csr_wstrb);
                ADDR_KEY1:  key_reg[63:32]   <= apply_wstrb(key_reg[63:32],   csr_wdata, csr_wstrb);
                ADDR_KEY2:  key_reg[95:64]   <= apply_wstrb(key_reg[95:64],   csr_wdata, csr_wstrb);
                ADDR_KEY3:  key_reg[127:96]  <= apply_wstrb(key_reg[127:96],  csr_wdata, csr_wstrb);

                ADDR_TEXT0: text_reg[31:0]   <= apply_wstrb(text_reg[31:0],   csr_wdata, csr_wstrb);
                ADDR_TEXT1: text_reg[63:32]  <= apply_wstrb(text_reg[63:32],  csr_wdata, csr_wstrb);
                ADDR_TEXT2: text_reg[95:64]  <= apply_wstrb(text_reg[95:64],  csr_wdata, csr_wstrb);
                ADDR_TEXT3: text_reg[127:96] <= apply_wstrb(text_reg[127:96], csr_wdata, csr_wstrb);

                // OUT0..3 are read-only; ignore writes
                default: ;
            endcase
        end
    end
end

// ----------------------------------------------------------------
// Read logic (combinational — AXI slave latches it the next cycle)
// ----------------------------------------------------------------
always @(*) begin
    csr_rdata = 32'h0;
    if (csr_rd_en) begin
        case (rd_waddr)
            ADDR_CTRL:  csr_rdata = {30'h0, decrypt_mode, 1'b0};
            ADDR_STS:   csr_rdata = {30'h0, busy, done_status};
            ADDR_KEY0:  csr_rdata = key_reg[31:0];
            ADDR_KEY1:  csr_rdata = key_reg[63:32];
            ADDR_KEY2:  csr_rdata = key_reg[95:64];
            ADDR_KEY3:  csr_rdata = key_reg[127:96];
            ADDR_TEXT0: csr_rdata = text_reg[31:0];
            ADDR_TEXT1: csr_rdata = text_reg[63:32];
            ADDR_TEXT2: csr_rdata = text_reg[95:64];
            ADDR_TEXT3: csr_rdata = text_reg[127:96];
            ADDR_OUT0:  csr_rdata = output_reg[31:0];
            ADDR_OUT1:  csr_rdata = output_reg[63:32];
            ADDR_OUT2:  csr_rdata = output_reg[95:64];
            ADDR_OUT3:  csr_rdata = output_reg[127:96];
            default:    csr_rdata = 32'h0;
        endcase
    end
end

endmodule
