`include "timescale.v"
// ============================================================
// aes_axi.v
// AES AXI4-Lite Top-Level Wrapper
//
// Integrates:
//   - aes_axi_slave      : AXI4-Lite protocol logic
//   - aes_csr_regs       : CSR register file
//   - aes_control_fsm    : Control FSM
//   - aes_cipher_top     : AES-128 encryption core
//   - aes_inv_cipher_top : AES-128 decryption core
// ============================================================

module aes_axi (
    input  wire        aclk,
    input  wire        aresetn,

    // ---------- Write address channel ----------
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    // ---------- Write data channel ----------
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    // ---------- Write response channel ----------
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    // ---------- Read address channel ----------
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    // ---------- Read data channel ----------
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready
);

// ----------------------------------------------------------------
// Internal signals: AXI slave <-> CSR
// ----------------------------------------------------------------
wire        csr_wr_en;
wire [5:0]  csr_wr_addr;
wire [31:0] csr_wdata;
wire [3:0]  csr_wstrb;

wire        csr_rd_en;
wire [5:0]  csr_rd_addr;
wire [31:0] csr_rdata;

// ----------------------------------------------------------------
// Internal signals: CSR <-> FSM
// ----------------------------------------------------------------
wire        start_pulse;
wire        decrypt_mode;
wire        busy;
wire        done_event;

// ----------------------------------------------------------------
// Data paths
// ----------------------------------------------------------------
wire [127:0] key_reg;
wire [127:0] text_reg;
wire [127:0] output_reg;   // written by FSM

wire [127:0] cipher_out;
wire [127:0] inverse_out;

// AES core control signals
wire cipher_ld;
wire cipher_done;
wire inverse_kld;
wire inverse_kdone;
wire inverse_ld;
wire inverse_done;

// ================================================================
// AXI4-Lite Slave
// ================================================================
aes_axi_slave u_axi_slave (
    .aclk        (aclk),
    .aresetn     (aresetn),

    .awaddr      (s_axi_awaddr),
    .awvalid     (s_axi_awvalid),
    .awready     (s_axi_awready),

    .wdata       (s_axi_wdata),
    .wstrb       (s_axi_wstrb),
    .wvalid      (s_axi_wvalid),
    .wready      (s_axi_wready),

    .bresp       (s_axi_bresp),
    .bvalid      (s_axi_bvalid),
    .bready      (s_axi_bready),

    .araddr      (s_axi_araddr),
    .arvalid     (s_axi_arvalid),
    .arready     (s_axi_arready),

    .rdata       (s_axi_rdata),
    .rresp       (s_axi_rresp),
    .rvalid      (s_axi_rvalid),
    .rready      (s_axi_rready),

    .csr_wr_en   (csr_wr_en),
    .csr_wr_addr (csr_wr_addr),
    .csr_wdata   (csr_wdata),
    .csr_wstrb   (csr_wstrb),

    .csr_rd_en   (csr_rd_en),
    .csr_rd_addr (csr_rd_addr),
    .csr_rdata   (csr_rdata)
);

// ================================================================
// CSR Register File
// ================================================================
aes_csr_regs u_csr_regs (
    .clk          (aclk),
    .rst          (aresetn),

    .csr_wr_en    (csr_wr_en),
    .csr_wr_addr  (csr_wr_addr),
    .csr_wdata    (csr_wdata),
    .csr_wstrb    (csr_wstrb),

    .csr_rd_en    (csr_rd_en),
    .csr_rd_addr  (csr_rd_addr),
    .csr_rdata    (csr_rdata),

    .start_pulse  (start_pulse),
    .decrypt_mode (decrypt_mode),
    .busy         (busy),
    .done_event   (done_event),

    .key_reg      (key_reg),
    .text_reg     (text_reg),
    .output_reg   (output_reg)
);

// ================================================================
// Control FSM
// ================================================================
aes_control_fsm u_ctrl_fsm (
    .clk           (aclk),
    .rst           (aresetn),

    .start_pulse   (start_pulse),
    .decrypt_mode  (decrypt_mode),

    .cipher_ld     (cipher_ld),
    .cipher_done   (cipher_done),

    .inverse_kld   (inverse_kld),
    .inverse_kdone (inverse_kdone),
    .inverse_ld    (inverse_ld),
    .inverse_done  (inverse_done),

    .cipher_out    (cipher_out),
    .inverse_out   (inverse_out),
    .output_reg    (output_reg),

    .busy          (busy),
    .done_event    (done_event)
);

// ================================================================
// AES Cipher Core (Encryption)
// ================================================================
aes_cipher_top u_cipher (
    .clk      (aclk),
    .rst      (aresetn),
    .ld       (cipher_ld),
    .done     (cipher_done),
    .key      (key_reg),
    .text_in  (text_reg),
    .text_out (cipher_out)
);

// ================================================================
// AES Inverse Cipher Core (Decryption)
// ================================================================
aes_inv_cipher_top u_inv_cipher (
    .clk      (aclk),
    .rst      (aresetn),
    .kld      (inverse_kld),
    .ld       (inverse_ld),
    .done     (inverse_done),
    .key      (key_reg),
    .text_in  (text_reg),
    .text_out (inverse_out)
);

// ----------------------------------------------------------------
// kdone tracker: replicate aes_inv_cipher_top's internal kdone.
// Inside the core: kcnt loads 0xA on kld, decrements each cycle
// while kb_ld is active, and kdone pulses when kcnt==0.
// We mirror that here to drive inverse_kdone into the FSM.
// ----------------------------------------------------------------
reg [3:0] kdone_cnt;
reg       kdone_active;

always @(posedge aclk) begin
    if (!aresetn) begin
        kdone_cnt    <= 4'hA;
        kdone_active <= 1'b0;
    end else begin
        if (inverse_kld) begin
            kdone_cnt    <= 4'hA;
            kdone_active <= 1'b1;
        end else if (kdone_active) begin
            if (kdone_cnt == 4'h0)
                kdone_active <= 1'b0;
            else
                kdone_cnt <= kdone_cnt - 4'h1;
        end
    end
end

assign inverse_kdone = kdone_active && (kdone_cnt == 4'h0);

endmodule
