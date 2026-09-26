// ============================================================================
// BMC SoC — Top-Level Verification Testbench (VeeR EL2 Core + All IPs)
// ============================================================================
// Instantiates the full synthesizable SoC (soc_top.v), which includes:
//   - VeeR EL2 RISC-V Processor Core
//   - 8KB External AXI ROM (preloaded with firmware.hex)
//   - 64-bit 3x8 AXI4 Crossbar Interconnect
//   - All BMC Hardware IPs:
//       1. 16550 AXI UART Controller
//       2. 32-bit System Timer
//       3. GPIO Status Register
//       4. Heartbeat Monitor IP
//       5. Power/Reset Sequencer IP
//       6. Recovery Policy & Circular Event Log IP
//       7. VGA Status Dashboard Engine
//
// The testbench monitors the UART TX pin in real time, decodes serial
// characters at 115200 baud, and streams firmware execution logs directly
// to the console. It also supports Synopsys Verdi FSDB waveform dumping.
// ============================================================================

`timescale 1ns / 1ps

module tb_soc_core;

    // ========================================================================
    // Parameters & Signals
    // ========================================================================
    localparam CLK_PERIOD = 10; // 100 MHz clock (10 ns period)
    `ifdef SIMULATION
    localparam BAUD_DIV   = 16;  // Fast UART in simulation (16 cycles/bit)
    `else
    localparam BAUD_DIV   = 868; // 100 MHz / 115200 baud = 868 cycles/bit
    `endif
    localparam BIT_PERIOD = CLK_PERIOD * BAUD_DIV;

    reg         clk;
    reg         rst_n;
    reg         heartbeat_in;
    wire        reset_out;
    reg         uart_rx;
    wire        uart_tx;
    reg         jtag_tck;
    reg         jtag_tms;
    reg         jtag_tdi;
    wire        jtag_tdo;
    wire        vga_hsync;
    wire        vga_vsync;
    wire [11:0] vga_rgb;

    // Simulation tracking
    reg [255:0] line_buf;
    integer     line_idx;
    integer     pass_flag;
    integer     fail_flag;

    // ========================================================================
    // DUT: Top-Level SoC
    // ========================================================================
    soc_top u_soc (
        .clk          (clk),
        .rst_n        (rst_n),
        .heartbeat_in (heartbeat_in),
        .reset_out    (reset_out),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .jtag_tck     (jtag_tck),
        .jtag_tms     (jtag_tms),
        .jtag_tdi     (jtag_tdi),
        .jtag_tdo     (jtag_tdo),
        .vga_hsync    (vga_hsync),
        .vga_vsync    (vga_vsync),
        .vga_rgb      (vga_rgb)
    );

    // ========================================================================
    // Clock Generation (100 MHz)
    // ========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ========================================================================
    // Periodic Simulated Host Heartbeat Pulse
    // ========================================================================
    initial begin
        heartbeat_in = 1'b0;
        @(posedge rst_n);
        forever begin
            #(1000 * CLK_PERIOD); // Pulse every 1000 cycles
            @(posedge clk);
            heartbeat_in <= 1'b1;
            @(posedge clk);
            heartbeat_in <= 1'b0;
        end
    end

    // Bus & CPU Execution Debug Monitor


    // ========================================================================
    // Main Test Stimulus
    // ========================================================================
    initial begin
        // Waveform dumping setup
        if ($test$plusargs("fsdb")) begin
            $fsdbDumpfile("soc_core.fsdb");
            $fsdbDumpvars(0, tb_soc_core);
        end else if ($test$plusargs("vcd")) begin
            $dumpfile("soc_core.vcd");
            $dumpvars(0, tb_soc_core);
        end

        // Initial pin states
        rst_n        = 1'b0;
        uart_rx      = 1'b1; // Idle high
        jtag_tck     = 1'b0;
        jtag_tms     = 1'b0;
        jtag_tdi     = 1'b0;
        line_idx     = 0;
        pass_flag    = 0;
        fail_flag    = 0;

        $display("================================================================");
        $display(" [TB] BMC SoC System Simulation Initialized");
        $display(" [TB] Clock: 100 MHz | UART Baud: 115200 (Divisor: %0d)", BAUD_DIV);
        $display(" [TB] AXI ROM initialized with firmware.hex");
        $display("================================================================\n");

        // Hold reset for 30 cycles
        repeat (30) @(posedge clk);
        rst_n = 1'b1;
        $display(" [TB] Reset deasserted (rst_n = 1). VeeR EL2 core booting from 0x80000000...\n");
    end

    // ========================================================================
    // Real-Time UART RX Monitor (Fast Sniffer)
    // ========================================================================
    reg [7:0] rx_byte;
    integer   bit_idx;

    initial begin
        @(posedge rst_n);
        forever begin
            // Wait for falling edge of UART start bit
            @(negedge uart_tx);
            
            // Sample in the middle of start bit (0.5 bit period)
            #(BIT_PERIOD / 2);
            if (uart_tx == 1'b0) begin
                // Read 8 data bits (sampled at 1.0 bit intervals)
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    #BIT_PERIOD;
                    rx_byte[bit_idx] = uart_tx;
                end

                // Wait for stop bit
                #BIT_PERIOD;

                // Stream character directly to terminal console
                $write("%c", rx_byte);
                $fflush();

                // Check for test completion banner
                if (rx_byte == 8'h0A || rx_byte == 8'h0D) begin // newline
                    line_idx = 0;
                end else begin
                    line_buf[line_idx*8 +: 8] = rx_byte;
                    line_idx = line_idx + 1;
                end

                // Detect PASS message (< in >>> ALL IP INTEGRATION TESTS PASSED SUCCESSFULLY! <<<)
                if (rx_byte == "<") begin
                    pass_flag = 1;
                end
                // Detect FAIL message (* in *** SOME IP TESTS FAILED! ***)
                if (rx_byte == "*") begin
                    fail_flag = 1;
                end
            end
        end
    end

    // ========================================================================
    // Test Completion & Watchdog Monitor
    // ========================================================================
    always @(posedge clk) begin
        if (pass_flag) begin
            // Wait for trailing characters to flush over UART
            repeat (30000) @(posedge clk);
            $display("\n================================================================");
            $display(" [TB] SIMULATION SUCCESS: All IP integration tests passed!");
            $display("================================================================\n");
            $finish;
        end
        if (fail_flag) begin
            repeat (30000) @(posedge clk);
            $display("\n================================================================");
            $display(" [TB] SIMULATION FAILED: One or more IP tests failed!");
            $display("================================================================\n");
            $finish;
        end
    end

    initial begin
        // 10 ms simulation watchdog (plenty of margin for fast 16-cycle baud)
        #10000000;
        $display("\n================================================================");
        $display(" [TB] TIMEOUT: Simulation reached watchdog limit.");
        $display("================================================================\n");
        $finish;
    end

endmodule
