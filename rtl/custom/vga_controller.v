// ============================================================================
// VGA Controller — Custom IP #4 (Optional)
// ============================================================================
// Generates VGA sync signals and pixel output from a firmware-written
// dashboard buffer. 640x480 @ 60Hz timing (25.175 MHz pixel clock derived
// from system clock via divider).
//
// Register Map (Wishbone slave, 32-bit registers):
//   0x00       VGA_CTRL     R/W  [0] enable
//   0x04       VGA_STATUS   R    [0] refresh_flag
//   0x08–0x7F  VGA_BUFFER   W    Dashboard text buffer (30 words = 120 chars)
//
// The dashboard buffer stores ASCII characters. Pixel logic renders them
// using a built-in 8x8 font ROM. Firmware writes status text; the VGA
// engine continuously scans the buffer to generate video output.
// ============================================================================

module vga_controller (
    // ---- Wishbone Slave Interface ----
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire [7:0]  wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire        wb_we_i,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,

    // ---- VGA Output Signals ----
    output reg         vga_hsync,
    output reg         vga_vsync,
    output reg  [11:0] vga_rgb
);

    // ========================================================================
    // Register Offset Definitions
    // ========================================================================
    localparam ADDR_VGA_CTRL   = 8'h00;
    localparam ADDR_VGA_STATUS = 8'h04;
    // 0x08–0x7F: buffer words (30 words × 4 bytes = 120 chars)
    // Word index = (addr - 0x08) / 4

    // ========================================================================
    // VGA Timing Parameters (640×480 @ 60Hz)
    // ========================================================================
    // Pixel clock: 25.175 MHz (approximated by dividing system clock)
    localparam H_ACTIVE      = 10'd640;
    localparam H_FRONT_PORCH = 10'd16;
    localparam H_SYNC_PULSE  = 10'd96;
    localparam H_BACK_PORCH  = 10'd48;
    localparam H_TOTAL       = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    localparam V_ACTIVE      = 10'd480;
    localparam V_FRONT_PORCH = 10'd10;
    localparam V_SYNC_PULSE  = 10'd2;
    localparam V_BACK_PORCH  = 10'd33;
    localparam V_TOTAL       = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    // Dashboard layout: 80 chars wide × 30 rows, but we only have 120 chars
    // Use a simplified layout: 40 chars × 3 rows for status display
    localparam CHARS_PER_ROW = 7'd40;
    localparam NUM_ROWS      = 5'd3;
    localparam CHAR_WIDTH    = 4'd8;
    localparam CHAR_HEIGHT   = 4'd8;

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg        vga_enable;
    reg        vga_refresh_flag;

    // Pixel clock divider (divide by 2 for ~50MHz → ~25MHz, or by 4 for ~100MHz → ~25MHz)
    reg [1:0]  pixel_clk_div;
    wire       pixel_clk_en;

    // Scan counters
    reg [9:0]  h_count;
    reg [9:0]  v_count;

    // Active video region
    wire       active_video;

    // Dashboard text buffer: 30 words × 32 bits = 120 bytes = 120 ASCII chars
    reg [31:0] dashboard_buffer [0:29];

    // ========================================================================
    // Pixel Clock Divider
    // ========================================================================
    // Generate pixel clock enable (1-in-4 for 100MHz sys clock → 25MHz pixel)
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            pixel_clk_div <= 2'd0;
        else
            pixel_clk_div <= pixel_clk_div + 2'd1;
    end

    assign pixel_clk_en = (pixel_clk_div == 2'd0);

    // ========================================================================
    // Wishbone Bus Interface
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_stb_i & wb_cyc_i & ~wb_ack_o;
    end

    // Register writes
    integer j;
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            vga_enable       <= 1'b0;
            vga_refresh_flag <= 1'b0;
            for (j = 0; j < 30; j = j + 1)
                dashboard_buffer[j] <= 32'h20202020;  // Spaces
        end else if (wb_stb_i && wb_cyc_i && wb_we_i && !wb_ack_o) begin
            case (wb_adr_i)
                ADDR_VGA_CTRL: begin
                    vga_enable <= wb_dat_i[0];
                end
                default: begin
                    // Buffer writes: address 0x08–0x7F
                    if (wb_adr_i >= 8'h08 && wb_adr_i <= 8'h7F) begin
                        dashboard_buffer[(wb_adr_i - 8'h08) >> 2] <= wb_dat_i;
                        vga_refresh_flag <= 1'b1;
                    end
                end
            endcase
        end
    end

    // Register reads
    always @(*) begin
        wb_dat_o = 32'd0;
        case (wb_adr_i)
            ADDR_VGA_CTRL:   wb_dat_o = {31'd0, vga_enable};
            ADDR_VGA_STATUS: wb_dat_o = {31'd0, vga_refresh_flag};
            default: begin
                if (wb_adr_i >= 8'h08 && wb_adr_i <= 8'h7F)
                    wb_dat_o = dashboard_buffer[(wb_adr_i - 8'h08) >> 2];
                else
                    wb_dat_o = 32'd0;
            end
        endcase
    end

    // ========================================================================
    // Scan Counters
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (pixel_clk_en) begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Active video area
    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    // ========================================================================
    // Sync Signal Generation
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            vga_hsync <= 1'b1;
            vga_vsync <= 1'b1;
        end else if (pixel_clk_en) begin
            // HSYNC: active low during sync pulse region
            vga_hsync <= ~((h_count >= (H_ACTIVE + H_FRONT_PORCH)) &&
                           (h_count < (H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE)));
            // VSYNC: active low during sync pulse region
            vga_vsync <= ~((v_count >= (V_ACTIVE + V_FRONT_PORCH)) &&
                           (v_count < (V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE)));
        end
    end

    // ========================================================================
    // Pixel Logic — Character Rendering
    // ========================================================================
    // Character position in the dashboard grid
    wire [6:0] char_col = h_count[9:3];   // h_count / 8
    wire [4:0] char_row = v_count[9:3];   // v_count / 8

    // Pixel position within the character cell
    wire [2:0] pixel_x = h_count[2:0];    // h_count % 8
    wire [2:0] pixel_y = v_count[2:0];    // v_count % 8

    // Character index in the buffer (row * CHARS_PER_ROW + col)
    // We display 3 rows of 40 chars = 120 chars total
    wire [6:0] char_idx;
    wire       in_text_area;

    assign in_text_area = (char_row < NUM_ROWS) && (char_col < CHARS_PER_ROW);
    assign char_idx     = (char_row * CHARS_PER_ROW) + char_col;

    // Fetch the ASCII character from the dashboard buffer
    // Each 32-bit word holds 4 characters (byte-packed, MSB first)
    wire [4:0] word_idx  = char_idx[6:2];        // char_idx / 4
    wire [1:0] byte_sel  = 2'd3 - char_idx[1:0]; // MSB-first byte order
    wire [7:0] ascii_char = dashboard_buffer[word_idx] >> (byte_sel * 8);

    // Simple built-in font: only render printable ASCII as white dots
    // For a real implementation, a font ROM would be used.
    // Here we use a minimal approach: if character is not space (0x20),
    // render a filled block for visual indication.
    wire pixel_on;

    // Simplified rendering: show character as a bordered block
    // Full font ROM would replace this with actual glyph data
    assign pixel_on = in_text_area &&
                      (ascii_char != 8'h20) &&  // Not a space
                      (ascii_char != 8'h00) &&  // Not null
                      (pixel_x > 3'd0) &&       // 1-pixel border
                      (pixel_x < 3'd7) &&
                      (pixel_y > 3'd0) &&
                      (pixel_y < 3'd7);

    // ========================================================================
    // RGB Output
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            vga_rgb <= 12'h000;
        end else if (pixel_clk_en) begin
            if (!vga_enable || !active_video)
                vga_rgb <= 12'h000;         // Black (blanking or disabled)
            else if (pixel_on)
                vga_rgb <= 12'h0F0;         // Green text (BMC terminal style)
            else
                vga_rgb <= 12'h001;         // Very dark blue background
        end
    end

    // ========================================================================
    // Refresh flag — clear at start of each frame
    // ========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            vga_refresh_flag <= 1'b0;
        else if (pixel_clk_en && h_count == 10'd0 && v_count == 10'd0)
            vga_refresh_flag <= 1'b0;  // Clear at frame start
    end

endmodule
