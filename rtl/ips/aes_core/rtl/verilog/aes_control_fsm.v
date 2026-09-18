`include "timescale.v"
// ============================================================
// aes_control_fsm.v
// AES Control FSM
//
// Converts software START pulse + decrypt_mode flag into
// the timed pulse sequences required by the AES IP cores.
//
// Encryption:  ld pulse → wait done
// Decryption:  kld pulse → wait kdone → ld pulse → wait done
//
// States:
//   IDLE          - waiting for start_pulse
//   ENC_LOAD      - assert cipher_ld for one cycle
//   ENC_WAIT_DONE - wait for cipher_done
//   DEC_KEY_LOAD  - assert inverse_kld for one cycle
//   DEC_WAIT_KDONE- wait for inverse_kdone
//   DEC_TEXT_LOAD - assert inverse_ld for one cycle
//   DEC_WAIT_DONE - wait for inverse_done
//   CAPTURE       - latch output, set done_event, clear busy
// ============================================================

module aes_control_fsm (
    input  wire        clk,
    input  wire        rst,           // active-low synchronous reset

    // From CSR
    input  wire        start_pulse,   // one-cycle, from CSR
    input  wire        decrypt_mode,  // 0=encrypt, 1=decrypt

    // AES cipher core
    output reg         cipher_ld,     // one-cycle ld to aes_cipher_top
    input  wire        cipher_done,   // one-cycle done from aes_cipher_top

    // AES inverse cipher core
    output reg         inverse_kld,   // one-cycle kld to aes_inv_cipher_top
    input  wire        inverse_kdone, // one-cycle kdone from aes_inv_cipher_top
    output reg         inverse_ld,    // one-cycle ld to aes_inv_cipher_top
    input  wire        inverse_done,  // one-cycle done from aes_inv_cipher_top

    // AES datapath selection
    input  wire [127:0] cipher_out,    // from aes_cipher_top
    input  wire [127:0] inverse_out,   // from aes_inv_cipher_top
    output reg  [127:0] output_reg,    // captured result

    // Status to CSR
    output reg         busy,
    output reg         done_event      // one-cycle pulse when captured
);

// ----------------------------------------------------------------
// State encoding
// ----------------------------------------------------------------
localparam [2:0]
    IDLE          = 3'd0,
    ENC_LOAD      = 3'd1,
    ENC_WAIT_DONE = 3'd2,
    DEC_KEY_LOAD  = 3'd3,
    DEC_WAIT_KDONE= 3'd4,
    DEC_TEXT_LOAD = 3'd5,
    DEC_WAIT_DONE = 3'd6,
    CAPTURE       = 3'd7;

reg [2:0] state, next_state;
reg       dec_mode_r;   // registered at start

// ----------------------------------------------------------------
// State register
// ----------------------------------------------------------------
always @(posedge clk) begin
    if (!rst)
        state <= IDLE;
    else
        state <= next_state;
end

// ----------------------------------------------------------------
// Next-state logic
// ----------------------------------------------------------------
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (start_pulse)
                next_state = decrypt_mode ? DEC_KEY_LOAD : ENC_LOAD;
        end

        ENC_LOAD:
            next_state = ENC_WAIT_DONE;

        ENC_WAIT_DONE:
            if (cipher_done)
                next_state = CAPTURE;

        DEC_KEY_LOAD:
            next_state = DEC_WAIT_KDONE;

        DEC_WAIT_KDONE:
            if (inverse_kdone)
                next_state = DEC_TEXT_LOAD;

        DEC_TEXT_LOAD:
            next_state = DEC_WAIT_DONE;

        DEC_WAIT_DONE:
            if (inverse_done)
                next_state = CAPTURE;

        CAPTURE:
            next_state = IDLE;

        default:
            next_state = IDLE;
    endcase
end

// ----------------------------------------------------------------
// Register decrypt_mode at the point of starting
// ----------------------------------------------------------------
always @(posedge clk) begin
    if (!rst)
        dec_mode_r <= 1'b0;
    else if (state == IDLE && start_pulse)
        dec_mode_r <= decrypt_mode;
end

// ----------------------------------------------------------------
// Output logic
// ----------------------------------------------------------------
always @(posedge clk) begin
    if (!rst) begin
        cipher_ld    <= 1'b0;
        inverse_kld  <= 1'b0;
        inverse_ld   <= 1'b0;
        busy         <= 1'b0;
        done_event   <= 1'b0;
        output_reg   <= 128'h0;
    end else begin
        // Default: de-assert all one-cycle signals
        cipher_ld   <= 1'b0;
        inverse_kld <= 1'b0;
        inverse_ld  <= 1'b0;
        done_event  <= 1'b0;

        case (next_state)
            IDLE: begin
                busy <= 1'b0;
            end

            ENC_LOAD: begin
                cipher_ld <= 1'b1;
                busy      <= 1'b1;
            end

            DEC_KEY_LOAD: begin
                inverse_kld <= 1'b1;
                busy        <= 1'b1;
            end

            DEC_TEXT_LOAD: begin
                inverse_ld <= 1'b1;
            end

            CAPTURE: begin
                // Latch the correct output register
                output_reg <= dec_mode_r ? inverse_out : cipher_out;
                done_event <= 1'b1;
                busy       <= 1'b0;
            end

            default: ;
        endcase
    end
end

endmodule
