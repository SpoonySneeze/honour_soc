// ============================================================================
// Wishbone B4 Interconnect — Address Decoder & Bus Multiplexer
// ============================================================================
// Routes Wishbone transactions from a single master (AXI-to-WB bridge) to
// one of 7 slave peripherals based on address decoding.
//
// Memory Map:
//   0x0002_0000 – 0x0002_00FF  →  Slave 0: UART
//   0x0002_0100 – 0x0002_01FF  →  Slave 1: Timer
//   0x0002_0200 – 0x0002_02FF  →  Slave 2: GPIO
//   0x0002_0300 – 0x0002_03FF  →  Slave 3: Heartbeat Monitor
//   0x0002_0400 – 0x0002_04FF  →  Slave 4: Power/Reset Sequencer
//   0x0002_0500 – 0x0002_05FF  →  Slave 5: Recovery Policy / Event Log
//   0x0002_0600 – 0x0002_06FF  →  Slave 6: VGA Controller
//
// Address decode uses bits [15:8] of the incoming address to select the slave.
// Bits [7:0] are passed as the local register offset within each peripheral.
// ============================================================================

module wb_interconnect #(
    parameter NUM_SLAVES   = 7,
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter SEL_WIDTH    = DATA_WIDTH / 8,
    // Base address of the peripheral region (upper bits)
    parameter PERIPH_BASE  = 32'h0002_0000
) (
    // ---- Wishbone Master Interface (from AXI-to-WB bridge) ----
    input  wire [ADDR_WIDTH-1:0]   wbm_adr_i,
    input  wire [DATA_WIDTH-1:0]   wbm_dat_i,
    output reg  [DATA_WIDTH-1:0]   wbm_dat_o,
    input  wire                    wbm_we_i,
    input  wire [SEL_WIDTH-1:0]    wbm_sel_i,
    input  wire                    wbm_stb_i,
    input  wire                    wbm_cyc_i,
    output reg                     wbm_ack_o,
    output reg                     wbm_err_o,

    // ---- Wishbone Slave 0: UART ----
    output wire [7:0]              wbs0_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs0_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs0_dat_i,
    output wire                    wbs0_we_o,
    output wire [SEL_WIDTH-1:0]    wbs0_sel_o,
    output wire                    wbs0_stb_o,
    output wire                    wbs0_cyc_o,
    input  wire                    wbs0_ack_i,

    // ---- Wishbone Slave 1: Timer ----
    output wire [7:0]              wbs1_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs1_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs1_dat_i,
    output wire                    wbs1_we_o,
    output wire [SEL_WIDTH-1:0]    wbs1_sel_o,
    output wire                    wbs1_stb_o,
    output wire                    wbs1_cyc_o,
    input  wire                    wbs1_ack_i,

    // ---- Wishbone Slave 2: GPIO ----
    output wire [7:0]              wbs2_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs2_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs2_dat_i,
    output wire                    wbs2_we_o,
    output wire [SEL_WIDTH-1:0]    wbs2_sel_o,
    output wire                    wbs2_stb_o,
    output wire                    wbs2_cyc_o,
    input  wire                    wbs2_ack_i,

    // ---- Wishbone Slave 3: Heartbeat Monitor ----
    output wire [7:0]              wbs3_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs3_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs3_dat_i,
    output wire                    wbs3_we_o,
    output wire [SEL_WIDTH-1:0]    wbs3_sel_o,
    output wire                    wbs3_stb_o,
    output wire                    wbs3_cyc_o,
    input  wire                    wbs3_ack_i,

    // ---- Wishbone Slave 4: Power/Reset Sequencer ----
    output wire [7:0]              wbs4_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs4_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs4_dat_i,
    output wire                    wbs4_we_o,
    output wire [SEL_WIDTH-1:0]    wbs4_sel_o,
    output wire                    wbs4_stb_o,
    output wire                    wbs4_cyc_o,
    input  wire                    wbs4_ack_i,

    // ---- Wishbone Slave 5: Recovery Policy / Event Log ----
    output wire [7:0]              wbs5_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs5_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs5_dat_i,
    output wire                    wbs5_we_o,
    output wire [SEL_WIDTH-1:0]    wbs5_sel_o,
    output wire                    wbs5_stb_o,
    output wire                    wbs5_cyc_o,
    input  wire                    wbs5_ack_i,

    // ---- Wishbone Slave 6: VGA Controller ----
    output wire [7:0]              wbs6_adr_o,
    output wire [DATA_WIDTH-1:0]   wbs6_dat_o,
    input  wire [DATA_WIDTH-1:0]   wbs6_dat_i,
    output wire                    wbs6_we_o,
    output wire [SEL_WIDTH-1:0]    wbs6_sel_o,
    output wire                    wbs6_stb_o,
    output wire                    wbs6_cyc_o,
    input  wire                    wbs6_ack_i
);

    // ========================================================================
    // Address Decode — One-Hot Slave Select
    // ========================================================================
    // Decode bits [15:8] of the address to select the slave.
    // Slave 0 (UART):       offset 0x00 → addr[15:8] == 8'h00
    // Slave 1 (Timer):      offset 0x01 → addr[15:8] == 8'h01
    // Slave 2 (GPIO):       offset 0x02 → addr[15:8] == 8'h02
    // Slave 3 (HB Monitor): offset 0x03 → addr[15:8] == 8'h03
    // Slave 4 (Reset Seq):  offset 0x04 → addr[15:8] == 8'h04
    // Slave 5 (Rec Policy): offset 0x05 → addr[15:8] == 8'h05
    // Slave 6 (VGA Ctrl):   offset 0x06 → addr[15:8] == 8'h06

    wire [7:0] slave_page = wbm_adr_i[15:8];

    wire sel_0 = (slave_page == 8'h00);  // UART
    wire sel_1 = (slave_page == 8'h01);  // Timer
    wire sel_2 = (slave_page == 8'h02);  // GPIO
    wire sel_3 = (slave_page == 8'h03);  // Heartbeat Monitor
    wire sel_4 = (slave_page == 8'h04);  // Power/Reset Sequencer
    wire sel_5 = (slave_page == 8'h05);  // Recovery Policy
    wire sel_6 = (slave_page == 8'h06);  // VGA Controller

    wire any_sel = sel_0 | sel_1 | sel_2 | sel_3 | sel_4 | sel_5 | sel_6;

    // ========================================================================
    // Local Address — Lower 8 bits passed to selected slave
    // ========================================================================
    wire [7:0] local_addr = wbm_adr_i[7:0];

    // ========================================================================
    // Shared Outputs to All Slaves (address, data, control)
    // ========================================================================
    // Address (local offset)
    assign wbs0_adr_o = local_addr;
    assign wbs1_adr_o = local_addr;
    assign wbs2_adr_o = local_addr;
    assign wbs3_adr_o = local_addr;
    assign wbs4_adr_o = local_addr;
    assign wbs5_adr_o = local_addr;
    assign wbs6_adr_o = local_addr;

    // Write data
    assign wbs0_dat_o = wbm_dat_i;
    assign wbs1_dat_o = wbm_dat_i;
    assign wbs2_dat_o = wbm_dat_i;
    assign wbs3_dat_o = wbm_dat_i;
    assign wbs4_dat_o = wbm_dat_i;
    assign wbs5_dat_o = wbm_dat_i;
    assign wbs6_dat_o = wbm_dat_i;

    // Write enable
    assign wbs0_we_o = wbm_we_i;
    assign wbs1_we_o = wbm_we_i;
    assign wbs2_we_o = wbm_we_i;
    assign wbs3_we_o = wbm_we_i;
    assign wbs4_we_o = wbm_we_i;
    assign wbs5_we_o = wbm_we_i;
    assign wbs6_we_o = wbm_we_i;

    // Byte select
    assign wbs0_sel_o = wbm_sel_i;
    assign wbs1_sel_o = wbm_sel_i;
    assign wbs2_sel_o = wbm_sel_i;
    assign wbs3_sel_o = wbm_sel_i;
    assign wbs4_sel_o = wbm_sel_i;
    assign wbs5_sel_o = wbm_sel_i;
    assign wbs6_sel_o = wbm_sel_i;

    // ========================================================================
    // Strobe and Cycle — Only asserted to the selected slave
    // ========================================================================
    assign wbs0_stb_o = wbm_stb_i & wbm_cyc_i & sel_0;
    assign wbs1_stb_o = wbm_stb_i & wbm_cyc_i & sel_1;
    assign wbs2_stb_o = wbm_stb_i & wbm_cyc_i & sel_2;
    assign wbs3_stb_o = wbm_stb_i & wbm_cyc_i & sel_3;
    assign wbs4_stb_o = wbm_stb_i & wbm_cyc_i & sel_4;
    assign wbs5_stb_o = wbm_stb_i & wbm_cyc_i & sel_5;
    assign wbs6_stb_o = wbm_stb_i & wbm_cyc_i & sel_6;

    assign wbs0_cyc_o = wbm_cyc_i & sel_0;
    assign wbs1_cyc_o = wbm_cyc_i & sel_1;
    assign wbs2_cyc_o = wbm_cyc_i & sel_2;
    assign wbs3_cyc_o = wbm_cyc_i & sel_3;
    assign wbs4_cyc_o = wbm_cyc_i & sel_4;
    assign wbs5_cyc_o = wbm_cyc_i & sel_5;
    assign wbs6_cyc_o = wbm_cyc_i & sel_6;

    // ========================================================================
    // Read Data Mux — Select data from the addressed slave
    // ========================================================================
    always @(*) begin
        wbm_dat_o = {DATA_WIDTH{1'b0}};
        case (1'b1)
            sel_0:   wbm_dat_o = wbs0_dat_i;
            sel_1:   wbm_dat_o = wbs1_dat_i;
            sel_2:   wbm_dat_o = wbs2_dat_i;
            sel_3:   wbm_dat_o = wbs3_dat_i;
            sel_4:   wbm_dat_o = wbs4_dat_i;
            sel_5:   wbm_dat_o = wbs5_dat_i;
            sel_6:   wbm_dat_o = wbs6_dat_i;
            default: wbm_dat_o = {DATA_WIDTH{1'b0}};
        endcase
    end

    // ========================================================================
    // Acknowledge Mux — Pass through ack from selected slave
    // ========================================================================
    always @(*) begin
        wbm_ack_o = 1'b0;
        case (1'b1)
            sel_0:   wbm_ack_o = wbs0_ack_i;
            sel_1:   wbm_ack_o = wbs1_ack_i;
            sel_2:   wbm_ack_o = wbs2_ack_i;
            sel_3:   wbm_ack_o = wbs3_ack_i;
            sel_4:   wbm_ack_o = wbs4_ack_i;
            sel_5:   wbm_ack_o = wbs5_ack_i;
            sel_6:   wbm_ack_o = wbs6_ack_i;
            default: wbm_ack_o = 1'b0;
        endcase
    end

    // ========================================================================
    // Error — Asserted when address doesn't match any slave
    // ========================================================================
    always @(*) begin
        wbm_err_o = wbm_stb_i & wbm_cyc_i & ~any_sel;
    end

endmodule
